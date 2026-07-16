class UserTypesController < AdminRecordsController
  before_action :require_user_admin_permission!

  self.record_class = UserType
  self.record_title = "User Type"
  self.record_fields = [
    { name: :name, label: "Role Name" },
    { name: :level, label: "Office Level", type: :static_select, options: UserType::LEVELS },
    { name: :active, label: "Active", type: :checkbox }
  ]
end
