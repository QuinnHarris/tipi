class Resource < Sequel::Model
  plugin :single_table_inheritance, :type
  plugin :versioned

  many_to_one :user

  ver_one_to_many :task

  # Probably need association that can find instances of this and all older
  # versions of this resource.
  one_to_many :instances, key: [:resource_version, :resource_branch_path],
              primary_key: [:version, :branch_path]


  ver_many_to_many :categories, join_table: :category_resource, inter: :context

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

# All User Resources are in the Root Branch
class UserResource < Resource
  def self.public
    return @@public.dup if class_variable_defined?('@@public')
    @@public = where(record_id: 1).first!.freeze
  end

  def self.access_dataset(user, filter = 2147483647)
    cte_table = :access_decend

    base_ds = raw_dataset.where(:record_id => [user && user.resource_record_id, 1].compact).finalize
    base_ds = base_ds.select_append(Sequel.as(filter, :access))

    r_ds = Resource.raw_dataset.from(cte_table).join(:resource_edges,
                                                 :from_record_id => :record_id)
    r_ds = r_ds.join(:resources, :record_id => :to_record_id)

    r_ds.opts[:last_joined_table] = nil # Don't do branch_path
    r_ds.opts[:versioned_table] = :resources
    r_ds.opts[:partition_columns] = [Sequel.qualify(:resources, :branch_id),
                                     Sequel.qualify(:resources, :record_id)]
    r_ds.opts[:order_columns] = [Sequel.qualify(:resources, :version),
                                 Sequel.qualify(:resource_edges, :version)]

    r_ds = r_ds.finalize(:extra_columns =>
                             (Sequel.qualify(cte_table, :access).sql_number &
                                 Sequel.qualify(:resource_edges, :access)).as(:access),
    )

    r_ds = r_ds.exclude(:access => 0)

    Resource.raw_dataset.from(cte_table).with_recursive(cte_table, base_ds, r_ds)
  end

  def self.access_dataset_with_categories(user, filter = 2147483647)
    ds = access_dataset(user, filter)

    ds = ds.join(:category_resource, :resource_record_id => :record_id)

    ds.opts[:last_joined_table] = nil # Don't do branch_path
    ds.opts[:partition_columns] = [:resource_record_id, :category_record_id]
    ds.opts[:order_columns] = [Sequel.qualify(:category_resource, :version)]

    ds.finalize(:model_table_name => ds.opts[:from].first,
                :extra_columns => [:category_record_id, :category_branch_path])
  end
end

class Project < Resource
  def clone(opts = {})
    p = nil
    branch.fork(name: opts[:name], user: opts[:user]) do
      p = create(opts)
    end
    p
  end
end