class Edge < Sequel::Model
  plugin :versioning
  include Versioned

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_one aspect, :class => Node, inter_branch: false
  end
end

class EdgeInter < Sequel::Model
end
