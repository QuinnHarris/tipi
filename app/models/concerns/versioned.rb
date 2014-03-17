class ExistingVersion < ActiveRecord::ActiveRecordError
end

module Versioned
  extend ActiveSupport::Concern

  included do
    default_scope { readonly }

    belongs_to :branch

    # Clear version just like id is cleared when record.dup
    def initialize_dup(other)
      super other
      @attributes['version'] = nil
      @readonly = false
    end

    # Should we have to be explicit about creating a new version?
    def new_version
      object = self.dup
      object.instance_variable_set('@association_cache', @association_cache)
      object
    end

    private
    # Would be better to use sequence as column DEFAULT but that requires significant rework in the postgres active record adaptor to query the resulting value.  Querying the sequence after the insert won't work as it could have changed between the insert and select (sequences are independent of transactions)
    def sequence_nextval(column)
      Integer(ActiveRecord::Base.connection.select_all("select nextval('#{self.class.table_name}_#{column}_seq');").rows.first.first)
    end

    # Set current value of record_id when this is a new record
    before_create :set_record_id
    def set_record_id
      return if record_id
      write_attribute(:record_id, sequence_nextval('record_id'))
    end

    # Set set this object version
    before_save :set_version
    def set_version
      raise ActiveRecord::ReadOnlyRecord if readonly?
      raise ExistingVersion unless new_record?
      raise ExistingVersion if version # we set the version here
      write_attribute(:version, sequence_nextval('version'))
    end

    # Once saved the row can't be changed
    after_save :readonly!
  end
end
