class DataExportsController < ApplicationController
  before_action :authenticate_user!

  # The Downloads list on an index page; reloaded while a file is being built.
  def index
    render partial: "shared/data_exports", locals: { kinds: requested_kinds }
  end

  def download
    export = DataExport.where(user: current_user).find(params[:id])
    unless export.downloadable?
      return redirect_back fallback_location: dashboard_path, alert: "This download is not ready or has expired. Please export again."
    end

    send_file export.file_path, filename: export.filename, type: "text/csv", disposition: "attachment"
  end

  private

  def requested_kinds
    Array(params[:kinds]).map(&:to_s) & DataExport::KINDS.keys
  end
end
