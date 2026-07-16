class AddCompositeExportIndexes < ActiveRecord::Migration[8.1]
  def change
    add_index :shg_loans, [ :shg_id, :distribution_date ] unless index_exists?(:shg_loans, [ :shg_id, :distribution_date ])
    add_index :shg_loans, [ :created_by_id, :distribution_date ] unless index_exists?(:shg_loans, [ :created_by_id, :distribution_date ])
    add_index :visit_records, [ :shg_id, :visit_date ] unless index_exists?(:visit_records, [ :shg_id, :visit_date ])
    add_index :visit_records, [ :created_by_id, :visit_date ] unless index_exists?(:visit_records, [ :created_by_id, :visit_date ])
    add_index :visit_records, [ :approval_status, :visit_date ] unless index_exists?(:visit_records, [ :approval_status, :visit_date ])
  end
end
