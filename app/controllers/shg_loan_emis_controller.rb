class ShgLoanEmisController < ApplicationController
  before_action :authenticate_user!
  before_action :require_manage_permission!
  before_action :set_loan
  before_action :set_emi

  def pay
    @emi.mark_paid!(params[:paid_amount])
    redirect_to @loan, notice: "EMI payment updated successfully."
  end

  private

  def set_loan
    @loan = visible_shg_loans.find(params[:shg_loan_id])
  end

  def set_emi
    @emi = @loan.shg_loan_emis.find(params[:id])
  end
end
