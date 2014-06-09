Branch
Resource

class User < Sequel::Model
  plugin :devise
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :confirmable, :lockable #, :omniauthable

  # Main View for user
  plugin :version_associations

  # References UserResource always in the Global branch.
  ver_many_to_one :resource
  def resource_branch_path; []; end

  # Called by devise when new User object is created
  def self.new_with_session(params, session)
    super.tap do |user|
      user.resource = UserResource.create(name: 'User', context: RootBranch.root)
    end
  end
end
