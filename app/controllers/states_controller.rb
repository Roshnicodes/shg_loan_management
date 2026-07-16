class StatesController < AdminRecordsController
  self.record_class = State
  self.record_title = "State"
  self.record_fields = [
    { name: :name, label: "State Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
