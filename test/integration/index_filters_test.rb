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

  test "a selected crp or shg narrows the location options above it" do
    crp = User.create!(
      name: "Filter CRP",
      email: "filter-crp@example.com",
      login_id: "252",
      mobile: "9876543252",
      user_type: UserType.create!(name: "Filter CRP Type", code: "CRP", level: "village"),
      state: @state,
      district: @district,
      password: "secret123",
      active: true
    )
    @other_shg.update_columns(created_by_id: crp.id)
    login_as(@admin)

    get location_options_filters_path, params: { crp_id: [ crp.id ] }
    data = JSON.parse(response.body)
    assert_equal [ @other_block.id ], data["blocks"].map { |block| block["id"] }
    assert_equal [ @other_village.id ], data["villages"].map { |village| village["id"] }
    assert_equal [ @other_shg.id ], data["shgs"].map { |shg| shg["id"] }
    assert_equal [ @state.id ], data["states"].map { |state| state["id"] }

    get location_options_filters_path, params: { shg_id: [ @shg.id ] }
    data = JSON.parse(response.body)
    assert_equal [ @block.id ], data["blocks"].map { |block| block["id"] }
    assert_includes data["shgs"].map { |shg| shg["id"] }, @other_shg.id
  end

  test "filter dropdowns have a type to search box" do
    login_as(@admin)

    get shg_loans_path
    assert_select ".multi-select-menu input.multi-select-search[data-multi-filter-target='search']:not([name])"
  end

  test "excel exports show disabled records" do
    @shg.update_columns(active: false)
    login_as(@admin)

    get_export export_shgs_path
    rows = CSV.parse(response.body, headers: true)
    assert_equal "Disabled", rows.find { |row| row["SHG"] == @shg.name }["Record Status"]
    assert_equal "Active", rows.find { |row| row["SHG"] == @other_shg.name }["Record Status"]
  end

  test "every export is prepared in the background and downloaded from the list" do
    login_as(@admin)

    {
      export_shg_loans_path => "Loan Record Status",
      emi_schedule_export_shg_loans_path => "Collection Due Date",
      loan_no_check_export_shg_loans_path => "Loan No",
      export_shg_members_path => "Record Status",
      export_shgs_path => "Record Status",
      export_visit_records_path => "Visit Date",
      export_reports_path => "First Collection Date",
      export_users_path => "Username"
    }.each do |path, header|
      get_export path
      assert_response :success
      assert_includes response.media_type, "csv"
      assert_includes response.body.lines.first, header, path
    end
  end

  test "export button returns at once and the list shows the download" do
    login_as(@admin)

    assert_enqueued_with(job: DataExportJob) { get emi_schedule_export_shg_loans_path, headers: { "Referer" => shg_loans_url } }
    assert_redirected_to shg_loans_url
    follow_redirect!
    assert_select ".data-export-list[data-export-status-running-value='true']", text: /EMI Schedule Excel/
  end

  test "a download belongs only to the user who asked for it" do
    login_as(@admin)
    get_export export_shgs_path
    export = DataExport.order(:id).last

    other = User.create!(
      name: "Other Admin", email: "other-admin@example.com", login_id: "253", mobile: "9876543253",
      user_type: @admin.user_type, state: @state, password: "secret123", active: true
    )
    login_as(other)
    get download_data_export_path(export)
    assert_redirected_to dashboard_path
    assert_not_includes response.media_type.to_s, "csv"
  end

  test "emi schedule excel lists each installment with its collection date" do
    login_as(@admin)

    get_export emi_schedule_export_shg_loans_path
    assert_response :success
    assert_includes response.body.lines.first, "Collection Due Date"
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
