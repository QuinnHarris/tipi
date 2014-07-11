Branch
Resource

class User < Sequel::Model
  plugin :devise
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :confirmable, :lockable #, :omniauthable

  # Assume this is in the Root Branch
  def branch; RootBranch.context; end
  def branch_path_context; []; end

  # Main View for user
  plugin :version_associations
  ver_many_to_one :resource
  def resource_branch_path; []; end

  one_to_many :resources

  # Called by devise when new User object is created
  def self.new_with_session(params, session)
    super.tap do |user|
      # Temporarily set to 0 but will be reset in registrations_controller
      user.resource_record_id = 0
    end
  end

  # Used by devise lib/devise/hooks/lockable.rb
  def update_attribute(key, value)
    send("#{key}=", value)
  end
end
