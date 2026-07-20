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
      [ "Visits", visit_records_path ],
      [ "SHG Loans", shg_loans_path ]
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
    blocks.map { |block| [ block.name, block.id, { data: { district_id: block.district_id } } ] }
  end

  def village_filter_options(villages)
    villages.map { |village| [ village.name, village.id, { data: { block_id: village.block_id } } ] }
  end

  def user_filter_options(users)
    users.map { |user| [ user.name, user.id, { data: user_location_filter_data(user) } ] }
  end

  def user_location_filter_data(user)
    district_ids = user.office_district_ids
    block_ids = user.office_block_ids
    village_ids = user.office_village_ids

    state_ids = user.office_state_ids
    state_ids += District.where(id: district_ids).pluck(:state_id) if district_ids.present?
    state_ids += Block.joins(:district).where(id: block_ids).pluck("districts.state_id") if block_ids.present?
    state_ids += Village.joins(block: :district).where(id: village_ids).pluck("districts.state_id") if village_ids.present?

    district_ids += Block.where(id: block_ids).pluck(:district_id) if block_ids.present?
    district_ids += Village.joins(:block).where(id: village_ids).pluck("blocks.district_id") if village_ids.present?
    district_ids = District.where(state_id: user.office_state_ids).pluck(:id) if district_ids.blank? && user.office_state_ids.present?

    if block_ids.blank?
      block_ids = village_ids.present? ? Village.where(id: village_ids).pluck(:block_id) : Block.where(district_id: district_ids).pluck(:id)
    end
    village_ids = Village.where(block_id: block_ids).pluck(:id) if village_ids.blank? && block_ids.present?

    {
      state_ids: state_ids.uniq.join(" "),
      district_ids: district_ids.uniq.join(" "),
      block_ids: block_ids.uniq.join(" "),
      village_ids: village_ids.uniq.join(" ")
    }
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
    return unless defined?(@total_count) && @total_count

    first_item = @total_count.zero? ? 0 : ((@page - 1) * @per_page) + 1
    last_item = [ @page * @per_page, @total_count ].min
    summary = content_tag(:span, "Showing #{first_item}-#{last_item} of #{@total_count} #{label}", class: "pagination-summary")

    links = []
    if @page > 1
      links << link_to("Previous", url_for(request.query_parameters.merge(page: @page - 1)), class: "secondary-link compact-button")
    else
      links << content_tag(:span, "Previous", class: "secondary-link compact-button disabled")
    end

    links << content_tag(:span, "Page #{@page} of #{[@total_pages, 1].max}", class: "pagination-page")

    if @total_pages.to_i > @page
      links << link_to("Next", url_for(request.query_parameters.merge(page: @page + 1)), class: "secondary-link compact-button")
    else
      links << content_tag(:span, "Next", class: "secondary-link compact-button disabled")
    end

    content_tag(:div, safe_join([ summary, content_tag(:div, safe_join(links), class: "pagination-links") ]), class: "pagination-bar")
  end

  def server_search_box(path, placeholder:)
    preserved_params = request.query_parameters.except(:q, :page, :commit)

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
