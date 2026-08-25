require "test_helper"

class ShgMemberTest < ActiveSupport::TestCase
  test "does not assign loan number before approval" do
    member = ShgMember.create!(
      shg: shgs(:one),
      occupation: occupations(:one),
      name: "Blank Loan Member",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543214",
      monthly_income: 10_000,
      address: "Test address"
    )

    assert_nil member.loan_no
  end

  test "assigns next ASAWO26 loan number with two digit sequence" do
    member = ShgMember.create!(
      shg: shgs(:one),
      occupation: occupations(:one),
      name: "Approved Loan Member",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543215",
      monthly_income: 10_000,
      address: "Test address"
    )

    assert_equal "ASAWO26-01", member.assign_next_loan_no!
  end

  test "allows duplicate member names in same shg" do
    shg = shgs(:one)
    occupation = occupations(:one)

    attrs = {
      shg: shg,
      occupation: occupation,
      name: "Parwati Yadav",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543212",
      monthly_income: 10_000,
      address: "Test address"
    }

    first = ShgMember.create!(attrs.merge(loan_no: "TEST-DUP-1"))
    second = ShgMember.new(attrs.merge(name: first.name, mobile: "9876543213", loan_no: "TEST-DUP-2"))

    assert second.valid?
  end
end
