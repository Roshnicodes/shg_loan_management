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

  test "assigns first missing ASAWO26 loan number before max plus one" do
    shg = shgs(:one)
    occupation = occupations(:one)
    activity = activities(:one)

    ShgMember.create!(
      shg: shg,
      occupation: occupation,
      activity: activity,
      name: "Sequence One Member",
      spouse_father_name: "Sequence One Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543220",
      monthly_income: 10_000,
      aadhaar_no: "123456789020",
      loan_no: "ASAWO26-01"
    )
    ShgMember.create!(
      shg: shg,
      occupation: occupation,
      activity: activity,
      name: "Sequence Three Member",
      spouse_father_name: "Sequence Three Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543221",
      monthly_income: 10_000,
      aadhaar_no: "123456789021",
      loan_no: "ASAWO26-03"
    )
    member = ShgMember.create!(
      shg: shg,
      occupation: occupation,
      activity: activity,
      name: "Sequence Gap Member",
      spouse_father_name: "Sequence Gap Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543222",
      monthly_income: 10_000,
      aadhaar_no: "123456789022"
    )

    assert_equal "ASAWO26-02", member.assign_next_loan_no!
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

  test "changing member shg keeps dependent loans and visits in the same shg" do
    old_shg = shgs(:one)
    new_shg = shgs(:two)
    old_shg.update_columns(active: true, approval_status: "pending_dc")

    member = ShgMember.create!(
      shg: old_shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Transfer Member",
      spouse_father_name: "Transfer Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543290",
      monthly_income: 10_000,
      aadhaar_no: "123456789090"
    )
    loan = ShgLoan.create!(
      shg: old_shg,
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
    visit = VisitRecord.create!(
      village: old_shg.village,
      shg: old_shg,
      shg_member: member,
      product: products(:one),
      visit_date: Date.current,
      purpose: "Follow up",
      observations: "Checked",
      created_by: users(:one)
    )

    member.update!(shg: new_shg)

    assert_equal new_shg, loan.reload.shg
    assert_equal new_shg, visit.reload.shg
    assert_equal new_shg.village, visit.village
  end
end
