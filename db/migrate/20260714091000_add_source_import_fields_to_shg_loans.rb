class AddSourceImportFieldsToShgLoans < ActiveRecord::Migration[8.1]
  def change
    add_column :shg_loans, :source_crp_identifier, :string
    add_column :shg_loans, :source_crp_name, :string
    add_column :shg_loans, :source_loan_status, :string
  end
end
