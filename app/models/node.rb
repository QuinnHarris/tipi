# Used to use function in pg array range accessors
class ExRange < Range
  def initialize(b, e)
    @begin, @end = b, e
  end
  attr_reader :begin, :end
end

module Sequel
  module Postgres
    class ArrayOp
      # Possible inclusion in Sequel to make pg_array_op perform as expected with arrays
      def initialize(value)
        if value.instance_of?(Array)
          super Sequel.pg_array(value)
        else
          super value
        end
      end

      def [](key)
        b = self
        # Kludge to wrap array in parenthesis
        b = SQL::Function.new('', b) if value.is_a?(PGArray)
        s = Sequel::SQL::Subscript.new(b, [key])
        s = ArrayOp.new(s) if key.is_a?(Range)
        s
      end
    end
  end

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
    end

    module ClassMethods
      def ver_many_to_many(name, opts=OPTS, &block)
        opts = opts.dup

        # join_class
        join_table = opts[:join_table]
        if join_class = opts[:join_class]
          raise "Can't specify join_class if join_table specified" if join_table
          join_table ||= opts[:join_class].table_name
          opts[:join_table] = join_table
        end

        left_key_prefix = opts.delete(:key) || name
        opts[:left_key] ||= ["#{left_key_prefix}_record_id"] # branch_path?
        if right_key_prefix = opts[:reciprocal]
          opts[:right_key] = ["#{right_key_prefix}_record_id"]
        end
        opts[:left_key_prefix] = left_key_prefix
        opts[:right_key_prefix] = right_key_prefix

        opts.merge!(
          :select => nil, # Don't override our select statements
          :dataset => (proc do |r|
            current_context.not_included_or_duplicated!(context, false)
            current_context.dataset do |context_data|
              dataset = r.associated_class.raw_dataset

              ds = dataset.from(r[:join_table])

              # Select edges connected to this node
              edge_src_path = Sequel.pg_array(:"#{r[:left_key_prefix]}_branch_path")
              this_branch_path = Sequel.pg_array_op(branch_path)
              ds = ds.where(:"#{r[:left_key_prefix]}_record_id" => record_id,
                            this_branch_path[
                                ExRange.new(1, Sequel.function(:coalesce,
                                                               edge_src_path.length,
                                                               0))] =>
                                edge_src_path)

              order_cols = []

              if r[:inter_branch]
                table_common = r[:join_table] #:connect_table

                # Determine if the connecting node is within the same context
                ds_common = ds.select_append(
                  Sequel.expr(:"#{r[:right_key_prefix]}_branch_id" =>
                                  db[context_data].select(:branch_id))
                    .as(:in_context))

                ds = dataset.from(table_common)

                ds_br = Branch.context_dataset_from_set(ds.exclude(:in_context),
                                                        :"#{r[:right_key_prefix]}_branch_id")

                ds = ds.with(table_common, ds_common)

                context_data = ds_br.union(
                    db.from(context_data)
                      .select_append(Sequel.as(nil, :context_id)))

                ds = ds.where { (Sequel.expr(:context_id => nil) & :in_context) |
                                Sequel.expr(:context_id => :"#{r[:right_key_prefix]}_branch_id") }
              else
                ds = ds.join_branch(context_data,
                                    join_table: r[:join_table],
                                    table_alias: :branch_edges)
                order_cols << Sequel.qualify(:branch_edges, :depth)
                order_cols << Sequel.qualify(r[:join_table], :version).desc
              end

              # Join final nodes
              ds = ds.join(:nodes,
                           :record_id => Sequel.qualify(r[:join_table],
                                                        "#{r[:right_key_prefix]}_record_id") )

              # Join branch context table(s)
              ds = ds.join_branch(context_data,
                                  join_table: :nodes,
                                  table_alias: :branch_nodes)
              order_cols << Sequel.qualify(:branch_nodes, :depth)
              order_cols << Sequel.qualify(:nodes, :version).desc

              # Exclude final nodes based on node branch_path
              edge_dst_path = Sequel.pg_array(:"#{r[:right_key_prefix]}_branch_path")
              branch_path_ctx = Sequel.qualify(:branch_nodes, :branch_path).pg_array
              branch_path_select = branch_path_ctx.concat(
                                        Sequel.qualify(:nodes, :branch_path))
              ds = ds.where(branch_path_select[
                                ExRange.new(1, Sequel.function(:coalesce,
                                                               edge_dst_path.length,
                                                               0))] =>
                      edge_dst_path)

              # NEED TO CHECK THIS MORE
              # Exclude final nodes based on left context branch_path
              # Ensures nodes will only link to other nodes in the same branch path
              # if those nodes are duplicated by a merge
              unless branch_path_context.empty?
                this_branch_path_context = Sequel.pg_array_op(branch_path_context)
                array_bounds = ExRange.new(1,
                                   Sequel.function(:LEAST,
                                       Sequel.function(:coalesce,
                                                       branch_path_ctx.length,
                                                       0),
                                       branch_path_context.length) )
                array_bounds =  ExRange.new(1,
                                   Sequel.function(:coalesce,
                                      Sequel.qualify(:branch_edges, :branch_path)
                                        .pg_array.length,
                                      0) ) unless r[:inter_branch]
                ds = ds.where(this_branch_path_context[array_bounds] =>
                                  branch_path_ctx[array_bounds])
              end

              ds = ds.select(Sequel::SQL::ColumnAll.new(:nodes),
                             branch_path_ctx.as(:branch_path_context),
                             Sequel.as(Sequel.qualify(r[:join_table], :deleted),
                                       :join_deleted),
                             Sequel.function(:rank)
                               .over(:partition => [:record_id, branch_path_select],
                                     :order => order_cols))

              ds.from_self
                .where(:rank => 1, :deleted => false, :join_deleted => false)
                .select(*r.associated_class.columns, :branch_path_context)
            end
          end)
        )
        many_to_many(name, opts, &block)

        # Should break sequel convention and return the edge object
        define_method "_add_#{name}" do |node, branch = nil, created_at = nil, deleted = nil|
          ctx = current_context(branch, false)

          ctx.not_included!(self)
          ctx.not_included!(node) unless opts[:inter_branch]

          h = if opts[:inter_branch]
                { :"#{opts[:left_key_prefix]}_branch_id" => ctx.id,
                  :"#{opts[:right_key_prefix]}_branch_id" => node.context.id }
              else
                { :branch_id => ctx.branch.id }
              end

          h.merge!(:"#{opts[:left_key_prefix]}_record_id" => record_id,
                   :"#{opts[:left_key_prefix]}_branch_path" => branch_path,
                   :"#{opts[:right_key_prefix]}_record_id" => node.record_id,
                   :"#{opts[:right_key_prefix]}_branch_path" => node.branch_path,
                   :created_at => created_at || self.class.dataset.current_datetime,
                   :deleted => deleted ? true : false)

          join_class.create(h)
        end

        define_method "_remove_#{name}" do |node, branch = nil, created_at = nil|
          # !!! Must check if the object actually exists
          send("_add_#{name}", node, branch, created_at, true)
        end
        # _remove_ and _remove_all_
      end

      def ver_many_to_one(name, opts=OPTS, &block)
        opts[:dataset] = proc do |r|
          current_context.not_included_or_duplicated!(context, false)
          current_context.dataset do |context_data|
            ds = r.associated_class.raw_dataset
          end
        end

        many_to_one(name, opts, &block)
      end

      def ver_one_to_many(name, opts=OPTS, &block)
        opts[:dataset] = proc do |r|
          current_context.not_included_or_duplicated!(context, false)
          current_context.dataset do |context_data|
            ds = r.associated_class.dataset

            # Select edges connected to this node
            edge_src_path = Sequel.pg_array(:"#{r[:left_key_prefix]}_branch_path")
            this_branch_path = Sequel.pg_array_op(branch_path)
            ds = ds.where(:"#{r[:left_key_prefix]}_record_id" => record_id,
                          this_branch_path[
                              ExRange.new(1, Sequel.function(:coalesce,
                                                             edge_src_path.length,
                                                             0))] =>
                              edge_src_path)

            unless r[:inter_branch]
              ds = ds.join_branch(
                  context_data,
                  context_column: r[:inter_branch] && :"#{r[:right_key_prefix]}_branch_id",
                  join_table: r.associated_class.table_name,
                  table_alias: :"branch_#{table}")
            end

            ds
          end
        end

        one_to_many(name, opts, &block)
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
                    :class => join_class,
                    inter_branch: inter_branch, read_only: true
  end
  end

  def client_values
    {        id: version,
      record_id: record_id,
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
