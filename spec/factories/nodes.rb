# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :node do

    factory :node_ajax do
      type  'node'
      op    'add'
      sequence(:name) { |n| "Node #{n}" }
      sequence(:doc) { |n| "Important Document #{n}" }
    end
  end


  factory :project do
    sequence(:name) { |n| "Project #{n}" }
  end
end
