class Branch < Sequel::Model
  many_to_many :predecessors, join_table: :branch_relations, :class => self,
                                left_key: :successor_id, right_key: :predecessor_id
  many_to_many :successors,   join_table: :branch_relations, :class => self,
                               right_key: :successor_id,  left_key: :predecessor_id

  def _add_successor(o, version = nil)
    model.db[:branch_relations].insert(predecessor_id: id,
                                       successor_id: o.id,
                                       version: version)
  end


  # Relations for all directly versioned objects
  # Should implement on Versioned concern include
  one_to_many :nodes

  # has_many :template_instances

  # Create new successor branch from current branch
  def fork!(options = {})
    version = options.delete(:version)
    db.transaction do
      o = self.class.create(options)
      add_successor(o, version)
      o
    end
  end

  # Create new successor branch from listed branches
  # e.g.
  #   Branch.merge!(branch_a, branch_b, name: 'Branch Name')
  #   Branch.merge!(branch_list, name: 'Branch Name')
  def self.merge!(*args)
    options = args.pop
    version = options.delete(:version)
    db.transaction do
      o = create(options)
      [args].flatten.each do |p|
        p.add_successor(o, version)
      end
      o
    end
  end

 # one_to_many :decendants, read_only: true,
 #   dataset: proc do     
 #   end

  # Return dataset with this and all predecessor branch ids and maximum version number for that branch
  def branch_dataset(version = nil)
    connect_table = :branch_relations
    cte_table = :branch_decend

    # All arrays must have same number of elements
    prkey_array = Array(primary_key)
    successor_array = [:successor_id]
    predecessor_array = [:predecessor_id]

    version_col = :version
    
    # Select this record as the start point of the recursive query
    # Include the version (or null) column used by recursive part
    base_ds = db[].select(*(prkey_array.map { |k| Sequel.as(send(k), k) } +
                                       [Sequel.as(Sequel.cast(version, :integer), version_col)] ) )
    
    # Connect from the working set (cte_table) through the connect_table back to this table
    # Use the least (lowest) version number from the current version or the connect_table version
    # This ensures the version column on the connect_table locks in all objects at or below that version
    recursive_ds = db[connect_table]
      .join(cte_table, prkey_array.zip(successor_array))
      .select(*( predecessor_array.map { |c| Sequel.qualify(connect_table, c) } +
                 [Sequel.function(:LEAST, *[connect_table, cte_table].map { |t|
                                    Sequel.qualify(t, version_col) })] ) )

    model.from(cte_table)
      .with_recursive(cte_table, base_ds, recursive_ds, union_all: false)
  end
end
