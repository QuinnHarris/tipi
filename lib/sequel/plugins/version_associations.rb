class VersionedError < StandardError; end

module Sequel
  module Plugins
    module VersionAssociations
      module InstanceMethods
        # Branch Context associated with this object
        def context(user = nil, &block)
          unless ctx = @context
            ctx = Branch::Context.get(branch)
          end
          ctx.apply(user: user, &block)
        end

        private
        attr_writer :context

        # Current Branch Context
        def current_context(ctx = nil, version = nil)
          Branch::Context.get(ctx || Branch::Context.current! || context, version)
        end
        def current_context!(ctx = nil)
          current_context(ctx, false)
        end

        def dataset_from_edge(ds, r, context_data, node_branch_path)
          dataset = r.associated_class.raw_dataset

          # Change context_data to include context table for inter branch dst
          if r[:inter]
            table_common = r[:join_table]
            ds_br = ::Branch.context_dataset_from_set(dataset.from(table_common)
                                                    .exclude(:in_context),
                                                    r[:right_branch_id],
                                                    current_context.version)
            context_data = ds_br.union(
                db.from(context_data)
                .select_append(Sequel.as(nil, :context_id)))

            ds = ds.where { (Sequel.expr(:context_id => nil) & :in_context) |
                Sequel.expr(:context_id => r[:right_branch_id] ||
                                           Sequel.qualify(r[:join_table], :branch_id) ) }
          end

          # Join branch context table(s)
          ds = ds.join_context(context_data,
                               table_alias: :branch_nodes)

          # Exclude final nodes based on node branch_path
          if r[:inter]

          else
            ds = ds.where(node_branch_path => ds.last_branch_path)
          end

          ds
        end
      end

      module ClassMethods
        private
        def ver_common_opts(opts)
          unless [nil, :branch, :context].include?(opts[:inter])
            raise "inter must be :branch or :context"
          end
        end

        def ver_connect_opts(opts, key_prefix, prefix = nil)
          key_prefix = "#{key_prefix}_" if key_prefix
          prefix = "#{prefix}_" if prefix
          ['record_id', 'branch_path', opts[:inter] == :branch ? 'branch_id' : nil
          ].compact.each do |sufix|
            opts[:"#{prefix}#{sufix}"] ||= :"#{key_prefix}#{sufix}"
          end
          opts[:"#{prefix}key"] ||= [opts[:"#{prefix}record_id"]]
        end
        public

        def ver_many_to_one(name, opts=OPTS, &block)
          opts = opts.dup
          ver_common_opts(opts)
          ver_connect_opts(opts, opts[:key] || name)
          opts[:key] = opts[:record_id] # Kludge to prevent stack level to deep

          opts[:dataset] = proc do |r|
            current_context.not_included_or_duplicated!(context, false)
            current_context.dataset do |context_data|
              ds = r.associated_class.raw_dataset

              ds = ds.where(:record_id => send(opts[:record_id]))

              ds = dataset_from_edge(ds, r, context_data,
                                     Sequel.pg_array(branch_path_context +
                                                         send(opts[:branch_path]),
                                                     'integer') )

              ds.finalize
            end
          end

          opts[:setter] = proc do |obj|
            #opts = association_reflections[name]
            send("#{name}_record_id=", obj.record_id)
            if respond_to?("#{name}_branch_path}=")
              send("#{name}_branch_path}=", obj.branch_path)
            end
          end

          many_to_one(name, opts, &block)
        end

      end
    end
  end
end
