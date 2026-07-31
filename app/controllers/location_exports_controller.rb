require "csv"

class LocationExportsController < ApplicationController
  before_action :authenticate_user!

  def show
    stream_csv("location-master-#{Date.current}.csv") do |stream|
      stream << CSV.generate_line([ "state", "district", "block", "village" ])

      State.includes(districts: { blocks: :villages }).order(:name).each do |state|
        if state.districts.empty?
          stream << CSV.generate_line([ state.name, nil, nil, nil ])
          next
        end

        state.districts.sort_by(&:name).each do |district|
          if district.blocks.empty?
            stream << CSV.generate_line([ state.name, district.name, nil, nil ])
            next
          end

          district.blocks.sort_by(&:name).each do |block|
            if block.villages.empty?
              stream << CSV.generate_line([ state.name, district.name, block.name, nil ])
              next
            end

            block.villages.sort_by(&:name).each do |village|
              stream << CSV.generate_line([ state.name, district.name, block.name, village.name ])
            end
          end
        end
      end
    end
  end
end
