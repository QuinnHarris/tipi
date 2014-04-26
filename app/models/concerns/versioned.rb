#class ExistingVersion < ActiveRecord::ActiveRecordError
#end

module DatasetBranchContext
  attr_reader :context
  private
  attr_writer :context

  def setup_object(o)
    return o if o.frozen?
    o.send('context=', context) if context
    o.freeze
    o
  end

  public
  def delete
    raise "Delete not permited on versioned datasets"
  end

  def update
    raise "Update not permited on versioned datasets"
  end

  def each
    super() do |r|
      yield setup_object(r)
    end
  end

  def paged_each(opts=OPTS)
    super(opts) do |r|
      yield setup_object(r)
    end
  end

  def first
    o = super
    o && setup_object(o)
  end

  protected
  def _all(block)
    super.map { |r| setup_object(r) }
  end
end

module Versioned
  extend ActiveSupport::Concern

  included do
    many_to_one :branch

    set_primary_key :version

    dataset_module DatasetBranchContext
    attr_reader :context
    private
    attr_writer :context
    attr_writer :previous
    public

    # Dataset for latest version of rows within the provided branch (and predecessors)
    # Join against the branch dataset or table and use a window function to rank first by branch depth (high precident branches) and then latest version.  Only return the 1st ranked results.
    private
    def self.dataset_from_branch(branch_context_dataset, allow_deleted = nil)
      ds = raw_dataset.join(branch_context_dataset, :id => :branch_id) do |j ,lj, js|
        Sequel.expr(Sequel.qualify(j, :version) => nil) | (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
      end
        .select(Sequel::SQL::ColumnAll.new(table_name)) { |o|
          o.rank.function.over(:partition => o.record_id, :order => [o.depth,  Sequel.qualify(table_name, :version).desc]) }

      # User original dataset if single table inheritance is used
      ds = (@sti_dataset || raw_dataset).from(ds).filter(:rank => 1)
      ds = ds.filter(:deleted => false) unless allow_deleted
      ds.select(*columns)
    end
    public
    
    # Kludgy: change dataset if in a context but only provide new behavoir once as dataset_from_branch and methods it calls will call dataset again.
    # There is probably a better way
    self.singleton_class.send(:alias_method, :raw_dataset, :dataset)
    def self.dataset(branch = nil, allow_deleted = nil)
      return super() if @in_dataset or (!Branch.in_context? and !branch)
      @in_dataset = true
      context = Branch.get_context(branch)
      context.table # Temporary
      ds = dataset_from_branch(context.dataset, allow_deleted)
      ds.send("context=", context)
      @in_dataset = nil
      ds
    end

    def versions
      self.class.raw_dataset.where(record_id: record_id).order(:version).reverse.all
    end

    # Automatically apply current context when creating object
    # Doesn't work right if you use your own model initializers
    def initialize(values = {})
      raise "Can't specify record_id" if values[:record_id]
      raise "Can't specify version" if values[:version]

      # Should this use Branch.get_context ?

      current = Branch.current!

      if values[:branch] && values[:branch_id] &&
          values[:branch].id != values[:branch_id]
        raise "Mismatched branch with branch_id"
      end

      if ctx = values.delete(:context)
        if values[:branch] && ctx.branch != values[:branch]
          raise "Specified branch doesn't match context"
        end
        if values[:branch_id] && ctx.branch.id != values[:branch_id]
          raise "Specified branch_id doesn't match montext"
        end
        if current && ctx != current
          raise "Specified context not current context"
        end
        current = ctx
      end

      if current
        raise "Can't add records with version lock" if current.version
        
        if br = (values[:branch] || values[:branch_id])
          unless current.includes?(br)
            raise "Passed branch is not contained in this context"
          end
        else
          values[:branch] = current.branch
          values[:branch_id] = current.branch.id
        end
      else
        raise "Must have branch if not in branch context" unless values[:branch] || values[:branch_id]
      end

      #values[:branch_id] ||= values[:branch].id if values[:branch]

      super values
    end

    def new(new_values = {}, &block)
      vals = values.dup
      record_id = vals.delete(:record_id) # Remove record_id to make initialize happy
      [:version, :created_at].each { |column| vals.delete(column) }
      vals[:context] = context if context
      # !!! Apply cached branch if availible
      o = self.class.new(vals.merge(new_values), &block)
      o.values.merge!(:record_id => record_id)
      o.send('previous=', self)
      o
    end

    # Make active model methods work right with versioning
    def persisted?
      !@previous.nil? || super
    end
    def to_key
      @previous ? @previous.to_key : super
    end
    

    def create(values = {}, &block)
      new(values, &block).save
    end

    # Should delete just be a row tag or an whole new table as this wastes alot of space
    # This approach simplifies and probably speeds up queries though
    def delete(branch = nil)
      ctx = Branch.get_context(branch || context, false)
      create(deleted: true, context: ctx)
    end

    # Check branch assignments are valid

    # Freeze objects retrieved from DB
    # Now done in dataset module
#    def self.call(values)
#      o = super(values)
#      o.freeze
#      o
#    end

    private
    # Freeze objects after save
    # Can't use after_save because class is modified after that call
    def _save(opts)
      super(opts)
      freeze
      self
    end
  end
end
