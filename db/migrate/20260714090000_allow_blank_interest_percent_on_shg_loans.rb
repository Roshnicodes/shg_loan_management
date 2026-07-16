class AllowBlankInterestPercentOnShgLoans < ActiveRecord::Migration[8.1]
  def change
    change_column_null :shg_loans, :interest_percent, true
    change_column_default :shg_loans, :interest_percent, from: 0, to: nil
  end
end
