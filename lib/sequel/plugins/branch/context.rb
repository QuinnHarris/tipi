class BranchContextError < StandardError; end

# Represents Branch Context with a version lock
class Sequel::Plugins::Branch::Context
  # Don't duplicate BranchContexts
  def self.new(branch, version = nil)
    return branch if branch.is_a?(self) and !version
    super
  end

  def initialize(branch, version = nil, user = nil)
    if branch.is_a?(Integer)
      @id = branch
    elsif branch.is_a?(Branch)
      @id = branch.id
      @branch = branch
    else
      raise "Unknown argument: #{branch.inspect}"
    end
    @version = version
    @user = user
  end
  attr_reader :id, :version, :user

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
    opts = opts.dup
    user_list = [opts.delete(:user), @user,
                 self.class.current! && self.class.current!.user]
    the_user = user_list.compact.uniq
    if the_user.length > 1
      raise "More than one user specified: #{user_list.inspect}"
    end
    @user = the_user.first
    begin
      @@context_stack.push(self)
      Branch.db.transaction(opts) do
        table # Generate context table

        yield branch
      end
    ensure
      raise "Context Stack Empty" if @@context_stack.empty?
      raise "Top of stack context mismatch" if self != @@context_stack.last
      table_clear! # !!!Remove table reference incase droped when transaction is complete.  Fix this
      @@context_stack.pop
    end
    self
  end


  # Information and checking methods
  private
  def id_version(ctx, sub_version = nil)
    if ctx.is_a?(self.class)
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

    return [] if sub_id == id

    path = []
    while sub_id
      elem = data.find { |h| h[:branch_id] == sub_id }
      return nil unless elem
      suc = elem[:successor_id]
      path << sub_id if data.find_all { |h| h[:successor_id] == suc }.length > 1
      sub_id = suc
    end
    path
  end
end
