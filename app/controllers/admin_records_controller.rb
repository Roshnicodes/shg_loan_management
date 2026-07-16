class AdminRecordsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_record, only: %i[show edit update destroy]
  before_action :require_manage_permission!, except: %i[index show]

  class_attribute :record_class, :record_fields, :record_title

  def index
    @records = paginate_relation(record_class.order(created_at: :desc))
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
    @record.destroy
    redirect_to polymorphic_path(record_class), notice: "#{record_title} removed successfully."
  end

  private

  def set_record
    @record = record_class.find(params[:id])
  end

  def record_params
    params.require(record_class.model_name.param_key).permit(record_fields.map { |field| field[:name] })
  end
end
