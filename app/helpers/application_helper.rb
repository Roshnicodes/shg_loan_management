module ApplicationHelper
  def app_nav_items
    items = [ [ "Dashboard", dashboard_path ] ]
    if can_manage_users?
      items += [
        [ "States", states_path ],
        [ "Districts", districts_path ],
        [ "Blocks", blocks_path ],
        [ "Villages", villages_path ],
        [ "User Types", user_types_path ],
        [ "Users", users_path ],
        [ "Loan Status", loan_statuses_path ],
        [ "Products", products_path ]
      ]
    end

    items += [
      [ "SHG Master", shgs_path ],
      [ "SHG Members", shg_members_path ],
      [ "SHG Loans", shg_loans_path ],
      [ "Visits", visit_records_path ],
      [ "Reports", reports_path ]
    ]

    items
  end

  def office_names(names)
    names.present? ? names.join(", ") : "-"
  end

  def district_filter_options(districts)
    districts.map { |district| [ district.name, district.id, { data: { state_id: district.state_id } } ] }
  end

  def block_filter_options(blocks)
    blocks.map { |block| [ block.name, block.id, { data: { district_id: block.district_id, state_id: district_state_ids_by_id[block.district_id] } } ] }
  end

  def village_filter_options(villages)
    villages.map do |village|
      block_id = village.block_id
      district_id = block_district_ids_by_id[block_id]
      [ village.name, village.id, { data: { block_id: block_id, district_id: district_id, state_id: district_state_ids_by_id[district_id] } } ]
    end
  end

  def shg_filter_options(shgs)
    shgs.map do |shg|
      [ shg.display_name, shg.id, { data: {
        state_id: shg.state_id,
        district_id: shg.district_id,
        block_id: shg.block_id,
        village_id: shg.village_id,
        user_ids: Array(@shg_user_ids_by_id&.[](shg.id)).uniq.join(" ")
      } } ]
    end
  end

  def member_filter_options(members)
    members.map do |member|
      [ "#{member.name} / #{member.loan_no.presence || member.id}", member.id, { data: {
        state_id: member.shg.state_id,
        district_id: member.shg.district_id,
        block_id: member.shg.block_id,
        village_id: member.shg.village_id,
        shg_id: member.shg_id,
        user_ids: Array(@member_user_ids_by_id&.[](member.id)).uniq.join(" ")
      } } ]
    end
  end

  def loan_filter_options(loans)
    loans.map do |loan|
      label = "#{loan.shg_member.loan_no.presence || loan.id} / #{loan.shg_member.name}"
      [ label, loan.id, { data: {
        state_id: loan.shg.state_id,
        district_id: loan.shg.district_id,
        block_id: loan.shg.block_id,
        village_id: loan.shg.village_id,
        shg_id: loan.shg_id,
        member_id: loan.shg_member_id,
        user_ids: Array(@loan_user_ids_by_id&.[](loan.id)).uniq.join(" ")
      } } ]
    end
  end

  def user_filter_options(users)
    users.map { |user| [ user.name, user.id, { data: user_location_filter_data(user) } ] }
  end

  def user_location_filter_data(user)
    district_ids = user.office_district_ids.dup
    block_ids = user.office_block_ids.dup
    village_ids = user.office_village_ids.dup

    state_ids = user.office_state_ids.dup
    state_ids += district_ids.filter_map { |id| district_state_ids_by_id[id] }
    state_ids += block_ids.filter_map { |id| block_state_ids_by_id[id] }
    state_ids += village_ids.filter_map { |id| village_state_ids_by_id[id] }

    district_ids += block_ids.filter_map { |id| block_district_ids_by_id[id] }
    district_ids += village_ids.filter_map { |id| village_district_ids_by_id[id] }
    block_ids += village_ids.filter_map { |id| village_block_ids_by_id[id] }

    {
      state_ids: state_ids.uniq.join(" "),
      district_ids: district_ids.uniq.join(" "),
      block_ids: block_ids.uniq.join(" "),
      village_ids: village_ids.uniq.join(" ")
    }
  end

  def district_state_ids_by_id
    @district_state_ids_by_id ||= District.pluck(:id, :state_id).to_h
  end

  def block_district_ids_by_id
    @block_district_ids_by_id ||= Block.pluck(:id, :district_id).to_h
  end

  def village_block_ids_by_id
    @village_block_ids_by_id ||= Village.pluck(:id, :block_id).to_h
  end

  def block_state_ids_by_id
    @block_state_ids_by_id ||= block_district_ids_by_id.transform_values { |district_id| district_state_ids_by_id[district_id] }
  end

  def village_district_ids_by_id
    @village_district_ids_by_id ||= village_block_ids_by_id.transform_values { |block_id| block_district_ids_by_id[block_id] }
  end

  def village_state_ids_by_id
    @village_state_ids_by_id ||= village_district_ids_by_id.transform_values { |district_id| district_state_ids_by_id[district_id] }
  end

  def record_field_value(record, field)
    name = field[:name].to_s
    if name.ends_with?("_id")
      assoc = name.delete_suffix("_id")
      related = record.public_send(assoc)
      related.respond_to?(:display_name) ? related.display_name : related&.name
    elsif field[:type] == :checkbox
      record.public_send(field[:name]) ? "Yes" : "No"
    else
      record.public_send(field[:name])
    end
  end

  def display_emi_status(emi)
    return "Paid" if emi.status == "overdue" || emi.overdue?

    emi.status.to_s.titleize
  end

  def display_emi_status_class(emi)
    return "paid" if emi.status == "overdue" || emi.overdue?

    emi.status
  end

  def display_loan_status_label(value)
    value.to_s.casecmp?("overdue") ? "Paid" : value
  end

  def loan_term_display(loan)
    term = loan.loan_term.to_i
    period =
      case loan.loan_term_type
      when "Monthly" then "Month"
      when "Quarterly" then "Quarter"
      when "Half Yearly" then "Half Year"
      when "Yearly" then "Year"
      else loan.loan_term_type.to_s
      end

    "#{term} #{period.pluralize(term)}"
  end

  def pagination_controls(label = "records")
    return unless defined?(@page) && @page

    first_item = ((@page - 1) * @per_page) + 1
    last_item = @page_item_count.to_i.zero? ? 0 : first_item + @page_item_count.to_i - 1
    summary = if @page_item_count.to_i.zero?
      content_tag(:span, "No #{label} found", class: "pagination-summary")
    elsif @total_count.present?
      content_tag(:span, "Showing #{first_item}-#{last_item} of #{@total_count} #{label}", class: "pagination-summary")
    else
      content_tag(:span, "Showing #{first_item}-#{last_item} #{label}", class: "pagination-summary")
    end

    links = []
    if @page > 1
      links << link_to("Previous", url_for(request.query_parameters.merge(page: @page - 1)), class: "secondary-link compact-button")
    else
      links << content_tag(:span, "Previous", class: "secondary-link compact-button disabled")
    end

    links << content_tag(:span, "Page #{@page}", class: "pagination-page")

    if @has_next_page
      links << link_to("Next", url_for(request.query_parameters.merge(page: @page + 1)), class: "secondary-link compact-button")
    else
      links << content_tag(:span, "Next", class: "secondary-link compact-button disabled")
    end

    content_tag(:div, safe_join([ summary, content_tag(:div, safe_join(links), class: "pagination-links") ]), class: "pagination-bar")
  end

  def server_search_box(path, placeholder:)
    preserved_params = request.query_parameters.except(:q, :page, :commit, :refresh_filters)

    form_with url: path, method: :get, class: "header-search-box server-search-box" do |form|
      fields = preserved_params.map do |key, value|
        hidden_field_tag(key, value)
      end
      fields << content_tag(:span, "Search")
      fields << form.search_field(:q, value: params[:q], placeholder: placeholder)
      fields << form.submit("Search", class: "search-submit")
      safe_join(fields)
    end
  end
end
