class AddActiveToLoansAndVisits < ActiveRecord::Migration[8.1]
  def change
    add_column :shg_loans, :active, :boolean, null: false, default: true
    add_column :visit_records, :active, :boolean, null: false, default: true
  end
end
