require "test_helper"

class ShgLoanTest < ActiveSupport::TestCase
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
end
