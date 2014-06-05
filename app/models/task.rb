class Task < Sequel::Model
  plugin :single_table_inheritance, :type
  plugin :versioned

  ver_many_to_one :resource

  # Probably need association that can find instances of this and all older
  # versions of this resource.
  one_to_many :actions, key: [:task_version, :task_branch_path],
              primary_key: [:version, :branch_path]

  [[TaskEdge, false], [TaskEdger, true]].each do |join_class, inter_branch|
    aspects = [:from, :to]
    aspects.zip(aspects.reverse).each do |aspect, opposite|
      relation_name = :"#{aspect}#{inter_branch ? '_inter' : ''}"
      ver_many_to_many relation_name, :class => self, join_class: join_class,
                       left_key_prefix: opposite, right_key_prefix: aspect,
                       inter_branch: inter_branch

      ver_one_to_many :"#{relation_name}_edge", :class => join_class,
                      key: opposite, target_prefix: aspect,
                      inter_branch: inter_branch, read_only: true
    end
  end

  def client_values
    %w(record_id branch_path branch_id created_at name doc)
      .each_with_object({}) do |attr, hash|
      hash[attr] = send attr
    end.merge('id' => version)
  end
end
