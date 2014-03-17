class Node < ActiveRecord::Base
  include Versioned

  # Need to develop custom has_many relations for versioning
#  has_many :edges
#  has_many :nodes, through: :edges
end

class Project < Node

end

class Step < Node

end
