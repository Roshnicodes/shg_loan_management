require "fileutils"

class LoanImportJob < ApplicationJob
  queue_as :default

  def perform(import_id, path, filename, user_id)
    import = LoanImport.find(import_id)
    import.update!(status: "running", started_at: Time.current)

    file = Struct.new(:path, :original_filename).new(path, filename)
    controller = ShgLoansController.new
    controller.define_singleton_method(:current_user) { User.find(user_id) }
    result = controller.send(:import_loans, file, progress_import: import)

    import.update!(
      status: "completed",
      total_rows: result[:rows],
      total_loans: result[:loans],
      approved_shgs: result[:approved_shgs],
      skipped_rows: result[:skipped],
      error_message: result[:errors].join(" | ").presence,
      finished_at: Time.current
    )
  rescue StandardError => e
    LoanImport.where(id: import_id).update_all(
      status: "failed",
      error_message: e.message.truncate(1000),
      finished_at: Time.current,
      updated_at: Time.current
    )
    Rails.logger.error("Loan import ##{import_id} failed: #{e.class}: #{e.message}")
    raise
  ensure
    FileUtils.rm_f(path) if path.present?
  end
end
