$(document).ready ->
	graph = {
		Digraph : new dagreD3.Digraph(),
		Renderer : new dagreD3.Renderer(),
		currentNode: null
	};



	createDagreNode = (id, label) ->
		graph.Digraph.addNode id, {label: label, width: '100px', height: '100px'}
		return

	addDragListener = (element) ->
		element.behavior.drag()
		return

	createLabel = (str) ->
		label = document.createElement('div')
		label.id = str.substr(0,2)
		label.draggable = true
		label.classList.add('draggable-node')
		label.style.padding = '20px'
		label.textContent = str
		label.outerHTML

	$(document).on "click", '#add-node', (e) ->
		if $(e.target).parents('section').attr('id') != 'alertify'
			alertify.prompt "Name your node", (e, str) ->
				if e

					createDagreNode str.substr(0,2), createLabel(str);
					graph.Renderer.run graph.Digraph, d3.select("svg g")
				return
			, ""
			return
	

	$(document).on "click", '.node:not(.marked)', (e) ->
		if graph.currentNode == null || graph.currentNode == undefined
			graph.currentNode = e.target.id
			$(e.target).addClass 'marked'
		else
			graph.Digraph.addEdge null, graph.currentNode, e.target.id
			graph.currentNode = null

		graph.Renderer.run graph.Digraph, d3.select("svg g")
		return

	$(document).on 'dragstart', '.draggable-node', (e) ->
		this.style.opacity = 0.4
		return

	return