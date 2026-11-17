require "csv"

# Finds ASAWO26-era loans whose disbursement year is before their SHG's linkage
# year (the year typed wrong, e.g. 30/10/2025 for 30/10/2026) and moves the
# date into the linkage year. Only the disbursement date changes: EMI dates
# come from the linkage date and payments are kept, so no schedule is rebuilt.
class DisbursementYearFix
  Change = Struct.new(:loan, :old_date, :new_date, keyword_init: true)

  def initialize(shg_ids: nil)
    @shg_ids = Array(shg_ids).compact_blank
  end

  def changes
    loans.filter_map do |loan|
      new_date = corrected_date(loan.distribution_date, loan.shg.linkage_date)
      next unless new_date

      Change.new(loan: loan, old_date: loan.distribution_date, new_date: new_date)
    end
  end

  def apply!
    change_rows = changes
    timestamp = Time.current
    ShgLoan.transaction do
      change_rows.each { |change| change.loan.update_columns(distribution_date: change.new_date, updated_at: timestamp) }
    end
    change_rows
  end

  def to_csv(change_rows = changes)
    CSV.generate do |csv|
      csv << [ "Loan ID", "Loan No", "Member", "SHG ID", "SHG", "Linkage Date", "Old Disbursement Date", "New Disbursement Date" ]
      change_rows.each do |change|
        loan = change.loan
        csv << [ loan.id, loan.shg_member&.loan_no, loan.shg_member&.name, loan.shg_id, loan.shg.name, loan.shg.linkage_date, change.old_date, change.new_date ]
      end
    end
  end

  private

  def loans
    relation = ShgLoan.joins(:shg)
      .left_joins(:shg_member)
      .where("shg_loans.distribution_date < shgs.linkage_date")
      .where("shg_members.loan_no IS NULL OR shg_members.loan_no = '' OR shg_members.loan_no LIKE ?", "#{ShgMember::LOAN_NO_PREFIX}-%")
      .includes(:shg, :shg_member)
      .order(:shg_id, :id)
    relation = relation.where(shg_id: @shg_ids) if @shg_ids.any?
    relation.to_a
  end

  # Only a wrong year is fixed: same day and month, moved into the linkage year.
  # A date a few days before linkage in the same year is left for a person to check.
  def corrected_date(date, linkage_date)
    return if date.blank? || linkage_date.blank? || date.year >= linkage_date.year

    date.change(year: linkage_date.year)
  rescue Date::Error
    Date.new(linkage_date.year, date.month, -1)
  end
end
