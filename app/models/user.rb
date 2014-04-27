class User < Sequel::Model
  plugin :devise
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :trackable, :validatable, :confirmable, :lockable #, :omniauthable

  # Main View for user
  Node
  one_to_one :view
end
