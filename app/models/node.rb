module Sequel
  module Plugins
  module Versioning
    module InstanceMethods
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
        raise(Sequel::Error, "expected #{opts[:join_class]} from _add_method got #{r.inspect}") unless r.instance_of?(opts[:join_class])
        if array = associations[opts[:name]] and !array.include?(o)
          array.push(o)
        end
        add_reciprocal_object(opts, o)
        run_association_callbacks(opts, :after_add, o)
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

      def dataset_from_edge(ds, r, context_data, node_branch_path)
        dataset = r.associated_class.raw_dataset

        # Change context_data to include context table for inter branch dst
        if r[:inter_branch]
          table_common = r[:join_table]
          ds_br = Branch.context_dataset_from_set(dataset.from(table_common)
                                                  .exclude(:in_context),
                                                  r[:right_branch_id],
                                                  current_context.version)
          context_data = ds_br.union(
              db.from(context_data)
              .select_append(Sequel.as(nil, :context_id)))

          ds = ds.where { (Sequel.expr(:context_id => nil) & :in_context) |
              Sequel.expr(:context_id => r[:right_branch_id]) }
        end

        # Join branch context table(s)
        ds = ds.join_context(context_data,
                            table_alias: :branch_nodes)

        # Exclude final nodes based on node branch_path
        if r[:inter_branch]

        else
          ds = ds.where(node_branch_path => ds.last_branch_path)
        end

        ds
      end
    end

    module ClassMethods
      private
      def ver_common_ops(opts, key_prefix, prefix = nil)
        key_prefix = "#{key_prefix}_" if key_prefix
        prefix = "#{prefix}_" if prefix
        ['record_id', 'branch_path', opts[:inter_branch] && 'branch_id'
        ].compact.each do |sufix|
          opts[:"#{prefix}#{sufix}"] ||= :"#{key_prefix}#{sufix}"
        end
        opts[:"#{prefix}key"] ||= [opts[:"#{prefix}record_id"]]
      end
      public

      def ver_many_to_many(name, opts=OPTS, &block)
        opts = opts.dup

        # join_class
        join_table = opts[:join_table]
        if join_class = opts[:join_class]
          raise "Can't specify join_class if join_table specified" if join_table
          join_table ||= opts[:join_class].table_name
          opts[:join_table] = join_table
        end

        { left: opts.delete(:key) || name,
          right: opts[:reciprocal] }.each do |prefix, key_prefix|
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

          # !!! Implement check with inter_branch
          unless opts[:inter_branch]
            ds = join_class.dataset(ctx, no_finalize: true).where(h_record_id)
            h_branch_path.each do |col, val|
              ds = ds.where(ds.last_branch_path_context.concat(
                                Sequel.qualify(ds.versioned_table, col)) => val)
            end
            p = ds.order(Sequel.qualify(ds.versioned_table, :version).desc).first
            exists = p && !p.deleted
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

          join_class.create(h)
        end

        opts[:remover] = proc do |node, branch = nil, created_at = nil|
          # !!! Must check if the object actually exists
          send("_add_#{name}", node, branch, created_at, true)
        end
        # _remove_ and _remove_all_

        opts[:select] = nil
        opts[:dataset] = proc do |r|
          current_context.not_included_or_duplicated!(context, false)
          current_context.dataset do |context_data|
            dataset = r.associated_class.raw_dataset
            ds  = dataset_to_edge(dataset, context_data, r)

            # Join final nodes
            ds = ds.join(:nodes,
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

      def ver_many_to_one(name, opts=OPTS, &block)
        opts = opts.dup
        ver_common_ops(opts, opts[:key] || name)
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

        many_to_one(name, opts, &block)
      end

    end
  end
  end
end


class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  plugin :versioning
  [[Edge, false], [EdgeInter, true]].each do |join_class, inter_branch|
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    relation_name = :"#{aspect}#{inter_branch ? '_inter' : ''}"
    ver_many_to_many relation_name, key: aspect,
                     join_class: join_class, :class => self,
                     reciprocal: opposite, inter_branch: inter_branch

    ver_one_to_many :"#{relation_name}_edge", key: aspect,
                    :class => join_class, target_prefix: opposite,
                    inter_branch: inter_branch, read_only: true
  end
  end

  def client_values
    {        id: version,
      record_id: record_id,
    branch_path: branch_path,
     created_at: created_at,
           name: name,
            doc: doc }
  end
end

class Project < Node
  def clone(opts = {})
    raise "Expected view context" unless context.branch.is_a?(ViewBranch)
    raise "Expected one from: #{from.inspect}" unless from.length == 1
    category = from.first
    raise "Expected category: #{category.inspect}" unless category.is_a?(Category)

    o = self.with_this_context
    raise "Expected ProjectBranch: #{context.inspect}" unless o.context.branch.is_a?(ProjectBranch)
    db.transaction do
      br = o.context.branch.fork(name: opts[:name]) do
        o = o.create(opts)
      end
      br.add_successor(context.branch)

      context.reset! # This should be automatic

      # o has different branch path in view context
      o = o.dup
      o.branch_path = [br.id]

      category.add_to(o)
    end
    o
  end
end

class Step < Node

end

# Categories can only be contained by other categories
class Category < Node
  def self.root(version = nil)
    # Must duplicate for each call so the BranchContext isn't cached
#    return @@root.dup if class_variable_defined?('@@root')
    @@root = dataset(BranchContext.new(ViewBranch.public, version)).where(version: 1).first!
  end

  alias_method :children, :to
  alias_method :parents, :from

#  def parents
#    return @parents if @parents
#    @parents = from_dataset.where(type: 'Category').all
#  end

  def children_and_projects
    return @children_and_projects if @children_and_projects
    @children_and_projects = from_dataset.where(type: %w(Category Project)).all
  end

  def add_child(values)
    self.class.db.transaction do
      child = self.class.create(values.merge(:context => context))
      add_to(child)
      child
    end
  end

  def get_child(name)
    child = from_dataset.where(type: 'Category', name: name).first
    return child if child
    add_child(name: name)
  end

  def get_path(path)
    cur = self
    path.split('/').each do |name|
      cur = cur.get_child(name)
    end
    cur
  end

  # Add a project node with its own branch
  def add_project(values)
    # Need better way to request specific types
    project = from_dataset.where(type: 'Project', name: values[:name]).first
    raise "Project Exists: #{values[:name]}" if project
    raise "Expected to be in View context" unless current_context!.branch.is_a?(ViewBranch)
    br = current_context.branch.subordinate(name: values[:name],
                                       class: ProjectBranch) do
      project = Project.create(values)
      yield project if block_given?
    end
    # Kludge to set path correctly !!! NEED TO FIX
    project = project.dup
    project.branch_path = [br.id]
    add_to(project)
    project
  end
end
