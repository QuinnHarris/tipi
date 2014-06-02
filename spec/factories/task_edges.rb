# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :task_edge do

    factory :task_edge_ajax do
      type  'edge'
      op    'add'
    end 
  end
end
