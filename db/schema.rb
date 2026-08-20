# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_20_093000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "activities", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text) gin_trgm_ops", name: "index_activities_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_activities_on_active_and_created_at"
    t.index ["name"], name: "index_activities_on_name"
  end

  create_table "blocks", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.bigint "district_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_blocks_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_blocks_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_blocks_on_active_and_created_at"
    t.index ["district_id", "name"], name: "index_blocks_on_district_id_and_name"
    t.index ["district_id"], name: "index_blocks_on_district_id"
  end

  create_table "districts", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "state_id", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_districts_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_districts_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_districts_on_active_and_created_at"
    t.index ["state_id", "name"], name: "index_districts_on_state_id_and_name"
    t.index ["state_id"], name: "index_districts_on_state_id"
  end

  create_table "loan_imports", force: :cascade do |t|
    t.integer "approved_shgs", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "filename", null: false
    t.datetime "finished_at"
    t.integer "skipped_rows", default: 0, null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.integer "total_loans", default: 0, null: false
    t.integer "total_rows", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status", "created_at"], name: "index_loan_imports_on_status_and_created_at"
    t.index ["user_id"], name: "index_loan_imports_on_user_id"
  end

  create_table "loan_statuses", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_loan_statuses_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_loan_statuses_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_loan_statuses_on_active_and_created_at"
    t.index ["code"], name: "index_loan_statuses_on_code"
    t.index ["name"], name: "index_loan_statuses_on_name"
  end

  create_table "occupations", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text) gin_trgm_ops", name: "index_occupations_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_occupations_on_active_and_created_at"
    t.index ["name"], name: "index_occupations_on_name"
  end

  create_table "products", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_products_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_products_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_products_on_active_and_created_at"
    t.index ["name"], name: "index_products_on_name"
  end

  create_table "shg_loan_emis", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "due_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.date "due_date", null: false
    t.integer "installment_no", null: false
    t.decimal "interest_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "paid_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.date "paid_on"
    t.decimal "principal_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "shg_loan_id", null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["shg_loan_id", "installment_no"], name: "index_shg_loan_emis_on_shg_loan_id_and_installment_no", unique: true
    t.index ["shg_loan_id"], name: "index_shg_loan_emis_on_shg_loan_id"
  end

  create_table "shg_loans", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "activity_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id", null: false
    t.date "distribution_date", null: false
    t.string "geography_type"
    t.decimal "interest_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "interest_percent", precision: 5, scale: 2
    t.bigint "loan_status_id", null: false
    t.integer "loan_term"
    t.string "loan_term_type"
    t.decimal "principal_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "product_id", null: false
    t.bigint "shg_id", null: false
    t.bigint "shg_member_id", null: false
    t.string "source_crp_identifier"
    t.string "source_crp_name"
    t.decimal "source_interest_amount", precision: 12, scale: 2
    t.decimal "source_interest_collect", precision: 12, scale: 2
    t.string "source_loan_status"
    t.decimal "source_paid", precision: 12, scale: 2
    t.decimal "source_principal_collect", precision: 12, scale: 2
    t.decimal "source_remaining", precision: 12, scale: 2
    t.decimal "source_total_payable", precision: 12, scale: 2
    t.decimal "total_payable", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index "lower((source_crp_identifier)::text) gin_trgm_ops", name: "index_shg_loans_on_lower_source_crp_identifier_trgm", using: :gin
    t.index "lower((source_crp_identifier)::text)", name: "index_shg_loans_on_lower_source_crp_identifier"
    t.index "lower((source_crp_name)::text) gin_trgm_ops", name: "index_shg_loans_on_lower_source_crp_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_shg_loans_on_active_and_created_at"
    t.index ["active", "distribution_date", "loan_status_id"], name: "index_shg_loans_on_active_date_status"
    t.index ["active", "distribution_date", "product_id"], name: "index_shg_loans_on_active_date_product"
    t.index ["active", "distribution_date"], name: "index_shg_loans_on_active_and_distribution_date"
    t.index ["active", "loan_status_id"], name: "index_shg_loans_on_active_and_loan_status_id"
    t.index ["active", "product_id"], name: "index_shg_loans_on_active_and_product_id"
    t.index ["active", "shg_id"], name: "index_shg_loans_on_active_and_shg_id"
    t.index ["active", "shg_member_id"], name: "index_shg_loans_on_active_and_shg_member_id"
    t.index ["activity_id"], name: "index_shg_loans_on_activity_id"
    t.index ["created_by_id", "distribution_date"], name: "index_shg_loans_on_created_by_id_and_distribution_date"
    t.index ["created_by_id"], name: "index_shg_loans_on_created_by_id"
    t.index ["distribution_date"], name: "index_shg_loans_on_distribution_date"
    t.index ["loan_status_id", "created_at"], name: "index_shg_loans_on_loan_status_id_and_created_at"
    t.index ["loan_status_id"], name: "index_shg_loans_on_loan_status_id"
    t.index ["product_id", "created_at"], name: "index_shg_loans_on_product_id_and_created_at"
    t.index ["product_id"], name: "index_shg_loans_on_product_id"
    t.index ["shg_id", "distribution_date"], name: "index_shg_loans_on_shg_id_and_distribution_date"
    t.index ["shg_id"], name: "index_shg_loans_on_shg_id"
    t.index ["shg_member_id", "created_at"], name: "index_shg_loans_on_shg_member_id_and_created_at"
    t.index ["shg_member_id"], name: "index_shg_loans_on_shg_member_id"
  end

  create_table "shg_members", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "address"
    t.datetime "created_at", null: false
    t.date "dob"
    t.string "gender"
    t.string "loan_no"
    t.string "mobile"
    t.decimal "monthly_income", precision: 12, scale: 2
    t.string "name", null: false
    t.bigint "occupation_id", null: false
    t.bigint "shg_id", null: false
    t.datetime "updated_at", null: false
    t.index "lower((loan_no)::text) gin_trgm_ops", name: "index_shg_members_on_lower_loan_no_trgm", using: :gin
    t.index "lower((mobile)::text) gin_trgm_ops", name: "index_shg_members_on_lower_mobile_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_shg_members_on_lower_name_trgm", using: :gin
    t.index ["created_at"], name: "index_shg_members_on_created_at"
    t.index ["loan_no"], name: "index_shg_members_on_loan_no", unique: true
    t.index ["occupation_id"], name: "index_shg_members_on_occupation_id"
    t.index ["shg_id", "created_at"], name: "index_shg_members_on_shg_id_and_created_at"
    t.index ["shg_id", "name"], name: "index_shg_members_on_shg_id_and_name"
    t.index ["shg_id"], name: "index_shg_members_on_shg_id"
  end

  create_table "shgs", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "approval_remarks"
    t.string "approval_status", default: "draft", null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "assistant_approved_at"
    t.bigint "assistant_approved_by_id"
    t.bigint "block_id", null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "dc_approved_at"
    t.bigint "dc_approved_by_id"
    t.bigint "district_id", null: false
    t.date "linkage_date"
    t.string "name", null: false
    t.string "shg_code", null: false
    t.bigint "state_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.index "lower((approval_status)::text) gin_trgm_ops", name: "index_shgs_on_lower_approval_status_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_shgs_on_lower_name_trgm", using: :gin
    t.index "lower((shg_code)::text) gin_trgm_ops", name: "index_shgs_on_lower_shg_code_trgm", using: :gin
    t.index ["active", "approval_status", "created_at"], name: "index_shgs_on_active_approval_and_created_at"
    t.index ["active", "created_at"], name: "index_shgs_on_active_and_created_at"
    t.index ["approval_status"], name: "index_shgs_on_approval_status"
    t.index ["approved_by_id"], name: "index_shgs_on_approved_by_id"
    t.index ["assistant_approved_by_id"], name: "index_shgs_on_assistant_approved_by_id"
    t.index ["block_id", "created_at"], name: "index_shgs_on_block_id_and_created_at"
    t.index ["block_id"], name: "index_shgs_on_block_id"
    t.index ["created_by_id", "created_at"], name: "index_shgs_on_created_by_id_and_created_at"
    t.index ["created_by_id"], name: "index_shgs_on_created_by_id"
    t.index ["dc_approved_by_id"], name: "index_shgs_on_dc_approved_by_id"
    t.index ["district_id", "created_at"], name: "index_shgs_on_district_id_and_created_at"
    t.index ["district_id"], name: "index_shgs_on_district_id"
    t.index ["linkage_date", "created_at"], name: "index_shgs_on_linkage_date_and_created_at"
    t.index ["shg_code"], name: "index_shgs_on_shg_code", unique: true
    t.index ["state_id", "created_at"], name: "index_shgs_on_state_id_and_created_at"
    t.index ["state_id"], name: "index_shgs_on_state_id"
    t.index ["village_id", "created_at"], name: "index_shgs_on_village_id_and_created_at"
    t.index ["village_id", "name"], name: "index_shgs_on_village_id_and_name"
    t.index ["village_id"], name: "index_shgs_on_village_id"
  end

  create_table "states", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_states_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_states_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_states_on_active_and_created_at"
    t.index ["code"], name: "index_states_on_code"
    t.index ["name"], name: "index_states_on_name"
  end

  create_table "user_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "level", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_user_types_on_lower_code_trgm", using: :gin
    t.index "lower((level)::text) gin_trgm_ops", name: "index_user_types_on_lower_level_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_user_types_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_user_types_on_active_and_created_at"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "block_id"
    t.datetime "created_at", null: false
    t.string "designation"
    t.bigint "district_id"
    t.string "email", null: false
    t.string "login_id", null: false
    t.integer "mapped_block_ids", default: [], null: false, array: true
    t.integer "mapped_district_ids", default: [], null: false, array: true
    t.integer "mapped_village_ids", default: [], null: false, array: true
    t.string "mobile"
    t.string "name", null: false
    t.string "password_digest", null: false
    t.bigint "state_id"
    t.datetime "updated_at", null: false
    t.bigint "user_type_id", null: false
    t.bigint "village_id"
    t.index "lower((designation)::text) gin_trgm_ops", name: "index_users_on_lower_designation_trgm", using: :gin
    t.index "lower((email)::text) gin_trgm_ops", name: "index_users_on_lower_email_trgm", using: :gin
    t.index "lower((email)::text)", name: "index_active_users_on_lower_email", unique: true, where: "(active = true)"
    t.index "lower((login_id)::text) gin_trgm_ops", name: "index_users_on_lower_login_id_trgm", using: :gin
    t.index "lower((login_id)::text)", name: "index_active_users_on_lower_login_id", unique: true, where: "(active = true)"
    t.index "lower((mobile)::text) gin_trgm_ops", name: "index_users_on_lower_mobile_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_users_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_users_on_active_and_created_at"
    t.index ["block_id"], name: "index_users_on_block_id"
    t.index ["district_id"], name: "index_users_on_district_id"
    t.index ["mapped_block_ids"], name: "index_users_on_mapped_block_ids_gin", using: :gin
    t.index ["mapped_district_ids"], name: "index_users_on_mapped_district_ids_gin", using: :gin
    t.index ["mapped_village_ids"], name: "index_users_on_mapped_village_ids_gin", using: :gin
    t.index ["name"], name: "index_users_on_name"
    t.index ["state_id"], name: "index_users_on_state_id"
    t.index ["user_type_id"], name: "index_users_on_user_type_id"
    t.index ["village_id"], name: "index_users_on_village_id"
  end

  create_table "villages", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.bigint "block_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower((code)::text) gin_trgm_ops", name: "index_villages_on_lower_code_trgm", using: :gin
    t.index "lower((name)::text) gin_trgm_ops", name: "index_villages_on_lower_name_trgm", using: :gin
    t.index ["active", "created_at"], name: "index_villages_on_active_and_created_at"
    t.index ["block_id", "name"], name: "index_villages_on_block_id_and_name"
    t.index ["block_id"], name: "index_villages_on_block_id"
  end

  create_table "visit_records", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.text "approval_remarks"
    t.string "approval_status", default: "pending_dc", null: false
    t.datetime "approved_at"
    t.bigint "approved_by_id"
    t.datetime "assistant_approved_at"
    t.bigint "assistant_approved_by_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.datetime "dc_approved_at"
    t.bigint "dc_approved_by_id"
    t.text "observations"
    t.bigint "product_id"
    t.text "purpose"
    t.bigint "shg_id", null: false
    t.bigint "shg_member_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "village_id", null: false
    t.date "visit_date", null: false
    t.integer "visit_number", default: 1, null: false
    t.index "lower((approval_status)::text) gin_trgm_ops", name: "index_visit_records_on_lower_approval_status_trgm", using: :gin
    t.index "lower(observations) gin_trgm_ops", name: "index_visit_records_on_lower_observations_trgm", using: :gin
    t.index "lower(purpose) gin_trgm_ops", name: "index_visit_records_on_lower_purpose_trgm", using: :gin
    t.index ["active", "approval_status"], name: "index_visit_records_on_active_and_approval_status"
    t.index ["active", "visit_date", "created_at"], name: "index_visit_records_on_active_visit_date_created_at"
    t.index ["approval_status", "visit_date"], name: "index_visit_records_on_approval_status_and_visit_date"
    t.index ["approval_status"], name: "index_visit_records_on_approval_status"
    t.index ["approved_by_id"], name: "index_visit_records_on_approved_by_id"
    t.index ["assistant_approved_by_id"], name: "index_visit_records_on_assistant_approved_by_id"
    t.index ["created_by_id", "visit_date"], name: "index_visit_records_on_created_by_id_and_visit_date"
    t.index ["created_by_id"], name: "index_visit_records_on_created_by_id"
    t.index ["dc_approved_by_id"], name: "index_visit_records_on_dc_approved_by_id"
    t.index ["product_id", "visit_date"], name: "index_visit_records_on_product_id_and_visit_date"
    t.index ["product_id"], name: "index_visit_records_on_product_id"
    t.index ["shg_id", "visit_date"], name: "index_visit_records_on_shg_id_and_visit_date"
    t.index ["shg_id"], name: "index_visit_records_on_shg_id"
    t.index ["shg_member_id"], name: "index_visit_records_on_shg_member_id"
    t.index ["village_id", "visit_date", "created_at"], name: "index_visit_records_on_village_visit_date_created_at"
    t.index ["village_id"], name: "index_visit_records_on_village_id"
    t.index ["visit_date"], name: "index_visit_records_on_visit_date"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "blocks", "districts"
  add_foreign_key "districts", "states"
  add_foreign_key "loan_imports", "users"
  add_foreign_key "shg_loan_emis", "shg_loans"
  add_foreign_key "shg_loans", "activities"
  add_foreign_key "shg_loans", "loan_statuses"
  add_foreign_key "shg_loans", "products"
  add_foreign_key "shg_loans", "shg_members"
  add_foreign_key "shg_loans", "shgs"
  add_foreign_key "shg_loans", "users", column: "created_by_id"
  add_foreign_key "shg_members", "occupations"
  add_foreign_key "shg_members", "shgs"
  add_foreign_key "shgs", "blocks"
  add_foreign_key "shgs", "districts"
  add_foreign_key "shgs", "states"
  add_foreign_key "shgs", "users", column: "approved_by_id"
  add_foreign_key "shgs", "users", column: "assistant_approved_by_id"
  add_foreign_key "shgs", "users", column: "created_by_id"
  add_foreign_key "shgs", "users", column: "dc_approved_by_id"
  add_foreign_key "shgs", "villages"
  add_foreign_key "users", "blocks"
  add_foreign_key "users", "districts"
  add_foreign_key "users", "states"
  add_foreign_key "users", "user_types"
  add_foreign_key "users", "villages"
  add_foreign_key "villages", "blocks"
  add_foreign_key "visit_records", "products"
  add_foreign_key "visit_records", "shg_members"
  add_foreign_key "visit_records", "shgs"
  add_foreign_key "visit_records", "users", column: "approved_by_id"
  add_foreign_key "visit_records", "users", column: "assistant_approved_by_id"
  add_foreign_key "visit_records", "users", column: "created_by_id"
  add_foreign_key "visit_records", "users", column: "dc_approved_by_id"
  add_foreign_key "visit_records", "villages"
end
