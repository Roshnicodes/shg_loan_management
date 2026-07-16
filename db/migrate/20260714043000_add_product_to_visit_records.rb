class AddProductToVisitRecords < ActiveRecord::Migration[8.1]
  def change
    add_reference :visit_records, :product, foreign_key: true
  end
end
