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
