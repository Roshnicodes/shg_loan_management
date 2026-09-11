require "test_helper"

class ShgMemberTest < ActiveSupport::TestCase
  test "does not assign loan number before approval" do
    member = ShgMember.create!(
      shg: shgs(:one),
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Blank Loan Member",
      spouse_father_name: "Blank Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543214",
      monthly_income: 10_000,
      aadhaar_no: "123456789014"
    )

    assert_nil member.loan_no
  end

  test "assigns next ASAWO26 loan number with two digit sequence" do
    member = ShgMember.create!(
      shg: shgs(:one),
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Approved Loan Member",
      spouse_father_name: "Approved Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543215",
      monthly_income: 10_000,
      aadhaar_no: "123456789015"
    )

    assert_equal "ASAWO26-01", member.assign_next_loan_no!
  end

  test "allows duplicate member names in same shg" do
    shg = shgs(:one)
    occupation = occupations(:one)

    attrs = {
      shg: shg,
      occupation: occupation,
      activity: activities(:one),
      name: "Parwati Yadav",
      spouse_father_name: "Parwati Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543212",
      monthly_income: 10_000,
      aadhaar_no: "123456789016"
    }

    first = ShgMember.create!(attrs.merge(loan_no: "TEST-DUP-1"))
    second = ShgMember.new(attrs.merge(name: first.name, mobile: "9876543213", aadhaar_no: "123456789017", loan_no: "TEST-DUP-2"))

    assert second.valid?
  end

  test "does not allow duplicate aadhaar numbers" do
    duplicate = ShgMember.new(
      shg: shgs(:one),
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Duplicate Aadhaar Member",
      spouse_father_name: "Duplicate Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543218",
      monthly_income: 10_000,
      aadhaar_no: shg_members(:one).aadhaar_no
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:aadhaar_no].any?
  end

  test "uses manually entered work activity before legacy activity" do
    member = ShgMember.new(
      shg: shgs(:one),
      occupation: occupations(:one),
      activity: activities(:one),
      work_activity: "Manual Work",
      name: "Manual Work Member",
      spouse_father_name: "Manual Work Guardian",
      gender: "Female",
      dob: Date.new(1991, 3, 2),
      mobile: "9876543219",
      monthly_income: 10_000,
      aadhaar_no: "123456789019"
    )

    assert member.valid?
    assert_equal "Manual Work", member.work_activity_name
  end
end
