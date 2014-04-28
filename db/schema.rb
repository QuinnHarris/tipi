Sequel.migration do
  change do
    create_table(:branches) do
      primary_key :id
      column :type, "text", :null=>false
      column :name, "text", :null=>false
      column :description, "text"
      column :created_at, "timestamp without time zone", :null=>false
      column :updated_at, "timestamp without time zone"
    end
    
    create_table(:schema_migrations) do
      column :filename, "text", :null=>false
      
      primary_key [:filename]
    end
    
    create_table(:branch_relations) do
      foreign_key :predecessor_id, :branches, :null=>false, :key=>[:id]
      foreign_key :successor_id, :branches, :null=>false, :key=>[:id]
      column :version, "bigint"
      
      primary_key [:predecessor_id, :successor_id]
      
      index [:predecessor_id, :successor_id], :unique=>true
    end
    
    create_table(:nodes) do
      primary_key :version, :type=>"bigint"
      foreign_key :branch_id, :branches, :null=>false, :key=>[:id]
      column :record_id, "integer", :default=>Sequel::LiteralString.new("nextval('nodes_record_id_seq'::regclass)"), :null=>false
      column :created_at, "timestamp without time zone", :null=>false
      column :type, "text", :null=>false
      column :name, "text", :null=>false
      column :data, "text"
      column :deleted, "boolean", :default=>false, :null=>false
      
      index [:branch_id, :record_id]
      index [:record_id, :branch_id]
    end
    
    create_table(:users) do
      primary_key :id
      foreign_key :branch_id, :branches, :key=>[:id]
      column :email, "text", :default=>"", :null=>false
      column :encrypted_password, "text", :default=>"", :null=>false
      column :reset_password_token, "text"
      column :reset_password_sent_at, "timestamp without time zone"
      column :remember_created_at, "timestamp without time zone"
      column :sign_in_count, "integer", :default=>0, :null=>false
      column :current_sign_in_at, "timestamp without time zone"
      column :last_sign_in_at, "timestamp without time zone"
      column :current_sign_in_ip, "text"
      column :last_sign_in_ip, "text"
      column :confirmation_token, "text"
      column :confirmed_at, "timestamp without time zone"
      column :confirmation_sent_at, "timestamp without time zone"
      column :unconfirmed_email, "text"
      column :failed_attempts, "integer", :default=>0, :null=>false
      column :unlock_token, "text"
      column :locked_at, "timestamp without time zone"
      column :provider, "text"
      column :uid, "text"
      column :name, "text"
      column :created_at, "timestamp without time zone"
      column :updated_at, "timestamp without time zone"
      
      index [:confirmation_token], :unique=>true
      index [:email], :unique=>true
      index [:reset_password_token], :unique=>true
      index [:unlock_token], :unique=>true
    end
    
    create_table(:edges) do
      primary_key :version, :type=>"bigint"
      foreign_key :branch_id, :branches, :null=>false, :key=>[:id]
      column :created_at, "timestamp without time zone", :null=>false
      foreign_key :from_version, :nodes, :type=>"bigint", :null=>false, :key=>[:version]
      foreign_key :to_version, :nodes, :type=>"bigint", :null=>false, :key=>[:version]
      column :deleted, "boolean", :default=>false, :null=>false
      
      index [:from_version]
      index [:from_version, :to_version, :deleted], :name=>:edges_from_version_to_version_deleted_key, :unique=>true
      index [:to_version]
    end
    
    create_table(:node_instances) do
      foreign_key :user_id, :users, :null=>false, :key=>[:id]
      foreign_key :node_version, :nodes, :null=>false, :key=>[:version]
      column :state, "text"
      
      primary_key [:user_id, :node_version]
    end
  end
end
Sequel.migration do
  change do
    self << "INSERT INTO \"schema_migrations\" (\"filename\") VALUES ('20140315161218_initial.rb')"
  end
end
