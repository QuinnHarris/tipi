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
var g = new dagreD3.Digraph();
var renderer = new dagreD3.Renderer;
var layout = dagreD3.layout();
layout = layout.nodeSep(20).rankSep(20);
var orientation = "vertical";
function render(){renderer.layout(layout).run(g, d3.select("svg g"));}

//getData (ajax)
var tempData;
function getData(name, version){
	var pathUrl = "/creator/" + name + "/" + version + "/nodes.json";
	$.ajax({
        type: "GET",
        url: pathUrl,
        dataType: "json",
        success: function(data){
        	tempData = data;
        },failure: function(errMsg) {
            alert(errMsg);
        }
  	});
}

//sendData (ajax)
function sendData(){
  	$.ajax({
        type: "POST",
        url: pathUrl,
        data: data,
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function(data){
        	alert(data);
        },failure: function(errMsg) {
            alert(errMsg);
        }
  	});
}

function format(node){
	var title = node.value;
	var subtitle = "Subtitle";
	var id = node.id;
	var inIcon = 'http://i.stack.imgur.com/BUlXq.png';
	var nodeIcon = 'http://www.endlessicons.com/wp-content/uploads/2013/02/wrench-icon-614x460.png';
	var outIcon = 'https://cdn2.iconfinder.com/data/icons/large-glossy-svg-icons/512/logout_user_login_account-512.png';
	var label = "<div class = 'node-outer'><img class = 'node-in' id = " + 
				id + " src = " + 
				inIcon + "><img class = 'node-icon' src = " +
				nodeIcon + "><div class = 'node-title-area'><div class = 'node-title'>" + 
				title + "</div><div class = 'node-subtitle'>" + 
				subtitle + "</div></div><img class = 'node-out' id = " + 
				id + " src = " + 
				outIcon + "></div>"; 
				node.value = label;
}
var data;
function draw(){
	g = new dagreD3.Digraph();
	for (node in data.nodes){
		var n = data.nodes[node];
		format(n);
    	g.addNode(n.id, n.value);
    };
    for(edge in data.edges){
    	var e = data.edges[edge];
    	g.addEdge(null, e.u, e.v);
	};
	render();
}

function loadProject(){
	getData("project","6");
	data = tempData;
	draw();
}

function newNode(name){
	var ids = [];
	var id;
	if(data.nodes[0].id == undefined){id = 1;}else{
		for(node in data.nodes){ids.push(data.nodes[node].id);}
		id = Math.max.apply(null,ids)+1;}
	var name = prompt("enter the name");
	data.nodes.push({"id": id, "name": name});
	draw();
}
function newEdge(to, from){
	data.edges.push({"id": null, "to": to, "from": from});
	draw();
}
//mouse events
$(document).ready(function(){
	$(document).on("click", function (e){
		e.preventDefault();
	});
	initSvg();
});

$(document).on('click', '#toggle-direction', toggleOrientation);

$(document).on('click', '#load-project', loadProject);

$(document).on('mousedown', '.node', mousedown);

$(document).on('mousedown', '.node-out', function(e){
	var target = mousedownNode = e.target.id;
	
});

// in mousedown

//keyboard events

d3.select(window)
    .on("keydown", keydown);
    
if (d3.event) {
    // prevent browser's default behavior
    d3.event.preventDefault();
  }

function keydown(){
	
}
//other dom interaction
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

function rescale(){}
