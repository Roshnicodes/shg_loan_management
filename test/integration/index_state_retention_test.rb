require "test_helper"

class IndexStateRetentionTest < ActionDispatch::IntegrationTest
  setup do
    @state = State.create!(name: "Retention State", code: "RTS")
    @district = District.create!(name: "Retention District", code: "RTD", state: @state)
    @block = Block.create!(name: "Retention Block", code: "RTB", district: @district)
    @village = Village.create!(name: "Retention Village", code: "RTV", block: @block)
    @product = Product.create!(name: "Retention Product", code: "RTP")
    @occupation = Occupation.create!(name: "Retention Occupation")
    @activity = Activity.create!(name: "Retention Activity")
    @loan_status = LoanStatus.create!(name: "Retention Active", code: "RTA")

    @admin_type = UserType.create!(name: "Retention Admin", code: "ADMIN", level: "state")
    @dc_type = UserType.create!(name: "Retention DC", code: "DIST_COORDINATOR", level: "district")
    @crp_type = UserType.create!(name: "Retention CRP", code: "CRP", level: "village")

    @admin = user_for("211", @admin_type, district: nil)
    @dc = user_for("212", @dc_type)
    @crp = user_for("213", @crp_type, block: @block, village: @village)

    @shg = Shg.new(
      name: "Retention SHG",
      shg_code: "RT-SHG",
      state: @state,
      district: @district,
      block: @block,
      village: @village,
      office_location: "Retention Office",
      borrower_short_address: "Retention Village",
      linkage_date: Date.current,
      approval_status: "pending_dc",
      created_by: @crp
    )
    attach_required_shg_files(@shg)
    @shg.save!

    @member = ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      activity: @activity,
      work_activity: @activity.name,
      name: "Retention Member",
      spouse_father_name: "Retention Guardian",
      gender: "Female",
      dob: Date.new(1992, 2, 2),
      mobile: "9876500211",
      monthly_income: 6500,
      aadhaar_no: "123456789121"
    )

    @loan = ShgLoan.create!(
      shg: @shg,
      shg_member: @member,
      activity: @activity,
      loan_status: @loan_status,
      created_by: @crp,
      distribution_date: Date.current,
      geography_type: "Rural",
      loan_term_type: "Monthly",
      loan_term: 12,
      principal_amount: 12_000,
      interest_percent: 1.0,
      active: true
    )
  end

  test "shg filters persist until clear is clicked" do
    login_as(@admin)

    get shgs_path(block_id: @block.id, page: 2)
    assert_response :success

    get shgs_path
    assert_redirected_to shgs_path(block_id: @block.id, page: 2)

    get shgs_path(clear_filters: 1)
    assert_redirected_to shgs_path

    follow_redirect!
    assert_response :success

    get shgs_path
    assert_response :success
  end

  test "shg update keeps page and filters" do
    login_as(@dc)

    patch shg_path(@shg, page: 4, block_id: @block.id), params: {
      shg: {
        state_id: @state.id,
        district_id: @district.id,
        block_id: @block.id,
        village_id: @village.id,
        name: "Retention SHG Updated",
        linkage_date: Date.current,
        active: "1"
      }
    }

    assert_redirected_to "#{shgs_path(page: 4, block_id: @block.id)}#results"
  end

  test "member update keeps page and filters" do
    login_as(@dc)

    patch shg_member_path(@member, page: 4, block_id: @block.id), params: {
      shg_member: {
        shg_id: @shg.id,
        name: "Retention Member Updated",
        spouse_father_name: @member.spouse_father_name,
        gender: "Female",
        dob: @member.dob,
        mobile: @member.mobile,
        monthly_income: @member.monthly_income,
        work_activity: @activity.name,
        aadhaar_no: @member.aadhaar_no,
        active: "1"
      }
    }

    assert_redirected_to "#{shg_members_path(page: 4, block_id: @block.id)}#results"
  end

  test "member disable also disables active loans for that member" do
    login_as(@admin)

    patch disable_shg_member_path(@member, page: 4, block_id: @block.id)

    assert_redirected_to "#{shg_members_path(page: 4, block_id: @block.id)}#results"
    assert_not @member.reload.active?
    assert_not @loan.reload.active?
  end

  test "member add another keeps reusable fields for next entry" do
    login_as(@dc)

    assert_difference("ShgMember.count", 1) do
      post shg_members_path(page: 3, block_id: @block.id), params: {
        add_another: "Save & Add Another",
        shg_member: {
          block_id: @block.id,
          village_id: @village.id,
          shg_id: @shg.id,
          name: "Carry Forward Member",
          spouse_father_name: "Carry Forward Guardian",
          gender: "Female",
          dob: Date.new(1993, 3, 3),
          mobile: "9876500999",
          monthly_income: "7200",
          work_activity: "Carry Forward Work",
          aadhaar_no: "123456789122",
          active: "1"
        }
      }
    end

    redirect_uri = URI.parse(response.location)
    redirect_params = Rack::Utils.parse_nested_query(redirect_uri.query)

    assert_equal new_shg_member_path, redirect_uri.path
    assert_equal "3", redirect_params["page"]
    assert_equal @block.id.to_s, redirect_params.dig("shg_member", "block_id")
    assert_equal @village.id.to_s, redirect_params.dig("shg_member", "village_id")
    assert_equal @shg.id.to_s, redirect_params.dig("shg_member", "shg_id")
    assert_equal "Female", redirect_params.dig("shg_member", "gender")
    assert_equal "7200", redirect_params.dig("shg_member", "monthly_income")
    assert_equal "Carry Forward Work", redirect_params.dig("shg_member", "work_activity")

    follow_redirect!

    assert_response :success
    assert_select "select[name='shg_member[block_id]'] option[selected='selected'][value='#{@block.id}']"
    assert_select "select[name='shg_member[village_id]'] option[selected='selected'][value='#{@village.id}']"
    assert_select "select[name='shg_member[shg_id]'] option[selected='selected'][value='#{@shg.id}']"
    assert_select "select[name='shg_member[gender]'] option[selected='selected']", text: "Female"
    assert_select "input[name='shg_member[work_activity]'][value='Carry Forward Work']"
    assert_select "textarea[name='shg_member[address]']", false
    assert_select "input[name='shg_member[name]'][value='Carry Forward Member']", false
    assert_select "input[name='shg_member[mobile]'][value='9876500999']", false
    assert_select "input[name='shg_member[aadhaar_no]'][value='123456789122']", false
    assert_select "input[name='shg_member[dob]'][value='1993-03-03']", false
  end

  test "new member form renders option data for strict village to shg cascade" do
    other_village = Village.create!(name: "Retention Other Village", code: "ROV", block: @block)
    other_shg = Shg.new(
      name: "Retention Other SHG",
      shg_code: "RT-OTHER-SHG",
      state: @state,
      district: @district,
      block: @block,
      village: other_village,
      office_location: "Retention Other Office",
      borrower_short_address: "Retention Other Village",
      linkage_date: Date.current,
      approval_status: "pending_dc",
      created_by: @crp
    )
    attach_required_shg_files(other_shg)
    other_shg.save!
    login_as(@dc)

    get new_shg_member_path(block_id: @block.id, village_id: @village.id)

    assert_response :success
    assert_select "form[data-location-select-strict-value='true'][data-dependent-dropdown-fallback='true']"
    assert_select "select[name='shg_member[village_id]'] option[value='#{@village.id}'][data-block-id='#{@block.id}']", text: @village.name
    assert_select "select[name='shg_member[village_id]'] option[value='#{other_village.id}'][data-block-id='#{@block.id}']", text: other_village.name
    assert_select "select[name='shg_member[shg_id]'] option[value='#{@shg.id}'][data-village-id='#{@village.id}']", text: @shg.display_name
    assert_select "select[name='shg_member[shg_id]'] option[value='#{other_shg.id}'][data-village-id='#{other_village.id}']", text: other_shg.display_name
  end

  test "new member form preloads option data for browser side strict cascade" do
    login_as(@dc)

    get new_shg_member_path

    assert_response :success
    assert_select "form[data-location-select-strict-value='true'][data-dependent-dropdown-fallback='true']"
    assert_select "select[name='shg_member[village_id]'] option[value='#{@village.id}'][data-block-id='#{@block.id}']", text: @village.name
    assert_select "select[name='shg_member[shg_id]'] option[value='#{@shg.id}'][data-village-id='#{@village.id}']", text: @shg.display_name
  end

  test "new loan form shows eligible members for selected shg" do
    other_shg = Shg.new(
      name: "Retention Same Village Other SHG",
      shg_code: "RT-SAME-VILLAGE-OTHER-SHG",
      state: @state,
      district: @district,
      block: @block,
      village: @village,
      office_location: "Retention Same Village Office",
      borrower_short_address: "Retention Same Village",
      linkage_date: Date.current,
      approval_status: "pending_dc",
      created_by: @crp
    )
    attach_required_shg_files(other_shg)
    other_shg.save!
    available_member = ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      activity: @activity,
      work_activity: @activity.name,
      name: "Available Loan Member",
      spouse_father_name: "Available Guardian",
      gender: "Female",
      dob: Date.new(1994, 4, 4),
      mobile: "9876500222",
      monthly_income: 7500,
      aadhaar_no: "123456789222"
    )
    other_member = ShgMember.create!(
      shg: other_shg,
      occupation: @occupation,
      activity: @activity,
      work_activity: @activity.name,
      name: "Other SHG Loan Member",
      spouse_father_name: "Other Guardian",
      gender: "Female",
      dob: Date.new(1994, 5, 5),
      mobile: "9876500223",
      monthly_income: 7600,
      aadhaar_no: "123456789223"
    )
    login_as(@dc)

    get new_shg_loan_path(shg_loan: { block_id: @block.id, village_id: @village.id, shg_id: @shg.id })

    assert_response :success
    assert_select "select[name='shg_loan[shg_member_id]'] option[value='#{available_member.id}'][data-shg-id='#{@shg.id}']", text: available_member.name
    assert_select "select[name='shg_loan[shg_member_id]'] option[value='#{other_member.id}'][data-shg-id='#{other_shg.id}']", text: other_member.name
  end

  test "new loan form preloads option data for browser side strict cascade" do
    available_member = ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      activity: @activity,
      work_activity: @activity.name,
      name: "Preloaded Loan Member",
      spouse_father_name: "Preloaded Guardian",
      gender: "Female",
      dob: Date.new(1994, 6, 6),
      mobile: "9876500224",
      monthly_income: 7700,
      aadhaar_no: "123456789224"
    )
    login_as(@dc)

    get new_shg_loan_path

    assert_response :success
    assert_select "form[data-controller='loan-member-details'][data-dependent-dropdown-fallback='true']"
    assert_select "select[name='shg_loan[village_id]'] option[value='#{@village.id}'][data-block-id='#{@block.id}']", text: @village.name
    assert_select "select[name='shg_loan[shg_id]'] option[value='#{@shg.id}'][data-village-id='#{@village.id}']", text: @shg.display_name
    assert_select "select[name='shg_loan[shg_member_id]'] option[value='#{available_member.id}'][data-shg-id='#{@shg.id}']", text: available_member.name
  end

  test "district scoped crp can select villages under same district blocks on new shg form" do
    second_block = Block.create!(name: "Retention Second Block", code: "RTB2", district: @district)
    second_village = Village.create!(name: "Retention Second Village", code: "RTV2", block: second_block)
    outside_district = District.create!(name: "Retention Outside District", code: "ROD", state: @state)
    outside_block = Block.create!(name: "Retention Outside Block", code: "ROB", district: outside_district)
    outside_village = Village.create!(name: "Retention Outside Village", code: "ROV2", block: outside_block)
    district_crp = user_for("214", @crp_type)

    login_as(district_crp)

    get new_shg_path

    assert_response :success
    assert_select "input[name='shg[state_id]'][value='#{@state.id}']"
    assert_select "input[name='shg[district_id]'][value='#{@district.id}']"
    assert_select "select[name='shg[block_id]'] option[value='#{@block.id}'][data-district-id='#{@district.id}']", text: @block.name
    assert_select "select[name='shg[block_id]'] option[value='#{second_block.id}'][data-district-id='#{@district.id}']", text: second_block.name
    assert_select "select[name='shg[village_id]'] option[value='#{@village.id}'][data-block-id='#{@block.id}']", text: @village.name
    assert_select "select[name='shg[village_id]'] option[value='#{second_village.id}'][data-block-id='#{second_block.id}']", text: second_village.name
    assert_select "select[name='shg[block_id]'] option[value='#{outside_block.id}']", false
    assert_select "select[name='shg[village_id]'] option[value='#{outside_village.id}']", false
  end

  test "loan update keeps page and filters" do
    login_as(@dc)

    patch shg_loan_path(@loan, page: 4, block_id: @block.id), params: {
      shg_loan: {
        shg_id: @shg.id,
        shg_member_id: @member.id,
        product_id: @product.id,
        geography_type: "Rural",
        distribution_date: Date.current,
        loan_term_type: "Monthly",
        loan_term: 12,
        principal_amount: 12_000,
        interest_percent: 1.0
      }
    }

    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"
  end

  test "loan index saves product code and keeps page" do
    login_as(@dc)

    patch update_product_shg_loan_path(@loan, page: 4, block_id: @block.id), params: {
      shg_loan: { product_id: @product.id }
    }

    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"
    assert_equal @product, @loan.reload.product
  end

  test "dc approval keeps page after product code is set" do
    @loan.update_columns(product_id: @product.id)
    login_as(@dc)

    patch approve_shg_path(@shg, page: 4, approval_status: "pending_dc")

    assert_redirected_to "#{shgs_path(page: 4, approval_status: "pending_dc")}#results"
    assert_equal "pending_assistant", @shg.reload.approval_status
  end

  test "loan index includes product code select" do
    login_as(@dc)

    get shg_loans_path(block_id: @block.id)

    assert_response :success
    assert_select "form[action='#{update_product_shg_loan_path(@loan, block_id: @block.id)}'] select[name='shg_loan[product_id]']"
    assert_select "select[name='shg_loan[product_id]'] option", text: "Product Code"
  end

  test "shg master approval row does not include product code select" do
    login_as(@dc)

    get shgs_path(approval_status: "pending_dc")

    assert_response :success
    assert_select "select[name^='loan_products']", false
  end

  test "village form includes state and village gs code" do
    login_as(@admin)

    get new_village_path

    assert_response :success
    assert_select "select[name='village[state_id]']"
    assert_select "select[name='village[district_id]']"
    assert_select "input[name='village[code]']"
    assert_includes response.body, "data-state-id=\"#{@state.id}\""
    assert_includes response.body, "data-district-id=\"#{@district.id}\""
  end

  test "existing village gs code can be edited" do
    login_as(@admin)

    patch village_path(@village), params: {
      village: {
        block_id: @block.id,
        name: @village.name,
        code: "RTV-GS-99",
        active: "1"
      }
    }

    assert_redirected_to villages_path
    assert_equal "RTV-GS-99", @village.reload.code
  end

  test "dc can edit loan after assistant admin approval while temporary edit access is enabled" do
    @loan.update_columns(product_id: @product.id)
    @shg.update!(
      approval_status: "approved",
      assistant_approved_by: @admin,
      assistant_approved_at: Time.current,
      approved_by: @admin,
      approved_at: Time.current
    )
    login_as(@dc)

    get shg_loans_path(block_id: @block.id)
    assert_response :success
    assert_select "a[href*='#{edit_shg_loan_path(@loan)}']", text: "Edit"

    get edit_shg_loan_path(@loan, page: 4, block_id: @block.id)

    assert_response :success

    patch shg_loan_path(@loan, page: 4, block_id: @block.id), params: {
      shg_loan: {
        shg_id: @shg.id,
        shg_member_id: @member.id,
        product_id: @product.id,
        geography_type: "Rural",
        distribution_date: Date.current,
        loan_term_type: "Monthly",
        loan_term: 12,
        principal_amount: 15_000,
        interest_percent: 1.0
      }
    }

    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"
    assert_equal @product, @loan.reload.product
    assert_equal 15_000.to_d, @loan.principal_amount
  end

  test "crp can edit approved shg member and loan while temporary edit access is enabled" do
    @loan.update_columns(product_id: @product.id)
    @shg.update!(
      approval_status: "approved",
      assistant_approved_by: @admin,
      assistant_approved_at: Time.current,
      approved_by: @admin,
      approved_at: Time.current
    )
    login_as(@crp)

    get shgs_path(block_id: @block.id)
    assert_response :success
    assert_select "a[href*='#{edit_shg_path(@shg)}']", text: "Edit"

    get edit_shg_path(@shg, page: 4, block_id: @block.id)
    assert_response :success

    patch shg_path(@shg, page: 4, block_id: @block.id), params: {
      shg: {
        state_id: @state.id,
        district_id: @district.id,
        block_id: @block.id,
        village_id: @village.id,
        name: "Retention SHG CRP Updated",
        office_location: @shg.office_location,
        borrower_short_address: @shg.borrower_short_address,
        linkage_date: @shg.linkage_date,
        active: "1"
      }
    }
    assert_redirected_to "#{shgs_path(page: 4, block_id: @block.id)}#results"
    assert_equal "Retention SHG CRP Updated", @shg.reload.name

    get shg_members_path(block_id: @block.id)
    assert_response :success
    assert_select "a[href*='#{edit_shg_member_path(@member)}']", text: "Edit"

    get edit_shg_member_path(@member, page: 4, block_id: @block.id)
    assert_response :success

    patch shg_member_path(@member, page: 4, block_id: @block.id), params: {
      shg_member: {
        shg_id: @shg.id,
        name: "Retention Member CRP Updated",
        spouse_father_name: @member.spouse_father_name,
        gender: @member.gender,
        dob: @member.dob,
        mobile: @member.mobile,
        monthly_income: @member.monthly_income,
        work_activity: @activity.name,
        aadhaar_no: @member.aadhaar_no,
        active: "1"
      }
    }
    assert_redirected_to "#{shg_members_path(page: 4, block_id: @block.id)}#results"
    assert_equal "Retention Member CRP Updated", @member.reload.name

    get shg_loans_path(block_id: @block.id)
    assert_response :success
    assert_select "a[href*='#{edit_shg_loan_path(@loan)}']", text: "Edit"

    get edit_shg_loan_path(@loan, page: 4, block_id: @block.id)
    assert_response :success

    patch shg_loan_path(@loan, page: 4, block_id: @block.id), params: {
      shg_loan: {
        shg_id: @shg.id,
        shg_member_id: @member.id,
        product_id: @product.id,
        geography_type: "Rural",
        distribution_date: Date.current,
        loan_term_type: "Monthly",
        loan_term: 12,
        principal_amount: 14_000,
        interest_percent: 1.0
      }
    }
    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"
    assert_equal 14_000.to_d, @loan.reload.principal_amount
  end

  private

  def user_for(login_id, user_type, district: @district, block: nil, village: nil)
    User.create!(
      name: "Retention User #{login_id}",
      email: "retention-#{login_id}@example.com",
      login_id: login_id,
      mobile: "98#{login_id}#{SecureRandom.random_number(10**5).to_s.rjust(5, "0")}",
      user_type: user_type,
      state: @state,
      district: district,
      block: block,
      village: village,
      password: "secret123",
      active: true
    )
  end

  def login_as(user)
    post login_path, params: { login_id: user.login_id, password: "secret123" }
    assert_redirected_to dashboard_path
  end
end
