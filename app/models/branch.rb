class SubContextError < StandardError; end

# Represents Branch Context with a version lock
class BranchContext
  def initialize(branch, version = nil)
    @branch, @version = branch.freeze, version
  end
  attr_reader :branch, :version
  
  def id
    branch.id
  end
  
  def table
    return @table if @table
    @table = @branch.create_context_table(version)
  end
  
  def data
    return @data if @data
    @data = Branch.db[table].all
  end
  
  # Returns dataset or table if exists
  def dataset
    return @table if @table
    return @dataset if @dataset
    @dataset = @branch.context_dataset(@version)
  end

  private
  def id_ver(ctx)
    if ctx.is_a?(BranchContext)
      sub_id = ctx.branch.id
      sub_version = ctx.version
    elsif ctx.is_a?(Branch)
      sub_id = ctx.id
      sub_version = nil
    elsif ctx.is_a?(Integer)
      sub_id = ctx
      sub_version = nil
    elsif ctx.respond_to?(:branch_id)
      sub_id = ctx.branch_id
      sub_version = ctx.version if ctx.respond_to?(:version)
    else
      raise "Unkown type"
    end
    return sub_id, sub_version
  end
  public

  def not_included!(ctx)
    sub_id, sub_version = id_ver(ctx)
    # Avoid loading data if we don't have to
    if id == sub_id
      return if version.nil?
      unless sub_version && sub_version <= version
        raise SubContextError, "Branches match (#{id}) but #{version} > #{sub_version}" 
      end
    end
    hash = data.find { |h| h[:id] == sub_id }
    unless hash
      raise SubContextError, "Could not find branch match for #{sub_id}"
    end

    return if hash[:version].nil?
    unless sub_version && sub_version <= hash[:version]
      raise SubContextError, "Branch found (#{sub_id}: #{hash[:name]}) but #{hash[:version]} > #{sub_version}"
    end
  end
end


class Branch < Sequel::Model
  plugin :single_table_inheritance, :type

  many_to_many :predecessors, join_table: :branch_relations, :class => self,
                                left_key: :successor_id, right_key: :predecessor_id
  many_to_many :successors,   join_table: :branch_relations, :class => self,
                               right_key: :successor_id,  left_key: :predecessor_id

  private
  def _version_param(version)
    return nil unless version
    return Sequel.cast(Sequel.function(:nextval, 'version_seq'), :regclass) if version == true
    
    # Do we need to check if version number isn't in the future or lower than a decendent version lock?
    return version if version.is_a?(Integer)
    version.version
  end
  
  def _add_successor(o, version = nil)
    model.db[:branch_relations].insert(predecessor_id: id,
                                       successor_id: o.id,
                                       version: _version_param(version))
  end

  def _add_predecessor(o, version = nil)
    model.db[:branch_relations].insert(predecessor_id: o.id,
                                       successor_id: id,
                                       version: _version_param(version))

    # If we have temp tables in a context they should be invalidated here
  end

  public

  # Relations for all directly versioned objects
  # Should implement on Versioned concern include
  one_to_many :nodes

  # has_many :template_instances

  # Special create method that accepts a block within the context of the created block
  def self.create(values = {}, &block)
    if block_given?
      db.transaction do
        context(super(values, &nil), {}, &block)
      end
    else
      super values
    end
  end

  # Create new successor branch from current branch with option context block
  def fork(options = {}, &block)
    version = options.delete(:version_lock)
    db.transaction do
      o = self.class.create(options)
      add_successor(o, version)
      self.class.context(o, {}, &block)
    end
  end

  # Create new successor branch from listed branches
  # e.g.
  #   Branch.merge!(branch_a, branch_b, name: 'Branch Name')
  #   Branch.merge!(branch_list, name: 'Branch Name')
  def self.merge(*args, &block)
    options = args.pop
    version = options.delete(:version_lock)
    db.transaction do
      o = create(options)
      [args].flatten.each do |p|
        p.add_successor(o, version)
      end
      context(o, {}, &block)
    end
  end

 # one_to_many :decendants, read_only: true,
 #   dataset: proc do     
 #   end

  # Return dataset with this and all predecessor branch ids and maximum version number for that branch
  def context_dataset(version = nil)
    self.class.context_dataset(id, version)
  end

  def self.context_dataset(branch_id, version = nil)
    connect_table = :branch_relations
    cte_table = :branch_decend

    # Select this record as the start point of the recursive query
    # Include the version (or null) column used by recursive part
    base_ds = db[].select(Sequel.as(Sequel.cast(branch_id, :integer), :id),
                          Sequel.as(name, :name),
                          Sequel.as(Sequel.cast(nil, :integer), :successor_id),
                          Sequel.as(Sequel.cast(version, :bigint), :version),
                          Sequel.as(0, :depth) )
    
    # Connect from the working set (cte_table) through the connect_table back to this table
    # Use the least (lowest) version number from the current version or the connect_table version
    # This ensures the version column on the connect_table locks in all objects at or below that version
    recursive_ds = db[connect_table]
      .join(cte_table, [[:id, :successor_id]])
      .select(Sequel.qualify(connect_table, :predecessor_id),
              Sequel.qualify(cte_table, :name),
              Sequel.qualify(connect_table, :successor_id),
              Sequel.function(:LEAST, *[connect_table, cte_table].map { |t|
                                Sequel.qualify(t, :version) }),
              Sequel.+(:depth, 1)
              )

    db[cte_table]
      .with_recursive(cte_table, base_ds, recursive_ds, union_all: false)
#      .select_group(:id, :depth).select_append { min(:version).as(:version) }
  end

  def create_context_table(version = nil)
    table_name = "branch_decend_#{id}#{version && "_#{version}"}".to_sym
    ds = context_dataset(version)
    db.drop_table? table_name #unless self.class.in_context?
    db.create_table table_name, :temp => true, :as => ds, :on_commit => self.class.in_context? && :drop
    table_name
  end

  @@context_list = []

  def self.in_context?
    @@context_list.empty? ? nil : true
  end

  def self.current!
    @@context_list.last
  end

  def self.current
    raise "No current context" if @@context_list.empty?
    current!
  end

  # Get a BranchContext for the specified branch or use the current context
  # if false is specified for version, raise exception if the context has a version lock
  # this is needed for anything that modifies the database
  def self.get_context(branch = nil, version = nil)
    if branch
      if branch.is_a?(BranchContext)
        raise "Version specified with context" if version
        ctx = branch
      elsif branch.is_a?(Branch)
        ctx = BranchContext.new(branch, version ? version : nil)
      elsif branch.is_a?(Integer)
        ctx = BranchContext.new(Branch.find(id: branch), version ? version : nil)
      end

      if in_context?
        Branch.current!.not_included!(ctx)
        ctx = Branch.current!
      end
    else
      ctx = Branch.current
    end

    if version == false and ctx.version
      raise "Version less context required"
    end

    ctx
  end


  def context(opts=OPTS, &block)
    self.class.context(self, opts, &block)
  end

  def self.context(branch, opts=OPTS)
    return branch unless block_given?
    version = opts[:version]
    version = version.version if version and !version.is_a?(Integer)

    cur = BranchContext.new(branch, version)
    current!.not_included!(cur) if current!

    begin
      db.transaction(opts) do
        @@context_list.push(cur)
        
        yield branch
      end
    ensure
      if current
        raise "WTF" if cur != @@context_list.last
        @@context_list.pop
      end
    end
    branch
  end
end

class View < Branch
  def self.public
    return @@public.dup if class_variable_defined?('@@public')
    @@public = where(id: 1).first!
  end
end
