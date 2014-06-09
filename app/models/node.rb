class Node < Sequel::Model
  plugin :single_table_inheritance, :type

  plugin :versioning
  [[Edge, false], [EdgeInter, true]].each do |join_class, inter_branch|
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    relation_name = :"#{aspect}#{inter_branch ? '_inter' : ''}"
    ver_many_to_many relation_name, key: aspect,
                     join_class: join_class, :class => self,
                     reciprocal: opposite, inter_branch: inter_branch

    ver_one_to_many :"#{relation_name}_edge", key: aspect, reciprocal: opposite,
                    :class => join_class, target_prefix: opposite,
                    inter_branch: inter_branch, read_only: true
  end
  end

  def client_values(no_bp = nil)
    res = %w(record_id branch_id created_at name doc)
      .each_with_object({}) do |attr, hash|
      hash[attr] = send attr
    end
    res['branch_path'] = branch_path unless no_bp
    res.merge('id' => version)
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

Branch

# Categories can only be contained by other categories
class Category < Node
  def self.root(version = nil)
    # Must duplicate for each call so the BranchContext isn't cached
#    return @@root.dup if class_variable_defined?('@@root')
    @@root = dataset(Sequel::Plugins::Branch::Context.new(ViewBranch.public, version)).where(version: 1).first!
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
