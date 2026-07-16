# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
state = State.find_or_create_by!(code: "MP") { |s| s.name = "Madhya Pradesh" }
district = District.find_or_create_by!(state: state, code: "BPL") { |d| d.name = "Bhopal" }
block = Block.find_or_create_by!(district: district, code: "PHN") { |b| b.name = "Phanda" }
village = Village.find_or_create_by!(block: block, code: "KHA") { |v| v.name = "Khajuri" }

admin_type = UserType.find_or_create_by!(code: "ADMIN") { |r| r.name = "Admin"; r.level = "state" }
assist_admin_type = UserType.find_or_create_by!(code: "ASSIST_ADMIN") { |r| r.name = "Assistant Admin"; r.level = "state" }
district_coordinator_type = UserType.find_or_create_by!(code: "DIST_COORDINATOR") { |r| r.name = "District Coordinator"; r.level = "district" }
crp_type = UserType.find_or_create_by!(code: "CRP") { |r| r.name = "CRP"; r.level = "village" }

LoanStatus.find_or_create_by!(code: "ACTIVE") { |s| s.name = "Active" }
LoanStatus.find_or_create_by!(code: "CLOSED") { |s| s.name = "Closed" }
LoanStatus.find_or_create_by!(code: "OVERDUE") { |s| s.name = "Overdue" }

[ "Agriculture", "Dairy", "Tailoring", "Small Shop" ].each { |name| Activity.find_or_create_by!(name: name) }
[ "Farmer", "Homemaker", "Vendor", "Artisan" ].each { |name| Occupation.find_or_create_by!(name: name) }
Product.find_or_create_by!(code: "IGL") { |p| p.name = "Income Generation Loan" }
Product.find_or_create_by!(code: "CL") { |p| p.name = "Consumption Loan" }

admin = User.find_or_initialize_by(email: "admin@shg.local")
admin.assign_attributes(
  login_id: "admin",
  name: "System Admin",
  mobile: "9999999999",
  designation: "Administrator",
  user_type: admin_type,
  state: state
)
admin.password = "password" if admin.new_record?
admin.password_confirmation = "password" if admin.new_record?
admin.save!

[
  [ "assistant@shg.local", "assistant", "Assistant Admin", assist_admin_type, state, nil, nil, nil ],
  [ "dc@shg.local", "dc", "District Coordinator", district_coordinator_type, state, district, nil, nil ],
  [ "crp@shg.local", "crp", "CRP User", crp_type, state, district, block, village ]
].each do |email, login_id, name, role, user_state, user_district, user_block, user_village|
  user = User.find_or_initialize_by(email: email)
  user.assign_attributes(
    login_id: login_id,
    name: name,
    mobile: "9999999999",
    designation: role.name,
    user_type: role,
    state: user_state,
    district: user_district,
    block: user_block,
    village: user_village
  )
  user.password = "password" if user.new_record?
  user.password_confirmation = "password" if user.new_record?
  user.save!
end

shg = Shg.find_or_create_by!(name: "Ujjwal Mahila Samuh", village: village) do |group|
  group.state = state
  group.district = district
  group.block = block
  group.linkage_date = Date.current - 1.year
end

ShgMember.find_or_create_by!(shg: shg, name: "Sita Bai") do |member|
  member.occupation = Occupation.find_by!(name: "Farmer")
  member.gender = "Female"
  member.aadhaar_no = "111122223333"
  member.mobile = "9000000001"
  member.address = "Khajuri, Bhopal"
end
