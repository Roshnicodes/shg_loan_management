require "test_helper"

class ShgLoansImportTest < ActiveSupport::TestCase
  test "treats ww only import rows as blank placeholders" do
    row = ShgLoansController::SpreadsheetImportRow.new(
      [ "loan number", "borrower id", "borrower name", "state", "district", "block" ],
      [ "ww", nil, "", nil, "", nil ]
    )

    assert ShgLoansController.new.send(:import_blank_row?, row)
  end

  test "does not treat ww rows with real data as blank" do
    row = ShgLoansController::SpreadsheetImportRow.new(
      [ "loan number", "borrower id", "borrower name", "state", "district", "block" ],
      [ "ww", "123", "Borrower", "Jharkhand", "Pakur", "Amrapara" ]
    )

    assert_not ShgLoansController.new.send(:import_blank_row?, row)
  end
end
