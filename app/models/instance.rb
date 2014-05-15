class Instance < Sequel::Model
  aspects = %w(predecessor successor)
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect.pluralize.to_sym, join_table: :instance_relations, :class => self,
      left_key: :"#{opposite}_id", right_key: :"#{aspect}_id"
    
    one_to_many :"#{aspect}_relations", :class => InstanceRelation, key: :"#{opposite}_id"
  end

  one_to_many :actions

  # Code to link to specific node version.  Should be able to enumerate new versions of node

end
