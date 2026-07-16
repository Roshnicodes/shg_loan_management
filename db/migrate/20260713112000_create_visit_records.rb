class CreateVisitRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :visit_records do |t|
      t.references :village, null: false, foreign_key: true
      t.references :shg, null: false, foreign_key: true
      t.references :shg_member, null: false, foreign_key: true
      t.references :created_by, foreign_key: { to_table: :users }
      t.references :approved_by, foreign_key: { to_table: :users }
      t.references :dc_approved_by, foreign_key: { to_table: :users }
      t.references :assistant_approved_by, foreign_key: { to_table: :users }
      t.string :visit_type, null: false
      t.date :visit_date, null: false
      t.string :approval_status, null: false, default: "pending_dc"
      t.text :purpose
      t.text :observations
      t.text :next_action
      t.text :approval_remarks
      t.datetime :approved_at
      t.datetime :dc_approved_at
      t.datetime :assistant_approved_at

      t.timestamps
    end

    add_column :shg_members, :loan_no, :string
    add_index :shg_members, :loan_no
  end
end
