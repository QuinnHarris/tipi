Branch

module DatasetBranchContext
  attr_reader :context
  private
  attr_writer :context

  def setup_object(o)
    return o if o.frozen?
    if context and o.respond_to?(:context)
      o.send('context=', context)
      o.send('branch_path_context=', o.values.delete(:branch_path_context) || [])
    end
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

  # Join a branch context table to the current dataset the context will apply to.
  def join_context(context_data, options = {})
    join_column = options[:join_column] || :branch_id

    prior_table = opts[:last_joined_table] || opts[:from].first

    ds = join(context_data, { :branch_id => join_column }, options) do |j, lj|
      Sequel.expr(Sequel.qualify(j, :version) => nil) |
          (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
    end
    ds.opts[:last_branch_path_context] =
        Sequel.qualify(ds.opts[:last_joined_table], :branch_path).pg_array
    ds.opts[:last_branch_path] =
        ds.opts[:last_branch_path_context].concat(
            Sequel.qualify(prior_table, :branch_path))
    ds.opts[:last_record_id] = Sequel.qualify(prior_table, :record_id)
    ds.opts[:order_columns] = (ds.opts[:order_columns] || []) +
        [Sequel.qualify(ds.opts[:last_joined_table], :depth),
         Sequel.qualify(prior_table, :version).desc]
    ds
  end

  def last_branch_path_context; @opts[:last_branch_path_context]; end
  def last_branch_path; @opts[:last_branch_path]; end
  def last_record_id; @opts[:last_record_id]; end

  # Pick latest versions and remove deleted records
  def finalize(opts = {})
    model_table_name = model.raw_dataset.first_source_table
    ds = select(*model.columns.map { |c|
                    Sequel.qualify(model_table_name, c) },
                Sequel.function(:rank)
                  .over(:partition => [last_record_id || :record_id,
                                       last_branch_path],
                        :order     => @opts[:order_columns] ||
                                        Sequel.qualify(model_table_name,
                                                       :version).desc))
    if last_branch_path_context
      ds = ds.select_append(last_branch_path_context.as(:branch_path_context))
    end

    if opts[:extra_deleted_column]
      ds = ds.select_append(opts[:extra_deleted_column].as(:extra_deleted))
    end

    return ds if opts[:include_all]

    ds = ds.from_self
           .where(:rank => 1)
    unless opts[:include_deleted]
      ds = ds.where(:deleted => false)
      ds = ds.where(:extra_deleted => false) if opts[:extra_deleted_column]
    end
    ds = ds.select(*model.columns)
    ds = ds.select_append(:branch_path_context) if last_branch_path_context
    ds
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

    def current_context(ctx = nil, version = nil)
      BranchContext.get(ctx || BranchContext.current! || context, version)
    end
    def current_context!(ctx = nil)
      current_context(ctx, false)
    end
    public


    def branch_path(ctx = nil)
      Sequel.pg_array(branch_path_context(ctx) + branch_path_record, 'integer')
    end
    def branch_path_record
      self[:branch_path]
    end
    def branch_path_context(ctx = nil)
      (current_context(ctx).path_from(context) || []) + @branch_path_context
    end
    private
    def branch_path_context=(val)
      @branch_path_context = Sequel.pg_array(val, 'integer')
    end
    public

    def set_context!(ctx)
      @branch_path_context = branch_path_context(ctx)
      @context = current_context(ctx)
    end

    # Change equals to handle computed branch_path
    def eql?(obj)
      super(obj) && (obj.branch_path_context == branch_path_context)
    end

    def inspect
      "#<#{model.name} ctx=#{@context.id},#{@context.version},[#{@branch_path_context.join(',')}] @values=#{inspect_values}>"
    end

    # Dataset for latest version of rows within the provided branch (and predecessors)
    # Join against the branch dataset or table and use a window function to rank first by branch depth (high precident branches) and then latest version.  Only return the 1st ranked results.
    private
    def self.dataset_from_context(context, options = {})
      context.dataset do |context_dataset|
        raw_dataset.join_context(context_dataset).finalize(options)
      end
    end
    public
    
    # Kludgy: change dataset if in a context but only provide new behavior once
    # as dataset_from_context and methods it calls will call dataset again.
    # There is probably a better way
    self.singleton_class.send(:alias_method, :raw_dataset, :dataset)
    def self.dataset(branch = nil, options = {})
      return super() if @in_dataset or (!BranchContext.current! and !branch)
      @in_dataset = true
      context = BranchContext.get(branch)
      ds = dataset_from_context(context, options)
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
      ds = dataset_from_context(BranchContext.new(context.branch), include_all: true)
      ds = ds.where { |o| o.nodes__version < context.version } if context.version
      ds.max(Sequel.qualify(:nodes, :version))
    end
    def self.next_version(context)
      return nil unless context.version
      dataset_from_context(BranchContext.new(context.branch), include_all: true).where { |o| o.nodes__version > context.version }.min(Sequel.qualify(:nodes, :version))
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

      @branch_path_context = []

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

      vals[:branch_path] = branch_path(ctx)

      # !!! Apply cached branch if available
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
    def delete(values = {})
      # !!! Shouldn't be able to delete already deleted object
      create(values.merge(deleted: true))
    end

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
