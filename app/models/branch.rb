class Branch < Sequel::Model
  plugin :single_table_inheritance, :type

  plugin :branch
end

class ProjectBranch < Branch
  
end

class ViewBranch < Branch
  def initialize(values = {})
    super({ :merge_point => true }.merge(values))
  end

  def self.public
    return @@public.dup if class_variable_defined?('@@public')
    @@public = where(id: 1).first!
  end
end
