class ShgLoanEmi < ApplicationRecord
  belongs_to :shg_loan

  STATUSES = [ "pending", "paid", "overdue" ].freeze

  validates :installment_no, :due_date, presence: true
  validates :due_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :paid_amount, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }

  before_save :sync_status
  after_commit :sync_loan_status, on: %i[create update]

  def remaining_amount
    due_amount.to_d - paid_amount.to_d
  end

  def overdue?
    remaining_amount.positive? && due_date < Date.current
  end

  def mark_paid!(amount = nil)
    payment = amount.presence ? amount.to_d : remaining_amount
    update!(paid_amount: [ paid_amount.to_d + payment, due_amount.to_d ].min, paid_on: Date.current)
  end

  private

  def sync_status
    self.status =
      if remaining_amount <= 0
        "paid"
      elsif due_date < Date.current
        "overdue"
      else
        "pending"
      end
  end

  def sync_loan_status
    loan = shg_loan
    return if loan.destroyed?

    status =
      if loan.closed?
        LoanStatus.find_by(code: "CLOSED")
      elsif loan.shg_loan_emis.any?(&:overdue?)
        LoanStatus.find_by(code: "OVERDUE")
      else
        LoanStatus.default_active
      end

    loan.update_column(:loan_status_id, status.id) if status && loan.loan_status_id != status.id
  end
end
