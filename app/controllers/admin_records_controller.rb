class AdminRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :require_user_admin_permission!
  before_action :set_record, only: %i[show edit update destroy disable]
  before_action :require_create_permission!, only: %i[new create]
  before_action :require_manage_permission!, except: %i[index show]
  before_action :require_bulk_delete_permission!, only: :destroy

  class_attribute :record_class, :record_fields, :record_title

  def index
    @records = paginate_relation(searched_records.order(created_at: :desc))
    render "admin_records/index"
  end

  def show
    render "admin_records/show"
  end

  def new
    @record = record_class.new(active: true)
    render "admin_records/form"
  end

  def create
    @record = record_class.new(record_params)
    if @record.save
      redirect_to polymorphic_path(record_class), notice: "#{record_title} saved successfully."
    else
      render "admin_records/form", status: :unprocessable_entity
    end
  end

  def edit
    render "admin_records/form"
  end

  def update
    if @record.update(record_params)
      redirect_to polymorphic_path(record_class), notice: "#{record_title} updated successfully."
    else
      render "admin_records/form", status: :unprocessable_entity
    end
  end

  def destroy
    disable
  end

  def disable
    @record.update!(active: false)
    redirect_to polymorphic_path(record_class), notice: "#{record_title} disabled successfully."
  end

  private

  def searched_records
    records = record_class.all
    query = params[:q].to_s.strip
    return records if query.blank?

    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query.downcase)}%"
    clauses = [ "CAST(#{record_class.table_name}.id AS TEXT) ILIKE :query" ]
    searchable_columns.each do |column|
      clauses << "LOWER(COALESCE(#{record_class.table_name}.#{column}, '')) LIKE :query"
    end

    records.where(clauses.join(" OR "), query: pattern)
  end

  def searchable_columns
    record_fields.filter_map do |field|
      column = field[:name].to_s
      column if record_class.columns_hash[column]&.type.in?(%i[string text])
    end
  end

  def set_record
    @record = record_class.find(params[:id])
  end

  def record_params
    params.require(record_class.model_name.param_key).permit(record_fields.map { |field| field[:name] })
  end
end
