module Sequel
  module Plugins
    module Versioned
      module DatasetBranchContext
        attr_reader :context
        private
        attr_writer :context

        def setup_object(o)
          if context and o.respond_to?(:context)
            o.send('context=', context)
            o.send('branch_path_context=', o.values.delete(:branch_path_context) || [])
          end
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
          #ds.opts[:last_record_id] = Sequel.qualify(versioned_table, :record_id)
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
        def last_record_id
          return opts[:last_record_id] if opts[:last_record_id]
          versioned_table ? Sequel.qualify(versioned_table, :record_id) : :record_id
        end

        # Pick latest versions and remove deleted records
        def finalize(opts = {})
          # Can we use opts[:from] instead of first_source_table and override?
          model_table_name = opts[:model_table_name] || model.raw_dataset.first_source_table
          sel_col = model.columns.map { |c| Sequel.qualify(model_table_name, c) }
          return select(*sel_col) if opts[:no_finalize]
          extra_columns = [opts[:extra_columns]].flatten.compact
          extra_columns_src = extra_columns.map { |c| c.try(:expression) || c }

          ds = select(*sel_col, *extra_columns,
                      Sequel.function(:rank)
                        .over(:partition => @opts[:partition_columns] ||
                                              (extra_columns_src +
                                               [last_record_id,
                                                last_branch_path].compact),
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

          ds = ds.from_self.where(:rank => 1)
          unless opts[:include_deleted]
            ds = ds.where(:deleted => false)
            ds = ds.where(:extra_deleted => false) if opts[:extra_deleted_column]
          end
          ds = ds.select(*model.columns)
          if opts[:extra_columns]
            ds = ds.select_append(*extra_columns.map { |c| c.try(:aliaz) || c })
          end
          ds = ds.select_append(:branch_path_context) if last_branch_path_context
          ds
        end

        #protected
        #def _all(block)
        #  super.map { |r| setup_object(r) }
        #end
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
        def branch_path(ctx = nil)
          Sequel.pg_array(branch_path_context(ctx) + branch_path_record, 'integer')
        end
        def branch_path_record
          self[:branch_path]
        end
        def branch_path_context(ctx = nil)
          (current_context(ctx).path_from(context) || []) + (@branch_path_context || [])
        end
        private
        def branch_path_context=(val)
          @branch_path_context = Sequel.pg_array(val, 'integer')
        end
        public

        def dup
          bpc = @branch_path_context
          c = @context
          super.instance_eval do
            @branch_path_context = bpc
            @context = c
            self
          end
        end

        def dup_with_context(ctx)
          s = self
          dup.instance_eval do
            ctx = current_context(ctx)
            branch_path_context = s.branch_path_context(ctx)
            @context = ctx
            self
          end
        end

        # Change equals to handle computed branch_path
        def eql?(obj)
          super(obj) && (obj.branch_path_context == branch_path_context)
        end

        def inspect
          str = "#<#{model.name} "
          str += "ctx=#{@context.id},#{@context.version},#{@context.user},[#{branch_path_context.join(',')}] " if @context
          str += "@values=#{inspect_values}>"
          str
        end

        def versions_dataset(all = false)
          ds = all ? self.class.raw_dataset : self.class.dataset(context, no_finalize: true)
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
          if self.class.columns.include?(:branch_id) # Kludge for inter branch edges
            values[:branch] = @context.branch_nil
            values[:branch_id] = @context.id
          end

          raise "No user" unless @context.user or values[:user]
          if @context.user and values[:user] and @context.user != values[:user]
            raise "Users are different"
          end
          values[:user] ||= @context.user

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
        private
        attr_writer :previous
        public
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
        # def _save(opts)
        #   super(opts)
        #   freeze
        #   self
        # end


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
      end


      module ClassMethods
        # join_table, context_version,
        # this_record_id   => left_record_id
        # this_branch_path => left_branch_path
        # inter { right_branch_id }
        def dataset_one_to_many(dataset, context_data, r)
          # Select edges connected to this node
          if r[:start_table]
            ds = dataset.from(r[:start_table])
                  .join(r[:join_table],
                        r[:left_record_id] => r[:this_record_id])
          else
            ds = dataset.from(r[:join_table])
                  .where(r[:left_record_id] => r[:this_record_id])
          end

          # Split edges between in context and out of context
          # Treat in context edges the same with or without inter branch
          if r[:inter]
            table_common = r[:join_table] #:connect_table

            # Determine if the connecting node is within the same context
            ds_common = ds.select_append(
                Sequel.expr(r[:right_branch_id] || :branch_id =>
                                db[context_data].select(:branch_id))
                .as(:in_context))

            if ctx_ver = r[:context_version]
              ds_common = ds_common.where { |o| o.version < ctx_ver }
            end

            ds_base = dataset.from(table_common)

            ds = ds_base.where(:in_context)
          end

          ds = ds.join_context(context_data,
                               join_column: r[:inter] == :branch ? r[:right_branch_id] : nil,
                               table_alias: :branch_edges)

          branch_path_select = ds.last_branch_path_context.concat(
              Sequel.qualify(r[:join_table], r[:left_branch_path]))

          ds = ds.where(branch_path_select => r[:this_branch_path])


          if r[:inter]
            ds = ds.select(Sequel::SQL::ColumnAll.new(table_common),
                           Sequel.qualify(:branch_edges, :depth)
                           .as(:edge_branch_depth),
                           Sequel.qualify(:branch_edges, :branch_path)
                           .as(:edge_branch_path))

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

        # join_table, context_version,
        # this_record_id   => left_record_id
        # this_branch_path => left_branch_path
        # right_record_id
        # right_branch_path
        # inter { right_branch_id }
        def dataset_many_to_many(dataset, context_data, r)
          ds  = dataset_one_to_many(dataset, context_data, r)

          # Join final nodes
          ds = ds.join(dataset.first_source_table,
                       :record_id => Sequel.qualify(r[:join_table],
                                                    r[:right_record_id]) )

          ds = dataset_many_to_one(ds, context_data, r,
                                   Sequel.qualify(:branch_edges,
                                                  :branch_path).pg_array.concat(
                                       Sequel.qualify(r[:join_table],
                                                      r[:right_branch_path]) ) )

          ds.finalize(extra_deleted_column: Sequel.qualify(r[:join_table],
                                                           :deleted),
                      extra_columns: r[:extra_columns])
        end

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

          ver_common_opts(opts)

          { left: self.name.underscore,
            right: name.to_s.singularize }.each do |prefix, key_prefix|
            ver_connect_opts(opts,
                           opts[:"#{prefix}_key_prefix"] ||= key_prefix,
                           prefix)
          end

          opts[:adder] = proc do |node, branch = nil, created_at = nil, delete = nil|
            ctx = current_context(branch, false)

            ctx.not_included!(self)
            ctx.not_included!(node) unless opts[:inter] == :branch

            h_record_id = {
                opts[:left_record_id] => record_id,
                opts[:right_record_id] => node.record_id,
            }

            h_branch_path = {
                opts[:left_branch_path] => branch_path,
                opts[:right_branch_path] => node.branch_path,
            }

            # !!! Implement check for inter_branch
            unless opts[:inter] == :branch
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
            if opts[:inter] == :branch
              h.merge!( opts[:left_branch_id] => ctx.id,
                        opts[:right_branch_id] => node.context.id )
            else
              h.merge!( :branch_id => ctx.id ) unless join_class
            end

            h.merge!(:created_at => created_at || self.class.dataset.current_datetime,
                     :deleted => delete ? true : false)

            if join_class
              h.merge!(type: join_class.to_s) if join_class.columns.include?(:type)
              join_class.create(h.merge(:context => ctx))
            else
              self.class.db[join_table].insert(h.merge(:user_id => ctx.user.id))
            end
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

              self.class.dataset_many_to_many(dataset, context_data,
                                              r.merge(this_record_id: record_id,
                                              this_branch_path: branch_path,
                                              context_version: current_context.version))
            end
          end

          many_to_many(name, opts, &block)
        end

        def ver_one_to_many(name, opts=OPTS, &block)
          opts = opts.dup
          ver_common_opts(opts)
          ver_connect_opts(opts, opts[:key] || name)
          ver_connect_opts(opts, opts[:target_prefix], :target)

          opts[:dataset] = proc do |r|
            current_context.not_included_or_duplicated!(context, false)
            current_context.dataset do |context_data|
              dataset = r.associated_class.raw_dataset
              ds = self.class.dataset_one_to_many(dataset, context_data,
                                   this_record_id: record_id,
                                   this_branch_path: branch_path,
                                   context_version: current_context.version,
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
