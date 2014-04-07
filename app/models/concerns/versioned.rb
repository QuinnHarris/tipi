#class ExistingVersion < ActiveRecord::ActiveRecordError
#end

module Versioned
  extend ActiveSupport::Concern

  included do
    many_to_one :branch

    # Determined automatically with PostgreSQL
    #primary_key [:record_id, :branch_id, :version]

    # Dataset for rows only in the given branch (and predecessors)
    # This will likely be replaced with a better interface
    def self.dataset_for_branch(branch, version = nil)
      branch_dataset = branch.branch_dataset(version)
      
      pk_ds = dataset.join(branch_dataset, :id => :branch_id) do |j ,lj, js|
        Sequel.expr(Sequel.qualify(j, :version) => nil) | (Sequel.qualify(lj, :version) <= Sequel.qualify(j, :version))
      end
        .select_group(:record_id, :branch_id)
        .select_append { |o| o.max(Sequel.qualify(table_name, :version)) }

      dataset.filter([:record_id, :branch_id, :version] => pk_ds)
    end

    def new(new_values = {}, &block)
      vals = values.dup
      keep = [:record_id, :branch_id].each_with_object({}) do |column, hash|
        hash[column] = vals.delete(column)
      end
      [:version, :created_at].each { |column| vals.delete(column) }
      o = self.class.new(vals.merge(new_values), &block)
      o.values.merge!(keep)
      o
    end

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
