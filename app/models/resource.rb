class Resource < Sequel::Model
  plugin :single_table_inheritance, :type
  plugin :versioned

  ver_one_to_many :task

  # Probably need association that can find instances of this and all older
  # versions of this resource.
  one_to_many :instances, key: [:resource_version, :resource_branch_path],
              primary_key: [:version, :branch_path]


  ver_many_to_many :categories, join_table: :category_resource

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_many aspect, :class => self, join_class: ResourceEdge,
                     left_key_prefix: opposite, right_key_prefix: aspect

    ver_one_to_many :"#{aspect}_edge", :class => ResourceEdge,
                    key: opposite, target_prefix: aspect,
                    read_only: true
  end

  def to_param
    "#{record_id}-#{branch_id}"
  end
end

class UserResource < Resource
  def self.public
    return @@public.dup if class_variable_defined?('@@public')
    @@public = where(id: 1).first!
  end
end

class Project < Resource
  def clone(opts = {})
    p = nil
    branch.fork(name: opts[:name]) do
      p = create(opts)
    end
    p
  end
end