//initial setttings (canvas size, colors, widths, dagre settings, rendering styles)
var width = 900,
	height = 500,
	fill = d3.scale.categories20;

//initialize svg
var svg = d3.select("create").append("svg")
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

// mouse event vars
var dragged = null,
    selected_node = null,
    selected_link = null,
    mousedown_link = null,
    mousedown_node = null,
    mouseup_node = null;

// add keyboard callback
d3.select(window)
    .on("keydown", keydown);
	
//prevent default browser behavior
if (d3.event) {
    d3.event.preventDefault();
  }

//read from the input
var inputGraph;
var oldInputGraph;
$(document).ready(function(){inputGraph = $('#inputGraph')[0];});
function updateInput() {
	if(oldInputGraph!==inputgraph.value){
		var result;
		try {result = graphlibDot.parse(inputGraph.value);
		} catch (e) {
			inputGraph.setAttribute("class", "error");
			throw e;
		}
		if (result){
			svg.
		};
	}
	var result;
	try {result = graphlibDot.parse(inputGraph.value);
	} catch (e) {
		
	}
}
	//

//input saved as data

//update graph

//event functions
	//mousedown
	//mouseup
	//keydown
	//keyup
	//focus
	//mousemove
	
//render graph

//configure graph settings (line styles, etc)

//configure layout settings (RL,TB, spacing)

//update
