class DisableActiveLoansForInactiveMembers < ActiveRecord::Migration[8.1]
  def up
    ShgLoan.where(active: true, shg_member_id: ShgMember.where(active: false).select(:id))
      .update_all(active: false, updated_at: Time.current)
  end

  def down
    # Data repair only. Disabled stale loans should not be reverted automatically.
  end
end
