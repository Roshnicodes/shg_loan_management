require "csv"

class LocationImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_manage_permission!

  def new; end

  def create
    file = params[:file]
    return redirect_to(new_location_import_path, alert: "Please select a CSV file.") unless file.present?

    result = import_locations(file)
    redirect_to villages_path, notice: "Location import completed. Rows: #{result[:rows]}, created/updated records: #{result[:records]}."
  rescue CSV::MalformedCSVError
    redirect_to new_location_import_path, alert: "Uploaded file is not a valid CSV file."
  rescue ActiveRecord::RecordInvalid => e
    redirect_to new_location_import_path, alert: e.record.errors.full_messages.to_sentence
  end

  private

  def import_locations(file)
    rows = 0
    records = 0

    CSV.foreach(file.path, headers: true, encoding: "bom|utf-8") do |row|
      attrs = normalized_row(row)
      next if attrs.values.all?(&:blank?)

      rows += 1
      state = find_or_create_state(attrs.fetch(:state))
      records += 1 if state.previously_new_record?

      next if attrs[:district].blank?

      district = District.find_or_create_by!(state: state, name: attrs[:district])
      records += 1 if district.previously_new_record?

      next if attrs[:block].blank?

      block = Block.find_or_create_by!(district: district, name: attrs[:block])
      records += 1 if block.previously_new_record?

      next if attrs[:village].blank?

      village = Village.find_or_create_by!(block: block, name: attrs[:village])
      records += 1 if village.previously_new_record?
    end

    { rows: rows, records: records }
  end

  def normalized_row(row)
    {
      state: value_for(row, "state", "state name"),
      district: value_for(row, "district", "district name"),
      block: value_for(row, "block", "block name"),
      village: value_for(row, "village", "village name")
    }
  end

  def value_for(row, *keys)
    keys.lazy.map { |key| row[key] || row[key.titleize] || row[key.upcase] }.find(&:present?).to_s.strip
  end

  def find_or_create_state(name)
    raise ActiveRecord::RecordInvalid.new(State.new.tap { |state| state.errors.add(:name, "is required") }) if name.blank?

    State.find_or_create_by!(name: name)
  end
end
