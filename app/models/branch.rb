class Branch < ActiveRecord::Base
  has_many :pre_relations, class_name: 'BranchRelation', foreign_key: :successor_id
  has_many :suc_relations, class_name: 'BranchRelation', foreign_key: :predecessor_id
  has_many :predecessors, through: :pre_relations, source: :predecessor
  has_many :successors,   through: :suc_relations, source: :successor

  has_many :template_instances

  has_many :contexts
  has_many :tasks

  def fork!(options = {})
    successors.create(options)
  end

  def view_where(version = nil)
    temp = Arel::Table.new(self.class.table_name)

    next_views = [self => version]
    all_views = []

    expr = nil

    until next_views.empty?
      next_views = next_views.collect do |view, ver|
        e = temp[:view_id].eq(view.id)
        e = e.and(temp[:version].lteq(ver)) if ver
        expr = expr ? expr.or(e) : e

        all_views << view
        view.predicessors.collect do |relation|
          { relation.predecessor => relation.version }
        end
      end.flatten.uniq
      next_views -= all_views
    end
    
    # Condition for this template
    expr = temp[:template_id].eq(id)
    expr = expr.and(temp[:version].lte(version)) if version

    current = self
    while current.predicessor_id
      expr = expr.or(temp[:template_id].eq(current.predicessor_id)
                       .and(temp[:version].lteq(current.predicessor_version)))
      current = current.predicessor
    end

    # max(id) and max(version) should always select the same record
    # if templates can't change predicessor_id and predicessor_version then max(id) and closest template should be the same record
    # What happens if predicessor_version changes?  Only do on merge operation and force updated records on conflicts or change this to account for template precidence
    # Can a template ever change its predicessor?
    query = temp.project(Arel.sql('max(id)')) 
    query.where(expr)
    query.group(:node_id)
    query.to_sql
  end
end
