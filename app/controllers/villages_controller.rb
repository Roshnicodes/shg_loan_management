class VillagesController < AdminRecordsController
  self.record_class = Village
  self.record_title = "Village"
  self.record_fields = [
    { name: :block_id, label: "Block", type: :select, collection: -> { Block.includes(:district).order(:name) } },
    { name: :name, label: "Village Name" },
    { name: :code, label: "Village GS Code", required: false },
    { name: :active, label: "Active", type: :checkbox }
  ]

  def create
    return super unless bulk_village_rows_submitted?

    @record = Village.new(active: bulk_village_active?)
    block = selected_bulk_block
    rows = bulk_village_rows

    unless block
      @record.errors.add(:block, "must be selected")
      return render "admin_records/form", status: :unprocessable_entity
    end

    unless selected_bulk_location_matches?(block)
      @record.errors.add(:block, "does not match selected state and district")
      return render "admin_records/form", status: :unprocessable_entity
    end

    if rows.blank?
      @record.errors.add(:name, "must be entered")
      return render "admin_records/form", status: :unprocessable_entity
    end

    created_count = 0
    Village.transaction do
      rows.each do |row|
        Village.create!(block: block, name: row.fetch(:name), code: row[:code].presence, active: bulk_village_active?)
        created_count += 1
      end
    end

    redirect_to villages_path, notice: "Villages saved successfully: #{created_count}."
  rescue ActiveRecord::RecordInvalid => e
    @record = e.record
    render "admin_records/form", status: :unprocessable_entity
  end

  private

  def bulk_village_params
    @bulk_village_params ||= params.fetch(:village, ActionController::Parameters.new).permit(:state_id, :district_id, :block_id, :active, bulk_rows: %i[name code])
  end

  def bulk_village_rows_submitted?
    params.dig(:village, :bulk_rows).present?
  end

  def bulk_village_rows
    @bulk_village_rows ||= Array(bulk_village_params[:bulk_rows]).filter_map do |row|
      attrs = row.to_h.symbolize_keys
      name = attrs[:name].to_s.squish
      next if name.blank?

      { name: name, code: attrs[:code].to_s.squish }
    end
  end

  def bulk_village_active?
    ActiveModel::Type::Boolean.new.cast(bulk_village_params.fetch(:active, true))
  end

  def selected_bulk_block
    @selected_bulk_block ||= Block.includes(district: :state).find_by(id: bulk_village_params[:block_id])
  end

  def selected_bulk_location_matches?(block)
    selected_district_id = bulk_village_params[:district_id].presence
    selected_state_id = bulk_village_params[:state_id].presence
    return false if selected_district_id.present? && block.district_id.to_s != selected_district_id.to_s
    return false if selected_state_id.present? && block.district.state_id.to_s != selected_state_id.to_s

    true
  end
end
