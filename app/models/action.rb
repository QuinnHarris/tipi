class Action < Sequel::Model
  many_to_one :instance

  # Code to link to a specific node
end
