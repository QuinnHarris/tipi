class Instance < Sequel::Model
  many_to_one :user

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :instance_relations, :class => self,
      left_key: :"#{opposite}_id", right_key: :"#{aspect}_id"
    
    one_to_many :"#{aspect}_edge", :class => InstanceEdge, key: :"#{opposite}_id"
  end

  one_to_many :actions

  many_to_one :resource, key: [:resource_version, :resource_branch_path],
              primary_key: [:version, :branch_path]

  # Code to link to specific node version.  Should be able to enumerate new versions of node

end
