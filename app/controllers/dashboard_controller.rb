class DashboardController < ApplicationController
  before_action :authenticate_user!

  def index
    shgs = visible_shgs
    loans = visible_shg_loans
    visits = visible_visit_records
    emis = ShgLoanEmi.where(shg_loan_id: loans.select(:id))

    @summary_counts = {
      "SHG Total" => loans.select(:shg_id).distinct.count,
      "SHG Members" => loans.select(:shg_member_id).count,
      "Total Loan" => helpers.number_to_currency(loans.sum(:principal_amount), unit: "₹"),
      "Collection" => helpers.number_to_currency(emis.sum(:paid_amount), unit: "₹")
    }

    @shg_approval_counts = approval_counts_for(shgs)
    @visit_approval_counts = approval_counts_for(visits)
    @recent_loans = loans.includes(:shg, :shg_member, :loan_status).order(created_at: :desc).limit(8)
  end

  private

  def approval_counts_for(relation)
    table_name = relation.klass.table_name
    returned = relation.where("LOWER(COALESCE(#{table_name}.approval_remarks, '')) LIKE ?", "%returned%")
    counts = relation.group(:approval_status).count

    {
      "Pending at DC" => counts.fetch("pending_dc", 0) - returned.where(approval_status: "pending_dc").count,
      "Pending at Assistant Admin" => counts.fetch("pending_assistant", 0),
      "Approved" => counts.fetch("approved", 0),
      "Rejected" => counts.fetch("rejected", 0),
      "Returned" => returned.count
    }
  end
end
