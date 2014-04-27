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