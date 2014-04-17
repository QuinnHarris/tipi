class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :edges, :class => self, reciprocal: opposite,
                         left_key: "#{aspect}_version".to_sym,
                         right_key: "#{opposite}_version".to_sym
    # No timestamps on edges (:before_add
  end

  # Work in progress !!!! IGNORE THIS
  # Currently returns edge records from this node in the branch
  # Needs to return associated nodes and be well intergrated into the association for to and from
  def temp_dataset_from(branch, branch_version = nil)
    connect_table = :branch_relations
    cte_table = :branch_accend

    temp_table = :branch_dataset

    src = :from
    dst = :to
    aspect_list = [src, dst]

    # Opening a branch context will typically create a temporary branch dataset table
    # Otherwise do this with a non recursive WITH
    branch_data = branch.decend_dataset(branch_version)
    db.drop_table? temp_table
    db.create_table temp_table, :temp => true, :as => branch_data  # :on_commit => c:drop, 
    branch_data = temp_table # Set branch_data to this table instead of dataset

    # !!! Check if this node is in the branch dataset

    # Src link must reference at or before this node.  If after its for a future version or branch
    src_branch_data = (branch.id == branch_id) ? branch_data : Branch.decend_dataset(branch_id)
    
    # Dst link must reference at or after this node so find all successor branched within the branch dataset
#    base_ds = Branch.dataset.from(branch_data).where(:id => branch_id)

#    recursive_ds = db[temp_table]
#      .join(connect_table, [[:successor_id, :id]])
#      .join(cte_table, [[:id, :predecessor_id]])
#      .select(Sequel::SQL::ColumnAll.new(temp_table))

#    dst_branch_data = db[cte_table].with_recursive(cte_table, base_ds, recursive_ds)
    
    # Somewhat the same as in versioned.rb
    ds = Edge.dataset
    aspect_list.zip([src_branch_data, branch_data]).each do |aspect, table|
      ds = ds.join(Sequel.as(table, aspect),
                   :id => Sequel.qualify(:edges, "#{aspect}_branch_id")
                   ) do |j|
        Sequel.expr(Sequel.qualify(j, :version) => nil) | 
        (Sequel.qualify(:edges, "#{aspect}_version") <= Sequel.qualify(j, :version))
      end
    end
    ds = ds.where("#{src}_record_id".to_sym => record_id)

#      .select { |o|
#      o.rank.function.over(:partition => "#{dst}_record_id", :order => [Sequal.qualify(dst, :depth),  Sequel.qualify(dst, :version).desc]) }
  end
end

class Project < Node

end

class Step < Node

end
