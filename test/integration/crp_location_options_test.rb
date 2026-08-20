require "test_helper"

class CrpLocationOptionsTest < ActionDispatch::IntegrationTest
  test "crp dropdown options include imported loan locations and cascade by block" do
    crp_type = UserType.create!(name: "CRP", code: "CRP", level: "village", active: true)
    state = State.create!(name: "Scope State", code: "SS", active: true)
    district = District.create!(state: state, name: "Scope District", code: "SD", active: true)
    block = Block.create!(district: district, name: "Scope Block", code: "SB", active: true)
    other_block = Block.create!(district: district, name: "Other Block", code: "OB", active: true)
    village = Village.create!(block: block, name: "Scope Village", code: "SV", active: true)
    other_village = Village.create!(block: other_block, name: "Other Village", code: "OV", active: true)
    inactive_only_village = Village.create!(block: block, name: "Inactive Only Village", code: "IOV", active: true)

    crp = User.create!(
      name: "Sheet CRP",
      email: "sheet-crp@example.com",
      login_id: "sheet_crp",
      mobile: "9876543999",
      designation: "CRP",
      user_type: crp_type,
      state: state,
      district: district,
      password: "secret123",
      active: true
    )

    imported_shg = Shg.create!(
      state: state,
      district: district,
      block: block,
      village: village,
      name: "Imported Scope SHG",
      shg_code: "IMPORTED-SCOPE-SHG",
      approval_status: "approved",
      active: true
    )
    other_shg = Shg.create!(
      state: state,
      district: district,
      block: other_block,
      village: other_village,
      name: "Other Scope SHG",
      shg_code: "OTHER-SCOPE-SHG",
      approval_status: "approved",
      active: true
    )
    inactive_shg = Shg.create!(
      state: state,
      district: district,
      block: block,
      village: inactive_only_village,
      name: "Inactive Scope SHG",
      shg_code: "INACTIVE-SCOPE-SHG",
      approval_status: "approved",
      active: false
    )
    member = ShgMember.create!(
      shg: imported_shg,
      occupation: occupations(:one),
      name: "Imported Member",
      gender: "Female",
      dob: Date.new(1995, 1, 1),
      mobile: "9876500001",
      loan_no: "ASAWO24-9911",
      monthly_income: 12_000,
      address: "Scope Village",
      active: true
    )
    inactive_member = ShgMember.create!(
      shg: inactive_shg,
      occupation: occupations(:one),
      name: "Inactive Member",
      gender: "Female",
      dob: Date.new(1995, 1, 1),
      mobile: "9876500002",
      loan_no: "ASAWO24-9912",
      monthly_income: 12_000,
      address: "Inactive Only Village",
      active: false
    )
    ShgLoan.create!(
      shg: imported_shg,
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
      total_payable: 10_000,
      source_crp_identifier: crp.login_id,
      active: true
    )
    ShgLoan.create!(
      shg: inactive_shg,
      shg_member: inactive_member,
      product: products(:one),
      activity: activities(:one),
      loan_status: loan_statuses(:one),
      created_by: crp,
      distribution_date: Date.current,
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 10_000,
      total_payable: 10_000,
      source_crp_identifier: crp.login_id,
      active: false
    )

    post login_path, params: { login_id: crp.login_id, password: "secret123" }
    assert_redirected_to dashboard_path

    get location_options_villages_path, params: { block_id: block.id }
    assert_response :success
    villages = response.parsed_body
    assert_equal [ village.id ], villages.map { |option| option["id"] }
    assert_not_includes villages.map { |option| option["id"] }, inactive_only_village.id

    get location_options_villages_path, params: { block_id: other_block.id }
    assert_response :success
    assert_empty response.parsed_body

    get location_options_shgs_path, params: { block_id: block.id, village_id: village.id }
    assert_response :success
    shgs = response.parsed_body
    assert_equal [ imported_shg.id ], shgs.map { |option| option["id"] }
    assert_not_includes shgs.map { |option| option["id"] }, other_shg.id
  end
end
