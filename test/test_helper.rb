ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    # Add more helper methods to be used by all tests here...
    def attach_required_shg_files(shg)
      shg.meeting_register.attach(
        io: StringIO.new("meeting register"),
        filename: "meeting-register.pdf",
        content_type: "application/pdf"
      )
      shg.meeting_photo.attach(
        io: StringIO.new("meeting photo"),
        filename: "meeting-photo.jpg",
        content_type: "image/jpeg"
      )
    end
  end
end

module DataExportTestHelper
  include ActiveJob::TestHelper

  # Clicks an export button, runs the background job, and downloads the file,
  # leaving the CSV in response.body.
  def get_export(path)
    perform_enqueued_jobs(only: DataExportJob) { get path }
    assert_response :redirect
    export = DataExport.order(:id).last
    assert_equal "completed", export.status, export.error_message
    get download_data_export_path(export)
  end
end

class ActionDispatch::IntegrationTest
  include DataExportTestHelper
end
