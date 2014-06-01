class Edge < Sequel::Model
  plugin :versioning
  include Versioned

  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_one aspect, :class => Node, inter_branch: false,
                    key: opposite
  end

  def client_values
    %w(branch_path branch_id created_at)
    .each_with_object({}) do |attr, hash|
      hash[attr] = send attr
    end.merge(
        'id' => version,
        'v_record_id' => from.record_id,
        'v_branch_path' => from.branch_path,
        'u_record_id' => to.record_id,
        'u_branch_path' => to.branch_path,
        'v' => from.version,
        'u' => to.version
    )
  end
end

class EdgeInter < Sequel::Model
end
