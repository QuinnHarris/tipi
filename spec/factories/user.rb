# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :user do
    sequence(:email) { |n| "joe#{n}@blow.com" }
    password 'Password0'
    password_confirmation 'Password0'
  end
end
