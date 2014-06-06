/*bugs: 
 * 
 * 
 */

/*features:
 * 
 * 		diagram showing cost in money and time
 * incremental display arrow keys
 * fill in keydown function
 * 		undo/redo functionality
 * 		forking
 * 		change coloring scheme to :completed(green), :active(red), :available(blue), :unavailable(grey)
 * 		social media interaction
 * 		permission
 * 		if the screen is a smart phone:
 * 		add moving text if title is to long
 * 		button for delegate to team
 * 		double click and activeNode link behavior
 * 		make data visible to google for seo
 * 	better node creation
	
//initialize svg (d3)
 * 
 * 
 */

var margin = { left: 20, top: 20, bottom: 0, right: 0 };
var svg;
var svgg;
var backdrop;
function initSvg(){
	svgNoZoom = d3.select("#svg-container")
		.append("svg");
		
	svg = svgNoZoom
		.append('g')
			.call(d3.behavior.zoom()
				.scaleExtent([1, 10])
				.on("zoom", zoom))
			.on("dblclick.zoom", null);
				
	backdrop = svg
		.append('rect')
			.attr('pointer-events', 'all')
			.attr("width", '100%')
			.attr("height", '100%')
			.attr("fill", 'none');
			
	svgg = svg.append("g")
		.attr('transform', 'translate(' + margin.top +  ',' + margin.left + ')');
		
	return svgg;
}
//initialize Dagre Renderer (dagre)
var g = new dagreD3.Digraph();
var renderer = new dagreD3.Renderer();
renderer.transition(transition);
var layout = dagreD3.layout();
layout = layout.nodeSep(20).rankSep(20);
var orientation = "vertical";

function transition (selection) { return selection.transition().duration(500); }

function render(){
	format();
	renderer
		.transition(transition)
		.layout(layout)
		.run(g, svgg);
	
	// post render
	svgg.selectAll('.node-outer')
		.call(d3.behavior.drag()
			.on('dragstart', dragstart)
			.on('dragend', dragend))
    	.on('contextmenu', contextmenu)
    	.on('mousedown', nodeClick);
    
    // set the active node's class
    if(typeof activeNode !== 'undefined'){
		svgg.selectAll('#' + activeNode + '.node-outer').classed('active-node', true);
		for(i=0;i<nextNodes.length;i++){
			svgg.selectAll('#' + nextNodes[i] + '.node-outer').classed('next-node', true);
		}
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
	edit();
	inter.load();
	setTimeout(function(){
		render();
		setH();
	}, 1000);
});

