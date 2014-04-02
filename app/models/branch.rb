class Branch < Sequel::Model
  # has_many :pre_relations, class_name: 'BranchRelation', foreign_key: :successor_id
  # has_many :suc_relations, class_name: 'BranchRelation', foreign_key: :predecessor_id
  # has_many :predecessors, through: :pre_relations, source: :predecessor
  # has_many :successors,   through: :suc_relations, source: :successor

  many_to_many :predecessors, join_table: :branch_relations, class: self,
                               right_key: :successor_id,  left_key: :predecessor_id
  many_to_many :successors,   join_table: :branch_relations, class: self,
                                left_key: :successor_id, right_key: :predecessor_id

  # has_many :template_instances

  def fork!(options = {})
    db.transaction do
      o = self.class.create(options)
      add_successor(o)
      o
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

  def branch_dataset(dataset, version = nil)
    dataset.filter do |o|
      next_branchs = [[self, version]]
      all_branchs = []

      or_list = []
      
      until next_branchs.empty?
        next_branchs = next_branchs.collect do |branch, ver|
          exp = o.&( :branch_id => branch )
          exp.args << o.<=( :version, [ver, version].compact.min ) if ver || version
          or_list << exp

          
        end.flatten.compact.uniq
      end

    end
  end
end
