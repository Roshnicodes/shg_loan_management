class OccupationsController < AdminRecordsController
  self.record_class = Occupation
  self.record_title = "Occupation"
  self.record_fields = [
    { name: :name, label: "Occupation Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
