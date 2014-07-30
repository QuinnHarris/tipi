class Forbidden < StandardError; end

class PermissionToken
  def initialize(value)
    @value = value
  end
  attr_accessor :value
end

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

  attr_reader :permission

  def self.access(record_id, filter = 2147483647)
    cte_table = :access_decend

    r = association_reflections[:from]
          .merge(this_record_id: Sequel.qualify(cte_table, :record_id),
                 this_branch_path: Sequel.qualify(cte_table, :branch_path),
                 context_version: nil,
                 start_table: cte_table,
                 extra_columns: Sequel.qualify(cte_table, :access))

    user_record_id = [current_context.user && current_context.user.resource_record_id, 1].compact

    ds = current_context.dataset do |context_data|
      # Class exclusion where IN clause goes through with_recursive
      base_ds = Resource.where(record_id: Integer(record_id))
      base_ds = base_ds.select_append(Sequel.as(filter, :access))

      r_ds = self.dataset_many_to_many(Resource.raw_dataset, context_data, r) do |ds|
        ds.where(~Sequel.expr(Sequel.qualify(raw_dataset.first_source_table, :type) => 'UserResource') |
                     Sequel.expr(Sequel.qualify(raw_dataset.first_source_table, :record_id) => user_record_id))
      end

      Resource.raw_dataset.from(cte_table).with_recursive(cte_table, base_ds, r_ds)
        .where(~Sequel.expr(:type => 'UserResource') | Sequel.expr(:record_id => user_record_id))
        .order(Sequel.expr(:type => 'UserResource'))
        .limit(2)
    end

    resource, user = ds.all

    raise Sequel::NoMatchingRow unless resource
    raise Forbidden unless user

    resource.instance_variable_set('@permission', PermissionToken.new(user.values[:access]))
    resource.values.delete(:access)
    resource
  end


  def access_resources
    from_dataset.where(:type => 'UserResource').all
  end
end

# All User Resources are in the Root Branch
class UserResource < Resource
  #one_to_one :user, key: :resource_record_id, primary_key: :record_id

  #mount_uploader :avatar, AvatarUploader

  # !! Replace with identifier table (email (multiple), alias)
  def email; data && data['email']; end
  def email=(val);
    self.data = Sequel.hstore({}) unless data
    self.data['email'] = val;
  end

  def self.public
    return @@public.dup if class_variable_defined?('@@public')
    @@public = where(record_id: 1).first!.freeze
  end

  def self.access_dataset(opts = {})
    cte_table = :access_decend

    user = opts[:user]
    version = opts[:version]
    filter = opts[:filter] || 2147483647

    base_ds = raw_dataset.where(:record_id => [user && user.resource_record_id, 1].compact)
    #base_ds = base_ds.where { |o| o.version <= version } if version
    base_ds = base_ds.finalize
    base_ds = base_ds.select_append(Sequel.as(filter, :access))

    r_ds = Resource.raw_dataset.from(cte_table).join(:resource_edges,
                                                 :from_record_id => :record_id)
    r_ds = r_ds.join(:resources, :record_id => :to_record_id)

    r_ds.opts[:last_joined_table] = nil # Don't do branch_path
    r_ds.opts[:versioned_table] = :resources
    r_ds.opts[:partition_columns] = [Sequel.qualify(:resources, :branch_id),
                                     Sequel.qualify(:resources, :record_id)]
    r_ds.opts[:order_columns] = [Sequel.qualify(:resources, :version).desc,
                                 Sequel.qualify(:resource_edges, :version).desc]

    r_ds = r_ds.where { |o| (Sequel.qualify(:resources, :version) <= version) &
        (Sequel.qualify(:resource_edges, :version) <= version) } if version
    r_ds = r_ds.finalize(:extra_columns =>
                             (Sequel.qualify(cte_table, :access).sql_number &
                                 Sequel.qualify(:resource_edges, :access)).as(:access),
    )

    r_ds = r_ds.exclude(:access => 0)

    Resource.raw_dataset.from(cte_table).with_recursive(cte_table, base_ds, r_ds)
  end

  def self.access_dataset_with_categories(opts = {})
    ds = access_dataset(opts)

    ds = ds.join(:category_resource, :resource_record_id => :record_id)

    ds.opts[:last_joined_table] = nil # Don't do branch_path
    ds.opts[:partition_columns] = [:resource_record_id, :category_record_id]
    ds.opts[:order_columns] = [Sequel.qualify(:category_resource, :version).desc]

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