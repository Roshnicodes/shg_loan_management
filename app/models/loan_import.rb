class LoanImport < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze

  belongs_to :user

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc) }

  def running?
    status == "running" || status == "queued"
  end
end
