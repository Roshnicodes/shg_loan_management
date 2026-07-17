namespace :crp_users do
  desc "Create/update CRP users from imported loan CRP IDs"
  task sync_from_loans: :environment do
    default_password = ENV.fetch("DEFAULT_CRP_PASSWORD", "123456")
    reset_existing_passwords = ActiveModel::Type::Boolean.new.cast(ENV["RESET_EXISTING_PASSWORDS"])
    crp_type = UserType.find_or_create_by!(code: "CRP") do |type|
      type.name = "CRP"
      type.level = "village"
    end

    created = 0
    updated = 0
    skipped = 0
    attached_loans = 0

    crp_rows = ShgLoan
      .joins(shg: [ village: [ block: [ district: :state ] ] ])
      .where.not(source_crp_identifier: [ nil, "" ])
      .select(
        "LOWER(TRIM(shg_loans.source_crp_identifier)) AS crp_login_id",
        "MAX(NULLIF(TRIM(shg_loans.source_crp_name), '')) AS crp_name",
        "MIN(states.id) AS state_id",
        "MIN(districts.id) AS district_id",
        "MIN(blocks.id) AS block_id",
        "MIN(villages.id) AS village_id",
        "COUNT(shg_loans.id) AS loans_count"
      )
      .group("LOWER(TRIM(shg_loans.source_crp_identifier))")

    crp_rows.each do |row|
      login_id = row.crp_login_id.to_s
      if login_id.blank? || login_id !~ /\A[a-zA-Z0-9_.-]+\z/
        skipped += 1
        next
      end

      user = User.find_or_initialize_by(login_id: login_id)
      created += 1 if user.new_record?
      updated += 1 unless user.new_record?

      name = row.crp_name.presence || "CRP #{login_id}"
      email = user.email.presence || "crp-#{login_id}@shg.local"

      user.assign_attributes(
        name: name,
        email: email,
        designation: "CRP",
        user_type: crp_type,
        state_id: row.state_id,
        district_id: row.district_id,
        block_id: row.block_id,
        village_id: row.village_id,
        active: true
      )

      if user.new_record? || reset_existing_passwords
        user.password = default_password
        user.password_confirmation = default_password
      end

      user.save!
      attached_loans += ShgLoan.where("LOWER(source_crp_identifier) = ?", login_id)
        .where.not(created_by_id: user.id)
        .update_all(created_by_id: user.id, updated_at: Time.current)
    end

    puts "CRP users sync completed."
    puts "Created: #{created}"
    puts "Updated: #{updated}"
    puts "Skipped invalid IDs: #{skipped}"
    puts "Loans attached: #{attached_loans}"
    puts "Default password for new users: #{default_password}"
  end
end
