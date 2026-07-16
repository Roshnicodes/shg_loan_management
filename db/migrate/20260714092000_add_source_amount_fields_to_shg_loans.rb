class AddSourceAmountFieldsToShgLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :shg_loans, :source_interest_amount, :decimal, precision: 12, scale: 2
    add_column :shg_loans, :source_total_payable, :decimal, precision: 12, scale: 2
    add_column :shg_loans, :source_principal_collect, :decimal, precision: 12, scale: 2
    add_column :shg_loans, :source_interest_collect, :decimal, precision: 12, scale: 2
    add_column :shg_loans, :source_paid, :decimal, precision: 12, scale: 2
    add_column :shg_loans, :source_remaining, :decimal, precision: 12, scale: 2
  end
end
