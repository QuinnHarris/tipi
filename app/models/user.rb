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
end
