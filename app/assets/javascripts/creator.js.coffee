$(document).ready ->
	graph = {
		Digraph : new dagreD3.Digraph(),
		Renderer : new dagreD3.Renderer(),
		relationFrom: null
	};



	createDagreNode = (id, label) ->
		graph.Digraph.addNode id, {label: label}
		return

	$(document).on "click", '#add-node', (e) ->
		if $(e.target).parents('section').attr('id') != 'alertify'
			alertify.prompt "Name your node", (e, str) ->
				if e
					createDagreNode str.substr(0,2), str;
					graph.Renderer.run graph.Digraph, d3.select("svg g")
				return
			, ""
			return
	

	$(document).on "click", '.node:not(.marked)', (e) ->
		if graph.relationFrom == null
			graph.relationFrom = e.target.__data__
			$(e.target).addClass 'marked'
		else
			graph.Digraph.addEdge null, graph.relationFrom, e.target.__data__
			graph.relationFrom = null

		graph.Renderer.run graph.Digraph, d3.select("svg g")
		return
	return
	
data = { 
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
 ] };