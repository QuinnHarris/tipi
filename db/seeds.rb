# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ name: 'Chicago' }, { name: 'Copenhagen' }])
#   Mayor.create(name: 'Emanuel', city: cities.first)

Resource
Branch.db.transaction do
  root_branch = RootBranch.create(name: 'Root Branch', merge_point: false)
  raise "Root branch id not 1" unless root_branch.id == 1

  root_user = User.new(email: 'root@pitri.net', password: 'tipiforthepitri',
                       password_confirmation: 'tipiforthepitri',
                       resource_record_id: 0)
  root_user.skip_confirmation!
  root_user.save
  raise "Root user id not 1" unless root_user.id == 1

  root_category = Category.create(name: 'Root Category', branch: root_branch, user: root_user)
  raise "Root category record_id not 1" unless root_category.record_id == 1

  public_resource = UserResource.create(name: 'Public Resource', branch: root_branch, user: root_user)
  raise "Public Resource record_id not 1" unless public_resource.record_id == 1

  root_resource = UserResource.create(name: 'Root User', branch: root_branch, user: root_user)
  root_user.resource = root_resource
  root_user.save_changes
end