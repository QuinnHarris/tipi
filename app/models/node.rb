class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :edges, :class => self, reciprocal: opposite,
                         left_key: "#{aspect}_version".to_sym,
                         right_key: "#{opposite}_version".to_sym,
    :select => nil, # Don't override our select statements
    :dataset =>
      (proc do |r|
         ctx = Branch.get_context(context)
         branch_context_data = ctx.dataset

         dataset = r.associated_class.raw_dataset
         
         # Assuming this node is the latest in the current branch context
         # Otherwise we need to establish a new context from this branch version and branch ids
         ds = dataset.join(Sequel.as(:nodes, :dst),
                           :record_id => :record_id) do |j, lj|
           Sequel.qualify(j, :version) <= Sequel.qualify(lj, :version)
         end
           .join(r[:join_table], r[:right_key] => :version)
           .join(Sequel.as(:nodes, :src), :version => r[:left_key])
           .where(Sequel.qualify(:src, :record_id) => record_id) { |o|
           Sequel.qualify(:src, :version) <= version } # Neccissary?
         
         # Must check to from branch context if there is a version lock
         tables = [r[:join_table], :nodes, :src]
         tables.each do |table|
           ds = ds.join(Sequel.as(branch_context_data, "branch_#{table}"),
                        :id => Sequel.qualify(table, :branch_id)) do |j, lj|
             Sequel.expr(Sequel.qualify(j, :version) => nil) | 
               (Sequel.qualify(table, :version) <= Sequel.qualify(j, :version))
           end
         end
         
         ds = ds.select(Sequel::SQL::ColumnAll.new(:nodes),
                        Sequel.as(Sequel.qualify(r[:join_table], :deleted),
                                  :join_deleted)) do |o|
           o.rank.function
             .over(:partition => Sequel.qualify(:nodes, :record_id),
                   :order => tables.map do |t|
                     [Sequel.qualify(:"branch_#{t}", :depth),
                      Sequel.qualify(t, :version).desc]
                   end.flatten)
         end
         
         ds = dataset.from(ds).filter(:rank => 1, :deleted => false, :join_deleted => false).select(*r.associated_class.columns)
         ds.send("context=" ,ctx)
         ds
       end)

    define_method "_add_#{aspect}" do |node, branch = nil, deleted = nil|
      ctx = Branch.get_context(branch || context, false)
      
      unless ctx.includes?(self)
        raise "Self branch not in context"
      end

      unless ctx.includes?(node)
        raise "Passed branch not in context"
      end

      h = { :branch_id => ctx.branch.id,
        :"#{aspect}_version" => version,
        :"#{opposite}_version" => node.version,
        :created_at => self.class.dataset.current_datetime,
        :deleted => deleted ? true : false}
      
      Edge.dataset.insert(h)
    end

    define_method "_remove_#{aspect}" do |node, branch = nil|
      # !!! Must check if the object actually exists
      send("_add_#{aspect}", node, branch, true)
    end

    # _remove_ and _remove_all_
  end
end

class Project < Node

end

class Step < Node

end

# Categories can only be contained by other categories
class Category < Node
  def self.root
    # Must duplicate for each call so the BranchContext isn't cached
#    return @@root.dup if class_variable_defined?('@@root')
    @@root = dataset(View.public).where(version: 1).first!
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
      child = Category.create(values.merge(:context => context))
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

  def add_project(name)
    # Need better way to request specific types
    project = from_dataset.where(type: 'Project', name: name).first
    raise "Project Exists: #{name}" if project
    project = Project.create(name: name)
    add_to(project)
    project
  end
end
