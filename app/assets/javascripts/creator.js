//initialize svg (d3)
var svg;
var backdrop;
function initSvg(){ 	
	svg = d3.select("#nodes-container")
		.append("svg")
			.attr("pointer-events", "all")
		.append("g")
			.attr('transform', 'translate(20,20)')
			.call(d3.behavior.zoom().on("zoom", rescale));
	backdrop = svg.append("rect")
		.attr("width", '100%')
		.attr("height", '100%')
		.attr("fill", 'aliceblue')
		.attr('class', 'backdrop')
		.on('mousemove', mousemove);
	return svg;
}

//initialize Dagre Renderer (dagre)
var g = new dagreD3.Digraph();
var renderer = new dagreD3.Renderer();
var layout = dagreD3.layout();
layout = layout.nodeSep(20).rankSep(20);
var orientation = "vertical";
function render(){renderer.layout(layout).run(g, d3.select('svg g'));}

var tempData;
function loadProject(){
	var pathUrl = dataPath + "/nodes.json";
	$.ajax({
        type: "GET",
        url: pathUrl,
        contentType: "application/json; charset=utf-8",
        dataType: "json",
        success: function(data){
        	tempData = data;
        	draw(data);
        },failure: function(errMsg) {
            alert(errMsg);
        }
  	});
}

function sendData(){
	var pathUrl = dataPath + "/nodes.json";
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

function format(data){
	for (node in data.nodes){
		if(data.nodes[node].value.label[0] !=="<"){
			var title = data.nodes[node].value.label;
			var subtitle = "Subtitle";
			var id = data.nodes[node].id;
			var nodeIcon = 'http://www.endlessicons.com/wp-content/uploads/2013/02/wrench-icon-614x460.png';
			var menuAlign = 'align:left';
			data.nodes[node].value.label = 
				"<div class = 'node-outer' id = " + id + ">" +
					"<img class = 'node-icon' src = " + nodeIcon + " id = " + id + ">" +
					"<div class = 'node-title-area' id = " + id + ">" +
						"<div class = 'node-title' id = " + id + ">" + 
							title + "</div><div class = 'node-subtitle' id = " + id + ">" + 
							subtitle + 
						"</div>" +
					"</div>" +
				"</div>"; 
		}
	}
}

function draw(data){
	var d = data;
	format(d);
	g = dagreD3.json.decode(d.nodes, d.edges);
    render();
    render();
    svg.selectAll('.node-outer')
    	.on('contextmenu', contextmenu)
    	.on('click', nodeClick);
}

function newNode(){
	var ids = [];
	var id;
	if(tempData.nodes[0].id == undefined){id = 1;}else{
		for(node in tempData.nodes){ids.push(tempData.nodes[node].id);}
		id = Math.max.apply(null,ids)+1;}
	var name = prompt("enter the name");
	tempData.nodes.push({ "id": id, "value": { "label": name } });
	draw(tempData);
	newId = id;
}

function newEdge(to, from){
	tempData.edges.push({"id": null, "v": to, "u": from});
	draw(tempData);
}

$(document).ready(function(){
	dataPath = $('#nodes-container').data().path;
	$(document).on("click", function (e){
		e.preventDefault();
	});
	initSvg();
	backdrop;
});
//buttons
$(document).on('click', '#add-node', function(){newNode();});

$(document).on('click', '#toggle-direction', toggleOrientation);

$(document).on('click', '#load-project', loadProject);

//keyboard call
d3.select(window)
    .on("keydown", keydown);
if (d3.event) {
    // prevent browser's default behavior
    d3.event.preventDefault();
  }

// listener functions

	//graph states
var selected_node = null,
    selected_link = null,
    mouseup_link = null,
    mousedown_node = null,
    mouseup_node = null;


function mousedown(){}
function mousemove(){
	var mouse = d3.mouse(this);
}
function mouseup(){}
function keydown(){}
function mouseenter(){}
function nodeClick(){
	if(targetNode == sourceNode){return;}else{
	newEdge(targetNode, sourceNode);
}}
var contextMenuShowing = false;
function contextmenu(){
	if(contextMenuShowing) {
        d3.event.preventDefault();
        d3.select(".popup").remove();
        contextMenuShowing = false;
    } else {
    	
		id = d3.event.target.id;
        d3.event.preventDefault();
        contextMenuShowing = true;
        mousePosition = d3.mouse(backdrop.node());
                
        menu = "<ul class = 'custom-context-menu'>";
        for(var i = 0; i < menuData.items.length; i++){
        	menu = menu + "<li class = 'context-menu-item' onclick = " +
        						menuData.items[i].action + "(" + id + ");" +">" +
        						menuData.items[i].text +
        					"</li>";
        }
        menu = menu + "</ul>";
        
        // Build the popup
		var w, h;
        popup = svg.append("foreignObject")
            .attr("class", "popup")
            .attr("width", 100000);

        popup.append('xhtml:div')
            .html(function() { return menu; })
      		.each(function() {
	        	w = this.clientWidth;
	        	h = this.clientHeight;
	      	});
	      	w = 300;
	      	h = h + 10;
		popup
			.attr('width', w)
			.attr('height', h)
			.attr('x', mousePosition[0])
			.attr('y', mousePosition[1] - h/2 );
        
        svgSize = [
            backdrop.node().width.animVal.value,
            backdrop.node().height.animVal.value
        ];
        //backdrop.node().width.animVal.value
        
        
        if (w + mousePosition[0] > svgSize[0]) {
            popup.attr('x', mousePosition[0] - w);
        }
        
        if (h + mousePosition[1] > svgSize[1]) {
            popup.attr('y', mousePosition[1] - h);
        }
        
        if (h > mousePosition[1]) {
            popup.attr('y', mousePosition[1]);
        }
    }
}

//DOM interaction functions
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

menuData = {
	"attr":{
		'height': 500,
		'width': 200,
		'x': null,
		'y': null
	}, 
	"items": [
		{
			"text": "Add child step",
			"action": 'nodeFrom'
		},
		{	
			"text": "Add Parent Step",
			"action": 'nodeTo'
		},
		{
			"text": "Edge from here",
			"action": 'edgeFrom'
		},
		{
			"text": "Edge to here",
			"action": 'edgeTo'
		},
		{
			"text": "Delete this node",
			"action": 'deleteNode'
		},
		{
			"text": "Open Linked Document",
			"action": 'function'
		}
]};
var targetNode,
	sourceNode;

function nodeFrom(source){
	newNode();
	newEdge(newId, source);
}

function nodeTo(target){
	newNode();
	newEdge(target, newId);
}

function edgeTo(target){
	targetNode = target;
}

function edgeFrom(source){
	sourceNode = source;
}
function deleteNode(id){
	for (i=0; i < tempData.nodes.length; i++){
	    if ((tempData.nodes[i].hasOwnProperty("id")) && (tempData.nodes[i]["id"] === id)) {
	        tempData.nodes = tempData.nodes.splice( id, 1 );
	        draw();
	        break;   // so that it doesn't keep looping, after finding a match
	    } 
	}
}
