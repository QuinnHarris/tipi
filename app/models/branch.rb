class Branch < Sequel::Model
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
  def decend_dataset(version = nil)
    self.class.decend_dataset(id, version)
  end

  def self.decend_dataset(branch_id, version = nil)
    connect_table = :branch_relations
    cte_table = :branch_decend

    # Select this record as the start point of the recursive query
    # Include the version (or null) column used by recursive part
    base_ds = db[].select(Sequel.as(Sequel.cast(branch_id, :integer), :id),
                          Sequel.as(0, :depth),
                          Sequel.as(Sequel.cast(version, :bigint), :version))
    
    # Connect from the working set (cte_table) through the connect_table back to this table
    # Use the least (lowest) version number from the current version or the connect_table version
    # This ensures the version column on the connect_table locks in all objects at or below that version
    recursive_ds = db[connect_table]
      .join(cte_table, [[:id, :successor_id]])
      .select(Sequel.qualify(connect_table, :predecessor_id),
              Sequel.+(:depth, 1),
              Sequel.function(:LEAST, *[connect_table, cte_table].map { |t|
                                Sequel.qualify(t, :version) }))

    db[cte_table]
      .with_recursive(cte_table, base_ds, recursive_ds, union_all: false)
  end

  def create_decend_table(version = nil)
    table_name = "branch_decend_#{id}#{version && "_#{version}"}".to_sym
    dataset = decend_dataset(version)
    db.create_table table_name, :temp => true, :as => dataset, :on_commit => self.class.in_context? && :drop
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

  # Represents Branch Context with a version lock
  class BranchContext
    def initialize(branch, version)
      @branch, @version = branch, version
    end
    attr_reader :branch, :version

    def id
      branch.id
    end

    def table
      return @table if @table
      @table = @branch.create_decend_table(version)
    end

    def data
      return @data if @data
      @data = Branch.db[table].all
    end

    def contains_branch?(branch)
      data.find { |h| h[:id] == branch.id }
    end
  end

  def context(opts=OPTS, &block)
    self.class.context(self, opts, &block)
  end

  def self.context(branch, opts=OPTS)
    return branch unless block_given?
    version = opts[:version]
    version = version.version if version and !version.is_a?(Integer)

    if cur = @@context_list.last
      unless rec = cur.contains_branch?(branch)
        raise "Branch #{branch.id} not predicessor of #{cur.branch.id}"
      end
      version = [version, rec[:version]].compact.min
    end

    current = nil
    begin
      db.transaction(opts) do
        current = BranchContext.new(branch, version)
        @@context_list.push(current)
        
        yield branch
      end
    ensure
      if current
        raise "WTF" if current != @@context_list.last
        @@context_list.pop
      end
    end
    branch
  end
end
