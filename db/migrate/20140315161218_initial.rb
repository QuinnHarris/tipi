class Initial < ActiveRecord::Migration
  def create_version_columns(t, prefix = nil, references = nil)
    # 3 columns could be primary key
    keys = %w(record_id branch_id version)
    columns = keys.collect do |column|
      "#{prefix && "#{prefix}_"}#{column}"
    end

    columns.each { |name| t.integer name, null: false }
    t.foreign_key :branches, column: columns[1]

    # Define index name with prefix only once to keep name under 63 characters
    index_name = proc { |k| "index_#{t.name}_on_#{prefix && "#{prefix}_"}#{k.join('_')}" }

    # Index by node
    t.index columns, unique: true, name: index_name.call(keys)
    
    # Index by branch
    t.index columns[1..2]+columns[0..0], unique: true, name: index_name.call(keys[1..2]+keys[0..0])

    # Kludge to return foreign key creation command if this is a reference
    "ALTER TABLE #{t.name} ADD CONSTRAINT #{t.name}_#{prefix}_#{keys.join('_')}_fk
                                           FOREIGN KEY (#{columns.join(',')})
                                           REFERENCES #{references} (#{keys.join(',')})" if references
  end

  def create_version_table(table_name, options = {})
    create_table(table_name, options) do |t|
      create_version_columns t
      
      t.boolean       :deleted
            
      yield t
    end

    # Create record_id and version sequence much like id but don't assign as column DEFAULT as the model should always handle this.  Active Record only fetches sequence numbers for id so we will do it manually for these columns.
    reversible do |dir|
      dir.up do
        ['record_id', 'version'].each do |name|
          execute "CREATE SEQUENCE #{table_name}_#{name}_seq
                          OWNED BY #{table_name}.#{name}"
          # OWNED BY causes Postgres to drop the sequence when the table is dropped
        end
      end
    end
  end

  def change
    create_table :branches do |t|
      t.string      :name
      t.text        :description

      t.timestamps
    end

    create_table :branch_relations do |t|
      t.integer     :predecessor_id
      t.foreign_key :branches, column: :predecessor_id
      t.integer     :successor_id
      t.foreign_key :branches, column: :successor_id
      t.index       [:predecessor_id, :successor_id], unique: true

      t.integer     :version
    end

    create_version_table :nodes do |t|
      t.string      :type, null: false
      
      t.string      :name, null: false
      t.text        :data
    end

    fk_cmds = nil
    create_table :edges do |t|
      fk_cmds = %w(from to).collect do |aspect|
        create_version_columns t, aspect, :nodes
      end
      t.boolean     :deleted

      t.boolean     :version_lock

      t.timestamps
    end
    reversible { |dir| dir.up { fk_cmds.each { |cmd| execute cmd } } }
    

    create_table :users do |t|
      t.belongs_to   :branch
      t.foreign_key  :branches
      

      # Devise
      ## Database authenticatable
      t.string   :email,              :null => false, :default => ""
      t.index    :email,              :unique => true
      t.string   :encrypted_password, :null => false, :default => ""

      ## Recoverable
      t.string   :reset_password_token
      t.index    :reset_password_token, :unique => true
      t.datetime :reset_password_sent_at

      ## Rememberable
      t.datetime :remember_created_at

      ## Trackable
      t.integer  :sign_in_count, :default => 0, :null => false
      t.datetime :current_sign_in_at
      t.datetime :last_sign_in_at
      t.string   :current_sign_in_ip
      t.string   :last_sign_in_ip

      ## Confirmable
      t.string   :confirmation_token
      t.index    :confirmation_token, :unique => true
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email # Only if using reconfirmable

      ## Lockable
      t.integer  :failed_attempts, :default => 0, :null => false # Only if lock strategy is :failed_attempts
      t.string   :unlock_token # Only if unlock strategy is :email or :both
      t.index    :unlock_token,    :unique => true
      t.datetime :locked_at

      ## OmniAuth
      t.string   :provider
      t.string   :uid
      t.string   :name

      t.timestamps
    end

    create_table :node_instances do |t|
      t.belongs_to   :user
      t.foreign_key  :users

      t.belongs_to   :node
      t.foreign_key  :nodes

      t.string       :state
    end
  end
end
