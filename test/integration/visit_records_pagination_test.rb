require "test_helper"

class VisitRecordsPaginationTest < ActionDispatch::IntegrationTest
  setup do
    @state = State.create!(name: "Pagination State", code: "PGS")
    @district = District.create!(name: "Pagination District", code: "PGD", state: @state)
    @block = Block.create!(name: "Pagination Block", code: "PGB", district: @district)
    @village = Village.create!(name: "Pagination Village", code: "PGV", block: @block)
    @product = Product.create!(name: "Pagination Product", code: "PGP")
    @occupation = Occupation.create!(name: "Pagination Occupation")
    @dc_type = UserType.create!(name: "Pagination DC", code: "DIST_COORDINATOR", level: "district")
    @assistant_type = UserType.create!(name: "Pagination Assistant", code: "ASSIST_ADMIN", level: "state")
    @dc = build_user("visit_page_dc", @dc_type)
    @assistant = build_user("visit_page_assistant", @assistant_type)
    @shg = Shg.create!(
      name: "Pagination SHG",
      shg_code: "PG-SHG",
      state: @state,
      district: @district,
      block: @block,
      village: @village,
      approval_status: "approved",
      created_by: @dc
    )
    @member = ShgMember.create!(
      shg: @shg,
      occupation: @occupation,
      name: "Pagination Member",
      gender: "Female",
      dob: Date.new(1990, 1, 1),
      mobile: "9876500001",
      monthly_income: 5000,
      address: "Pagination Village"
    )
    @visit = create_visit("pending_dc")
  end

  test "approval keeps visit index page params" do
    login_as(@dc)

    patch approve_visit_record_path(@visit, page: 4, approval_status: "pending_dc", q: "Pagination")

    assert_redirected_to visit_records_path(page: 4, approval_status: "pending_dc", q: "Pagination")
  end

  test "update keeps visit index page params" do
    login_as(@dc)

    patch visit_record_path(@visit, page: 3, block_id: @block.id), params: {
      visit_record: {
        block_id: @block.id,
        village_id: @village.id,
        shg_id: @shg.id,
        shg_member_id: @member.id,
        product_id: @product.id,
        visit_date: Date.current,
        purpose: "Updated purpose",
        observations: "Updated observation"
      }
    }

    assert_redirected_to visit_records_path(page: 3, block_id: @block.id)
  end

  test "disable keeps visit index page params" do
    login_as(@assistant)
    visit = create_visit("pending_assistant")

    patch disable_visit_record_path(visit, page: 2, month: "2026-08")

    assert_redirected_to visit_records_path(page: 2, month: "2026-08")
  end

  test "duplicate visit submit reuses existing record" do
    login_as(@dc)

    assert_no_difference -> { VisitRecord.count } do
      post visit_records_path, params: {
        visit_record: {
          block_id: @block.id,
          village_id: @village.id,
          shg_id: @shg.id,
          shg_member_id: @member.id,
          product_id: @product.id,
          visit_date: @visit.visit_date,
          purpose: "Pagination check",
          observations: "Keep page params"
        }
      }
    end

    assert_redirected_to visit_records_path
    assert_equal 1, @visit.reload.visit_number
  end

  test "second visit updates existing record and increments visit number" do
    login_as(@dc)

    assert_no_difference -> { VisitRecord.count } do
      post visit_records_path, params: {
        visit_record: {
          block_id: @block.id,
          village_id: @village.id,
          shg_id: @shg.id,
          shg_member_id: @member.id,
          product_id: @product.id,
          visit_date: @visit.visit_date + 1.day,
          purpose: "Second visit",
          observations: "Updated on second visit"
        }
      }
    end

    @visit.reload
    assert_redirected_to visit_records_path
    assert_equal 2, @visit.visit_number
    assert_equal "Second visit", @visit.purpose
    assert_equal "Updated on second visit", @visit.observations
  end

  private

  def build_user(login_id, user_type)
    User.new(
      name: login_id.titleize,
      email: "#{login_id}@example.com",
      login_id: login_id,
      mobile: "98765#{rand(10000..99999)}",
      designation: user_type.name,
      user_type: user_type,
      state: @state,
      district: @district,
      password: "password",
      password_confirmation: "password",
      active: true
    ).tap { |user| user.save!(validate: false) }
  end

  def create_visit(status)
    VisitRecord.create!(
      village: @village,
      shg: @shg,
      shg_member: @member,
      product: @product,
      visit_date: Date.current,
      purpose: "Pagination check",
      observations: "Keep page params",
      approval_status: status,
      created_by: @dc
    )
  end

  def login_as(user)
    post login_path, params: { login_id: user.login_id, password: "password" }
    assert_redirected_to dashboard_path
  end
end
