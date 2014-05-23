/*bugs: 
	on zoom the html shrinks more than the svg
*/

// diagram showing cost in money and time
// incremental display arrow keys
// node bank
// temporary display of active node contents
	// fill in keydown function
	// undo/redo functionality
	// forking
	// social media interaction
	// permission
// project title area and real toolbars
	// if the screen is a smart phone:
	// mark completed nodes green
	// mark available nodes
	// update svg margins with the d3 example
	// add scrolling
	// add moving text if title is to long
	// button for delegate to team
	// animate transition
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
renderer.transition(transition);
var layout = dagreD3.layout();
layout = layout.nodeSep(20).rankSep(20);
var orientation = "vertical";

function transition (selection) {
	return selection.transition().duration(500);
}

function render(){
	format();
	renderer.transition(transition).layout(layout).run(g, d3.select('svg g'));
	svg.selectAll('.node-outer')
		.call(d3.behavior.drag()
			.on('dragend', nodeDragend))
    	.on('contextmenu', contextmenu)
    	.on('mousedown', nodeClick);
    svg.selectAll('node-outer');
    	
    	if(typeof activeNode !== 'undefined'){
		svg.selectAll('#' + activeNode + '.node-outer').classed('active-node', true);
	}
}

function format(){
	g.eachNode( function(id, value){
		if (typeof value.label === 'undefined'){
			var title = value.name;
			var subtitle = "Subtitle";
			var nodeIcon = 'http://www.endlessicons.com/wp-content/uploads/2013/02/wrench-icon-614x460.png';
			value.label = 
				"<div class = 'node-outer' id = " + id + ">" +
					"<img class = 'node-icon' src = " + nodeIcon + " id = " + id + ">" +
					"<div class = 'node-title-area' id = " + id + ">" +
						"<div class = 'node-title' id = " + id + ">" + 
							title + "</div>" + /*<div class = 'node-subtitle' id = " + id + ">" + 
							subtitle + 
						"</div>" + */
					"</div>" +
				"</div>";
		}
	});
}

$(document).ready(function(){
	dataPath = $('#nodes-container').data().path;
	$(document).on("click", function (e){
		e.preventDefault();
	});
	initSvg();
	backdrop;
	
});

inter = {
	ops: [],
	load: function(){
		d3.json(dataPath + '.json', function(d){
			g = new dagreD3.Digraph();
			for (i = 0; i < d.length; i++){
				if (d[i].type == 'node'){
					var n = g.addNode(null, { id: d[i].id, name: d[i].name });
				}
				if (d[i].type == 'edge'){
					var from, to;
					g.eachNode(function(id,value){
						if (d[i].u == value.id){from = id;}
						if (d[i].v == value.id){to = id;}
					});
					g.addEdge(null, from, to);
				}
			}
			render();
		});
	},
	addNode: function(name){
		// user input for name if name isn't given
		if (typeof name === 'undefined' || typeof name === 'null'){
			name = prompt('name your node:');
			if (typeof name === 'undefined' || typeof name === 'null'){return null;}
		}
		
		cid = g.addNode( null, { name: name });
		inter.ops.push({op: 'add', type: 'node', name: name, cid: cid});
		return cid;
	},
	addEdge: function(to, from){
		txn = {op: 'add', type: 'edge' };
		if (g.node(to).id)
			txn['v'] = g.node(to).id;
		else
			txn['cv'] = to;
		
		if (g.node(from).id)
			txn['u'] = g.node(from).id;
		else
			txn['cu'] = to;
		
		id = g.addEdge(null, from, to);
		inter.ops.push(txn);
		return id;
	},
	delNode: function(cid){
		id = g.node(cid).id;
		g.delNode(cid);
		inter.ops.push({op: 'remove', type: 'node', id: id});
	},
	delEdge: function(e){
		from = g.node(g.source(e)).id;
		to = g.node(g.target(e)).id;
		g.delEdge(e);
		inter.ops.push({op: 'remove', type: 'edge', v:to, u: from});
	},
	changeNode: function(id, name){
	},
	run: function(){
		$.ajax({
			type: 'POST',
			dataType: 'json',
			url: dataPath + '/write',
			data: { 'data': JSON.stringify(inter.ops)},
			success: function (d){
				for (i = 0; i < d.length; i++){
					if (d[i].type == 'node' && d[i].op == 'add'){
						g.node(d[i].cid).id = d[i].id;
					}
				}
			}
		});
		inter.ops = [];
	}
};

function addNode(name){
	inter.addNode(name);
	inter.run();
	render();
}
function addEdge(to, from){
	inter.addEdge(to,from);
	inter.run();
	render();
}

function nodeFrom(source, name){
	var target = inter.addNode(name);
	inter.addEdge(target, source);
	inter.run();
	render();
}

function nodeTo(target, name){
	var source = inter.addNode(name);
	inter.addEdge(target, source);
	inter.run();
	render();
}

function delNode(id){
	inter.delNode(id);
	inter.run();
	render();
}

function delEdge(target, source){
	var arr = g.incidentEdges(target,source);
	inter.delEdge(arr[0]);
	inter.run();
	render();
}



//buttons
$(document).on('click', '#add-node', addNode); 

$(document).on('click', '#toggle-direction', toggleOrientation);

$(document).on('click', '#load-project', inter.load);

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
	if(typeof activeNode !== 'undefined'){
		var abort = false;
		var source = this.id;
		var target = d3.event.sourceEvent.target.id;
		g.eachEdge(function(id,from,to){
			if(to == target && source == from) abort = true;//check for identical
			if(to == source && target == from){// check for reverse
				delEdge(target, source);
				abort = true;
			}	
		});
		// make sure it is not an edge to itself and make sure target is a real target
		if(target != source && abort == false && target !== ''){
			addEdge(target, source);
		}else if (target === ''){
			nodeFrom(source);
		}
	}
}
function mousemove(){
	var mouse = d3.mouse(this);
}

function keydown(){
	if (typeof activeNode !== 'undefined') {
		switch (d3.event.keyCode) {
	    case 8: // backspace
	    case 46: // delete
	        delNode(activeNode);
			break;
		case 13: //enter
		case 17: //control
		case 37: // left
		case 38: // up
		case 39: // right
		case 40: // down
		case 90: //z
		case 89: //y
		
		}
	}
}
function nodeClick(){
	activeNode = d3.event.target.id;
	render();
}

function contextmenu(){
    d3.event.preventDefault(); // prevent default menu
    var popup = d3.select(".popup");
    popup.remove();// delete old menu in case it's there
	id = d3.event.target.id;
    mousePosition = d3.mouse(backdrop.node()); //map mouse movements
    //Create the html for the menu
    menu = "<ul class = 'custom-context-menu'>";
    for(i = 0; i < menuData.items.length; i++){
    	menu = menu + "<li class = 'context-menu-item' onclick = " +
    						menuData.items[i].action + "('" + id + "');" +">" +
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
	"attr": {
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
			"action": 'delNode'
		}
]};