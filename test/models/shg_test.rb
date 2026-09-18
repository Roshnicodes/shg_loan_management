require "test_helper"

class ShgTest < ActiveSupport::TestCase
  test "does not allow duplicate shg names case insensitive" do
    existing = shgs(:one)
    duplicate = Shg.new(
      state: states(:two),
      district: districts(:two),
      block: blocks(:two),
      village: villages(:two),
      name: existing.name.downcase,
      shg_code: "UNIQUE-SHG-CODE",
      linkage_date: Date.current
    )
    attach_required_shg_files(duplicate)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "display name includes shg id and village" do
    shg = shgs(:one)

    assert_equal "#{shg.name} / #{shg.id} / #{shg.village.name}", shg.display_name
  end

  test "changing shg village syncs location and dependent visits" do
    shg = shgs(:one)
    attach_required_shg_files(shg)
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "Village Sync Member",
      spouse_father_name: "Village Sync Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543280",
      monthly_income: 10_000,
      aadhaar_no: "123456789080"
    )
    visit = VisitRecord.create!(
      village: shg.village,
      shg: shg,
      shg_member: member,
      visit_date: Date.current,
      purpose: "Follow up",
      observations: "Checked",
      created_by: users(:one)
    )

    shg.update!(village: villages(:two))

    assert_equal villages(:two), shg.reload.village
    assert_equal villages(:two).block, shg.block
    assert_equal villages(:two).block.district, shg.district
    assert_equal villages(:two).block.district.state, shg.state
    assert_equal villages(:two), visit.reload.village
  end

  test "district coordinator cannot approve when any active loan is missing product" do
    shg = shgs(:one)
    shg.update_column(:approval_status, "pending_dc")
    loan = shg_loans(:one)
    loan.shg_member.update_columns(active: true)
    loan.update_columns(product_id: nil, active: true)

    dc_type = UserType.create!(name: "Approval DC", code: "DIST_COORDINATOR", level: "district", active: true)
    dc = User.create!(
      name: "Approval DC",
      email: "approval-dc@example.com",
      login_id: "102",
      mobile: "9876501111",
      user_type: dc_type,
      state: shg.state,
      district: shg.district,
      password: "secret123",
      active: true
    )

    assert_raises(ActiveRecord::RecordInvalid) { shg.approve!(dc) }
    assert_equal "pending_dc", shg.reload.approval_status
  end

  test "district coordinator approval ignores inactive member loan missing product" do
    shg = shgs(:one)
    shg.update_column(:approval_status, "pending_dc")
    attach_required_shg_files(shg)
    active_member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "DC Active Approved Member",
      spouse_father_name: "DC Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543216",
      monthly_income: 10_000,
      aadhaar_no: "123456789020"
    )
    ShgLoan.create!(
      shg: shg,
      shg_member: active_member,
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
    inactive_member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      activity: activities(:one),
      name: "DC Inactive Extra Member",
      spouse_father_name: "DC Inactive Guardian",
      gender: "Female",
      dob: Date.new(1991, 1, 1),
      mobile: "9876543217",
      monthly_income: 10_000,
      aadhaar_no: "123456789021",
      active: false
    )
    ShgLoan.create!(
      shg: shg,
      shg_member: inactive_member,
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

    dc_type = UserType.create!(name: "Loan Number DC", code: "DIST_COORDINATOR", level: "district", active: true)
    dc = User.create!(
      name: "Loan Number DC",
      email: "loan-number-dc@example.com",
      login_id: "103",
      mobile: "9876501112",
      user_type: dc_type,
      state: shg.state,
      district: shg.district,
      password: "secret123",
      active: true
    )

    shg.approve!(dc)

    assert_equal "pending_assistant", shg.reload.approval_status
    assert_match(/\AASAWO26-\d{2,}\z/, active_member.reload.loan_no)
    assert_nil inactive_member.reload.loan_no
  end
end
