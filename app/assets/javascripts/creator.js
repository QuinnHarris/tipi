var g = new dagreD3.Digraph();
var renderer = new dagreD3.Renderer();
var layout = new dagreD3.layout();
var relationFrom = null;
var data = {nodes: [], edges: []};
var orientation = "vertical";
function render(){renderer.layout(layout).nodeSep(20).run(g, d3.select("svg g"));}

var createNode = function(id, name){
	//var format = [
	//"<div style = 'background-image: linear-gradient(to right bottom, #5D5AAD 0%, #ACD6E8 85%);'>",
	//	"<img style = 'height: 1 em;' src= 'https://cdn1.iconfinder.com/data/icons/huge-basic-icons/512/Wrench.png</div>'",
	//	"<ul class = 'node-title'>#{name}</ul>",
	//	"<ul class = 'node-buttons'>",
	//"</div>"].join('\n');
	g.addNode(id, {label: name});
};

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
	 ]};
	draw();
}

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


$(document).ready(function(){
	$(document).on("click", function (e){
		e.preventDefault();
	});
	var overrideLable = window.addLable;
	window.addLable = function(node, root, marginX, marginY){
		overrideLable();
	};
});

$(document).on('click', '#toggle-direction', toggleOrientation);

$(document).on('click', '#load-project', loadProject);

$(document).on('mousedown', '.node', loadProject);
	



