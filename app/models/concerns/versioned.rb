#class ExistingVersion < ActiveRecord::ActiveRecordError
#end

module Versioned
  extend ActiveSupport::Concern

  included do
    many_to_one :branch

    # scope :where_branch, -> (branch) { where(branch.branch_where(self.table_name)) }

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
