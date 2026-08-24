class AllowBlankProductOnShgLoans < ActiveRecord::Migration[8.1]
  def change
    change_column_null :shg_loans, :product_id, true
  end
end
