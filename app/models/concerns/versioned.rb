Branch

module DatasetBranchContext
  attr_reader :context
  private
  attr_writer :context

  def setup_object(o)
    return o if o.frozen?
    o.send('context=', context) if context and o.respond_to?(:context)
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

  def join_branch(context_data, options = {})
    join_column = options[:join_table] ?
        Sequel.qualify(options[:join_table], :branch_id) : :branch_id

    join(context_data, { :branch_id => join_column }, options) do |j, lj|
      exp = Sequel.expr(Sequel.qualify(j, :version) => nil) |
          (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
      if options[:context_column]
        exp &= (Sequel.expr(:context_id => nil) & :in_context) |
            Sequel.expr(:context_id => options[:context_column])
      end
      exp
    end
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

    # Include branch_path as primary key as branching can cause duplicate (but different) objects with the same version.  Only version should be used to update rows though.
    set_primary_key :version
    #, :branch_path]

    dataset_module DatasetBranchContext
    def context(&block)
      @context.apply(&block)
    end

    def with_this_context
      return self if context.id == branch_id
      o = dup
      ctx = o.send("context=", BranchContext.get(branch_id, context.version))
      path = context.path_from(ctx)
      o.branch_path -= path # Should work but doesn't check for problems
      o.freeze
      o
    end
    private
    attr_writer :context
    attr_writer :previous

    def current_context(branch = nil, version = nil)
      BranchContext.get(branch || BranchContext.current! || context, version)
    end
    def current_context!(branch = nil)
      current_context(branch, false)
    end
    public

    # Dataset for latest version of rows within the provided branch (and predecessors)
    # Join against the branch dataset or table and use a window function to rank first by branch depth (high precident branches) and then latest version.  Only return the 1st ranked results.
    private
    def self.dataset_from_context(context, options = {})
      context.dataset do |branch_context_dataset|
        ds = raw_dataset.join_branch(branch_context_dataset)
        
        branch_path_select = Sequel.qualify(ds.opts[:last_joined_table], :branch_path)
          .pg_array.concat(Sequel.qualify(table_name, :branch_path) )
        
        ds = ds.select(*(columns - [:branch_path]).map { |n| Sequel.qualify(table_name, n) },
                       branch_path_select.as(:branch_path))
        
        next ds if options[:versions]

        ds = ds.select_append(Sequel.function(:rank)
                                .over(:partition => [:record_id, branch_path_select],
                                      :order => [:depth, Sequel.qualify(table_name, :version).desc] ) )
        
        # Use original dataset if single table inheritance is used
        ds = (@sti_dataset || raw_dataset).from(ds).filter(:rank => 1)
        ds = ds.filter(:deleted => false) unless options[:deleted]
        ds.select(*columns)
      end
    end
    public
    
    # Kludgy: change dataset if in a context but only provide new behavoir once as dataset_from_context and methods it calls will call dataset again.
    # There is probably a better way
    self.singleton_class.send(:alias_method, :raw_dataset, :dataset)
    def self.dataset(branch = nil, options = {})
      return super() if @in_dataset or (!BranchContext.current! and !branch)
      @in_dataset = true
      context = BranchContext.get(branch)
      ds = dataset_from_context(context, options = {})
      @in_dataset = nil
      ds
    end

    def versions_dataset(all = false)
      ds = all ? self.class.raw_dataset : self.class.dataset_from_context(context, versions: true)
      ds.where(record_id: record_id)
    end
    def versions(all = false)
      versions_dataset(all).order(:version).reverse.all
    end

    def self.prev_version(context)
      ds = dataset_from_context(BranchContext.new(context.branch), versions: true)
      ds = ds.where { |o| o.nodes__version < context.version } if context.version
      ds.max(Sequel.qualify(:nodes, :version))
    end
    def self.next_version(context)
      return nil unless context.version
      dataset_from_context(BranchContext.new(context.branch), versions: true).where { |o| o.nodes__version > context.version }.min(Sequel.qualify(:nodes, :version))
    end

    private
    def check_context_specifier(values)
      list = [:context, :branch, :branch_id].map { |i| values[i] }.compact
      if list.length > 1
        raise "Only specify one context, branch or branch_id"
      end
      list.first
    end
    public

    # Doesn't work right if you use your own model initializers
    def initialize(values = {})
      raise "Can't specify record_id" if values[:record_id]
      raise "Can't specify version" if values[:version]

      @context = BranchContext.get(check_context_specifier(values), false)

      values = values.dup
      values.delete(:context)
      values[:branch] = @context.branch_nil
      values[:branch_id] = @context.id

      super values
    end

    def new(new_values = {}, &block)
      vals = values.dup

      raise "Expected context" unless context

      unless check_context_specifier(new_values)
        vals[:context] = context unless BranchContext.current!
      end
      record_id = vals.delete(:record_id) # Remove record_id to make initialize happy
      [:version, :branch_id, :created_at].each { |column| vals.delete(column) }
      vals = vals.merge(new_values) # Should only have one context specifier

      ctx = BranchContext.new(vals[:context] || vals[:branch] || vals[:branch_id] || BranchContext.current!)
      ctx.not_included!(branch_id, version)
      ctx.not_included_or_duplicated!(context, false)
      # We assume context includes branch_id

      vals[:branch_path] = ctx.path_from(context) + vals[:branch_path]

      # !!! Apply cached branch if availible
      o = self.class.new(vals, &block)
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
      # !!! Shouldn't be able to delete already deleted object
      create(deleted: true, branch: branch)
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
