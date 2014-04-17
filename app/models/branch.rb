class Branch < Sequel::Model
  many_to_many :predecessors, join_table: :branch_relations, :class => self,
                                left_key: :successor_id, right_key: :predecessor_id
  many_to_many :successors,   join_table: :branch_relations, :class => self,
                               right_key: :successor_id,  left_key: :predecessor_id


  # Relations for all directly versioned objects
  # Should implement on Versioned concern include
  one_to_many :nodes

  # has_many :template_instances

  def fork!(options = {})
    db.transaction do
      o = self.class.create(options)
      add_successor(o)
      o
    end
  end

  def self.merge!(options = {}, pred)
    db.transaction do
      o = create(options)
      pred.each do |p|
        o.add_predecessor(p)
      end
    end
  end

  # # SQL where clause to include only objects from this branch (and predecessors)
  # # pass table_name and an optional maximum version number.
  # # This does not handle returning multiple versions with the same record_id if different branch relations with different version locks refers to the same record_id
  # # This assumes a higher branch id always implies that it is a successor.  This is true if branches relations can NOT be changed after creation.
  # def branch_where(table_name, version = nil)
  #   temp = Arel::Table.new(table_name)

  #   next_branchs = [[self, version]]
  #   all_branchs = []

  #   expr = nil

  #   until next_branchs.empty?
  #     next_branchs = next_branchs.collect do |branch, ver|
  #       e = temp[:branch_id].eq(branch.id)
  #       e = e.and(temp[:version].lteq([ver, version].compact.min)) if ver || version
  #       expr = expr ? expr.or(e) : e

  #       all_branchs << branch
  #       branch.pre_relations.collect do |relation|
  #         next nil if all_branchs.include?(relation.predecessor)
  #         [ relation.predecessor, relation.version ]
  #       end
  #     end.flatten.compact.uniq
  #   end
    
  #   query = temp.project(Arel.sql('record_id, max(branch_id) AS branch_id, max(version) AS version')) 
  #   query.where(expr)
  #   query.group(:record_id)
    
  #   # Should probably use Arel but need to study and probably extend
  #   select = %w(record_id branch_id version).collect { |s| "\"#{table_name}\".\"#{s}\"" }.join(', ')
  #   "(#{select}) IN (#{query.to_sql})"
  # end

 # one_to_many :decendants, read_only: true,
 #   dataset: proc do     
 #   end

  # Need to add version column
  def branch_dataset(version = nil)
    connect_table = :branch_relations
    successor_array = [:successor_id]
    predecessor_array = [:predecessor_id]
    cte_table = :branch_decend

    prkey_array = Array(primary_key)

    # Select all columns from this table
    #c_all = [Sequel::SQL::ColumnAll.new(model.table_name)]
    select_cols = [:id]
    
    # Select this record as the start point of the recursive query
    # Resulting dataset will include this record
    base_ds = model.filter(prkey_array.zip(prkey_array.map { |k| send(k) }))
    
    # Connect from the working set (cte_table) through the connect_table back to this table
    recursive_ds = model
      .join(connect_table, predecessor_array.zip(prkey_array))
      .join(cte_table, prkey_array.zip(successor_array))

    # SQL::AliasedExpression.new(t, table_alias)).
    model.from(cte_table)
      .with_recursive(cte_table,
                      base_ds.select(select_cols),
                      recursive_ds.select(select_cols.map { |c| Sequel::SQL::QualifiedIdentifier.new(model.table_name, c) }),
                      union_all: false)
  end

#  def branch_dataset(dataset, version = nil)
#    #Sequel.or
#    dataset.filter do |o|
#      next_branchs = [[self, version]]
#      all_branchs = []
#
#      or_list = []
#      
#      until next_branchs.empty?
#        next_branchs = next_branchs.collect do |branch, ver|
#          exp = o.&( :branch_id => branch )
#          exp.args << o.<=( :version, [ver, version].compact.min ) if ver || version
#          or_list << exp
#
#          
#        end.flatten.compact.uniq
#      end
#    end
#  end
end
