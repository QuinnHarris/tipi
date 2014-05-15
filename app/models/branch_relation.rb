class BranchRelation < Sequel::Model
  [:predecessor, :successor].each do |aspect|
    many_to_one aspect, :class => Branch
  end
end
