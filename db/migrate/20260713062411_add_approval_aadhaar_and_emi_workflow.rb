class AddApprovalAadhaarAndEmiWorkflow < ActiveRecord::Migration[8.1]
  def change
    rename_column :shgs, :formation_date, :linkage_date

    add_column :shgs, :approval_status, :string, null: false, default: "pending"
    add_reference :shgs, :created_by, foreign_key: { to_table: :users }
    add_reference :shgs, :approved_by, foreign_key: { to_table: :users }
    add_column :shgs, :approved_at, :datetime
    add_column :shgs, :approval_remarks, :text

    add_column :shg_members, :aadhaar_no, :string
    add_index :shg_members, :aadhaar_no, unique: true

    create_table :shg_loan_emis do |t|
      t.references :shg_loan, null: false, foreign_key: true
      t.integer :installment_no, null: false
      t.date :due_date, null: false
      t.decimal :principal_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :interest_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :due_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :paid_amount, precision: 12, scale: 2, default: 0, null: false
      t.date :paid_on
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :shg_loan_emis, [ :shg_loan_id, :installment_no ], unique: true
  end
end
