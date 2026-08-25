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

  test "district coordinator cannot approve when any active loan is missing product" do
    shg = shgs(:one)
    shg.update_column(:approval_status, "pending_dc")
    loan = shg_loans(:one)
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

  test "district coordinator approval assigns loan numbers to blank members" do
    shg = shgs(:one)
    shg.update_column(:approval_status, "pending_dc")
    attach_required_shg_files(shg)
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      name: "DC Approved Member",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876543216",
      monthly_income: 10_000,
      address: "Test address"
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
    assert_equal "ASAWO26-01", member.reload.loan_no
  end
end
