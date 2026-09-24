require "csv"
require "securerandom"

class LoanNumberResequencer
  Change = Struct.new(:member_id, :member_name, :loan_ids, :old_loan_no, :new_loan_no, keyword_init: true)

  def initialize(prefix: ShgMember::LOAN_NO_PREFIX)
    @prefix = prefix
  end

  def changes
    ordered_members.each_with_index.filter_map do |member, index|
      new_loan_no = formatted_loan_no(index + 1)
      next if member.loan_no == new_loan_no

      Change.new(
        member_id: member.id,
        member_name: member.name,
        loan_ids: member.shg_loans.map(&:id),
        old_loan_no: member.loan_no,
        new_loan_no: new_loan_no
      )
    end
  end

  def apply!
    change_rows = changes
    return change_rows if change_rows.blank?

    ShgMember.transaction do
      locked_members = ShgMember.where(id: change_rows.map(&:member_id)).lock.index_by(&:id)
      timestamp = Time.current

      change_rows.each do |change|
        locked_members.fetch(change.member_id).update_columns(loan_no: temporary_loan_no(change.member_id), updated_at: timestamp)
      end

      change_rows.each do |change|
        locked_members.fetch(change.member_id).update_columns(loan_no: change.new_loan_no, updated_at: timestamp)
      end
    end

    change_rows
  end

  def to_csv(change_rows = changes)
    CSV.generate do |csv|
      csv << [ "Member ID", "Member", "Loan IDs", "Old Loan No", "New Loan No" ]
      change_rows.each do |change|
        csv << [ change.member_id, change.member_name, change.loan_ids.join("|"), change.old_loan_no, change.new_loan_no ]
      end
    end
  end

  private

  attr_reader :prefix

  def ordered_members
    ShgMember.includes(:shg_loans)
      .joins(:shg_loans)
      .where("shg_members.loan_no LIKE ?", "#{prefix}-%")
      .distinct
      .to_a
      .select { |member| loan_no_sequence(member.loan_no) }
      .sort_by { |member| [ loan_no_sequence(member.loan_no), member.id ] }
  end

  def loan_no_sequence(loan_no)
    loan_no.to_s[/\A#{Regexp.escape(prefix)}-(\d+)\z/, 1]&.to_i
  end

  def formatted_loan_no(sequence)
    "#{prefix}-#{sequence.to_s.rjust(2, '0')}"
  end

  def temporary_loan_no(member_id)
    "__RESEQ__#{member_id}__#{SecureRandom.hex(4)}"
  end
end
