class VillagesController < AdminRecordsController
  self.record_class = Village
  self.record_title = "Village"
  self.record_fields = [
    { name: :block_id, label: "Block", type: :select, collection: -> { Block.includes(:district).order(:name) } },
    { name: :name, label: "Village Name" },
    { name: :code, label: "Village GS Code", required: false },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
