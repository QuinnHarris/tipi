module Sequel
  module Plugins
    module Versioned
      module DatasetBranchContext
        attr_reader :context
        private
        attr_writer :context

        def setup_object(o)
          return o if o.frozen?
          if context and o.respond_to?(:context)
            o.send('context=', context)
            o.send('branch_path_context=', o.values.delete(:branch_path_context) || [])
          end
          o.freeze
          o
        end

        public
        def delete
          raise "Delete not permited on versioned datasets"
        end

        def update
          raise "Update not permited on versioned datasets"
        end

        def each
          super() do |r|
            yield setup_object(r)
          end
        end

        def paged_each(opts=OPTS)
          super(opts) do |r|
            yield setup_object(r)
          end
        end

        def first
          o = super
          o && setup_object(o)
        end

        # Join a branch context table to the current dataset the context will apply to.
        def join_context(context_data, options = {})
          join_column = options[:join_column] || :branch_id

          versioned_table = opts[:last_joined_table] || opts[:from].first

          ds = join(context_data, { :branch_id => join_column }, options) do |j, lj|
            Sequel.expr(Sequel.qualify(j, :version) => nil) |
                (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
          end
          ds.opts[:versioned_table] = versioned_table
          ds.opts[:last_record_id] = Sequel.qualify(versioned_table, :record_id)
          ds.opts[:order_columns] = (ds.opts[:order_columns] || []) +
              [Sequel.qualify(ds.opts[:last_joined_table], :depth),
               Sequel.qualify(versioned_table, :version).desc]
          ds
        end

        def versioned_table; @opts[:versioned_table]; end
        def last_branch_path_context
          return unless @opts[:last_joined_table]
          Sequel.qualify(@opts[:last_joined_table], :branch_path).pg_array
        end
        def last_branch_path
          return unless last_branch_path_context
          last_branch_path_context.concat(
              Sequel.qualify(versioned_table, :branch_path))
        end
        def last_record_id; @opts[:last_record_id] || :record_id; end

        # Pick latest versions and remove deleted records
        def finalize(opts = {})
          return self if opts[:no_finalize]
          model_table_name = model.raw_dataset.first_source_table
          ds = select(*model.columns.map { |c|
            Sequel.qualify(model_table_name, c) },
                      Sequel.function(:rank)
                      .over(:partition => [last_record_id,
                                           last_branch_path].compact,
                            :order     => @opts[:order_columns] ||
                                Sequel.qualify(model_table_name,
                                               :version).desc))
          if last_branch_path_context
            ds = ds.select_append(last_branch_path_context.as(:branch_path_context))
          end

          if opts[:extra_deleted_column]
            ds = ds.select_append(opts[:extra_deleted_column].as(:extra_deleted))
          end

          return ds if opts[:include_all]

          ds = ds.from_self
          .where(:rank => 1)
          unless opts[:include_deleted]
            ds = ds.where(:deleted => false)
            ds = ds.where(:extra_deleted => false) if opts[:extra_deleted_column]
          end
          ds = ds.select(*model.columns)
          ds = ds.select_append(:branch_path_context) if last_branch_path_context
          ds
        end

        protected
        def _all(block)
          super.map { |r| setup_object(r) }
        end
      end


      def self.apply(model, opts=OPTS)
        model.plugin :version_associations
        model.many_to_one :branch

        model.dataset_module DatasetBranchContext

        model.singleton_class.send(:alias_method, :raw_dataset, :dataset)

        # Include branch_path as primary key as branching can cause duplicate (but different) objects with the same version.  Only version should be used to update rows though.
        #set_primary_key :version
        #, :branch_path]

      end


      module InstanceMethods
        def context(&block)
          unless ctx = @context
            ctx = Branch::Context.get(branch)
          end
          ctx.apply(&block)
        end

        def with_this_context
          return self if context.id == branch_id
          o = dup
          ctx = o.send("context=", Branch::Context.get(branch_id, context.version))
          path = context.path_from(ctx)
          o.branch_path -= path # Should work but doesn't check for problems
          o.freeze
          o
        end
        private
        attr_writer :context
        attr_writer :previous

        def current_context(ctx = nil, version = nil)
          Branch::Context.get(ctx || Branch::Context.current! || context, version)
        end
        def current_context!(ctx = nil)
          current_context(ctx, false)
        end
        public


        def branch_path(ctx = nil)
          Sequel.pg_array(branch_path_context(ctx) + branch_path_record, 'integer')
        end
        def branch_path_record
          self[:branch_path]
        end
        def branch_path_context(ctx = nil)
          (current_context(ctx).path_from(context) || []) + @branch_path_context
        end
        private
        def branch_path_context=(val)
          @branch_path_context = Sequel.pg_array(val, 'integer')
        end
        public

        def set_context!(ctx)
          @branch_path_context = branch_path_context(ctx)
          @context = current_context(ctx)
        end

        # Change equals to handle computed branch_path
        def eql?(obj)
          super(obj) && (obj.branch_path_context == branch_path_context)
        end

        def inspect
          "#<#{model.name} ctx=#{@context.id},#{@context.version},[#{@branch_path_context.join(',')}] @values=#{inspect_values}>"
        end

        def versions_dataset(all = false)
          ds = all ? self.class.raw_dataset : self.class.dataset_from_context(context, versions: true)
          ds.where(record_id: record_id)
        end
        def versions(all = false)
          versions_dataset(all).order(:version).reverse.all
        end

        private
        def check_context_specifier(values)
          list = [:context, :branch, :branch_id].map { |i| values[i] }.compact
          if list.length > 1
            raise "Only specify one context, branch or branch_id"
          end
          list.first
        end
        public

        # Doesn't work right if you use your own model initializers
        def initialize(values = {})
          raise "Can't specify record_id" if values[:record_id]
          raise "Can't specify version" if values[:version]

          @context = Branch::Context.get(check_context_specifier(values), false)

          @branch_path_context = []

          values = values.dup
          values.delete(:context)
          values[:branch] = @context.branch_nil
          values[:branch_id] = @context.id

          super values
        end

        def new(new_values = {}, &block)
          vals = values.dup

          raise "Expected context" unless context

          unless check_context_specifier(new_values)
            vals[:context] = context unless Branch::Context.current!
          end
          record_id = vals.delete(:record_id) # Remove record_id to make initialize happy
          [:version, :branch_id, :created_at].each { |column| vals.delete(column) }
          vals = vals.merge(new_values) # Should only have one context specifier

          ctx = Branch::Context.new(vals[:context] || vals[:branch] || vals[:branch_id] || Branch::Context.current!)
          ctx.not_included!(branch_id, version)
          ctx.not_included_or_duplicated!(context, false)
          # We assume context includes branch_id

          vals[:branch_path] = branch_path(ctx)

          # !!! Apply cached branch if available
          o = self.class.new(vals, &block)
          o.values.merge!(:record_id => record_id)
          o.send('previous=', self)
          o
        end

        # Make active model methods work right with versioning
        def persisted?
          !@previous.nil? || super
        end
        def to_key
          @previous ? @previous.to_key : super
        end


        def create(values = {}, &block)
          new(values, &block).save
        end

        # Should preform delete check here instead of DB trigger because the context
        # is needed to do this correctly.
        def delete(values = {})
          o = new(values.merge(deleted: true))
          ds = self.class.dataset(o.context, no_finalize: true)
          p = ds.where(ds.last_record_id => record_id,
                       ds.last_branch_path => o.branch_path)
          .order(Sequel.qualify(ds.versioned_table, :version).desc).first
          raise VersionedError, "Delete without existing record" unless p
          raise VersionedError, "Delete with existing deleted record" if p.deleted
          o.save
        end

        private
        # Freeze objects after save
        # Can't use after_save because class is modified after that call
        def _save(opts)
          super(opts)
          freeze
          self
        end


        private
        # Redefine add_associated_object from Sequel associations.rb
        # Add option join_class to return added object with many_to_many relations
        def add_associated_object(opts, o, *args)
          klass = opts.associated_class
          if o.is_a?(Hash) && opts[:join_class].nil?
            o = klass.new(o)
          elsif o.is_a?(Integer) || o.is_a?(String) || o.is_a?(Array)
            o = klass.with_pk!(o)
          elsif !o.is_a?(klass)
            raise(Sequel::Error, "associated object #{o.inspect} not of correct type #{klass}")
          end
          raise(Sequel::Error, "model object #{inspect} does not have a primary key") if opts.dataset_need_primary_key? && !pk
          ensure_associated_primary_key(opts, o, *args)
          return if run_association_callbacks(opts, :before_add, o) == false
          return if !(r = send(opts._add_method, o, *args)) && opts.handle_silent_modification_failure?
          raise(Sequel::Error, "expected #{opts[:join_class]} from _add_method got #{r.inspect}") unless !opts[:join_class] or r.instance_of?(opts[:join_class])
          if array = associations[opts[:name]] and !array.include?(o)
            array.push(o)
          end
          add_reciprocal_object(opts, o)
          run_association_callbacks(opts, :after_add, o)
          opts[:join_class] ? r : o
        end

        def remove_associated_object(opts, o, *args)
          klass = opts.associated_class
          if o.is_a?(Integer) || o.is_a?(String) || o.is_a?(Array)
            o = remove_check_existing_object_from_pk(opts, o, *args)
          elsif !o.is_a?(klass)
            raise(Sequel::Error, "associated object #{o.inspect} not of correct type #{klass}")
          elsif opts.remove_should_check_existing? && send(opts.dataset_method).where(o.pk_hash).empty?
            raise(Sequel::Error, "associated object #{o.inspect} is not currently associated to #{inspect}")
          end
          raise(Sequel::Error, "model object #{inspect} does not have a primary key") if opts.dataset_need_primary_key? && !pk
          raise(Sequel::Error, "associated object #{o.inspect} does not have a primary key") if opts.need_associated_primary_key? && !o.pk
          return if run_association_callbacks(opts, :before_remove, o) == false
          return if !(r = send(opts._remove_method, o, *args)) && opts.handle_silent_modification_failure?
          raise(Sequel::Error, "expected #{opts[:join_class]} from _add_method got #{r.inspect}") unless !opts[:join_class] or r.instance_of?(opts[:join_class])
          associations[opts[:name]].delete_if{|x| o === x} if associations.include?(opts[:name])
          remove_reciprocal_object(opts, o)
          run_association_callbacks(opts, :after_remove, o)
          opts[:join_class] ? r : o
        end

        def dataset_to_edge(dataset, context_data, r)
          ds = dataset.from(r[:join_table])

          # Select edges connected to this node
          ds = ds.where(r[:left_record_id] => record_id)

          # Split edges between in context and out of context
          # Treat in context edges the same with or without inter branch
          if r[:inter_branch]
            table_common = r[:join_table] #:connect_table

            # Determine if the connecting node is within the same context
            ds_common = ds.select_append(
                Sequel.expr(r[:right_branch_id] =>
                                db[context_data].select(:branch_id))
                .as(:in_context))

            if ctx_ver = current_context.version
              ds_common = ds_common.where { |o| o.version < ctx_ver }
            end

            ds_base = dataset.from(table_common)

            ds = ds_base.where(:in_context)
          end

          ds = ds.join_context(context_data,
                               join_column: r[:inter_branch] && r[:right_branch_id],
                               table_alias: :branch_edges)

          branch_path_select = ds.last_branch_path_context.concat(
              Sequel.qualify(r[:join_table], r[:left_branch_path]))

          ds = ds.where(branch_path_select => branch_path)


          if r[:inter_branch]
            ds = ds.select(Sequel::SQL::ColumnAll.new(table_common),
                           Sequel.as(:depth, :edge_branch_depth),
                           Sequel.as(:branch_path, :edge_branch_path))

            ds_in = ds
            ds_out = ds_base.exclude(:in_context)
            .select_append(Sequel.as(0, :edge_branch_depth),
                           Sequel.cast(Sequel.pg_array([]), 'integer[]')
                           .as(:edge_branch_path))

            ds = dataset.from(Sequel::SQL::AliasedExpression.new(ds_in.union(ds_out),
                                                                 r[:join_table]))
            .with(table_common, ds_common)

            ds.opts[:last_branch_path_context] = Sequel.qualify(r[:join_table],
                                                                :edge_branch_path)
            ds.opts[:order_columns] = [Sequel.qualify(r[:join_table],
                                                      :edge_branch_depth),
                                       ds_in.opts[:order_columns].last]
          end

          ds
        end
      end

      module ClassMethods
        # Dataset for latest version of rows within the provided branch (and predecessors)
        # Join against the branch dataset or table and use a window function to rank first by branch depth (high precident branches) and then latest version.  Only return the 1st ranked results.
        private
        def dataset_from_context(context, options = {})
          context.dataset do |context_dataset|
            raw_dataset.join_context(context_dataset).finalize(options)
          end
        end
        public

        # Kludgy: change dataset if in a context but only provide new behavior once
        # as dataset_from_context and methods it calls will call dataset again.
        # There is probably a better way
        def dataset(branch = nil, options = {})
          return super() if @in_dataset or (!Branch::Context.current! and !branch)
          @in_dataset = true
          context = Branch::Context.get(branch)
          ds = dataset_from_context(context, options)
          @in_dataset = nil
          ds
        end

        def ver_many_to_many(name, opts=OPTS, &block)
          opts = opts.dup

          # join_class
          join_table = opts[:join_table]
          if join_class = opts[:join_class]
            raise "Can't specify join_class if join_table specified" if join_table
            join_table ||= opts[:join_class].table_name
            opts[:join_table] = join_table
          end

          { left: self.name.underscore,
            right: name.to_s.singularize }.each do |prefix, key_prefix|
            ver_common_ops(opts,
                           opts[:"#{prefix}_key_prefix"] ||= key_prefix,
                           prefix)
          end

          opts[:adder] = proc do |node, branch = nil, created_at = nil, delete = nil|
            ctx = current_context(branch, false)

            ctx.not_included!(self)
            ctx.not_included!(node) unless opts[:inter_branch]

            h_record_id = {
                opts[:left_record_id] => record_id,
                opts[:right_record_id] => node.record_id,
            }

            h_branch_path = {
                opts[:left_branch_path] => branch_path,
                opts[:right_branch_path] => node.branch_path,
            }

            # !!! Implement check for inter_branch
            unless opts[:inter_branch]
              ds = self.class.db[join_table].extend(DatasetBranchContext)
                       .join_context(ctx.dataset).where(h_record_id)
              h_branch_path.each do |col, val|
                ds = ds.where(ds.last_branch_path_context.concat(
                                  Sequel.qualify(ds.versioned_table, col)) => val)
              end
              p = ds.order(Sequel.qualify(ds.versioned_table, :version).desc).first
              exists = p && !p[:deleted]
              if !exists != !delete
                raise VersionedError, "Edge add doesn't change edge state"
              end
            end

            h = h_record_id.merge(h_branch_path)
            if opts[:inter_branch]
              h.merge!( opts[:left_branch_id] => ctx.id,
                        opts[:right_branch_id] => node.context.id )
            else
              h.merge!( :branch_id => ctx.branch.id )
            end

            h.merge!(:created_at => created_at || self.class.dataset.current_datetime,
                     :deleted => delete ? true : false)

            join_class ? join_class.create(h) : self.class.db[join_table].insert(h)
          end

          opts[:remover] = proc do |node, branch = nil, created_at = nil|
            send("_add_#{name}", node, branch, created_at, true)
          end
          #  _remove_all_ ?

          opts[:select] = nil
          opts[:dataset] = proc do |r|
            current_context.not_included_or_duplicated!(context, false)
            current_context.dataset do |context_data|
              dataset = r.associated_class.raw_dataset
              ds  = dataset_to_edge(dataset, context_data, r)

              # Join final nodes
              ds = ds.join(dataset.first_source_table,
                           :record_id => Sequel.qualify(r[:join_table],
                                                        r[:right_record_id]) )

              ds = dataset_from_edge(ds, r, context_data,
                                     Sequel.qualify(:branch_edges,
                                                    :branch_path).pg_array.concat(
                                         Sequel.qualify(r[:join_table],
                                                        r[:right_branch_path]) ) )

              ds.finalize(extra_deleted_column: Sequel.qualify(r[:join_table],
                                                               :deleted))
            end
          end

          many_to_many(name, opts, &block)
        end

        def ver_one_to_many(name, opts=OPTS, &block)
          opts = opts.dup
          ver_common_ops(opts, opts[:key] || name)
          ver_common_ops(opts, opts[:target_prefix], :target)

          opts[:dataset] = proc do |r|
            current_context.not_included_or_duplicated!(context, false)
            current_context.dataset do |context_data|
              dataset = r.associated_class.raw_dataset
              ds = dataset_to_edge(dataset, context_data,
                                   join_table: dataset.first_source_table,
                                   left_record_id: r[:record_id],
                                   left_branch_path: r[:branch_path])

              ds.opts[:last_record_id] = r[:target_record_id]
              ds.opts[:last_branch_path] = r[:target_branch_path] # Wrong

              ds.finalize
            end
          end

          one_to_many(name, opts, &block)
        end
      end
    end
  end
end