require "csv"

class LocationExportsController < ApplicationController
  before_action :authenticate_user!

  def show
    send_data location_csv,
      filename: "location-master-#{Date.current}.csv",
      type: "text/csv; charset=utf-8"
  end

  private

  def location_csv
    CSV.generate(headers: true) do |csv|
      csv << [ "state", "district", "block", "village" ]

      State.includes(districts: { blocks: :villages }).order(:name).each do |state|
        if state.districts.empty?
          csv << [ state.name, nil, nil, nil ]
          next
        end

        state.districts.sort_by(&:name).each do |district|
          if district.blocks.empty?
            csv << [ state.name, district.name, nil, nil ]
            next
          end

          district.blocks.sort_by(&:name).each do |block|
            if block.villages.empty?
              csv << [ state.name, district.name, block.name, nil ]
              next
            end

            block.villages.sort_by(&:name).each do |village|
              csv << [ state.name, district.name, block.name, village.name ]
            end
          end
        end
      end
    end
  end
end
