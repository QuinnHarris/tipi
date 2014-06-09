Resource

class Category < Sequel::Model
  plugin :versioned

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_many aspect, :class => self, join_table: :category_edges,
                     left_key_prefix: opposite, right_key_prefix: aspect
  end

  ver_many_to_many :resources, join_table: :category_resource, inter: :context

  alias_method :children, :to
  alias_method :parents, :from

  # Root category isn't versioned
  def self.root(context = nil)
    dataset(context).where(record_id: 1).first!
    #return @@root.dup if class_variable_defined?('@@root')
    #@@root = where(record_id: 1).first!
  end

  def previous_version(context = nil)
    ds = dataset(context, no_finalize: true)
    ds = ds.where(Sequel.qualify(table_name, :version) < context.version) if context.version
    ds.max(Sequel.qualify(table_name, :version))
  end

  # Add a project node with its own branch
  def add_project(values)
    # Need better way to request specific types
    #project = from_dataset.where(type: 'Project', name: values[:name]).first
    #raise "Project Exists: #{values[:name]}" if project
    #raise "Expected to be in View context" unless current_context!.branch.is_a?(ProjectBranch)
    project = nil
    RootBranch.root.fork(name: values[:name], class: ProjectBranch) do
      project = Project.create(values)
      add_resource(project)
      yield project if block_given?
    end
    project
  end

  def add_child(values)
    self.class.db.transaction do
      child = self.class.create(values.merge(:context => context))
      add_to(child)
      child
    end
  end

  def get_child(name)
    return child if child = to_dataset.where(name: name).first
    add_child(name: name)
  end

  def get_path(path)
    cur = self
    path.split('/').each do |name|
      cur = cur.get_child(name)
    end
    cur
  end

  # !!!! OLD CATEGORY CODE

  Branch

  # This should be removed soon
  def prev_version(context)
    ds = dataset_from_context(Branch::Context.new(context.branch), include_all: true)
    ds = ds.where(Sequel.qualify(table_name, :version) < context.version) if context.version
    ds.max(Sequel.qualify(table_name, :version))
  end
  def next_version(context)
    return nil unless context.version
    dataset_from_context(Branch::Context.new(context.branch), include_all: true)
    .where(Sequel.qualify(table_name, :version) < context.version)
    .min(Sequel.qualify(table_name, :version))
  end

#  def parents
#    return @parents if @parents
#    @parents = from_dataset.where(type: 'Category').all
#  end

  def children_and_projects
    return @children_and_projects if @children_and_projects
    @children_and_projects = from_dataset.where(type: %w(Category Project)).all
  end



end