inter = {
	ops: [],
	load: function(){
		d3.json(dataPath + '.json', function(d){
			g = new dagreD3.Digraph();
			for (i = 0; i < d.length; i++){
				if (d[i].type == 'node'){
					var n = g.addNode(null, { id: d[i].id, name: d[i].name, doc: d[i].doc});
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
		if (typeof name !== 'string'){
			name = prompt('name your node:');
			if (name == null) return;
		}
		
		cid = g.addNode( null, { name: name });
		inter.ops.push({op: 'add', type: 'node', name: name, cid: cid});
		return cid;
	},
	addEdge: function(to, from){
		var txn = {op: 'add', type: 'edge' };
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
		//TODO make sure edges are removed	
		d3.selectAll('.froala-box').classed("custom-box", true);
		$('#doc').editable('setHTML', "");
		delete activeNode;
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
	if (typeof target !== 'undefined') {
		inter.addEdge(target, source);
		inter.run();
		render();
	}
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

$(window).resize(setH);
//keyboard call
d3.select(window)
    .on("keydown", keydown);
if (d3.event) {
    // prevent browser's default behavior
    d3.event.preventDefault();
}

// listener functions
function dragstart(){
	d3.event.sourceEvent.stopPropagation();
}

function dragend(){
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

function zoom(){
	var ev = d3.event;
	var t = ev.translate;
	var a = [t[0] + margin.top, t[1] + margin.left];
	svgg.attr('transform', 'translate(' + a + ') scale(' + ev.scale + ')');
}

function keydown(){
	if (typeof activeNode !== 'undefined' && !$('.froala-element').is(':focus'))
		switch (d3.event.keyCode) {
	    case 8: // backspace
	    	d3.event.preventDefault();
	    	break;
	    case 46: // delete
	    	console.log (d3.event.keyCode)
	        delNode(activeNode);
			break;
		case 13: //enter
			break;
		case 17: //control
			break;
		case 37: // left
			break;
		case 38: // up
			break;
		case 39: // right
			break;
		case 40: // down
			break;
		case 90: //z
			break;
		case 89: //y
			break;
		}
}
function nodeClick(){
	if( typeof activeNode !== 'undefined')
		$('#doc').editable('save');
	activeNode = d3.event.target.id;
	nextNodes = g.successors(activeNode);
	$('#doc').editable('setHTML', g.node(activeNode).doc);
	d3.selectAll('.froala-box').classed("custom-box", false);
	$('#doc-title').text(g.node(activeNode).name);
	setH();
	render();
	d3.select('.popup').remove();
}

function contextmenu(){
    d3.event.preventDefault(); // prevent default menu
    var popup = d3.select(".popup");
    popup.remove();// delete old menu in case it's there
	id = d3.event.target.id;
	console.log(this);
	console.log(d3.event);
    mousePosition = d3.mouse(svgNoZoom.node()); //map mouse movements
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
    popup = svgNoZoom.append("foreignObject")
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
	    	if (d3.event.relatedTarget.id !== id) d3.select('.popup').remove();
	    })
	    .on('click', function(){
	    	d3.select('.popup').remove();
	    });
    
    d3.selectAll('.node-outer#'+ id)
	    .on('mouseleave', function(){
	    	target = d3.event.relatedTarget;
	    	// check if it is list item
	    	if (target.className === 'context-menu-item') return;
	    	//chekc if it is list
	    	if (target.hasChildNodes() && target.firstElementChild.className === 'custom-context-menu') return;
	    	else d3.select('.popup').remove();
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
		d3.selectAll('#toggle-direction').classed('fa-arrows-h', false);
		d3.selectAll('#toggle-direction').classed('fa-arrows-v', true);
	}else{
		layout = layout.rankDir("TB");
		orientation = "vertical";
		d3.selectAll('#toggle-direction').classed('fa-arrows-v', false);
		d3.selectAll('#toggle-direction').classed('fa-arrows-h', true);
	}
	render();
	return;
}

function edit(){
	$(function(){
		$('#doc').editable({
			//autosave: true,
			//autosaveInterval: 2500,
			saveURL: dataPath + "/post_doc",
			inlineMode: false,
			height: '100%',
			buttons: ["bold", "italic", "underline",
				 "strikeThrough", "fontFamily", "fontSize",
				 "color", "formatBlock", "blockStyle",
				 "align", "insertOrderedList", 
				 "insertUnorderedList", "outdent",
				 "indent", "selectAll", "createLink",
				 "insertImage", "insertVideo", "undo",
				 "redo", "html", "save", "insertHorizontalRule"],
			preloaderSrc: "http://preloaders.net/preloaders/290/Long%20fading%20lines.gif",
			typingTimer: 750,
			beforeSaveCallback: function(){
				if(!activeNode) return
					docNode = activeNode;
					$('#doc').editable('option', "saveParams", {version: g.node(activeNode).id});
			},
			afterSaveCallback: function (d){
				g.node(docNode).doc = d.doc;
				g.node(docNode).id = d.id;
				if(docNode == activeNode) $('#doc').editable('option', "saveParams", {version: d.id});
			},
			saveErrorCallback: function(error){
				console.log(error);
			}
			});
	});
}

function setH(){
	var pad = 12;
	var buffer = 5;
	var h = {};
	h.app = $(window).height()
		- $(".top-bar").height()
		- buffer;
	h.doc = h.app
		- $(".froala-editor.f-basic").height()
		- $('#doc-title').height()
		- pad
		- buffer;
	h.svg = h.app
		- $("#buttons-container").height()
		- buffer;
	$('#app-container').height(h.app);
	$('svg').height(h.svg);
	$("#doc").height(h.doc);
}

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
		},
		{
			'text': "Create project from this node",
			"action": null
		}	
]};
