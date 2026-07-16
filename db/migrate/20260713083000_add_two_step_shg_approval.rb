class AddTwoStepShgApproval < ActiveRecord::Migration[8.1]
  def up
    change_column_default :shgs, :approval_status, from: "pending", to: "pending_dc"

    add_reference :shgs, :dc_approved_by, foreign_key: { to_table: :users }
    add_column :shgs, :dc_approved_at, :datetime
    add_reference :shgs, :assistant_approved_by, foreign_key: { to_table: :users }
    add_column :shgs, :assistant_approved_at, :datetime

    execute <<~SQL.squish
      UPDATE shgs
      SET approval_status = 'pending_dc'
      WHERE approval_status = 'pending'
    SQL

    execute <<~SQL.squish
      UPDATE shgs
      SET assistant_approved_by_id = approved_by_id,
          assistant_approved_at = approved_at
      WHERE approval_status = 'approved'
    SQL
  end

  def down
    change_column_default :shgs, :approval_status, from: "pending_dc", to: "pending"

    execute <<~SQL.squish
      UPDATE shgs
      SET approval_status = 'pending'
      WHERE approval_status IN ('pending_dc', 'pending_assistant')
    SQL

    remove_column :shgs, :assistant_approved_at
    remove_reference :shgs, :assistant_approved_by, foreign_key: { to_table: :users }
    remove_column :shgs, :dc_approved_at
    remove_reference :shgs, :dc_approved_by, foreign_key: { to_table: :users }
  end
end
