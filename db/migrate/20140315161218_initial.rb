module Sequel
  module Schema
    class CreateTableGenerator
      def version_columns(references = nil, prefix = nil)
        prefix ||= references
        keys = [:record_id, :branch_id, :version]
        columns = keys.collect do |column|
          "#{prefix && "#{prefix}_"}#{column}".to_sym
        end

        columns.each do |name|
          if name == :version
            Bignum name, null: false, default: { :sequence => 'version_seq' }
          else
            Integer name, null: false
          end
        end

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
    # Ideally this would be submitted to the Sequel project
    def create_sequence_sql(name, options)
      # Need to implement INCREMENT, MINVALUE, MAXVALUE, START, CACHE, CYCLE
      sql = "CREATE #{temporary_table_sql if options[:temp]}SEQUENCE #{options[:temp] ? quote_identifier(name) : quote_schema_table(name)}"
      sql += " INCREMENT BY #{options[:increment]}" if options[:increment]
      sql += " MINVALUE #{options[:minvalue]}" if options[:minvalue]
      sql += " MAXVALUE #{options[:maxvalue]}" if options[:maxvalue]
      sql += " START WITH #{options[:start]}" if options[:start]
      sql += " CACHE #{options[:cache]}" if options[:cache]
      sql += " CYCLE" if options[:cycle]
      sql += " OWNED BY #{options[:ownedby_table]}.#{options[:ownedby_column]}" if options[:ownedby_table]
      sql
    end

    def create_sequence(name, options=OPTS)
      run(create_sequence_sql(name, options))
    end

    # Monkey patchs to Sequel from database/schema_methods.rb

    # Enable alter_table_op_sql to support sequences on default values
    # Is there a better way?  Can literal function support unquoted output?
    alias_method :alter_table_op_sql_orig, :alter_table_op_sql
    def alter_table_op_sql(table, op)
      if op[:op] == :set_column_default and op[:default][:sequence]
        quoted_name = quote_identifier(op[:name]) if op[:name]
        "ALTER COLUMN #{quoted_name} SET DEFAULT nextval(#{literal(op[:default][:sequence])}::regclass)"
      else
        alter_table_op_sql_orig(table, op)
      end
    end

    # Copied and modified from original
    # Add default SQL fragment to column creation SQL.
    def column_definition_default_sql(sql, column)
      return unless column.include?(:default)
      if column[:default].is_a?(Hash) && column[:default].include?(:sequence)
        sql << " DEFAULT nextval(#{literal(column[:default][:sequence])}::regclass)"
      else
        sql << " DEFAULT #{literal(column[:default])}"
      end
    end


    def create_version_table(table_name, options = {}, &block)
      create_table(table_name, options) do
        version_columns
        
        TrueClass       :deleted

        instance_eval(&block)
      end

      # OWNED BY causes Postgres to drop the sequence when the table is dropped
      sequence_name = "#{table_name}_record_id_seq"
      create_sequence(sequence_name,
                      ownedby_table: table_name, ownedby_column: :record_id)
      set_column_default(table_name, :record_id, sequence: sequence_name)
    end
  end
end

Sequel.migration do
  up do
    # Global version sequence
    create_sequence(:version_seq)

    # Should the version sequence be global?  Would it be useful, will we overflow it.
    create_table :branches do
      primary_key   :id
      String        :name
      String        :description, text: true

      DateTime      :created_at
      DateTime      :updated_at
    end

    create_table :branch_relations do
      foreign_key   :predecessor_id, :branches
      foreign_key   :successor_id, :branches
      primary_key   [:successor_id, :predecessor_id]

      # Index by both successor_id and predecessor_id (primary_key creates index)
      index         [:predecessor_id, :successor_id], unique: true

      BigInt        :version

      check { predecessor_id != successor_id }
    end

    # Use stored proceedure and trigger to test for cycles
    # This will not detect cycles when two transactions are opened simultaniously that together insert rows causing a cycle
    run %(
CREATE FUNCTION cycle_test() RETURNS TRIGGER AS $cycle_test$
DECLARE
  cycle_path integer ARRAY;
BEGIN
  IF (TG_OP = 'UPDATE' AND
      NEW.successor_id = OLD.successor_id AND
      NEW.predecessor_id = OLD.predecessor_id) THEN
    RETURN NULL;
  END IF;

  WITH RECURSIVE branch_decend AS (
      SELECT NEW.successor_id AS id,
             ARRAY[NEW.predecessor_id, NEW.successor_id] AS path,
             false AS cycle
    UNION
      SELECT branch_relations.successor_id,
             branch_decend.path || branch_relations.successor_id,
	     branch_relations.successor_id = ANY(branch_decend.path)
        FROM branch_relations
	  INNER JOIN branch_decend
	    ON branch_relations.predecessor_id = branch_decend.id
        WHERE NOT branch_decend.cycle
  ) SELECT path INTO cycle_path
      FROM branch_decend WHERE cycle LIMIT 1;
  
  IF FOUND THEN
    RAISE EXCEPTION 'cycle found %', cycle_path;
  END IF;

  RETURN NULL;
END;
$cycle_test$ LANGUAGE plpgsql;

CREATE CONSTRAINT TRIGGER cycle_test
  AFTER INSERT OR UPDATE ON branch_relations
  FOR EACH ROW EXECUTE PROCEDURE cycle_test();
)

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
