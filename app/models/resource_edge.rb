class ResourceEdge < Sequel::Model
  plugin :versioned

  [:from, :to].each do |aspect|
    ver_many_to_one aspect, :class => Resource
  end
end
