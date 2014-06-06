class Edge < Sequel::Model
  plugin :versioning


  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    ver_many_to_one aspect, :class => Node, inter_branch: false,
                    key: opposite
  end

  def client_values
    val = %w(branch_path branch_id created_at)
    .each_with_object({}) do |attr, hash|
      hash[attr] = send attr
    end.merge(
        'id' => version,
        'v_record_id' => from_record_id,
        'v_branch_path' => from_branch_path,
        'u_record_id' => to_record_id,
        'u_branch_path' => to_branch_path,
    )
    val['v'] = from.version if associations[:from]
    val['u'] = to.version if associations[:to]
    val
  end
end

class EdgeInter < Sequel::Model
end
