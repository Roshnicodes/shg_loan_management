require "test_helper"

class DisbursementYearFixTest < ActiveSupport::TestCase
  setup do
    @shg = shgs(:one)
    @shg.update_columns(linkage_date: Date.new(2026, 10, 30), active: true, approval_status: "pending_dc")
    member = ShgMember.create!(
      shg: @shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Wrong Year Member",
      spouse_father_name: "Wrong Year Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543282",
      monthly_income: 10_000,
      aadhaar_no: "123456789082"
    )
    member.update_columns(loan_no: "#{ShgMember::LOAN_NO_PREFIX}-5443")
    @loan = ShgLoan.create!(
      shg: @shg,
      shg_member: member,
      product: products(:one),
      activity: activities(:one),
      loan_status: loan_statuses(:one),
      created_by: users(:one),
      distribution_date: Date.new(2026, 10, 30),
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 12_000,
      interest_percent: 1.0
    )
    # Wrong-year dates already in the database (the form now refuses them).
    @loan.update_columns(distribution_date: Date.new(2025, 10, 30))
  end

  test "preview lists the wrong-year loan without changing it" do
    changes = DisbursementYearFix.new.changes

    change = changes.find { |row| row.loan.id == @loan.id }
    assert_equal Date.new(2026, 10, 30), change.new_date
    assert_equal Date.new(2025, 10, 30), @loan.reload.distribution_date
  end

  test "apply fixes the year and leaves the EMI schedule and payments alone" do
    first_emi = @loan.shg_loan_emis.order(:installment_no).first
    first_emi.update_columns(paid_amount: 500, paid_on: Date.new(2026, 11, 2))
    emis_before = @loan.shg_loan_emis.order(:installment_no).pluck(:id, :due_date, :due_amount, :paid_amount, :paid_on)

    DisbursementYearFix.new(shg_ids: [ @shg.id ]).apply!

    assert_equal Date.new(2026, 10, 30), @loan.reload.distribution_date
    assert_equal emis_before, @loan.shg_loan_emis.order(:installment_no).pluck(:id, :due_date, :due_amount, :paid_amount, :paid_on)
    assert_empty DisbursementYearFix.new(shg_ids: [ @shg.id ]).changes
  end

  test "loans in the linkage year are left alone, even a few days before linkage" do
    [ Date.new(2026, 11, 1), Date.new(2026, 10, 25) ].each do |date|
      @loan.update_columns(distribution_date: date)

      assert_not DisbursementYearFix.new.changes.any? { |row| row.loan.id == @loan.id }, date.to_s
    end
  end
end
