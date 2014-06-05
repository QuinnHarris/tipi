# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :task do
    factory :task_ajax do
      type  'node'
      op    'add'
      sequence(:name) { |n| "Node #{n}" }
      sequence(:doc) { |n| "Important Document #{n}" }
    end
  end
end
