namespace :loan_dates do
  desc "Preview loans whose disbursement date is before the SHG linkage date (no data changed). Optional SHG_IDS=1,2"
  task preview_disbursement_fix: :environment do
    fix = DisbursementYearFix.new(shg_ids: ENV["SHG_IDS"].to_s.split(","))
    changes = fix.changes
    puts fix.to_csv(changes)
    puts "Loans to fix: #{changes.size}"
    puts "No data changed. Run loan_dates:apply_disbursement_fix CONFIRM=YES only after reviewing this list."
  end

  desc "Move those disbursement dates into the linkage year. Requires CONFIRM=YES. Optional SHG_IDS=1,2"
  task apply_disbursement_fix: :environment do
    unless ENV["CONFIRM"] == "YES"
      abort "Refusing to change disbursement dates. First run loan_dates:preview_disbursement_fix, then rerun with CONFIRM=YES."
    end

    fix = DisbursementYearFix.new(shg_ids: ENV["SHG_IDS"].to_s.split(","))
    applied = fix.apply!
    puts fix.to_csv(applied)
    puts "Updated disbursement dates: #{applied.size}"
  end
end
