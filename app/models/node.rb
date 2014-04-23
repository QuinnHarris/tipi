class Node < Sequel::Model
  plugin :single_table_inheritance, :type
  include Versioned

  # Need to develop custom has_many relations for versioning
  aspects = [:from, :to]
  aspects.zip(aspects.reverse).each do |aspect, opposite|
    many_to_many aspect, join_table: :edges, :class => self, reciprocal: opposite,
                         left_key: "#{aspect}_version".to_sym,
                         right_key: "#{opposite}_version".to_sym,
    :dataset =>
      (proc do |r|
         branch_context_data = Branch.get_context_data #(branch, branch_version)

         dataset = r.associated_class.raw_dataset
         
         # Assuming this node is the latest in the current branch context
         # Otherwise we need to establish a new context from this branch version and branch ids
         ds = dataset.join(Sequel.as(:nodes, :dst),
                           :record_id => :record_id) do |j, lj|
           Sequel.qualify(j, :version) <= Sequel.qualify(lj, :version)
         end
           .join(r[:join_table], r[:right_key] => :version)
           .join(Sequel.as(:nodes, :src), :version => r[:left_key])
           .where(Sequel.qualify(:src, :record_id) => record_id) { |o|
           Sequel.qualify(:src, :version) <= version } # Neccissary?
         
         # Must check to from branch context if there is a version lock
         tables = [r[:join_table], :nodes, :src]
         tables.each do |table|
           ds = ds.join(Sequel.as(branch_context_data, "branch_#{table}"),
                        :id => Sequel.qualify(table, :branch_id)) do |j, lj|
             Sequel.expr(Sequel.qualify(j, :version) => nil) | 
               (Sequel.qualify(table, :version) <= Sequel.qualify(j, :version))
           end
         end
         
         ds = ds.select(Sequel::SQL::ColumnAll.new(:nodes),
                        Sequel.as(Sequel.qualify(r[:join_table], :deleted),
                                  :join_deleted)) do |o|
           o.rank.function
             .over(:partition => Sequel.qualify(:nodes, :record_id),
                   :order => tables.map do |t|
                     [Sequel.qualify(:"branch_#{t}", :depth),
                      Sequel.qualify(t, :version)]
                   end.flatten)
         end
         
         dataset.from(ds).filter(:rank => 1, :deleted => false, :join_deleted => false).select(*r.associated_class.columns)
       end)

    define_method "_add_#{aspect}" do |node, branch = nil, deleted = nil|
      context = Branch.get_context(branch, false)
      
      unless context.includes?(self)
        raise "Self branch not in context"
      end

      unless context.includes?(node)
        raise "Passed branch not in context"
      end

      h = { :branch_id => context.branch.id,
        :"#{aspect}_version" => version,
        :"#{opposite}_version" => node.version,
        :created_at => self.class.dataset.current_datetime,
        :deleted => deleted ? true : false}
      
      Edge.dataset.insert(h)
    end

    define_method "_remove_#{aspect}" do |node, branch = nil|
      # !!! Must check if the object actually exists
      send("_add_#{aspect}", node, branch, true)
    end

    # _remove_ and _remove_all_
  end
end

class Project < Node

end

class Step < Node

end
