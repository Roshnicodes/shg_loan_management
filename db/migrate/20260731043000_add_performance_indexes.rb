class AddPerformanceIndexes < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    enable_extension "pg_trgm" unless extension_enabled?("pg_trgm")

    add_btree_index :shgs, [ :active, :created_at ], name: "index_shgs_on_active_and_created_at"
    add_btree_index :shgs, [ :active, :approval_status, :created_at ], name: "index_shgs_on_active_approval_and_created_at"
    add_btree_index :shgs, [ :linkage_date, :created_at ], name: "index_shgs_on_linkage_date_and_created_at"
    add_btree_index :shgs, [ :state_id, :created_at ], name: "index_shgs_on_state_id_and_created_at"
    add_btree_index :shgs, [ :district_id, :created_at ], name: "index_shgs_on_district_id_and_created_at"
    add_btree_index :shgs, [ :block_id, :created_at ], name: "index_shgs_on_block_id_and_created_at"
    add_btree_index :shgs, [ :village_id, :created_at ], name: "index_shgs_on_village_id_and_created_at"
    add_btree_index :shgs, [ :created_by_id, :created_at ], name: "index_shgs_on_created_by_id_and_created_at"

    add_btree_index :shg_members, [ :created_at ], name: "index_shg_members_on_created_at"
    add_btree_index :shg_members, [ :shg_id, :created_at ], name: "index_shg_members_on_shg_id_and_created_at"

    add_btree_index :shg_loans, [ :active, :created_at ], name: "index_shg_loans_on_active_and_created_at"
    add_btree_index :shg_loans, [ :active, :distribution_date ], name: "index_shg_loans_on_active_and_distribution_date"
    add_btree_index :shg_loans, [ :active, :shg_id ], name: "index_shg_loans_on_active_and_shg_id"
    add_btree_index :shg_loans, [ :active, :shg_member_id ], name: "index_shg_loans_on_active_and_shg_member_id"
    add_btree_index :shg_loans, [ :active, :loan_status_id ], name: "index_shg_loans_on_active_and_loan_status_id"
    add_btree_index :shg_loans, [ :active, :product_id ], name: "index_shg_loans_on_active_and_product_id"
    add_btree_index :shg_loans, [ :active, :distribution_date, :loan_status_id ], name: "index_shg_loans_on_active_date_status"
    add_btree_index :shg_loans, [ :active, :distribution_date, :product_id ], name: "index_shg_loans_on_active_date_product"
    add_btree_index :shg_loans, [ :loan_status_id, :created_at ], name: "index_shg_loans_on_loan_status_id_and_created_at"
    add_btree_index :shg_loans, [ :product_id, :created_at ], name: "index_shg_loans_on_product_id_and_created_at"
    add_btree_index :shg_loans, [ :shg_member_id, :created_at ], name: "index_shg_loans_on_shg_member_id_and_created_at"

    add_btree_index :visit_records, [ :active, :visit_date, :created_at ], name: "index_visit_records_on_active_visit_date_created_at"
    add_btree_index :visit_records, [ :active, :approval_status ], name: "index_visit_records_on_active_and_approval_status"
    add_btree_index :visit_records, [ :village_id, :visit_date, :created_at ], name: "index_visit_records_on_village_visit_date_created_at"
    add_btree_index :visit_records, [ :product_id, :visit_date ], name: "index_visit_records_on_product_id_and_visit_date"
    add_btree_index :states, [ :active, :created_at ], name: "index_states_on_active_and_created_at"
    add_btree_index :districts, [ :active, :created_at ], name: "index_districts_on_active_and_created_at"
    add_btree_index :blocks, [ :active, :created_at ], name: "index_blocks_on_active_and_created_at"
    add_btree_index :villages, [ :active, :created_at ], name: "index_villages_on_active_and_created_at"
    add_btree_index :user_types, [ :active, :created_at ], name: "index_user_types_on_active_and_created_at"
    add_btree_index :users, [ :active, :created_at ], name: "index_users_on_active_and_created_at"
    add_btree_index :activities, [ :active, :created_at ], name: "index_activities_on_active_and_created_at"
    add_btree_index :occupations, [ :active, :created_at ], name: "index_occupations_on_active_and_created_at"
    add_btree_index :products, [ :active, :created_at ], name: "index_products_on_active_and_created_at"
    add_btree_index :loan_statuses, [ :active, :created_at ], name: "index_loan_statuses_on_active_and_created_at"
    add_array_gin_index :users, :mapped_district_ids, "index_users_on_mapped_district_ids_gin"
    add_array_gin_index :users, :mapped_block_ids, "index_users_on_mapped_block_ids_gin"
    add_array_gin_index :users, :mapped_village_ids, "index_users_on_mapped_village_ids_gin"

    add_trgm_index :states, "LOWER(name)", "index_states_on_lower_name_trgm"
    add_trgm_index :states, "LOWER(code)", "index_states_on_lower_code_trgm"
    add_trgm_index :districts, "LOWER(name)", "index_districts_on_lower_name_trgm"
    add_trgm_index :districts, "LOWER(code)", "index_districts_on_lower_code_trgm"
    add_trgm_index :blocks, "LOWER(name)", "index_blocks_on_lower_name_trgm"
    add_trgm_index :blocks, "LOWER(code)", "index_blocks_on_lower_code_trgm"
    add_trgm_index :villages, "LOWER(name)", "index_villages_on_lower_name_trgm"
    add_trgm_index :villages, "LOWER(code)", "index_villages_on_lower_code_trgm"
    add_trgm_index :user_types, "LOWER(name)", "index_user_types_on_lower_name_trgm"
    add_trgm_index :user_types, "LOWER(code)", "index_user_types_on_lower_code_trgm"
    add_trgm_index :user_types, "LOWER(level)", "index_user_types_on_lower_level_trgm"
    add_trgm_index :activities, "LOWER(name)", "index_activities_on_lower_name_trgm"
    add_trgm_index :occupations, "LOWER(name)", "index_occupations_on_lower_name_trgm"
    add_trgm_index :shgs, "LOWER(name)", "index_shgs_on_lower_name_trgm"
    add_trgm_index :shgs, "LOWER(shg_code)", "index_shgs_on_lower_shg_code_trgm"
    add_trgm_index :shgs, "LOWER(approval_status)", "index_shgs_on_lower_approval_status_trgm"
    add_trgm_index :shg_members, "LOWER(name)", "index_shg_members_on_lower_name_trgm"
    add_trgm_index :shg_members, "LOWER(loan_no)", "index_shg_members_on_lower_loan_no_trgm"
    add_trgm_index :shg_members, "LOWER(mobile)", "index_shg_members_on_lower_mobile_trgm"
    add_trgm_index :users, "LOWER(name)", "index_users_on_lower_name_trgm"
    add_trgm_index :users, "LOWER(login_id)", "index_users_on_lower_login_id_trgm"
    add_trgm_index :users, "LOWER(email)", "index_users_on_lower_email_trgm"
    add_trgm_index :users, "LOWER(mobile)", "index_users_on_lower_mobile_trgm"
    add_trgm_index :users, "LOWER(designation)", "index_users_on_lower_designation_trgm"
    add_trgm_index :products, "LOWER(name)", "index_products_on_lower_name_trgm"
    add_trgm_index :products, "LOWER(code)", "index_products_on_lower_code_trgm"
    add_trgm_index :loan_statuses, "LOWER(name)", "index_loan_statuses_on_lower_name_trgm"
    add_trgm_index :loan_statuses, "LOWER(code)", "index_loan_statuses_on_lower_code_trgm"
    add_trgm_index :shg_loans, "LOWER(source_crp_identifier)", "index_shg_loans_on_lower_source_crp_identifier_trgm"
    add_trgm_index :shg_loans, "LOWER(source_crp_name)", "index_shg_loans_on_lower_source_crp_name_trgm"
    add_trgm_index :visit_records, "LOWER(purpose)", "index_visit_records_on_lower_purpose_trgm"
    add_trgm_index :visit_records, "LOWER(observations)", "index_visit_records_on_lower_observations_trgm"
    add_trgm_index :visit_records, "LOWER(approval_status)", "index_visit_records_on_lower_approval_status_trgm"
  end

  def down
    [
      "index_visit_records_on_lower_approval_status_trgm",
      "index_visit_records_on_lower_observations_trgm",
      "index_visit_records_on_lower_purpose_trgm",
      "index_shg_loans_on_lower_source_crp_name_trgm",
      "index_shg_loans_on_lower_source_crp_identifier_trgm",
      "index_loan_statuses_on_lower_code_trgm",
      "index_loan_statuses_on_lower_name_trgm",
      "index_products_on_lower_code_trgm",
      "index_products_on_lower_name_trgm",
      "index_users_on_lower_designation_trgm",
      "index_users_on_lower_mobile_trgm",
      "index_users_on_lower_email_trgm",
      "index_users_on_lower_login_id_trgm",
      "index_users_on_lower_name_trgm",
      "index_shg_members_on_lower_mobile_trgm",
      "index_shg_members_on_lower_loan_no_trgm",
      "index_shg_members_on_lower_name_trgm",
      "index_shgs_on_lower_approval_status_trgm",
      "index_shgs_on_lower_shg_code_trgm",
      "index_shgs_on_lower_name_trgm",
      "index_occupations_on_lower_name_trgm",
      "index_activities_on_lower_name_trgm",
      "index_user_types_on_lower_level_trgm",
      "index_user_types_on_lower_code_trgm",
      "index_user_types_on_lower_name_trgm",
      "index_villages_on_lower_code_trgm",
      "index_villages_on_lower_name_trgm",
      "index_blocks_on_lower_code_trgm",
      "index_blocks_on_lower_name_trgm",
      "index_districts_on_lower_code_trgm",
      "index_districts_on_lower_name_trgm",
      "index_states_on_lower_code_trgm",
      "index_states_on_lower_name_trgm"
    ].each { |name| execute "DROP INDEX CONCURRENTLY IF EXISTS #{name}" }

    remove_index_if_exists :users, name: "index_users_on_mapped_village_ids_gin"
    remove_index_if_exists :users, name: "index_users_on_mapped_block_ids_gin"
    remove_index_if_exists :users, name: "index_users_on_mapped_district_ids_gin"
    remove_index_if_exists :visit_records, name: "index_visit_records_on_product_id_and_visit_date"
    remove_index_if_exists :visit_records, name: "index_visit_records_on_active_and_approval_status"
    remove_index_if_exists :loan_statuses, name: "index_loan_statuses_on_active_and_created_at"
    remove_index_if_exists :products, name: "index_products_on_active_and_created_at"
    remove_index_if_exists :occupations, name: "index_occupations_on_active_and_created_at"
    remove_index_if_exists :activities, name: "index_activities_on_active_and_created_at"
    remove_index_if_exists :users, name: "index_users_on_active_and_created_at"
    remove_index_if_exists :user_types, name: "index_user_types_on_active_and_created_at"
    remove_index_if_exists :villages, name: "index_villages_on_active_and_created_at"
    remove_index_if_exists :blocks, name: "index_blocks_on_active_and_created_at"
    remove_index_if_exists :districts, name: "index_districts_on_active_and_created_at"
    remove_index_if_exists :states, name: "index_states_on_active_and_created_at"
    remove_index_if_exists :visit_records, name: "index_visit_records_on_village_visit_date_created_at"
    remove_index_if_exists :visit_records, name: "index_visit_records_on_active_visit_date_created_at"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_shg_member_id_and_created_at"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_product_id_and_created_at"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_loan_status_id_and_created_at"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_date_product"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_date_status"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_product_id"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_loan_status_id"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_shg_member_id"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_shg_id"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_distribution_date"
    remove_index_if_exists :shg_loans, name: "index_shg_loans_on_active_and_created_at"
    remove_index_if_exists :shg_members, name: "index_shg_members_on_shg_id_and_created_at"
    remove_index_if_exists :shg_members, name: "index_shg_members_on_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_created_by_id_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_village_id_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_block_id_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_district_id_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_state_id_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_linkage_date_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_active_approval_and_created_at"
    remove_index_if_exists :shgs, name: "index_shgs_on_active_and_created_at"
  end

  private

  def add_btree_index(table, columns, name:)
    add_index table, columns, name: name, algorithm: :concurrently unless index_exists?(table, columns, name: name)
  end

  def add_trgm_index(table, expression, name)
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} ON #{table} USING gin (#{expression} gin_trgm_ops)"
  end

  def add_array_gin_index(table, column, name)
    execute "CREATE INDEX CONCURRENTLY IF NOT EXISTS #{name} ON #{table} USING gin (#{column})"
  end

  def remove_index_if_exists(table, name:)
    remove_index table, name: name, algorithm: :concurrently if index_exists?(table, name: name)
  end
end
