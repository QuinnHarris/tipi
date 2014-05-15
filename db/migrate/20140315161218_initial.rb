module Sequel
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

    def create_version_table(table_name, options = {}, &block)
      create_table(table_name, options) do
        Bignum :version, null: false, default: Sequel.function(:nextval, 'version_seq')
        primary_key [:version]

        unless options[:no_branch]
          foreign_key :branch_id, :branches, null: false
          column      :branch_path, 'integer[]', null: false, default: '{}'
        end

        unless options[:no_record]
          Integer   :record_id, null: false

          index :record_id
        end
         
        DateTime    :created_at, null: false

        instance_eval(&block) if block_given?

        # Does moving this to the end improve allocation like in C?
        TrueClass   :deleted,    null: false, default: false
      end

      unless options[:no_record]
        # OWNED BY causes Postgres to drop the sequence when the table is dropped
        sequence_name = "#{table_name}_record_id_seq"
        create_sequence(sequence_name,
                        ownedby_table: table_name, ownedby_column: :record_id)
        set_column_default(table_name, :record_id, Sequel.function(:nextval, sequence_name))
      end
    end

    def create_many_to_many_version_table(table_name, options = {}, &block)
      create_version_table :edges, no_record: true, no_branch: options[:cross_branch] do
        fgn_keys = [:from, :to].map do |aspect|
          rows = %w(record_id branch_path branch_id).map { |n| :"#{aspect}_#{n}" }
          rows.pop unless options[:cross_branch]
          record_id, branch_path, branch_id = rows
          # must be in set of record_ids on nodes but record_ids is not unique
          Integer record_id, null: false
          
          foreign_key branch_id, :branches, null: false if branch_id
          column branch_path, 'integer[]', null: false, default: '{}'
          
          index rows
          rows
        end.flatten

        instance_eval(&block) if block_given?

        unique fgn_keys + [:deleted]
      end
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
      String        :type, null: false
      String        :name,        null: false
      String        :description, text: true

      Boolean	    :merge_point

      DateTime      :created_at,  null: false
      DateTime      :updated_at
    end

    create_table :branch_relations do
      foreign_key   :predecessor_id, :branches
      foreign_key   :successor_id, :branches
      primary_key   [:successor_id, :predecessor_id]

      # Index by both successor_id and predecessor_id (primary_key creates index)
      index         [:successor_id, :predecessor_id], unique: true

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
    end

    create_many_to_many_version_table(:edges)

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
      foreign_key    :node_version, :nodes
      primary_key    [:user_id, :node_version]

      String       :state
    end
  end
end
