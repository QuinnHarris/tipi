class Branch < Sequel::Model
  plugin :single_table_inheritance, :type

  plugin :branch
end

class ProjectBranch < Branch
  
end

# Only one instance of this branch
class RootBranch < Branch
  def self.branch
    return @@root.dup if class_variable_defined?('@@root')
    @@root = where(id: 1).first!
  end

  def self.context(opts = {}, &block)
    unless defined? @@context
      @@context = branch.context
      @@context.data
      @@context.table_clear!
      @@context.freeze
    end
    ctx = opts.empty? ? @@context : @@context.new(opts)
    ctx.apply(&block)
  end
end
