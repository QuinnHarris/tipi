class BranchRelation < ActiveRecord::Base
  belongs_to :predecessor, class_name: 'Branch', foreign_key: :predecessor_id
  belongs_to :successor,   class_name: 'Branch', foreign_key: :successor_id
end
