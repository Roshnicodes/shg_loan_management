class AddIndexToShgLoansSourceCrpIdentifier < ActiveRecord::Migration[8.1]
  def change
    add_index :shg_loans,
      "LOWER(source_crp_identifier)",
      name: "index_shg_loans_on_lower_source_crp_identifier"
  end
end
