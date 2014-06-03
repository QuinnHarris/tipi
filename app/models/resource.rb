class Resource < Sequel::Model
  plugin :single_table_inheritance, :type
  plugin :versioned

  ver_one_to_many :task

  # Probably need association that can find instances of this and all older
  # versions of this resource.
  one_to_many :instances, key: [:resource_version, :resource_branch_path],
              primary_key: [:version, :branch_path]

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_many aspect, key: aspect,
                     join_class: ResourceEdge, :class => self,
                     reciprocal: opposite

    ver_one_to_many :"#{aspect}_edge", key: aspect, reciprocal: opposite,
                    :class => ResourceEdge, target_prefix: opposite,
                    read_only: true
  end
end
