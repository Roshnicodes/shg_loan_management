require "fileutils"

# Runs a controller's existing export action without a browser request and
# writes its CSV to a file (see ApplicationController#stream_csv).
class DataExportJob < ApplicationJob
  queue_as :default

  # Collects the CSV lines into the file and counts them.
  class FileWriter
    attr_reader :lines

    def initialize(file)
      @file = file
      @lines = 0
    end

    def <<(line)
      @file.write(line)
      @lines += 1
      self
    end
  end

  def perform(export_id)
    export = DataExport.find_by(id: export_id)
    return unless export

    DataExport.clean_up_old!
    export.update!(status: "running", started_at: Time.current)

    FileUtils.mkdir_p(DataExport.directory)
    path = DataExport.directory.join("#{export.id}-#{SecureRandom.hex(8)}.csv").to_s
    controller = build_controller(export)

    File.open(path, "w") do |file|
      writer = FileWriter.new(file)
      controller.instance_variable_set(:@background_export_writer, writer)
      controller.send(export.action_name)
      export.update!(
        status: "completed",
        filename: controller.instance_variable_get(:@background_export_filename) || "#{export.kind}-#{Date.current}.csv",
        file_path: path,
        total_rows: [ writer.lines - 1, 0 ].max,
        finished_at: Time.current
      )
    end
  rescue StandardError => e
    FileUtils.rm_f(path) if path.present?
    DataExport.where(id: export_id).update_all(
      status: "failed",
      error_message: e.message.truncate(1000),
      finished_at: Time.current,
      updated_at: Time.current
    )
    Rails.logger.error("Data export ##{export_id} failed: #{e.class}: #{e.message}")
  end

  private

  def build_controller(export)
    user = export.user
    filters = ActionController::Parameters.new(export.filter_params)
    # A request like the one that asked for the export, for links in the file.
    base = "#{export.request_protocol.presence || "https://"}#{export.request_host.presence || "localhost"}"
    request = ActionDispatch::Request.new(
      Rack::MockRequest.env_for("#{base}/?#{Rack::Utils.build_nested_query(export.filter_params)}")
    )

    controller = export.controller_class.new
    controller.define_singleton_method(:current_user) { user }
    controller.define_singleton_method(:params) { filters }
    controller.define_singleton_method(:request) { request }
    controller
  end
end
