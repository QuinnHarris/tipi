/*Place all the behaviors and hooks related to the matching controller here.
  All this logic will automatically be available in application.js.
*/

//initial settings
var width = 960,
	height = 500;
	
	//colors
var fill = d3.scale.category20();

// mouse event vars
var dragged = null,
    selected_node = null,
    selected_link = null,
    mousedown_link = null,
    mousedown_node = null,
    mouseup_node = null;

// init svg
var svg = d3.select("body").append("svg")
    .attr("width", width)
    .attr("height", height)
    .on("mousemove", mousemove)
    .on("mousedown", mousedown)
    .on("mouseup", mouseup);

// line displayed when dragging new nodes
var drag_line = svg.append("line")
    .attr("class", "drag_line")
    .attr("x1", 0)
    .attr("y1", 0)
    .attr("x2", 0)
    .attr("y2", 0);
    
// add keyboard callback
d3.select(window)
    .on("keydown", keydown); 
    
redraw();

// focus on svg?
svg.node().focus();

function mousedown() {

  if (!mousedown_node && !mousedown_link) {
    selected_node = null;
    selected_link = null; 
    redraw();
    return;
  }

  if (mousedown_node) {
    // reposition drag line
    drag_line
        .attr("class", "link")
        .attr("x1", mousedown_node.x)
        .attr("y1", mousedown_node.y)
        .attr("x2", mousedown_node.x)
        .attr("y2", mousedown_node.y);
  }

// get layout properties

  redraw();
}   

function mouseup() {
  // hide drag line
  drag_line
    .attr("class", "drag_line_hidden");

  if (mouseup_node == mousedown_node) { resetMouseVars(); return; }

  if (mouseup_node) {
    // add link
    var link = {source: mousedown_node, target: mouseup_node};
    links.push(link);

    // select new link
    selected_link = link;
    selected_node = null;

  }
  else {
    // add node
    var point = d3.mouse(this),
      node = {x: point[0], y: point[1]},
      n = nodes.push(node);

    // select new node
    selected_node = node;
    selected_link = null;
    
    // add link to mousedown node
    links.push({source: mousedown_node, target: node});
  }

  // clear mouse event vars
  resetMouseVars();

  redraw();
}

function resetMouseVars() {
  dragged = null;
  mousedown_node = null;
  mouseup_node = null;
  mousedown_link = null;
}

function tick() {
  link.attr("x1", function(d) { return d.source.x; })
      .attr("y1", function(d) { return d.source.y; })
      .attr("x2", function(d) { return d.target.x; })
      .attr("y2", function(d) { return d.target.y; });

  node.attr("cx", function(d) { return d.x; })
      .attr("cy", function(d) { return d.y; });
}

function spliceLinksForNode(node) {
  toSplice = links.filter(
    function(l) { 
      return (l.source === node) || (l.target === node); });
  toSplice.map(
    function(l) {
      links.splice(links.indexOf(l), 1); });
}

function keydown() {
  if (!selected_node && !selected_link) return;
  switch (d3.event.keyCode) {
    case 8: // backspace
    case 46: { // delete
      if (selected_node) {
        nodes.splice(nodes.indexOf(selected_node), 1);
        spliceLinksForNode(selected_node);
      }
      else if (selected_link) {
        links.splice(links.indexOf(selected_link), 1);
      }
      selected_link = null;
      selected_node = null;
      redraw();
      break;
    }
  }
}

  if (d3.event) {
    // prevent browser's default behavior
    d3.event.preventDefault();
  }

!!!  force.start();

var inputGraph;
var oldInputGraphValue;

$( document ).ready(function() {
	inputGraph = $('#inputGraph')[0];
	tryDraw();
});

function graphToURL() {
  		var elems = [window.location.protocol, '//',
               window.location.host,
               window.location.pathname,
               '?'];

	var queryParams = [];
	if (debugAlignment) {
    	queryParams.push('alignment=' + debugAlignment);
	}
  	queryParams.push('graph=' + encodeURIComponent(inputGraph.value));
  	elems.push(queryParams.join('&'));

  	return elems.join('');
}

var graphRE = /[?&]graph=([^&]+)/;
var graphMatch = window.location.search.match(graphRE);
if (graphMatch) {inputGraph.value = decodeURIComponent(graphMatch[1]);}
var debugAlignmentRE = /[?&]alignment=([^&]+)/;
var debugAlignmentMatch = window.location.search.match(debugAlignmentRE);
var debugAlignment;
if (debugAlignmentMatch) debugAlignment = debugAlignmentMatch[1];

function tryDraw() {
	var result;
	if (oldInputGraphValue !== inputGraph.value) {
    	inputGraph.setAttribute("class", "");
    	oldInputGraphValue = inputGraph.value;
    	
    	//parse input code
    	try {
      		result = graphlibDot.parse(inputGraph.value);
    	} catch (e) {
      		inputGraph.setAttribute("class", "error");
      		throw e;
    	}
		if (result) {

      		// Cleanup old graph
      		var svg = d3.select("svg");

      		var renderer = new dagreD3.Renderer();

      		// Handle debugAlignment
      		renderer.postLayout(function(graph) {
        		if (debugAlignment) {
          			// First find necessary delta...
          			var minX = Math.min.apply(null, graph.nodes().map(function(u) {
            			var value = graph.node(u);
            			return value[debugAlignment] - value.width / 2;
          			}));

          			// Update node positions
          			graph.eachNode(function(u, value) {
            			value.x = value[debugAlignment] - minX;
          			});

          			// Update edge positions
          			graph.eachEdge(function(e, u, v, value) {
            			value.points.forEach(function(p) {
              				p.x = p[debugAlignment] - minX;
            			});
          			});
        		}
      		});

			// Uncomment the following line to get straight edges
			//renderer.edgeInterpolate('linear');
			// Custom transition function
			function transition(selection) {
				return selection.transition().duration(500);
			}
			renderer.transition(transition);
			var layout = renderer.run(result, svg.select("g"));
	      	transition(d3.select("svg"))
	      		.attr("width", layout.graph().width + 40)
	        	.attr("height", layout.graph().height + 40);
	      	d3.select("svg")
	        	.call(d3.behavior.zoom().on("zoom", function() {
	        		var ev = d3.event;
	          		svg.select("g")
	            		.attr("transform", "translate(" + ev.translate + ") scale(" + ev.scale + ")");
	        	}));
		 }
	 }
}