module Sequel
  module Schema
    class CreateTableGenerator
      def version_columns(references = nil, prefix = nil)
        prefix ||= references
        keys = [:record_id, :branch_id, :version]
        columns = keys.collect do |column|
          "#{prefix && "#{prefix}_"}#{column}".to_sym
        end

        columns.each { |name| Integer name, null: false }

        unless prefix
          primary_key columns
          # primary key creates index
        else
          index columns
        end
        
        # Index by branch
        index columns[1..2]+columns[0..0], unique: !prefix
        
        if references
          foreign_key columns, references, key: keys
        else
          foreign_key [columns[1]], :branches
        end
        
        columns
      end
    end
  end

  class Database
    def create_version_table(table_name, options = {}, &block)
      create_table(table_name, options) do
        version_columns
        
        TrueClass       :deleted

        instance_eval(&block)
      end
  
      # Create record_id and version sequence much like id.
      ['record_id', 'version'].each do |column_name|
        sequence_name = "#{table_name}_#{column_name}_seq"
        run "CREATE SEQUENCE #{sequence_name}
                           OWNED BY #{table_name}.#{column_name}"
        # OWNED BY causes Postgres to drop the sequence when the table is dropped

        run "ALTER TABLE #{table_name} ALTER COLUMN #{column_name}
                         SET DEFAULT nextval('#{sequence_name}'::regclass)"
      end
    end
  end
end

Sequel.migration do
  change do
    # Should the version sequence be global?  Would it be useful, will we overflow it.
    create_table :branches do
      primary_key   :id
      String        :name
      String        :description, text: true

      DateTime      :created_at
      DateTime      :updated_at
    end

    create_table :branch_relations do
      foreign_key   :successor_id, :branches
      foreign_key   :predecessor_id, :branches
      primary_key   [:successor_id, :predecessor_id]

      # Index by both successor_id and predecessor_id (primary_key creates index)
      index         [:predecessor_id, :successor_id], unique: true

      Integer       :version
    end

    create_version_table :nodes do
      String        :type, null: false
      
      String        :name, null: false
      String        :data, text: true

      DateTime      :created_at
    end

    create_table :edges do
      columns = %w(from to).collect do |aspect|
        version_columns :nodes, aspect
      end.flatten
      primary_key columns

      TrueClass     :deleted    

      TrueClass     :version_lock

      DateTime      :created_at
      DateTime      :updated_at
    end
    

    create_table :users do
      primary_key :id
      foreign_key :branch_id, :branches

      # Devise
      ## Database authenticatable
      String      :email,              null: false, default: ''
      index       :email,              unique: true
      String      :encrypted_password, null: false, default: ''

      ## Recoverable
      String      :reset_password_token
      index       :reset_password_token, unique: true
      DateTime    :reset_password_sent_at

      ## Rememberable
      DateTime :remember_created_at

      ## Trackable
      Integer  :sign_in_count,          null: false, default: 0
      DateTime :current_sign_in_at
      DateTime :last_sign_in_at
      String   :current_sign_in_ip
      String   :last_sign_in_ip

      ## Confirmable
      String   :confirmation_token
      index    :confirmation_token,     unique: true
      DateTime :confirmed_at
      DateTime :confirmation_sent_at
      String   :unconfirmed_email # Only if using reconfirmable

      ## Lockable
      Integer  :failed_attempts,        null: false, default: 0 # Only if lock strategy is :failed_attempts
      String   :unlock_token # Only if unlock strategy is :email or :both
      index    :unlock_token,           unique: true
      DateTime :locked_at

      ## OmniAuth
      String   :provider
      String   :uid
      String   :name

      DateTime      :created_at
      DateTime      :updated_at
    end

    create_table :node_instances do
      foreign_key    :user_id, :users
      columns = version_columns :nodes
      primary_key    [:user_id] + columns

      String       :state
    end
  end
end
