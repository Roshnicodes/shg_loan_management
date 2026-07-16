class LoanStatusesController < AdminRecordsController
  self.record_class = LoanStatus
  self.record_title = "Loan Status"
  self.record_fields = [
    { name: :name, label: "Status Name" },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
