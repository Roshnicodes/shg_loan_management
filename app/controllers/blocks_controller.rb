class BlocksController < AdminRecordsController
  self.record_class = Block
  self.record_title = "Block"
  self.record_fields = [
    { name: :district_id, label: "District", type: :select, collection: -> { District.includes(:state).order(:name) } },
    { name: :name, label: "Block Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
