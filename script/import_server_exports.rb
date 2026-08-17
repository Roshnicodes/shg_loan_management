require "csv"

FILES = {
  shgs: "/home/asa/Downloads/shg-master-2026-08-17.csv",
  members: "/home/asa/Downloads/shg-members-2026-08-17.csv",
  loans: "/home/asa/Downloads/shg-loans-2026-08-17.csv",
  visits: "/home/asa/Downloads/visit-records-2026-08-17.csv"
}.freeze

def clean(value)
  value.to_s.strip
end

def normalized(value)
  clean(value).downcase
end

def parse_date(value)
  raw = clean(value)
  return if raw.blank?
  return Date.strptime(raw.tr(".", "/").tr("-", "/"), "%d/%m/%Y") if raw.match?(/\A\d{1,2}[\/.\-]\d{1,2}[\/.\-]\d{4}\z/)

  Date.parse(raw)
rescue Date::Error
  nil
end

def parse_decimal(value)
  raw = clean(value).delete(",").delete("%")
  raw.present? ? raw.to_d : nil
end

def find_or_create_state(name)
  State.where("LOWER(name) = ?", normalized(name)).first || State.create!(name: clean(name))
end

def find_or_create_district(state, name)
  District.where(state: state).where("LOWER(name) = ?", normalized(name)).first || District.create!(state: state, name: clean(name))
end

def find_or_create_block(district, name)
  Block.where(district: district).where("LOWER(name) = ?", normalized(name)).first || Block.create!(district: district, name: clean(name))
end

def find_or_create_village(block, name)
  Village.where(block: block).where("LOWER(name) = ?", normalized(name)).first || Village.create!(block: block, name: clean(name))
end

def location_for(row)
  state = find_or_create_state(row.fetch("State"))
  district = find_or_create_district(state, row.fetch("District"))
  block = find_or_create_block(district, row.fetch("Block"))
  village = find_or_create_village(block, row.fetch("Village"))
  [ state, district, block, village ]
end

def user_by_name(name)
  value = clean(name)
  return if value.blank?

  User.where("LOWER(name) = ? OR LOWER(login_id) = ? OR LOWER(email) = ?", value.downcase, value.downcase, value.downcase).first
end

def fallback_user
  @fallback_user ||= User.joins(:user_type).where("UPPER(user_types.code) IN (?)", %w[ASSIST_ADMIN ASSISTANT_ADMIN ADMIN]).first || User.first
end

def approval_status(label)
  case normalized(label)
  when "approved" then "approved"
  when "rejected" then "rejected"
  when "pending assistant", "pending at assistant admin", "pending_assistant" then "pending_assistant"
  else "pending_dc"
  end
end

def loan_status_for(label, total_payable, paid, remaining)
  status = clean(label)
  status = "Closed" if remaining.to_d.zero? || (total_payable.to_d.positive? && paid.to_d >= total_payable.to_d)
  status = "Active" if status.blank?
  LoanStatus.where("LOWER(name) = ? OR LOWER(code) = ?", status.downcase, status.downcase).first || LoanStatus.default_active
end

def product_for(name)
  value = clean(name).presence || "Imported Loan"
  Product.where("LOWER(name) = ?", value.downcase).first || Product.create!(name: value)
end

def shg_key(name, state, district, block, village)
  [ normalized(name), normalized(state), normalized(district), normalized(block), normalized(village) ]
end

def find_shg!(name, state, district, block, village, shgs_by_key)
  key = shg_key(name, state, district, block, village)
  shgs_by_key[key] || raise("SHG not found: #{key.join(' / ')}")
end

