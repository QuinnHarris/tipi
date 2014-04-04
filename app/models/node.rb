class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  keys = [:record_id, :branch_id, :version]
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :edges, :class => self, reciprocal: opposite,
                         left_key: keys.map { |k| "#{aspect}_#{k}".to_sym },
                         right_key: keys.map { |k| "#{opposite}_#{k}".to_sym }
    # No timestamps on edges (:before_add
  end
end

class Project < Node

end

class Step < Node

end
