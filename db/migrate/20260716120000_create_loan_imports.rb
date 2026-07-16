class CreateLoanImports < ActiveRecord::Migration[8.1]
  def change
    create_table :loan_imports do |t|
      t.references :user, null: false, foreign_key: true
      t.string :filename, null: false
      t.string :status, null: false, default: "queued"
      t.integer :total_rows, null: false, default: 0
      t.integer :total_loans, null: false, default: 0
      t.integer :approved_shgs, null: false, default: 0
      t.integer :skipped_rows, null: false, default: 0
      t.text :error_message
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :loan_imports, [ :status, :created_at ]
  end
end
