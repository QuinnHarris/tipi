category_path = 'Flying/QuadCopters'
project_name = 'First QuadCopter'

json_data = %q(
{ 
"nodes": [
 {"id":  0, "name": "Start"},
 {"id":  1, "name": "Mount Propellers" },
 {"id":  2, "name": "Frame"},
 {"id":  3, "name": "Program Controller"},
 {"id":  4, "name": "Mount Motors"},
 {"id":  5, "name": "Mount Flight Controller"},
 {"id":  6, "name": "Mount Battery"},
 {"id":  7, "name": "Mount Speed Regulator"},
 {"id":  8, "name": "Sync Remote Control"},
 {"id":  9, "name": "Wire"},
 {"id": 10, "name": "Wire"},
 {"id": 11, "name": "Wire"},
 {"id": 12, "name": "Wire"},
 {"id": 13, "name": "Test"},
 {"id": 14, "name": "Quadcopter"}
],
"edges": [
 {"id":  0, "to":  0, "from":  1},
 {"id":  1, "to":  0, "from":  2},
 {"id":  2, "to":  0, "from":  3},
 {"id":  4, "to":  1, "from":  9},
 {"id":  5, "to":  2, "from":  4},
 {"id":  6, "to":  2, "from":  5},
 {"id":  7, "to":  2, "from":  6},
 {"id":  8, "to":  2, "from":  7},
 {"id":  9, "to":  3, "from":  8},
 {"id": 10, "to":  4, "from":  9},
 {"id": 11, "to":  4, "from": 10},
 {"id": 12, "to":  5, "from": 10},
 {"id": 13, "to":  5, "from": 11},
 {"id": 14, "to":  5, "from": 12},
 {"id": 15, "to":  6, "from": 11},
 {"id": 16, "to":  7, "from": 12},
 {"id": 17, "to":  8, "from": 13},
 {"id": 18, "to":  9, "from": 13},
 {"id": 19, "to": 10, "from": 13},
 {"id": 20, "to": 11, "from": 13},
 {"id": 21, "to": 12, "from": 13},
 {"id": 22, "to": 13, "from": 14}
 ] }
)

category_path = ARGV[0] if ARGV[0]
project_name = ARGV[1] if ARGV[1]
if ARGV[2]
  json_data = File.open(ARGV[2]) { |f| f.read }
end

require ::File.expand_path('../../config/environment',  __FILE__)

data = ActiveSupport::JSON.decode(json_data)

ViewBranch.public.context do
  category = Category.root.get_path(category_path)

  category.add_project(project_name) do |project|    
    node_map = {}
    data['nodes'].each do |node_h|
      id, name = %w(id name).map do |k|
        node_h[k].tap { |v|
          raise "No #{k} attribute in #{node_h.inspect} for nodes" unless v }
      end
      raise "Duplicate node ID: #{id}" if node_map.has_key?(id)
      node_map[id] = Step.create(name: name)
    end
    
    has_to = Set.new
    data['edges'].each do |edge_h|
      from, to = %w(from to).map do |k|
        v = edge_h[k]
        raise "No #{k} attribute in #{edge_h.inspect} for edges" unless v
        node_map[v].tap { |n|
          raise "No associated node #{v} for #{k} attribute in #{edge_h.inspect} for edges" unless n }
      end
      from.add_to(to)
      has_to << to
    end
    
    # Make sure project depends on all nodes (indirectly)
    (node_map.values - has_to.to_a).each do |node|
      project.add_to(node)
    end
  end

end