def emi_rows_for(loan_id, loan_attrs, paid_amount)
  installments = loan_attrs[:loan_term].to_i
  return [] if installments <= 0

  interval =
    case loan_attrs[:loan_term_type]
    when "Quarterly" then 3
    when "Half Yearly" then 6
    when "Yearly" then 12
    else 1
    end
  principal_total = loan_attrs[:principal_amount].to_d
  total_due = loan_attrs[:total_payable].to_d
  interest_total = [ total_due - principal_total, loan_attrs[:interest_amount].to_d ].max
  principal_emi = principal_total / installments
  interest_emi = interest_total / installments
  due_emi = total_due / installments
  principal_allocated = 0.to_d
  interest_allocated = 0.to_d
  due_allocated = 0.to_d
  paid_remaining = paid_amount.to_d
  timestamp = Time.current

  installments.times.map do |index|
    final = index == installments - 1
    principal = final ? principal_total - principal_allocated : principal_emi.round(2)
    interest = final ? interest_total - interest_allocated : interest_emi.round(2)
    due = final ? total_due - due_allocated : due_emi.round(2)
    principal_allocated += principal
    interest_allocated += interest
    due_allocated += due
    paid = [ paid_remaining, due ].min
    paid_remaining -= paid
    due_date = loan_attrs[:distribution_date] + ((index + 1) * interval).months

    {
      shg_loan_id: loan_id,
      installment_no: index + 1,
      due_date: due_date,
      principal_amount: principal.round(2),
      interest_amount: interest.round(2),
      due_amount: due.round(2),
      paid_amount: paid.round(2),
      paid_on: paid.positive? ? Date.current : nil,
      status: paid >= due ? "paid" : (due_date < Date.current ? "overdue" : "pending"),
      created_at: timestamp,
      updated_at: timestamp
    }
  end
end

