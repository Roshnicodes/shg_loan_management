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
      linkage_date: Date.current,
      approval_status: "pending_dc",
      created_by: @crp
    )
    attach_required_shg_files(@shg)
    @shg.save!

    @member = ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      name: "Retention Member",
      gender: "Female",
      dob: Date.new(1992, 2, 2),
      mobile: "9876500211",
      monthly_income: 6500,
      address: "Retention Village"
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
        gender: "Female",
        dob: @member.dob,
        mobile: @member.mobile,
        monthly_income: @member.monthly_income,
        address: @member.address,
        active: "1"
      }
    }

    assert_redirected_to "#{shg_members_path(page: 4, block_id: @block.id)}#results"
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
          gender: "Female",
          dob: Date.new(1993, 3, 3),
          mobile: "9876500999",
          monthly_income: "7200",
          address: "Shared member address",
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
    assert_equal "Shared member address", redirect_params.dig("shg_member", "address")

    follow_redirect!

    assert_response :success
    assert_select "select[name='shg_member[block_id]'] option[selected='selected'][value='#{@block.id}']"
    assert_select "select[name='shg_member[village_id]'] option[selected='selected'][value='#{@village.id}']"
    assert_select "select[name='shg_member[shg_id]'] option[selected='selected'][value='#{@shg.id}']"
    assert_select "select[name='shg_member[gender]'] option[selected='selected']", text: "Female"
    assert_select "textarea[name='shg_member[address]']", text: "Shared member address"
    assert_select "input[name='shg_member[name]'][value='Carry Forward Member']", false
    assert_select "input[name='shg_member[mobile]'][value='9876500999']", false
    assert_select "input[name='shg_member[dob]'][value='1993-03-03']", false
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

  test "loan cannot be edited after assistant admin approval" do
    @loan.update_columns(product_id: @product.id)
    @shg.update!(
      approval_status: "approved",
      assistant_approved_by: @admin,
      assistant_approved_at: Time.current,
      approved_by: @admin,
      approved_at: Time.current
    )
    login_as(@dc)

    get edit_shg_loan_path(@loan, page: 4, block_id: @block.id)

    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"

    patch shg_loan_path(@loan, page: 4, block_id: @block.id), params: {
      shg_loan: {
        shg_id: @shg.id,
        shg_member_id: @member.id,
        product_id: nil,
        geography_type: "Rural",
        distribution_date: Date.current,
        loan_term_type: "Monthly",
        loan_term: 12,
        principal_amount: 12_000,
        interest_percent: 1.0
      }
    }

    assert_redirected_to "#{shg_loans_path(page: 4, block_id: @block.id)}#results"
    assert_equal @product, @loan.reload.product
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
