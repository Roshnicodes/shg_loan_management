require "test_helper"

class IndexFiltersTest < ActionDispatch::IntegrationTest
  setup do
    @state = State.create!(name: "Filter State", code: "FLS")
    @district = District.create!(name: "Filter District", code: "FLD", state: @state)
    @block = Block.create!(name: "Filter Block", code: "FLB", district: @district)
    @other_block = Block.create!(name: "Other Filter Block", code: "OFB", district: @district)
    @village = Village.create!(name: "Filter Village", code: "FLV", block: @block)
    @other_village = Village.create!(name: "Other Filter Village", code: "OFV", block: @other_block)
    @shg = build_shg("Filter SHG", "FL-SHG", @block, @village)
    @other_shg = build_shg("Other Filter SHG", "OFL-SHG", @other_block, @other_village)

    admin_type = UserType.create!(name: "Filter Admin", code: "ADMIN", level: "state")
    @admin = User.create!(
      name: "Filter Admin",
      email: "filter-admin@example.com",
      login_id: "251",
      mobile: "9876543251",
      user_type: admin_type,
      state: @state,
      password: "secret123",
      active: true
    )
  end

  test "filter options endpoint returns child options for the selected parents" do
    login_as(@admin)

    get location_options_filters_path, params: { block_id: [ @block.id ] }
    assert_response :success

    data = JSON.parse(response.body)
    village_ids = data["villages"].map { |village| village["id"] }
    shg_ids = data["shgs"].map { |shg| shg["id"] }

    assert_includes village_ids, @village.id
    assert_not_includes village_ids, @other_village.id
    assert_includes shg_ids, @shg.id
    assert_not_includes shg_ids, @other_shg.id
    assert_equal @block.id, data["villages"].find { |village| village["id"] == @village.id }["block_id"]
    assert_includes data["blocks"].map { |block| block["id"] }, @other_block.id
  end

  test "index pages show the search box inside the filter form" do
    login_as(@admin)

    [ shg_loans_path, shg_members_path, shgs_path, visit_records_path ].each do |path|
      get path, params: { q: "Filter", block_id: [ @block.id ] }
      assert_response :success
      assert_select "form.filter-grid[data-location-select-filter-remote-value='true'] input[type='search'][name='q'][value='Filter']"
      assert_select "form.server-search-box", false
    end
  end

  private

  def build_shg(name, code, block, village)
    shg = Shg.new(
      name: name,
      shg_code: code,
      state: @state,
      district: @district,
      block: block,
      village: village,
      office_location: "#{name} Office",
      borrower_short_address: village.name,
      linkage_date: Date.current,
      approval_status: "approved",
      active: true
    )
    attach_required_shg_files(shg)
    shg.save!
    shg
  end

  def login_as(user)
    post login_path, params: { login_id: user.login_id, password: "secret123" }
    assert_redirected_to dashboard_path
  end
end
