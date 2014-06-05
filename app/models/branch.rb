class Branch < Sequel::Model
  plugin :single_table_inheritance, :type

  plugin :branch
end

class ProjectBranch < Branch
  
end

class RootBranch < Branch
  def initialize(values = {})
    super({ :merge_point => true }.merge(values))
  end

  def self.root
    return @@root.dup if class_variable_defined?('@@root')
    @@root = where(id: 1).first!
  end
end
