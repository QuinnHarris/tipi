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
end

class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  [[:edges, false], [:edge_inters, true]].each do |join_table, inter_branch|
  aspects = inter_branch ? [:from_inter, :to_inter] : [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: join_table, :class => self,
                         reciprocal: opposite,
                         left_key: [:"#{aspect}_record_id"], #, :"#{aspect}_branch_path"],
                         right_key: [:"#{opposite}_record_id"], #, :"#{opposite}_branch_path"],
      :select => nil, # Don't override our select statements
      :dataset => (proc do |r|
        current_context.not_included_or_duplicated!(context, false)
        current_context.dataset do |context_data|
          dataset = r.associated_class.raw_dataset


          ds = dataset.from(r[:join_table])

          # Select edges connected to this node
          edge_src_path = Sequel.pg_array(:"#{aspect}_branch_path")
          this_branch_path = Sequel.pg_array_op(branch_path)
          ds = ds.where(:"#{aspect}_record_id" => record_id,
                      this_branch_path[ExRange.new(1, Sequel.function(:coalesce,
                                                          edge_src_path.length,
                                                          0))] =>
                            edge_src_path)

          if inter_branch
            table_common = :connect_table

            # Determine if the connecting node is within the same context
            # Only relevant for inter_branch links
            ds_common = ds.select_append(Sequel.expr(:"#{opposite}_branch_id")
                                         .in?(db[context_data]
                                              .select(:branch_id))
                                         .as(:in_context))

            ds = db.from(table_common)

            ds_br = Branch.context_dataset_from_set(ds.exclude(:in_context),
                                                    :"#{opposite}_branch_id")
            context_data = ds_br.union(
                db.from(context_data)
                .select_append(Sequel.as(false, :context_id)))
          end

          # Join final nodes
          ds = ds.join(:nodes, :record_id => :"#{opposite}_record_id")

          # Join branch context table(s)
          tables = [:nodes]
          tables.unshift(r[:join_table]) unless inter_branch
          tables.each do |table|
            ds = ds.join_branch(
                   context_data,
                   context_column: inter_branch && :"#{opposite}_branch_id",
                   join_table: table,
                   table_alias: :"branch_#{table}")
          end

          # Exclude final nodes based on branch_path
          edge_dst_path = Sequel.pg_array(:"#{opposite}_branch_path")
          branch_path_select =
              Sequel.qualify(ds.opts[:last_joined_table], :branch_path)
              .pg_array.concat(Sequel.qualify(:nodes, :branch_path))
          ds = ds.where(
              branch_path_select[ExRange.new(1, Sequel.function(:coalesce,
                                                    edge_dst_path.length,
                                                    0))] =>
                  edge_dst_path)

          ds = ds.select(*(r.associated_class.columns-[:branch_path]).map { |n|
                             Sequel.qualify(:nodes, n) },
                         branch_path_select.as(:branch_path),
                         Sequel.as(Sequel.qualify(r[:join_table], :deleted),
                                   :join_deleted),
                         Sequel.function(:rank)
                         .over(:partition => [:record_id, branch_path_select],
                               :order => tables.map do |t|
                                 [Sequel.qualify("branch_#{t}", :depth),
                                  Sequel.qualify(t, :version).desc]
                               end.flatten))

          ds = ds.with(table_common, ds_common) if inter_branch

          dataset.from(ds)
            .where(:rank => 1, :deleted => false, :join_deleted => false)
            .select(*r.associated_class.columns)
        end
      end)

    define_method "_add_#{aspect}" do |node, branch = nil, deleted = nil|
      ctx = current_context(branch, false)
      
      ctx.not_included!(self)
      ctx.not_included!(node) unless inter_branch

      h = if inter_branch
        { :"#{aspect}_branch_id" => ctx.id,
          :"#{opposite}_branch_id" => node.context.id }
      else
        { :branch_id => ctx.branch.id }
      end
      
      h.merge!(:"#{aspect}_record_id" => record_id,
               :"#{aspect}_branch_path" => branch_path,
               :"#{opposite}_record_id" => node.record_id,
               :"#{opposite}_branch_path" => node.branch_path,
               :created_at => self.class.dataset.current_datetime,
               :deleted => deleted ? true : false)
      
      Edge.dataset.insert(h)
    end

    define_method "_remove_#{aspect}" do |node, branch = nil|
      # !!! Must check if the object actually exists
      send("_add_#{aspect}", node, branch, true)
    end

    # _remove_ and _remove_all_
  end
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
