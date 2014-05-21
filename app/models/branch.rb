class BranchContextError < StandardError; end

# Represents Branch Context with a version lock
class BranchContext
  # Don't duplicate BranchContexts
  def self.new(branch, version = nil)
    return branch if branch.is_a?(BranchContext) and !version
    super
  end

  def initialize(branch, version = nil)
    if branch.is_a?(Integer)
      @id = branch
    elsif branch.is_a?(Branch)
      @id = branch.id
      @branch = branch
    else
      raise "Unknown argument: #{branch.inspect}"
    end
    @version = version
  end
  attr_reader :id, :version

  def branch_nil; @branch; end

  def branch
    return @branch if @branch
    @branch = Branch.where(id: @id).first
  end

  def ==(other)
    id == other.id and version == other.version
  end

  def table_clear!
    @table = nil
  end
  
  def table
    return @table if @table
    @table = "branch_decend_#{id}#{version && "_#{version}"}".to_sym
    ds = branch.context_dataset(version)
    Branch.db.drop_table? @table #unless self.class.in_context?
    Branch.db.create_table @table, :temp => true, :as => ds, :on_commit => self.class.current! && :drop
    @table
  end
  
  def data
    return @data if @data
    @data = Branch.db[table].all
  end

  def reset!
    Branch.db.drop_table? @table if @table
    @table = nil
    @data = nil
  end
  
  # Returns dataset or table if exists
  def dataset
    if block_given?
      if @table
        ds = yield @table
      else
        @dataset ||=  @branch.context_dataset(@version)
        table_name = :branch_decend
        ds = yield table_name
        ds = ds.with(table_name, @dataset)
      end
      ds.send("context=", self)
      ds
    else
      return @table if @table
      @dataset ||= @branch.context_dataset(@version)
    end
  end

  # Context Stack
  @@context_stack = []

  def self.current!
    @@context_stack.last
  end

  def self.current
    raise BranchContextError, "No current context" if @@context_stack.empty?
    current!
  end

  # Get a BranchContext for the specified branch or use the current context
  # if false is specified for version, raise exception if the context has a version lock
  # this is needed for anything that modifies the database
  def self.get(branch = nil, version = nil)
    if branch
      ctx = self.new(branch, version ? version : nil)
      current!.not_included!(ctx) if current!
    else
      ctx = current
    end

    if version == false and ctx.version
      raise BranchContextError, "Context without version required"
    end

    ctx
  end

  def apply(opts = {})
    return self unless block_given?
    begin
      Branch.db.transaction(opts) do
        @@context_stack.push(self)
        table # Generate context table
        
        yield branch
      end
    ensure
      raise "WTF" if self != @@context_stack.last
      table_clear! # !!!Remove table reference incase droped when transaction is complete.  Fix this
      @@context_stack.pop
    end
    self
  end


  # Information and checking methods
  private
  def id_version(ctx, sub_version = nil)
    if ctx.is_a?(BranchContext)
      sub_id = ctx.branch.id
      raise "Unexpected Version" if sub_version
      sub_version = ctx.version
    elsif ctx.is_a?(Branch)
      sub_id = ctx.id
    elsif ctx.is_a?(Integer)
      sub_id = ctx
    elsif ctx.respond_to?(:branch_id)
      sub_id = ctx.branch_id
      if ctx.respond_to?(:version)
        raise "Unexpected Version" if sub_version
        sub_version = ctx.version
      end
    else
      raise "Unkown type"
    end
    return sub_id, sub_version
  end
  public

  # Raise BranchContextError if the passed branch/context is not included in this context
  def not_included!(ctx, ver = nil)
    sub_id, sub_version = id_version(ctx, ver)
    # Avoid loading data if we don't have to
    if id == sub_id
      return if version.nil? or ver == false
      unless sub_version && sub_version <= version
        raise BranchContextError, "Branch match (#{id}) but #{version} > #{sub_version}"
      end
      return
    end
    hash = data.find { |h| h[:branch_id] == sub_id }
    unless hash
      raise BranchContextError, "Branch not found for #{sub_id}"
    end

    return sub_id if hash[:version].nil? or ver == false
    unless sub_version && sub_version <= hash[:version]
      raise BranchContextError, "Branch found (#{sub_id}: #{hash[:name]}) but #{hash[:version]} > #{sub_version}"
    end
    return sub_id
  end

  # Raise BranchContextError if objects from the passed branch/context would have been
  # duplicated through merged branches to this context
  def not_included_or_duplicated!(ctx, ver = nil)
    sub_id = not_included!(ctx, ver)
    return unless sub_id

    while true
      list = data.find_all { |h| h[:branch_id] == sub_id }
      raise BranchContextError, "Object Duplicated: #{list.inspect}" if list.length > 1
      raise "Unexpected empty list" if list.empty?
      if list.first[:successor_id]
        sub_id = list.first[:successor_id]
      else
        raise "Did not find root" unless sub_id == id
        break
      end
    end
  end

  # Called after not_included_or_duplicated!
  def path_from(ctx)
    sub_id, sub_version = id_version(ctx)
    
    path = []
    while sub_id
      suc = data.find { |h| h[:branch_id] == sub_id }[:successor_id]
      path << sub_id if data.find_all { |h| h[:successor_id] == suc }.length > 1
      sub_id = suc
    end
    path
  end
end


