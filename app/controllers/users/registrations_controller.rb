class Users::RegistrationsController < Devise::RegistrationsController
  def create
    User.db.transaction do
      super do |user|
        user.resource = UserResource.create(name: 'User', branch: RootBranch.root, user: user)
      end
    end
  end
end
