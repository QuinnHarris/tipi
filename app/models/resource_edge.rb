class ResourceEdge < Sequel::Model
  plugin :versioned

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_one aspect, :class => Resource, :key => opposite
  end
end
