class Action < Sequel::Model
  many_to_one :instance

  many_to_one :task, key: [:task_version, :task_branch_path],
              primary_key: [:version, :branch_path]
end
