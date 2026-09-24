require "test_helper"

class LoanNumberResequencerTest < ActiveSupport::TestCase
  setup do
    @shg = shgs(:one)
    @shg.update_columns(active: true, approval_status: "approved")
    @occupation = occupations(:one)
    @activity = activities(:one)
    @product = products(:one)
    @loan_status = loan_statuses(:one)
    @user = users(:one)
  end

  test "previews compressed loan number changes for members with loans" do
    first = create_member_with_loan!("Reseq First", "ASAWO26-01", 80)
    second = create_member_with_loan!("Reseq Second", "ASAWO26-03", 81)
    third = create_member_with_loan!("Reseq Third", "ASAWO26-04", 82)
    stale = create_member_without_loan!("Reseq Stale", "ASAWO26-99", 83)

    changes = LoanNumberResequencer.new.changes

    assert_equal [ second.id, third.id ], changes.map(&:member_id)
    assert_equal [ "ASAWO26-03", "ASAWO26-04" ], changes.map(&:old_loan_no)
    assert_equal [ "ASAWO26-02", "ASAWO26-03" ], changes.map(&:new_loan_no)
    assert_not_includes changes.map(&:member_id), first.id
    assert_not_includes changes.map(&:member_id), stale.id
  end

  test "applies compressed loan number changes through temporary values" do
    first = create_member_with_loan!("Apply First", "ASAWO26-01", 90)
    second = create_member_with_loan!("Apply Second", "ASAWO26-03", 91)
    third = create_member_with_loan!("Apply Third", "ASAWO26-04", 92)

    applied = LoanNumberResequencer.new.apply!

    assert_equal [ second.id, third.id ], applied.map(&:member_id)
    assert_equal "ASAWO26-01", first.reload.loan_no
    assert_equal "ASAWO26-02", second.reload.loan_no
    assert_equal "ASAWO26-03", third.reload.loan_no
  end

  private

  def create_member_with_loan!(name, loan_no, suffix)
    member = create_member_without_loan!(name, loan_no, suffix)
    ShgLoan.create!(
      shg: @shg,
      shg_member: member,
      product: @product,
      activity: @activity,
      loan_status: @loan_status,
      created_by: @user,
      distribution_date: Date.current,
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 10_000,
      interest_percent: 1.0
    )
    member
  end

  def create_member_without_loan!(name, loan_no, suffix)
    ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      activity: @activity,
      name: name,
      spouse_father_name: "#{name} Guardian",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "98765432#{suffix}",
      monthly_income: 10_000,
      aadhaar_no: "1234567890#{suffix}",
      loan_no: loan_no
    )
  end
end
