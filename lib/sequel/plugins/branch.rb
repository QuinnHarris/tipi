module Sequel
  module Plugins
    module Branch
      def self.apply(model, opts=OPTS)
        aspects = %w(predecessor successor)
        aspects.zip(aspects.reverse).each do |aspect, opposite|
          model.many_to_many aspect.pluralize.to_sym, join_table: :branch_relations, :class => model,
                       left_key: :"#{opposite}_id", right_key: :"#{aspect}_id"

          model.one_to_many :"#{aspect}_relations", :class => BranchRelation, key: :"#{opposite}_id"
        end

        # Relations for all directly versioned objects
        # Should implement on Versioned concern include
        #one_to_many :nodes
      end

      module InstanceMethods
        private
        def _version_param(version)
          return nil unless version
          return Sequel.cast(Sequel.function(:nextval, 'version_seq'), :regclass) if version == true

          # Do we need to check if version number isn't in the future or lower than a decendent version lock?
          return version if version.is_a?(Integer)
          version.version
        end

        def _add_successor(o, version = nil)
          model.db[:branch_relations].insert(predecessor_id: id,
                                             successor_id: o.id,
                                             version: _version_param(version))
        end

        def _add_predecessor(o, version = nil)
          model.db[:branch_relations].insert(predecessor_id: o.id,
                                             successor_id: id,
                                             version: _version_param(version))

          # If we have temp tables in a context they should be invalidated here
        end

        public

        # has_many :template_instances

        # Create new successor branch from current branch with option context block
        def fork(options = {}, &block)
          version = options.delete(:version_lock)
          klass = options.delete(:class) || self.class
          raise "Must be Branch class: #{klass}" unless klass <= ::Branch
          db.transaction do
            o = klass.create(options)
            add_successor(o, version)
            Context.new(o).apply(&block)
            o
          end
        end

        def subordinate(options, &block)
          klass = options.delete(:class) || self.class
          raise "Must be Branch class: #{klass}" unless klass <= ::Branch
          Context.current.reset! if Context.current! # Should make this more efficient, NEEDS PROPER TEST
          db.transaction do
            if (merge_point == false) and !predecessors.empty?
              raise "Merge not allowed on this branch #{merge_point.inspect}"
            end
            o = klass.create(options)
            add_predecessor(o)
            o.context(&block)
            o
          end
        end

        # Return dataset with this and all predecessor branch ids and maximum version number for that branch
        def context_dataset(version = nil)
          self.class.context_dataset(id, name, merge_point, version)
        end

        def context(opts=OPTS, &block)
          self.class.context(self, opts, &block)
        end
      end

      module ClassMethods
        # Special create method that accepts a block within the context of the created block
        def create(values = {}, &block)
          if block_given?
            db.transaction do
              o = super(values, &nil)
              o.context(&block)
              o
            end
          else
            super values
          end
        end

        # Create new successor branch from listed branches
        # e.g.
        #   Branch.merge!(branch_a, branch_b, name: 'Branch Name')
        #   Branch.merge!(branch_list, name: 'Branch Name')
        def merge(*args, &block)
          options = args.pop
          version = options.delete(:version_lock)
          db.transaction do
            o = create(options)
            [args].flatten.each do |p|
              p.add_successor(o, version)
            end
            o.context(&block)
            o
          end
        end

        def has_merge_point?
          columns.include?(:merge_point)
        end

        def use_context_name?
          has_merge_point? || Rails.env.development?
        end

        def context_dataset_select_list(branch_id, version)
          [   Sequel.as(branch_id || Sequel.cast(nil, :integer), :branch_id),
              Sequel.cast(nil, :integer).as(:successor_id),
              Sequel.cast(version, :bigint).as(:version),
              Sequel.as(0, :depth),
              Sequel.cast(Sequel.pg_array([]), 'integer[] ').as(:branch_path) ]
        end

        def context_dataset(branch_id, name = nil, merge_point = nil, version = nil)
          # Select this record as the start point of the recursive query
          # Include the version (or null) column used by recursive part
          b_ds = db[].select(*context_dataset_select_list(branch_id, version))

          b_ds = b_ds.select_append(Sequel.as(name, :name)) if use_context_name?

          b_ds = b_ds.select_append(Sequel.as(merge_point || false,
                                              :merge_point) ) if has_merge_point?

          context_dataset_recursive(b_ds)
        end

        def context_dataset_from_set(ds, join_column = nil, version = nil)
          join_column ||= :branch_id

          if has_merge_point? or use_context_name?
            ds = ds.join(table_name, :id => join_column)
          end

          ds = ds.distinct(join_column)
          .select(*context_dataset_select_list(join_column, version))

          ds = ds.select_append(:name) if use_context_name?

          ds = ds.select_append(Sequel.function(:coalesce,
                                                :merge_point,
                                                false).as(:merge_point)) if has_merge_point?

          ds = ds.select_append(Sequel.as(join_column, :context_id))

          context_dataset_recursive(ds, true, :branch_decend_sub)
        end

        def context_dataset_recursive(base_ds, include_context = nil, cte_table = :branch_decend)
          connect_table = :branch_relations

          # Connect from the working set (cte_table) through the connect_table back to
          # this table.  Use the least (lowest) version number from the current
          # version or the connect_table version.  This ensures the version column
          # on the connect_table retrieves in all objects at or below that version.
          r_ds = db.from(cte_table)
          .join(connect_table, :successor_id => :branch_id)
          r_ds = r_ds.join(table_name,
                           :id => :predecessor_id) if use_context_name? or
              has_merge_point?
          r_ds = r_ds.select(
              Sequel.as(:predecessor_id, :branch_id),
              Sequel.qualify(connect_table, :successor_id),
              Sequel.function(:LEAST,
                              *[connect_table, cte_table].map { |t|
                                Sequel.qualify(t, :version) })
              .as(:version),
              Sequel.+(:depth, 1).as(:depth),
              :branch_path,
              Sequel.function(:count).*
              .over(:partition =>
                        Sequel.qualify(connect_table, :successor_id)).as(:count) )
          r_ds = r_ds.select_append(
              Sequel.qualify(table_name, :name)) if use_context_name?
          r_ds = r_ds.select_append(
              Sequel.qualify(cte_table, :merge_point).as(:merge_siblings),
              Sequel.function(:coalesce,
                              Sequel.qualify(table_name, :merge_point),
                              false).as(:merge_point) )  if has_merge_point?
          r_ds = r_ds.select_append(:context_id) if include_context

          bp_app_cond = Sequel.expr(:count) > 1
          bp_app_cond = bp_app_cond | Sequel.expr(:merge_siblings) if has_merge_point?
          r_ds = db.from(r_ds)
          .select(:branch_id, :successor_id, :version, :depth,
                  Sequel.case([[bp_app_cond,
                                Sequel.pg_array(:branch_path)
                                .concat(:branch_id) ]],
                              :branch_path) )
          r_ds = r_ds.select_append(:name) if use_context_name?
          r_ds = r_ds.select_append(:merge_point) if has_merge_point?
          r_ds = r_ds.select_append(:context_id) if include_context

          ds = db[cte_table].with_recursive(cte_table, base_ds, r_ds)
          .select(:branch_id, :successor_id, :version, :depth, :branch_path)
          ds = ds.select_append(:name) if use_context_name?
          ds = ds.select_append(:context_id) if include_context
          ds
        end

        def context(branch, opts=OPTS, &block)
          Context.get(branch, opts[:version]).apply(opts, &block)
        end
      end
    end
  end
end