ActiveRecord::Base.transaction do
  puts "Clearing local transactional data..."
  ShgLoanEmi.delete_all
  VisitRecord.delete_all
  ShgLoan.delete_all
  ShgMember.delete_all
  Shg.delete_all

  shgs_by_key = {}
  member_by_loan_no = {}
  timestamp = Time.current
  imported_occupation = Occupation.find_or_create_by!(name: "Imported")
  default_activity = Activity.find_or_create_by!(name: "General")

  puts "Importing SHGs..."
  CSV.foreach(FILES.fetch(:shgs), headers: true, encoding: "bom|utf-8:utf-8").with_index(1) do |row, index|
    state, district, block, village = location_for(row)
    created_by = user_by_name(row["Created By"]) || fallback_user
    assistant = user_by_name(row["Assistant Approval"])
    status = approval_status(row["Approval"])
    shg = Shg.new(
      state_id: state.id,
      district_id: district.id,
      block_id: block.id,
      village_id: village.id,
      created_by_id: created_by&.id,
      name: clean(row.fetch("SHG")),
      shg_code: "SRV-#{index}",
      linkage_date: parse_date(row["Linkage Date"]),
      approval_status: status,
      assistant_approved_by_id: assistant&.id,
      assistant_approved_at: assistant ? timestamp : nil,
      approved_by_id: assistant&.id,
      approved_at: status == "approved" ? timestamp : nil,
      approval_remarks: clean(row["Remarks"]).presence,
      active: true
    )
    shg.save!(validate: false)
    shgs_by_key[shg_key(row.fetch("SHG"), row.fetch("State"), row.fetch("District"), row.fetch("Block"), row.fetch("Village"))] = shg
  end

  puts "Importing members..."
  CSV.foreach(FILES.fetch(:members), headers: true, encoding: "bom|utf-8:utf-8") do |row|
    shg = find_shg!(row.fetch("SHG"), row.fetch("State"), row.fetch("District"), row.fetch("Block"), row.fetch("Village"), shgs_by_key)
    member = ShgMember.new(
      shg_id: shg.id,
      occupation_id: imported_occupation.id,
      name: clean(row.fetch("Member")),
      loan_no: clean(row.fetch("Loan No")),
      mobile: clean(row["Mobile"]).gsub(/\D/, ""),
      monthly_income: parse_decimal(row["Monthly HH Income"]),
      address: [ clean(row["Village"]), clean(row["Block"]), clean(row["District"]) ].compact_blank.join(", "),
      active: true
    )
    member.save!(validate: false)
    member_by_loan_no[normalized(row.fetch("Loan No"))] = member
  end

  puts "Importing loans..."
  CSV.foreach(FILES.fetch(:loans), headers: true, encoding: "bom|utf-8:utf-8").with_index(1) do |row, index|
    shg = find_shg!(row.fetch("SHG Name"), row.fetch("State"), row.fetch("District"), row.fetch("Block"), row.fetch("Village"), shgs_by_key)
    member = member_by_loan_no[normalized(row.fetch("Loan No"))]
    unless member
      member = ShgMember.new(
        shg_id: shg.id,
        occupation_id: imported_occupation.id,
        name: clean(row.fetch("Member")),
        loan_no: clean(row.fetch("Loan No")).presence || "SRV-MISSING-#{index}",
        mobile: clean(row["Mobile"]).gsub(/\D/, ""),
        monthly_income: parse_decimal(row["Monthly hh income"]),
        address: [ clean(row["Village"]), clean(row["Block"]), clean(row["District"]) ].compact_blank.join(", "),
        active: true
      )
      member.save!(validate: false)
    end
    member_by_loan_no[normalized(member.loan_no)] = member

    product = product_for(row["Product"])
    total_payable = parse_decimal(row["Total Payable"])
    paid = parse_decimal(row["Paid"])
    remaining = parse_decimal(row["Remaining"])
    loan_status = loan_status_for(row["Loan Status"], total_payable, paid, remaining)
    loan_attrs = {
      shg_id: shg.id,
      shg_member_id: member.id,
      product_id: product.id,
      activity_id: default_activity.id,
      loan_status_id: loan_status.id,
      created_by_id: (user_by_name(row["CRPName"]) || fallback_user)&.id,
      source_crp_identifier: clean(row["CRP ID"]),
      source_crp_name: clean(row["CRPName"]),
      source_loan_status: clean(row["Loan Status"]),
      source_interest_amount: parse_decimal(row["Interest Amount"]),
      source_total_payable: total_payable,
      source_principal_collect: parse_decimal(row["Principal Collected"]),
      source_interest_collect: parse_decimal(row["Interest collected"]),
      source_paid: paid,
      source_remaining: remaining,
      geography_type: "Rural",
      distribution_date: parse_date(row["Disbursement Date"]) || Date.current,
      loan_term_type: clean(row["Term Type"]).presence || "Monthly",
      loan_term: clean(row["Loan term"]).presence || 1,
      principal_amount: parse_decimal(row["Principal"]) || 0,
      interest_percent: parse_decimal(row["Annual Interest Percent"]),
      interest_amount: parse_decimal(row["Interest Amount"]) || 0,
      total_payable: total_payable || ((parse_decimal(row["Principal"]) || 0) + (parse_decimal(row["Interest Amount"]) || 0)),
      active: true,
      created_at: timestamp,
      updated_at: timestamp
    }
    loan = ShgLoan.new(loan_attrs)
    loan.manual_import_totals = true
    loan.save!(validate: false)
    ShgLoanEmi.insert_all!(emi_rows_for(loan.id, loan_attrs, paid)) if loan_attrs[:loan_term].to_i.positive?
  end

  puts "Importing visits..."
  CSV.foreach(FILES.fetch(:visits), headers: true, encoding: "bom|utf-8:utf-8") do |row|
    shg = find_shg!(row.fetch("SHG"), row.fetch("State"), row.fetch("District"), row.fetch("Block"), row.fetch("Village"), shgs_by_key)
    member = member_by_loan_no[normalized(row["Loan No"])] || ShgMember.where(shg: shg).where("LOWER(name) = ?", normalized(row["Member"])).first
    next unless member

    product = product_for(row["Product"])
    creator = user_by_name(row["Created By"]) || fallback_user
    dc = user_by_name(row["DC Approval"])
    assistant = user_by_name(row["Assistant Approval"])
    status = approval_status(row["Approval"])
    visit = VisitRecord.new(
      village_id: shg.village_id,
      shg_id: shg.id,
      shg_member_id: member.id,
      product_id: product.id,
      created_by_id: creator&.id,
      dc_approved_by_id: dc&.id,
      dc_approved_at: dc ? timestamp : nil,
      assistant_approved_by_id: assistant&.id,
      assistant_approved_at: assistant ? timestamp : nil,
      approved_by_id: status == "approved" ? (assistant || dc || creator)&.id : nil,
      approved_at: status == "approved" ? timestamp : nil,
      visit_date: parse_date(row["Visit Date"]) || Date.current,
      purpose: clean(row["Purpose"]),
      observations: clean(row["Observations"]),
      approval_status: status,
      approval_remarks: clean(row["Remarks"]).presence,
      active: true
    )
    visit.save!(validate: false)
  end

  puts({
    states: State.count,
    districts: District.count,
    blocks: Block.count,
    villages: Village.count,
    shgs: Shg.count,
    members: ShgMember.count,
    loans: ShgLoan.count,
    emis: ShgLoanEmi.count,
    visits: VisitRecord.count
  }.inspect)
end
