module Sequel
  module Schema
    class CreateTableGenerator
      def ver_foreign_key(prefix, opts = {})
        rows = []
        table_name = opts[:table_name] || prefix.to_s.pluralize.to_sym
        if opts[:version]
          Bignum :"#{prefix}_version".tap { |s| rows << s }, null: false
          foreign_key rows.dup, table_name
        else
          Integer :"#{prefix}_record_id".tap { |s| rows << s }, null: false
        end

        column :"#{prefix}_branch_path".tap { |s| rows << s }, 'integer[]', null: false, default: '{}'
        index rows
        rows
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

    def full_text_search(table_name, column_map)
      add_column  table_name, :tsv, 'tsvector'
      add_index   table_name, :tsv, :index_type => :gin

      sql = %(
          CREATE FUNCTION #{table_name}_tsearch_trigger() RETURNS TRIGGER AS $$
          BEGIN
            NEW.tsv := )

      sql += column_map.map do |name, weight|
        "setweight(to_tsvector('pg_catalog.english', coalesce(NEW.#{name},'')), '#{weight}')"
      end.join(' || ') + ';'

      sql += %(
            RETURN NEW;
          END
          $$ LANGUAGE plpgsql;

          CREATE TRIGGER #{table_name}_tsearch
            BEFORE INSERT OR UPDATE ON #{table_name}
            FOR EACH ROW EXECUTE PROCEDURE #{table_name}_tsearch_trigger();
        )

      run sql
    end

    def create_version_table(table_name, options = {}, &block)
      create_table(table_name, options) do
        Bignum :version, null: false, default: Sequel.function(:nextval, 'version_seq')
        primary_key [:version]

        unless options[:no_record]
          Integer   :record_id, null: false

          index :record_id
        end

        unless options[:no_branch]
          foreign_key :branch_id, :branches, null: false
          column      :branch_path, 'integer[]', null: false, default: '{}'
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

    def create_many_to_many_version_table(table_name, opts = {}, &block)
      create_version_table table_name, no_record: true, no_branch: opts[:inter_branch] do
        src_table = opts[:src_table]
        dst_table = opts[:dst_table] || src_table
        src_prefix = opts[:src_prefix] || (src_table == dst_table ? :from : src_table.to_s.singularize)
        dst_prefix = opts[:dst_prefix] || (src_table == dst_table ? :to : dst_table.to_s.singularize)
        [[src_table, src_prefix], [dst_table, dst_prefix]].each do |table, prefix|
          ver_foreign_key prefix, table_name: table
          foreign_key :"#{prefix}_branch_id", :branches, null: false if opts[:inter_branch]
        end

        instance_eval(&block) if block_given?

        #unique fgn_keys + [:deleted]
      end
    end
  end
end

Sequel.migration do
  up do
    # Global version sequence
    create_sequence(:version_seq)

    create_table :branches do
      primary_key   :id
      String        :type, null: false
      String        :name,        null: false
      String        :description, text: true

      Boolean	      :merge_point

      DateTime      :created_at,  null: false
      DateTime      :updated_at
    end

    create_table :branch_relations do
      foreign_key   :predecessor_id, :branches
      foreign_key   :successor_id, :branches
      primary_key   [:successor_id, :predecessor_id]

      BigInt        :version

      check { predecessor_id != successor_id }
    end

    # Use stored procedure and trigger to test for cycles
    # This will not detect cycles when two transactions are opened
    # simultaneously that together insert rows causing a cycle
    run %(
      CREATE FUNCTION cycle_test() RETURNS TRIGGER AS $$
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
      END
      $$ LANGUAGE plpgsql;

      CREATE CONSTRAINT TRIGGER cycle_test
        AFTER INSERT OR UPDATE ON branch_relations
        FOR EACH ROW EXECUTE PROCEDURE cycle_test();
    )

    create_version_table :resources do
      String        :type, null: false

      String        :name, null: false
      String        :doc,  text: true
    end
    full_text_search :resources, { :name => 'A', :doc => 'B' }

    create_many_to_many_version_table(:resource_edges, src_table: :resources) do
   #   String        :type, null: false
      String        :data
    end

    create_version_table :tasks do
      ver_foreign_key :resource

      String        :type, null: false

      String        :name, null: false
      String        :doc,  text: true
    end
    full_text_search :tasks, { :name => 'A', :doc => 'B' }

    create_many_to_many_version_table(:task_edges, src_table: :tasks)
    create_many_to_many_version_table(:task_edgers, src_table: :tasks, inter_branch: true)


    create_version_table :categories do
      String        :name, null: false
      String        :doc,  text: true
    end
    full_text_search :categories, { :name => 'A', :doc => 'B' }

    create_many_to_many_version_table(:category_edges, src_table: :categories)
    create_many_to_many_version_table(:category_resource,
                                      src_table: :categories,
                                      dst_table: :resources)

    create_table :instances do
      primary_key :id

      ver_foreign_key :resource, version: true
      foreign_key :branch_id, :branches

      String      :state
      Integer     :count, null: false, default: 1
      String      :data, text: true

      DateTime    :created_at, null: false
      DateTime    :updated_at, null: false
    end

    create_table :instance_edges do
      foreign_key   :predecessor_id, :branches
      foreign_key   :successor_id, :branches
      primary_key   [:successor_id, :predecessor_id]

      check { predecessor_id != successor_id }
    end

    create_table :actions do
      foreign_key :instance_id, :instances
      ver_foreign_key :task, version: true
      primary_key [:instance_id, :task_version, :task_branch_path]

      String      :state
    end

    create_table :users do
      primary_key :id
      # Reference record_id but not full ver_foreign_key because it is always
      # in the global branch
      Integer  :resource_record_id, null: false
      #ver_foreign_key :resource

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
      # Only if lock strategy is :failed_attempts
      Integer  :failed_attempts,        null: false, default: 0
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
  end
end
