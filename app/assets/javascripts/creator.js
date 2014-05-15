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

function render(){
	renderer.layout(layout).run(g, d3.select('svg g'));
	svg.selectAll('.node-outer')
		.call(d3.behavior.drag()
			.on('dragend', nodeDragend))
    	.on('contextmenu', contextmenu)
    	.on('mousedown', nodeClick);
    svg.selectAll('node-outer')
    	.on('mouseover', nodeMouseover);
    	
    	if(activeNode){
		svg.selectAll('#' + activeNode + '.node-outer').classed('active-node', true);
	}
}
	

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
        	draw();
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

function format(){
	for (node in tempData.nodes){
		if(tempData.nodes[node].value.label[0] !=="<"){
			var title = tempData.nodes[node].value.label;
			var subtitle = "Subtitle";
			var id = "id" + tempData.nodes[node].id;
			var nodeIcon = 'http://www.endlessicons.com/wp-content/uploads/2013/02/wrench-icon-614x460.png';
			var menuAlign = 'align:left';
			tempData.nodes[node].value.label = 
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

function draw(){
	var d = tempData;
	format();
	g = dagreD3.json.decode(d.nodes, d.edges);
    render();
    render();
}
function newNode(){
	var ids = [];
	var id;
	if(tempData.nodes[0].id == undefined){id = 1;}else{
		for(node in tempData.nodes){ids.push(tempData.nodes[node].id);}
		id = Math.max.apply(null,ids)+1;}
	var name = prompt("enter the name");
	tempData.nodes.push({ "id": id, "value": { "label": name } });
	draw();
	newId = id;
}

function newEdge(to, from){
	tempData.edges.push({"id": null, "v": to, "u": from});
	draw();
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
function nodeDragend(){
	if(activeNode){
		var abort = false;
		var source = activeNode.substr(2,100);
		var target = d3.event.sourceEvent.target.id.substr(2,100);
		g.eachEdge(function(e,u,v,label){
			if(source == u && target == v){
				abort = true;
				return;
			}
		});
		if(target != source && abort == false){
			newEdge(target, source);
		}
	}
}
function nodeMouseover(){
	mouseNode = d3.event.target.id;
	console.log(mouseNode);
}
function mousemove(){
	var mouse = d3.mouse(this);
}

function keydown(){}
function nodeClick(){
	activeNode = d3.event.target.id;
	render();
	d3.select('.popup').remove();
}

function contextmenu(){
    d3.event.preventDefault(); // prevent default menu
    var popup = d3.select(".popup");
    popup.remove();// delete old menu in case it's there
	id = d3.event.target.id.substr(2,100); 
    mousePosition = d3.mouse(backdrop.node()); //map mouse movements
    
    //Create the html for the menu
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
    
    //keep menu inside the boundaries
    if (w + mousePosition[0] > svgSize[0]) {
        popup.attr('x', mousePosition[0] - w);
    }
    
    if (h + mousePosition[1] > svgSize[1]) {
        popup.attr('y', mousePosition[1] - h);
    }
    
    if (h > mousePosition[1]) {
        popup.attr('y', mousePosition[1]);
    }
    
    //delete context menu on mouse exit
    
    popup
    .on('mouseleave', function(){
    	if (d3.event.target.class !== 'custom-context-menu' || d3.event.target.id !== id){
    		d3.select('.popup').remove();
    	}
    })
    .on('click', function(){
    	d3.select('.popup').remove();
    });
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
			"text": "Open Linked Document",
			"action": 'function'
		},
		{
			"text": "Add child step",
			"action": 'nodeFrom'
		},
		{	
			"text": "Add Parent Step",
			"action": 'nodeTo'
		},
		{
			"text": "Delete this node",
			"action": 'deleteNode'
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
	g.delNode(id);
	render();
}
