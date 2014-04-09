class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  keys = [:record_id, :branch_id, :version]
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :edges, :class => self, reciprocal: opposite,
                         left_key: keys.map { |k| "#{aspect}_#{k}".to_sym },
                         right_key: keys.map { |k| "#{opposite}_#{k}".to_sym }
    # No timestamps on edges (:before_add
  end

  # Work in progress
  # Currently returns edge records from this node in the branch
  # Needs to return associated nodes and be well intergrated into the association for to and from
  def temp_dataset_from(branch, branch_version = nil)
    connect_table = :branch_relations
    cte_table = :branch_accend

    temp_table = :branch_dataset

    successor_array = [:successor_id]
    predecessor_array = [:predecessor_id]

    # Opening a branch context will typically create a temporary branch dataset table
    # Otherwise do this with a non recursive WITH
    branch_dataset = branch.branch_dataset(branch_version)
    db.drop_table? temp_table
    db.create_table temp_table, :temp => true, :as => branch_dataset  # :on_commit => :drop, 

    # !!! This node should be in the branch dataset
    
    # record_id = this.record_id
    # branch_id = this and successor branch_id
    # version >= this.version and <= branch_id version from branch_dataset (max)
    
    # Find the relevant branches from branch dataset that are all successors of this nodes branch_id
    base_ds = db[temp_table].where(:id => branch_id)

    recursive_ds = db[temp_table]
      .join(connect_table, [[:successor_id, :id]])
      .join(cte_table, [[:id, :predecessor_id]])
      .select(Sequel::SQL::ColumnAll.new(temp_table))

    branch_subset = db[cte_table].with_recursive(cte_table, base_ds, recursive_ds)
    
    src = :from
    dst = :to
    aspect_list = [src, dst]
    

    # Somewhat the same as in versioned.rb
    ds = Edge.dataset
    aspect_list.zip([branch_subset, temp_table]).each do |aspect, table|
      ds = ds.join(table,
                   :id => Sequel.qualify(:edges, "#{aspect}_branch_id")
                   ) do |j|
        Sequel.expr(Sequel.qualify(j, :version) => nil) | 
        (Sequel.qualify(:edges, "#{aspect}_version") <= Sequel.qualify(j, :version))
      end
    end
    ds.where("#{src}_record_id".to_sym => record_id)
  end
end

class Project < Node

end

class Step < Node

end
