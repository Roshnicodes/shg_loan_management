require "fileutils"

# An Excel/CSV download built in the background by DataExportJob, so the
# browser never waits on one long request (which nginx cut off with a 504).
# Files live in tmp/data_exports for a day.
class DataExport < ApplicationRecord
  STATUSES = %w[queued running completed failed].freeze
  KEEP_FOR = 1.day

  # kind => [controller, action, label]
  KINDS = {
    "loans" => [ "ShgLoansController", :export, "Loans Export CSV" ],
    "emi_schedule" => [ "ShgLoansController", :emi_schedule_export, "EMI Schedule Excel" ],
    "loan_no_check" => [ "ShgLoansController", :loan_no_check_export, "Loan No Check Excel" ],
    "members" => [ "ShgMembersController", :export, "SHG Members Export" ],
    "shgs" => [ "ShgsController", :export, "SHG Export" ],
    "visits" => [ "VisitRecordsController", :export, "Visits Export" ],
    "reports" => [ "ReportsController", :export, "Loan Report Excel" ],
    "users" => [ "UsersController", :export, "Users Export" ]
  }.freeze

  belongs_to :user

  validates :status, inclusion: { in: STATUSES }
  validates :kind, inclusion: { in: KINDS.keys }

  scope :recent, -> { order(created_at: :desc) }

  def self.directory
    Rails.root.join("tmp", "data_exports")
  end

  # Removes exports older than KEEP_FOR together with their files.
  def self.clean_up_old!
    where(created_at: ...KEEP_FOR.ago).find_each do |export|
      FileUtils.rm_f(export.file_path) if export.file_path.present?
      export.destroy
    end
  end

  def controller_class = KINDS.fetch(kind).first.constantize
  def action_name = KINDS.fetch(kind).second
  def label = KINDS.fetch(kind).third

  def running?
    status == "queued" || status == "running"
  end

  def downloadable?
    status == "completed" && file_path.present? && File.exist?(file_path)
  end
end
