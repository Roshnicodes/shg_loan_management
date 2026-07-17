class ShgLoan < ApplicationRecord
  attr_accessor :manual_import_totals

  belongs_to :shg
  belongs_to :shg_member
  belongs_to :product
  belongs_to :activity
  belongs_to :loan_status
  belongs_to :created_by, class_name: "User"
  has_many :shg_loan_emis, dependent: :destroy

  TERM_TYPES = [ "Monthly", "Quarterly", "Half Yearly", "Yearly" ].freeze
  GEOGRAPHY_TYPES = [ "Rural", "Urban" ].freeze

  before_validation :set_defaults
  before_save :calculate_totals
  after_commit :rebuild_emi_schedule, on: %i[create update], unless: :manual_total_loan?
  after_commit :submit_shg_for_approval, on: :create

  validates :distribution_date, :loan_term_type, :loan_term, presence: true
  validates :geography_type, inclusion: { in: GEOGRAPHY_TYPES }
  validates :loan_term_type, inclusion: { in: TERM_TYPES }
  validates :principal_amount, numericality: { greater_than: 0 }
  validates :interest_percent, numericality: { greater_than_or_equal_to: 0, allow_blank: true }

  def emi_interval_months
    case loan_term_type
    when "Quarterly" then 3
    when "Half Yearly" then 6
    when "Yearly" then 12
    else 1
    end
  end

  def installments_per_year
    12 / emi_interval_months
  end

  def periodic_interest_rate
    return 0.to_d if interest_percent.blank?

    interest_percent.to_d / 100
  end

  def principal_installment_amount
    principal = principal_amount.to_d
    installments = loan_term.to_i
    return 0.to_d if principal <= 0 || installments <= 0

    principal / installments
  end

  def reducing_balance_schedule
    installments = loan_term.to_i
    return [] if installments <= 0

    outstanding = principal_amount.to_d
    principal_emi = principal_installment_amount

    installments.times.map do |index|
      interest = outstanding * periodic_interest_rate
      principal_component = index == installments - 1 ? outstanding : [ principal_emi, outstanding ].min
      due = principal_component + interest
      outstanding -= principal_component

      {
        installment_no: index + 1,
        due_date: distribution_date + ((index + 1) * emi_interval_months).months,
        principal_amount: principal_component.round(2),
        interest_amount: interest.round(2),
        due_amount: due.round(2)
      }
    end
  end

  def equal_installment_schedule
    installments = loan_term.to_i
    return [] if installments <= 0

    total_due = total_payable.to_d.positive? ? total_payable.to_d : principal_amount.to_d + interest_amount.to_d
    principal_total = principal_amount.to_d
    interest_total = [ total_due - principal_total, interest_amount.to_d ].max
    principal_emi = principal_total / installments
    interest_emi = interest_total / installments
    due_emi = total_due / installments
    principal_allocated = 0.to_d
    interest_allocated = 0.to_d
    due_allocated = 0.to_d

    installments.times.map do |index|
      final_installment = index == installments - 1
      principal_component = final_installment ? principal_total - principal_allocated : principal_emi.round(2)
      interest_component = final_installment ? interest_total - interest_allocated : interest_emi.round(2)
      due_amount = final_installment ? total_due - due_allocated : due_emi.round(2)

      principal_allocated += principal_component
      interest_allocated += interest_component
      due_allocated += due_amount

      {
        installment_no: index + 1,
        due_date: distribution_date + ((index + 1) * emi_interval_months).months,
        principal_amount: principal_component.round(2),
        interest_amount: interest_component.round(2),
        due_amount: due_amount.round(2)
      }
    end
  end

  def total_paid
    shg_loan_emis.sum(:paid_amount)
  end

  def cumulative_due_amount(as_of = Date.current)
    shg_loan_emis.to_a.sum { |emi| emi.due_date <= as_of ? emi.due_amount.to_d : 0.to_d }.round(2)
  end

  def cumulative_interest_collected
    shg_loan_emis.to_a.sum { |emi| [ emi.paid_amount.to_d, emi.interest_amount.to_d ].min }.round(2)
  end

  def cumulative_principal_collected
    shg_loan_emis.to_a.sum do |emi|
      interest_paid = [ emi.paid_amount.to_d, emi.interest_amount.to_d ].min
      [ emi.paid_amount.to_d - interest_paid, emi.principal_amount.to_d ].min
    end.round(2)
  end

  def remaining_amount
    total_payable.to_d - total_paid.to_d
  end

  def closed?
    remaining_amount <= 0
  end

  def ensure_emi_schedule!
    rebuild_emi_schedule(preserve_payments: true) if shg_loan_emis.empty? || emi_schedule_outdated?
  end

  def emi_schedule_outdated?
    expected_schedule = expected_emi_schedule
    current_schedule = shg_loan_emis.order(:installment_no).to_a
    return true if expected_schedule.size != current_schedule.size

    expected_schedule.zip(current_schedule).any? do |expected, current|
      current.due_date != expected[:due_date] ||
        current.principal_amount.to_d.round(2) != expected[:principal_amount].to_d.round(2) ||
        current.interest_amount.to_d.round(2) != expected[:interest_amount].to_d.round(2) ||
        current.due_amount.to_d.round(2) != expected[:due_amount].to_d.round(2)
    end
  end

  def manual_total_loan?
    manual_import_totals || source_total_payable.present? || source_interest_amount.present? || interest_percent.blank?
  end

  def expected_emi_schedule
    manual_total_loan? ? equal_installment_schedule : reducing_balance_schedule
  end

  private

  def set_defaults
    self.distribution_date ||= Date.current
    self.loan_status ||= LoanStatus.default_active
  end

  def calculate_totals
    return if manual_total_loan?

    schedule = expected_emi_schedule
    self.interest_amount = schedule.sum { |emi| emi[:interest_amount] }.round(2)
    self.total_payable = schedule.sum { |emi| emi[:due_amount] }.round(2)
  end

  def rebuild_emi_schedule(preserve_payments: false)
    return if loan_term.blank? || loan_term <= 0

    paid_amount = preserve_payments ? total_paid.to_d : 0.to_d
    schedule = expected_emi_schedule
    total_interest = schedule.sum { |emi| emi[:interest_amount] }.round(2)
    total_due = schedule.sum { |emi| emi[:due_amount] }.round(2)

    update_columns(interest_amount: total_interest, total_payable: total_due) if persisted?

    shg_loan_emis.delete_all

    schedule.each do |emi|
      applied_payment = [ paid_amount, emi[:due_amount].to_d ].min
      paid_amount -= applied_payment

      shg_loan_emis.create!(
        installment_no: emi[:installment_no],
        due_date: emi[:due_date],
        principal_amount: emi[:principal_amount],
        interest_amount: emi[:interest_amount],
        due_amount: emi[:due_amount],
        paid_amount: applied_payment,
        paid_on: applied_payment.positive? ? Date.current : nil
      )
    end
  end

  def submit_shg_for_approval
    shg.submit_for_approval!(created_by) if shg&.draft?
  end
end
