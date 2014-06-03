class InstanceEdge < Sequel::Model
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_one aspect, :class => Instance, :key => :"#{opposite}_id"
  end
end
