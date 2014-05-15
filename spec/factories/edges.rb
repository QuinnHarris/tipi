# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :edge do

    factory :edge_ajax do
      type  'edge'
      op    'add'
    end 
  end
end
