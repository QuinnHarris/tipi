class Users::RegistrationsController < Devise::RegistrationsController
  def create
    User.db.transaction do
      super do |user|
        user.resource = UserResource.create(name: params[:user][:name],
                                            branch: RootBranch.branch,
                                            user: user,
                                            email: user.email)
      end
    end
  end
end
