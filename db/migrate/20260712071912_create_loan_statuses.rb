class CreateLoanStatuses < ActiveRecord::Migration[8.1]
  def change
    create_table :loan_statuses do |t|
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :active, default: true, null: false

      t.timestamps
    end
  end
end