class Branch < Sequel::Model
  plugin :single_table_inheritance, :type

  aspects = %w(predecessor successor)
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect.pluralize.to_sym, join_table: :branch_relations, :class => self,
      left_key: :"#{opposite}_id", right_key: :"#{aspect}_id"
    
    one_to_many :"#{aspect}_relations", :class => BranchRelation, key: :"#{opposite}_id"
  end

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
        o = super(values, &nil)
        o.context(&block)
        o
      end
    else
      super values
    end
  end

  # Create new successor branch from current branch with option context block
  def fork(options = {}, &block)
    version = options.delete(:version_lock)
    klass = options.delete(:class) || self.class
    raise "Must be Branch class: #{klass}" unless klass <= Branch
    db.transaction do
      o = klass.create(options)
      add_successor(o, version)
      o.context(&block)
      o
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
      o.context(&block)
      o
    end
  end

  def subordinate(options, &block)
    klass = options.delete(:class) || self.class
    raise "Must be Branch class: #{klass}" unless klass <= Branch
    BranchContext.current.reset! if BranchContext.current! # Should make this more efficient, NEEDS PROPER TEST
    db.transaction do
      if (merge_point == false) and !predecessors.empty?
        raise "Merge not allowed on this branch #{merge_point.inspect}"
      end
      o = klass.create(options)
      add_predecessor(o)
      o.context(&block)
      o
    end
  end

 # one_to_many :decendants, read_only: true,
 #   dataset: proc do     
 #   end

  # Return dataset with this and all predecessor branch ids and maximum version number for that branch
  def context_dataset(version = nil)
    self.class.context_dataset(id, name, merge_point, version)
  end

  def self.has_merge_point?
    columns.include?(:merge_point)
  end

  def self.use_context_name?
    has_merge_point? || Rails.env.development?
  end

  def self.context_dataset(branch_id, name = nil, merge_point = nil, version = nil)
    # Select this record as the start point of the recursive query
    # Include the version (or null) column used by recursive part
    b_ds = db[].select(
        Sequel.as(branch_id, :branch_id),
        Sequel.cast(nil, :integer).as(:successor_id),
        Sequel.cast(version, :bigint).as(:version),
        Sequel.as(0, :depth),
        Sequel.cast(Sequel.pg_array([]), 'integer[]').as(:branch_path) )

    b_ds = b_ds.select_append(Sequel.as(name, :name)) if use_context_name?
    b_ds = b_ds.select_append(Sequel.as(merge_point || false,
                                        :merge_point) ) if has_merge_point?

    context_dataset_recursive(b_ds)
  end

  def self.context_dataset_from_set(ds, join_column = :branch_id, version = nil)
    if has_merge_point? or use_context_name?
      ds = ds.join(table_name, :id => join_column)
    end

    ds = ds.distinct(join_column).select(
        Sequel.as(join_column, :branch_id),
        Sequel.cast(nil, :integer).as(:successor_id),
        Sequel.cast(version, :bigint).as(:version),
        Sequel.as(0, :depth),
        Sequel.cast(Sequel.pg_array([]), 'integer[]').as(:branch_path) )

    ds = ds.select_append(:name) if use_context_name?
    ds = ds.select_append(Sequel.function(:coalesce,
                            :merge_point,
                            false).as(:merge_point)) if has_merge_point?

    ds = ds.select_append(Sequel.as(join_column, :context_id))

    context_dataset_recursive(ds, true)
  end

  def self.context_dataset_recursive(base_ds, include_context = nil)
    cte_table = :branch_decend
    connect_table = :branch_relations

    # Connect from the working set (cte_table) through the connect_table back to
    # this table.  Use the least (lowest) version number from the current
    # version or the connect_table version.  This ensures the version column
    # on the connect_table retrieves in all objects at or below that version.
    r_ds = db.from(cte_table)
    .join(connect_table, :successor_id => :branch_id)
    r_ds = r_ds.join(table_name,
                     :id => :predecessor_id) if use_context_name? or
        has_merge_point?
    r_ds = r_ds.select(
        Sequel.as(:predecessor_id, :branch_id),
        Sequel.qualify(connect_table, :successor_id),
        Sequel.function(:LEAST,
                        *[connect_table, cte_table].map { |t|
                          Sequel.qualify(t, :version) })
        .as(:version),
        Sequel.+(:depth, 1).as(:depth),
        :branch_path,
        Sequel.function(:count).*
        .over(:partition =>
                  Sequel.qualify(connect_table, :successor_id)).as(:count) )
    r_ds = r_ds.select_append(
        Sequel.qualify(table_name, :name)) if use_context_name?
    r_ds = r_ds.select_append(
        Sequel.qualify(cte_table, :merge_point).as(:merge_siblings),
        Sequel.function(:coalesce,
                        Sequel.qualify(table_name, :merge_point),
                        false).as(:merge_point) )  if has_merge_point?
    r_ds = r_ds.select_append(:context_id) if include_context

    bp_app_cond = Sequel.expr(:count) > 1
    bp_app_cond = bp_app_cond | Sequel.expr(:merge_siblings) if has_merge_point?
    r_ds = db.from(r_ds)
    .select(:branch_id, :successor_id, :version, :depth,
            Sequel.case([[bp_app_cond,
                          Sequel.pg_array(:branch_path)
                          .concat(:branch_id) ]],
                        :branch_path) )
    r_ds = r_ds.select_append(:name) if use_context_name?
    r_ds = r_ds.select_append(:merge_point) if has_merge_point?
    r_ds = r_ds.select_append(:context_id) if include_context

    ds = db[cte_table].with_recursive(cte_table, base_ds, r_ds)
      .select(:branch_id, :successor_id, :version, :depth, :branch_path)
    ds = ds.select_append(:name) if use_context_name?
    ds
  end

  def context(opts=OPTS, &block)
    self.class.context(self, opts, &block)
  end

  def self.context(branch, opts=OPTS, &block)
    BranchContext.get(branch, opts[:version]).apply(opts, &block)
  end
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

