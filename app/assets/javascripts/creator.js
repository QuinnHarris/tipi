//initialize svg (d3)
var svg = d3.select("#nodes-container")
	.append("svg")
		.attr("pointer-events", "all")
	.append("g")
		.attr('transform', 'translate(20,20)')
		.call(d3.behavior.zoom().on("zoom", rescale));
function initSvg(){ 	
	d3.select("#nodes-container")
		.append("svg")
			.attr("pointer-events", "all")
		.append("g")
			.attr('transform', 'translate(20,20)')
			.call(d3.behavior.zoom().on("zoom", rescale));
		}

//initialize Dagre Renderer (dagre)
var graph = new dagreD3.Digraph();
var renderer = new dagreD3.Renderer();
var layout = new dagreD3.layout();

layout = layout.nodeSep(20).rankSep(20);
var orientation = "vertical";
function render(){renderer.layout(layout).run(g, d3.select("svg g"));}

//getData (ajax)
var data;
function getData(){
	graph = new dagreD3.Digraph; //reset the digraph
	$.getJSON( "data.json", function( data ) {
		$.each( data.nodes, function( id, name ) {
  			var inIcon = "src = 'http://i.stack.imgur.com/BUlXq.png'";
			var projectIcon = "src = 'http://www.endlessicons.com/wp-content/uploads/2013/02/wrench-icon-614x460.png'";
			var outIcon = "src = 'https://cdn2.iconfinder.com/data/icons/large-glossy-svg-icons/512/logout_user_login_account-512.png'";
			var title = name;
			var subtitle ="Subtitle";
			var format = ["<div class = 'node-outer'><img class = 'node-in' id = ",
							id, 
							inIcon, "><img class = 'node-icon' ", 
							projectIcon, "><div class = 'node-title-area'><div class = 'node-title'>",
							title,"</div><div class = 'node-subtitle'>",
							subtitle,"</div></div><img class = 'node-out' id = ",
							id,
							outIcon,"></div>"].join('\n');
			this.value = format;
  		});
  		graph.json(data.nodes,data.edges);
	});
}
//sendData (ajax)
	$.ajax({
		type: PUSH,
  		url: "localhost:3000/creator/" + projectName + "/" + projectVersion + "/" + data + ".json",
  		dataType: "json",
  		context: document.body,
	}).done(function() {
	  	$( this ).addClass( "done" );
	});
//updateSvg (Dagre/graphlib)

//updateData (Graphlib)

//appendNode 

//appendEdges

//mouse events
$(document).ready(function(){
	$(document).on("click", function (e){
		e.preventDefault();
	});
	initSvg();
});

//keyboard events


//other events
function toggleOrientation(){
	if (orientation == "vertical"){
		layout = layout.rankDir("LR");
		orientation = "horizontal";
	}else{
		layout = layout.rankDir("TB");
		orientation = "vertical";
	}
	render();
	return;
}













/*var g = new dagreD3.Digraph();

var drag_line = svg.append("line")
    .attr("class", "drag_line")
    .attr("x1", 0)
    .attr("y1", 0)
    .attr("x2", 0)
    .attr("y2", 0);
    
var selectedNode;
var selectedEdge;

// add keyboard callback
d3.select(window)
    .on("keydown", keydown);
    
if (d3.event) {
    // prevent browser's default behavior
    d3.event.preventDefault();
  }

var createNode = function(id, name){

	g.addNode(id, {label: format});
};

function initSVG(){
	d3.select("#nodes-container")
	.append("svg")
		.attr("pointer-events", "all")
	.append("g")
		.attr('transform', 'translate(20,20)')
		.call(d3.behavior.zoom().on("zoom", rescale));
}

function draw(){
	g = new dagreD3.Digraph;
	for(node in data.nodes){
		var n = data.nodes[node];
    	createNode(n.id, n.name);
    };
    for(edge in data.edges){
    	var e = data.edges[edge];
    	g.addEdge(e.id, e.to, e.from);
    };
  	render();
};

function newNode(){
	var ids = [];
	var id;
	if(data.nodes[0].id == undefined){id = 1;}else{
		for(node in data.nodes){ids.push(data.nodes[node].id);}
		id = Math.max.apply(null,ids)+1;}
	var name = prompt("enter the name");
	data.nodes.push({"id": id, "name": name});
	draw();
}

function newD(to, from){
	data.edges.push({"id": null, "to": to, "from": from});
	draw();
}

function loadProject(){
	
	draw();
}



function mousedown(){
	
}



$(document).on('click', '#toggle-direction', toggleOrientation);

$(document).on('click', '#load-project', loadProject);

$(document).on('mousedown', '.node', mousedown);
	
function getData(){
	
}
function updateData(){
	$.ajax({
  		type: "POST",
 	 	url: "localhost:3000/creator/" + projectName + "/" + projectVersion + "/" + data + ".json",
  		data: data,
  		dataType: "json"
	})
  	.done(function( msg ) {
    	alert( "Data Saved: " + msg );
  	});
}
function startDragLine(){
	
};
$(document).on('mousedown', '.node-out', function(e){
	var target = mousedownNode = e.target.id;
	startDragLine(target);
	x1 = 
});

function keydown(){}
*/
