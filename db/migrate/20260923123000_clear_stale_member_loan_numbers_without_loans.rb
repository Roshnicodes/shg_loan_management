class ClearStaleMemberLoanNumbersWithoutLoans < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      UPDATE shg_members
      SET loan_no = NULL, updated_at = CURRENT_TIMESTAMP
      WHERE loan_no IS NOT NULL
        AND btrim(loan_no) <> ''
        AND NOT EXISTS (
          SELECT 1
          FROM shg_loans
          WHERE shg_loans.shg_member_id = shg_members.id
        )
    SQL
  end

  def down
    # Historical loan numbers cannot be safely reconstructed after cleanup.
  end
end
