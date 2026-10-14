require "test_helper"

class ShgLoanTest < ActiveSupport::TestCase
  test "starts collection next month for linkage dates through the 15th" do
    loan = schedule_loan_for(Date.new(2026, 9, 15))

    assert_equal Date.new(2026, 10, 15), loan.collection_start_date
    assert_equal [ Date.new(2026, 10, 15), Date.new(2026, 11, 15) ], loan.expected_emi_schedule.pluck(:due_date)
  end

  test "starts collection in the second following month for linkage dates from the 16th" do
    loan = schedule_loan_for(Date.new(2026, 9, 20))

    assert_equal Date.new(2026, 11, 20), loan.collection_start_date
    assert_equal [ Date.new(2026, 11, 20), Date.new(2026, 12, 20) ], loan.expected_emi_schedule.pluck(:due_date)
  end

  test "refreshes a saved schedule when its linkage date changes" do
    shg = shgs(:one)
    shg.update_columns(linkage_date: Date.new(2026, 9, 5), active: true, approval_status: "pending_dc")
    loan = persisted_schedule_loan(shg)

    assert_equal Date.new(2026, 10, 5), loan.shg_loan_emis.order(:installment_no).first.due_date

    attach_required_shg_files(shg)
    shg.update!(linkage_date: Date.new(2026, 9, 20))

    assert_equal Date.new(2026, 11, 20), loan.reload.shg_loan_emis.order(:installment_no).first.due_date
  end

  test "uses selected member shg as source of truth" do
    shg = shgs(:one)
    shg.update_columns(active: true, approval_status: "pending_dc")
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Loan Shg Sync Member",
      spouse_father_name: "Loan Shg Sync Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543270",
      monthly_income: 10_000,
      aadhaar_no: "123456789070"
    )

    loan = ShgLoan.create!(
      shg: shgs(:two),
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

    assert_equal shg, loan.shg
  end

  test "creating active loan does not assign loan number before dc approval" do
    shg = shgs(:one)
    shg.update_columns(active: true, approval_status: "pending_dc")
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Loan Number On Create",
      spouse_father_name: "Loan Number Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543220",
      monthly_income: 10_000,
      aadhaar_no: "123456789030"
    )

    assert_nil member.loan_no

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

    assert_nil member.reload.loan_no
  end

  test "creating loan does not assign loan number to inactive member" do
    shg = shgs(:one)
    shg.update_columns(active: true, approval_status: "pending_dc")
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Inactive Loan Number Member",
      spouse_father_name: "Inactive Loan Number Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543221",
      monthly_income: 10_000,
      aadhaar_no: "123456789031",
      active: false
    )

    ShgLoan.create!(
      shg: shg,
      shg_member: member,
      product: nil,
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

    assert_nil member.reload.loan_no
  end

  test "moving only loan away clears stale loan number from previous member" do
    shg = shgs(:one)
    shg.update_columns(active: true, approval_status: "pending_dc")
    old_member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Stale Loan Number Member",
      spouse_father_name: "Stale Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543230",
      monthly_income: 10_000,
      aadhaar_no: "123456789040",
      loan_no: "ASAWO26-77777"
    )
    new_member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Replacement Loan Member",
      spouse_father_name: "Replacement Guardian",
      gender: "Female",
      dob: Date.new(1991, 1, 1),
      mobile: "9876543231",
      monthly_income: 10_000,
      aadhaar_no: "123456789041"
    )
    loan = ShgLoan.create!(
      shg: shg,
      shg_member: old_member,
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

    loan.update!(shg_member: new_member)

    assert_nil old_member.reload.loan_no
    assert_empty old_member.shg_loans.reload
  end

  private

  def schedule_loan_for(linkage_date)
    ShgLoan.new(
      shg: Shg.new(linkage_date: linkage_date),
      distribution_date: Date.new(2026, 9, 1),
      loan_term_type: "Monthly",
      loan_term: 2,
      principal_amount: 10_000,
      interest_percent: 1.0
    )
  end

  def persisted_schedule_loan(shg)
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Linkage Schedule Member",
      spouse_father_name: "Linkage Schedule Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543280",
      monthly_income: 10_000,
      aadhaar_no: "123456789080"
    )

    ShgLoan.create!(
      shg: shg,
      shg_member: member,
      product: products(:one),
      activity: activities(:one),
      loan_status: loan_statuses(:one),
      created_by: users(:one),
      distribution_date: Date.new(2026, 9, 1),
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 2,
      principal_amount: 10_000,
      interest_percent: 1.0
    )
  end
end
