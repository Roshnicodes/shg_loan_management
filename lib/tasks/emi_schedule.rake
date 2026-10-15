namespace :emi do
  desc "Move existing EMI due dates onto the SHG linkage-date collection cycle (amounts and payments are kept)"
  task refresh_due_dates: :environment do
    loans = 0
    emis = 0

    ShgLoan.includes(:shg).find_each do |loan|
      changed = loan.refresh_collection_due_dates!
      next if changed.zero?

      loans += 1
      emis += changed
    end

    puts "Updated #{emis} EMI due dates across #{loans} loans."
  end
end
