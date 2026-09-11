class ClearPreapprovalGeneratedLoanNumbers < ActiveRecord::Migration[8.1]
  def up
    ShgMember
      .joins(:shg)
      .where(shgs: { approval_status: %w[draft pending_dc] })
      .where("shg_members.loan_no LIKE ?", "#{ShgMember::LOAN_NO_PREFIX}-%")
      .update_all(loan_no: nil, updated_at: Time.current)
  end

  def down
    # Loan numbers are assigned during DC approval, so cleared pre-approval numbers
    # should not be recreated by rollback.
  end
end
