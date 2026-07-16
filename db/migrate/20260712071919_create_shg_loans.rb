class CreateShgLoans < ActiveRecord::Migration[8.1]
  def change
    create_table :shg_loans do |t|
      t.references :shg, null: false, foreign_key: true
      t.references :shg_member, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.references :activity, null: false, foreign_key: true
      t.references :loan_status, null: false, foreign_key: true
      t.string :geography_type
      t.date :distribution_date, null: false
      t.string :loan_term_type
      t.integer :loan_term
      t.decimal :principal_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :interest_percent, precision: 5, scale: 2, default: 0, null: false
      t.decimal :interest_amount, precision: 12, scale: 2, default: 0, null: false
      t.decimal :total_payable, precision: 12, scale: 2, default: 0, null: false
      t.references :created_by, null: false, foreign_key: { to_table: :users }

      t.timestamps
    end
  end
end
