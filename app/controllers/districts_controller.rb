class DistrictsController < AdminRecordsController
  self.record_class = District
  self.record_title = "District"
  self.record_fields = [
    { name: :state_id, label: "State", type: :select, collection: -> { State.order(:name) } },
    { name: :name, label: "District Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
