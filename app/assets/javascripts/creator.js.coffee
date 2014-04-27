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
	
data = { node: [ {id: 0, name: "Start"}, {id: 1, name: "Mount Propellers" }, {id: 2, name: "Frame"}, {id: 3, name: "Program Controller"}, {id: 4, name: "Mount Motors"}, {id: 5, name: "Mount Flight Controller"}, {id: 6, name: "Mount Battery"}, {id: 7, name: "Mount Speed Regulator"}, {id: 8, name: "Sync Remote Control"}, {id: 9, name: "Wire"}, {id: 10, name: "Wire"}, {id: 11, name: "Wire"}, {id: 12, name: "Wire"}, {id: 13, name: "Test"}, {id: 14, name: "Quadcopter"}, ], edge: [ {id: 0, in:0, out:1}, {id: 1, in:0, out:2}, {id: 2, in:0, out:3}, {id: 3, in:0, out:1}, {id: 4, in:1, out:9}, {id: 5, in:2, out:4}, {id: 6, in:2, out:5}, {id: 7, in:2, out:6}, {id: 8, in:2, out:7}, {id: 9, in:3, out:8}, {id: 10, in:4, out:9}, {id: 11, in:4, out:10}, {id: 12, in:5, out:10}, {id: 13, in:5, out:11}, {id: 14, in:5, out:12}, {id: 15, in:6, out:11}, {id: 16, in:7, out:12}, {id: 17, in:8, out:13}, {id: 18, in:9, out:13}, {id: 19, in:10, out:13}, {id: 20, in:11, out:13}, {id: 21, in:12, out:13}, {id: 22, in:13, out:14} ] };