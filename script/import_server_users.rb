require "csv"

PATH = "/home/asa/Downloads/cash360-users-20260817.csv"
TEMP_PASSWORD = "Use Reset Password"

def clean(value)
  value.to_s.strip
end

def normalized(value)
  clean(value).downcase
end

def role_for(name)
  role = normalized(name)
  UserType.where("LOWER(name) = ? OR LOWER(code) = ?", role, role).first ||
    UserType.find_or_create_by!(name: clean(name)) { |type| type.code = clean(name).parameterize(separator: "_").upcase }
end

def state_for(name)
  value = clean(name)
  return if value.blank?

  State.where("LOWER(name) = ?", value.downcase).first || State.create!(name: value)
end

def ids_for(model, names)
  names.to_s.split(",").map(&:strip).reject(&:blank?).filter_map do |name|
    model.where("LOWER(name) = ?", name.downcase).first&.id
  end.uniq
end

imported_user_ids = []
created = 0
updated = 0
deactivated = 0

ActiveRecord::Base.transaction do
  CSV.foreach(PATH, headers: true, encoding: "bom|utf-8:utf-8") do |row|
    id = clean(row["ID"]).presence&.to_i
    login_id = normalized(row["Login ID"])
    next if login_id.blank?

    user = User.find_by(login_id: login_id) || User.new

    user.assign_attributes(
      name: clean(row["Name"]),
      login_id: login_id,
      email: clean(row["Email"]),
      mobile: clean(row["Mobile"]).gsub(/\D/, ""),
      designation: clean(row["Designation"]),
      user_type: role_for(row["Role"]),
      state: state_for(row["State"]),
      district_id: nil,
      block_id: nil,
      village_id: nil,
      mapped_district_ids: ids_for(District, row["Districts"]),
      mapped_block_ids: ids_for(Block, row["Blocks"]),
      mapped_village_ids: ids_for(Village, row["Villages"]),
      active: !clean(row["Active"]).casecmp?("no")
    )

    if user.new_record?
      user.password = TEMP_PASSWORD
      user.password_confirmation = TEMP_PASSWORD
      user.save!(validate: false)
      created += 1
    else
      user.save!(validate: false)
      updated += 1
    end
    imported_user_ids << user.id
  end

  if imported_user_ids.present?
    deactivated = User.where.not(id: imported_user_ids.uniq).update_all(active: false, updated_at: Time.current)
  end

  User.connection.reset_pk_sequence!("users")
end

puts({
  csv_users: imported_user_ids.size,
  created: created,
  updated: updated,
  deactivated_not_in_csv: deactivated,
  local_users: User.count,
  active_users: User.where(active: true).count
}.inspect)
