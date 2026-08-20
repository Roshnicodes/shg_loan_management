require "test_helper"

class RoleVisibilityScopeTest < ActionDispatch::IntegrationTest
  test "admin assistant dc and crp see the expected sheet and shg master scope" do
    admin_type = UserType.create!(name: "Admin", code: "ADMIN", level: "state", active: true)
    assistant_type = UserType.create!(name: "Assistant Admin", code: "ASSIST_ADMIN", level: "state", active: true)
    dc_type = UserType.create!(name: "District Coordinator", code: "DIST_COORDINATOR", level: "district", active: true)
    crp_type = UserType.create!(name: "CRP", code: "CRP", level: "village", active: true)

    state = State.create!(name: "Role Scope State", code: "RSS", active: true)
    district = District.create!(state: state, name: "Role Scope District", code: "RSD", active: true)
    other_district = District.create!(state: state, name: "Other Scope District", code: "OSD", active: true)
    block = Block.create!(district: district, name: "Role Scope Block", code: "RSB", active: true)
    other_block = Block.create!(district: other_district, name: "Other Scope Block", code: "OSB", active: true)
    village = Village.create!(block: block, name: "Imported Village", code: "IV", active: true)
    created_village = Village.create!(block: block, name: "Created Village", code: "CV", active: true)
    other_village = Village.create!(block: other_block, name: "Other District Village", code: "ODV", active: true)

    admin = user_for(admin_type, state, nil, "scope-admin")
    assistant = user_for(assistant_type, state, nil, "scope-assistant")
    dc = user_for(dc_type, state, district, "scope-dc")
    crp = user_for(crp_type, state, district, "scope-crp")

    imported_shg = shg_for(state, district, block, village, "Imported Sheet SHG")
    crp_created_shg = shg_for(state, district, block, created_village, "CRP Master SHG", created_by: crp)
    other_shg = shg_for(state, other_district, other_block, other_village, "Other District SHG")
    unrelated_same_district_shg = shg_for(state, district, block, village, "Unrelated Same District SHG")

    create_loan(imported_shg, crp.login_id, users(:one))
    create_loan(crp_created_shg, crp.login_id, crp)
    create_loan(other_shg, "other-crp", users(:one))
    create_loan(unrelated_same_district_shg, "someone-else", users(:one))

    assert_shg_options_for(admin, block, village, [ imported_shg, unrelated_same_district_shg ])
    assert_shg_options_for(assistant, other_block, other_village, [ other_shg ])
    assert_shg_options_for(dc, block, village, [ imported_shg, unrelated_same_district_shg ])
    assert_shg_options_for(dc, other_block, other_village, [])
    assert_shg_options_for(crp, block, village, [ imported_shg ])
    assert_shg_options_for(crp, block, created_village, [ crp_created_shg ])
    assert_shg_options_for(crp, other_block, other_village, [])
  end

  private

  def user_for(user_type, state, district, login_id)
    User.create!(
      name: login_id.titleize,
      email: "#{login_id}@example.com",
      login_id: login_id,
      mobile: "98#{SecureRandom.random_number(10**8).to_s.rjust(8, "0")}",
      designation: user_type.name,
      user_type: user_type,
      state: state,
      district: district,
      password: "secret123",
      active: true
    )
  end

  def shg_for(state, district, block, village, name, created_by: nil)
    Shg.create!(
      state: state,
      district: district,
      block: block,
      village: village,
      name: name,
      shg_code: name.parameterize.upcase.first(24),
      approval_status: "approved",
      created_by: created_by,
      active: true
    )
  end

  def create_loan(shg, source_crp_identifier, created_by)
    member = ShgMember.create!(
      shg: shg,
      occupation: occupations(:one),
      name: "#{shg.name} Member",
      gender: "Female",
      dob: Date.new(1995, 1, 1),
      mobile: "97#{SecureRandom.random_number(10**8).to_s.rjust(8, "0")}",
      loan_no: "LN-#{SecureRandom.hex(4)}",
      monthly_income: 12_000,
      address: shg.village.name,
      active: true
    )

    ShgLoan.create!(
      shg: shg,
      shg_member: member,
      product: products(:one),
      activity: activities(:one),
      loan_status: loan_statuses(:one),
      created_by: created_by,
      distribution_date: Date.current,
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 10_000,
      total_payable: 10_000,
      source_crp_identifier: source_crp_identifier,
      active: true
    )
  end

  def assert_shg_options_for(user, block, village, expected_shgs)
    post login_path, params: { login_id: user.login_id, password: "secret123" }

    get location_options_shgs_path, params: { block_id: block.id, village_id: village.id }
    assert_response :success
    assert_equal expected_shgs.map(&:id).sort, response.parsed_body.map { |option| option["id"] }.sort
  ensure
    delete logout_path
  end
end
