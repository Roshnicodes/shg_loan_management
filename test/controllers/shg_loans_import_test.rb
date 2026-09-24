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

  test "submits ready imported draft shgs without assigning loan numbers" do
    shg = shgs(:one)
    shg.update_columns(active: true, approval_status: "pending_dc")
    attach_required_shg_files(shg)
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Ready Draft Import Member",
      spouse_father_name: "Ready Draft Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543292",
      monthly_income: 10_000,
      aadhaar_no: "123456789092"
    )
    ShgLoan.create!(
      shg: shg,
      shg_member: member,
      product: products(:one),
      activity: activities(:one),
      loan_status: loan_statuses(:one),
      created_by: users(:one),
      distribution_date: Date.current,
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 10_000,
      interest_percent: 1.0
    )
    shg.update_columns(approval_status: "draft", dc_approved_by_id: nil, dc_approved_at: nil)

    controller = ShgLoansController.new
    controller.instance_variable_set(:@import_shgs, { [ shg.village_id, shg.name ] => shg })
    processed_rows = [ { attrs: { shg: shg.name }, village: shg.village } ]

    assert_equal 1, controller.send(:submit_ready_import_shgs!, processed_rows)
    assert_equal "pending_dc", shg.reload.approval_status
    assert_nil member.reload.loan_no
  end
end
