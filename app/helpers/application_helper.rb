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

  def masked_aadhaar(value)
    digits = value.to_s.gsub(/\D/, "")
    return "-" if digits.blank?

    "XXXX-XXXX-#{digits.last(4)}"
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
end
