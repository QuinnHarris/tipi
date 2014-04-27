# encoding: UTF-8
# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 20140315161218) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "branch_relations", force: true do |t|
    t.integer "predecessor_id"
    t.integer "successor_id"
    t.integer "version"
  end

  add_index "branch_relations", ["predecessor_id", "successor_id"], name: "index_branch_relations_on_predecessor_id_and_successor_id", unique: true, using: :btree

  create_table "branches", force: true do |t|
    t.string   "name"
    t.text     "description"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  create_table "edges", force: true do |t|
    t.integer  "from_record_id", null: false
    t.integer  "from_branch_id", null: false
    t.integer  "from_version",   null: false
    t.integer  "to_record_id",   null: false
    t.integer  "to_branch_id",   null: false
    t.integer  "to_version",     null: false
    t.boolean  "deleted"
    t.boolean  "version_lock"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "edges", ["from_branch_id", "from_version", "from_record_id"], name: "index_edges_on_from_branch_id_version_record_id", unique: true, using: :btree
  add_index "edges", ["from_record_id", "from_branch_id", "from_version"], name: "index_edges_on_from_record_id_branch_id_version", unique: true, using: :btree
  add_index "edges", ["to_branch_id", "to_version", "to_record_id"], name: "index_edges_on_to_branch_id_version_record_id", unique: true, using: :btree
  add_index "edges", ["to_record_id", "to_branch_id", "to_version"], name: "index_edges_on_to_record_id_branch_id_version", unique: true, using: :btree

  create_table "node_instances", force: true do |t|
    t.integer "user_id"
    t.integer "node_id"
    t.string  "state"
  end

  create_table "nodes", force: true do |t|
    t.integer "record_id", null: false
    t.integer "branch_id", null: false
    t.integer "version",   null: false
    t.boolean "deleted"
    t.string  "type",      null: false
    t.string  "name",      null: false
    t.text    "data"
  end

  add_index "nodes", ["branch_id", "version", "record_id"], name: "index_nodes_on_branch_id_version_record_id", unique: true, using: :btree
  add_index "nodes", ["record_id", "branch_id", "version"], name: "index_nodes_on_record_id_branch_id_version", unique: true, using: :btree

  create_table "users", force: true do |t|
    t.integer  "branch_id"
    t.string   "email",                  default: "", null: false
    t.string   "encrypted_password",     default: "", null: false
    t.string   "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.integer  "sign_in_count",          default: 0,  null: false
    t.datetime "current_sign_in_at"
    t.datetime "last_sign_in_at"
    t.string   "current_sign_in_ip"
    t.string   "last_sign_in_ip"
    t.string   "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string   "unconfirmed_email"
    t.integer  "failed_attempts",        default: 0,  null: false
    t.string   "unlock_token"
    t.datetime "locked_at"
    t.string   "provider"
    t.string   "uid"
    t.string   "name"
    t.datetime "created_at"
    t.datetime "updated_at"
  end

  add_index "users", ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true, using: :btree
  add_index "users", ["email"], name: "index_users_on_email", unique: true, using: :btree
  add_index "users", ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true, using: :btree
  add_index "users", ["unlock_token"], name: "index_users_on_unlock_token", unique: true, using: :btree

  add_foreign_key "branch_relations", "branches", name: "branch_relations_predecessor_id_fk", column: "predecessor_id"
  add_foreign_key "branch_relations", "branches", name: "branch_relations_successor_id_fk", column: "successor_id"

  add_foreign_key "edges", "branches", name: "edges_from_branch_id_fk", column: "from_branch_id"
  add_foreign_key "edges", "branches", name: "edges_to_branch_id_fk", column: "to_branch_id"
  add_foreign_key "edges", "nodes", name: "edges_from_record_id_branch_id_version_fk", column: "from_record_id", primary_key: "record_id"
  add_foreign_key "edges", "nodes", name: "edges_to_record_id_branch_id_version_fk", column: "to_record_id", primary_key: "record_id"

  add_foreign_key "node_instances", "nodes", name: "node_instances_node_id_fk"
  add_foreign_key "node_instances", "users", name: "node_instances_user_id_fk"

  add_foreign_key "nodes", "branches", name: "nodes_branch_id_fk"

  add_foreign_key "users", "branches", name: "users_branch_id_fk"

end
