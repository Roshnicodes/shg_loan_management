namespace :loan_numbers do
  desc "Preview ASAWO loan number resequencing without changing data"
  task preview_resequence: :environment do
    resequencer = LoanNumberResequencer.new
    changes = resequencer.changes

    puts resequencer.to_csv(changes)
    puts "Changes: #{changes.size}"
    puts "No data changed. Run loan_numbers:apply_resequence CONFIRM=YES only after reviewing this mapping."
  end

  desc "Apply ASAWO loan number resequencing after preview review. Requires CONFIRM=YES"
  task apply_resequence: :environment do
    unless ENV["CONFIRM"] == "YES"
      abort "Refusing to change loan numbers. First run loan_numbers:preview_resequence, then rerun with CONFIRM=YES."
    end

    resequencer = LoanNumberResequencer.new
    changes = resequencer.changes
    puts resequencer.to_csv(changes)
    applied = resequencer.apply!
    puts "Applied changes: #{applied.size}"
  end
end
