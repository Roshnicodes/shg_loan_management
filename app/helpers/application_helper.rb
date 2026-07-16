module ApplicationHelper
  def app_nav_items
    items = [
      [ "Dashboard", dashboard_path ],
      [ "States", states_path ],
      [ "Districts", districts_path ],
      [ "Blocks", blocks_path ],
      [ "Villages", villages_path ],
      [ "Loan Status", loan_statuses_path ],
      [ "Products", products_path ],
      [ "SHG Master", shgs_path ],
      [ "SHG Members", shg_members_path ],
      [ "Visits", visit_records_path ],
      [ "SHG Loans", shg_loans_path ]
    ]

    items.insert(5, [ "User Types", user_types_path ], [ "Users", users_path ]) if can_manage_users?
    items
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
end
