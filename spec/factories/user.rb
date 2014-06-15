# Read about factories at https://github.com/thoughtbot/factory_girl

FactoryGirl.define do
  factory :user do
    to_create do |user|
      user.resource_record_id = 0
      user.save
      user.resource = UserResource.create(name: 'User', context: RootBranch.branch, user: user)
      user.save_changes
    end

    sequence(:email) { |n| Faker::Internet.email }
    password p = Faker::Internet.password
    password_confirmation p
  end
end
