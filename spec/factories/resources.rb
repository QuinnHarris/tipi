# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :resource do
  end

  factory :project do
    sequence(:name) { |n| "Project #{n}" }
  end
end
