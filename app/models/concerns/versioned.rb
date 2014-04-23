#class ExistingVersion < ActiveRecord::ActiveRecordError
#end

module Versioned
  extend ActiveSupport::Concern

  included do
    many_to_one :branch

    set_primary_key :version

    # Dataset for latest version of rows within the provided branch (and predecessors)
    # Join against the branch dataset or table and use a window function to rank first by branch depth (high precident branches) and then latest version.  Only return the 1st ranked results.
    private
    def self.dataset_from_branch(branch_context_dataset)
      ds = dataset.join(branch_context_dataset, :id => :branch_id) do |j ,lj, js|
        Sequel.expr(Sequel.qualify(j, :version) => nil) | (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
      end
        .select(Sequel::SQL::ColumnAll.new(table_name)) { |o|
          o.rank.function.over(:partition => o.record_id, :order => [o.depth,  Sequel.qualify(table_name, :version).desc]) }

      dataset.from(ds).filter(:rank => 1, :deleted => false).select(*columns)
    end
    
    public
    # Kludgy: change dataset if in a context but only provide new behavoir once as dataset_from_branch and methods it calls will call dataset again.
    # There is probably a better way
    def self.dataset(branch = nil, version = nil)
      return super() if @in_dataset or (!Branch.in_context? and !branch)
      @in_dataset = true
      ds = dataset_from_branch(Branch.get_context_data(branch, version))
      @in_dataset = nil
      ds
    end

    # UBER Kludgy, used by node.rb association
    def self.raw_dataset
      @in_dataset = true
      ds = dataset
      @in_dataset = nil
      ds
    end

    # Automatically apply current context when creating object
    # Doesn't work right if you use your own model initializers
    def initialize(values = {})
      if current = Branch.current!
        raise "Can't add records with version lock" if current.version
        
        if values[:branch] || values[:branch_id]
          unless current.contains_branch?(branch)
            raise "Passed branch is not contained in this context"
          end
        else
          values[:branch] = current.branch
        end
      else
        raise "Must have branch if not in branch context" unless values[:branch] || values[:branch_id]
      end

      super values
    end

    def new(new_values = {}, &block)
      vals = values.dup
      # Should branch_id be kept or always reassigned?
      keep = [:record_id, :branch_id].each_with_object({}) do |column, hash|
        hash[column] = vals.delete(column)
      end
      # !!! Fix branch and branch_id handling
      keep[:branch_id] = Branch.get_branch(vals[:branch]).id
      [:version, :created_at].each { |column| vals.delete(column) }
      o = self.class.new(vals.merge(new_values), &block)
      o.values.merge!(keep)
      o
    end

    def create(values = {}, &block)
      new(values, &block).save
    end

    # Should delete just be a row tag or an whole new table as this wastes alot of space
    # This approach simplifies and probably speeds up queries though
    def delete(branch = nil)
      create(deleted: true, branch: branch)
    end

    # Check branch assignments are valid

    # Freeze objects retrieved from DB
    def self.call(values)
      o = super(values)
      o.freeze
      o
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
