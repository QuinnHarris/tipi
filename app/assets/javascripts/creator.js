/*Place all the behaviors and hooks related to the matching controller here.
  All this logic will automatically be available in application.js.
  You can use CoffeeScript in this file: http://coffeescript.org/
*/
$( document ).ready(function() {
	// Create a new directed graph
	var g = new dagreD3.Digraph();
	
	// Nodes (id, {meta});
	g.addNode("kspacey",    { label: "Kevin Spacey" });
	g.addNode("swilliams",  { label: "Saul Williams" });
	g.addNode("bpitt",      { label: "Brad Pitt" });
	g.addNode("hford",      { label: "Harrison Ford" });
	g.addNode("lwilson",    { label: "Luke Wilson" });
	g.addNode("kbacon",     { label: "Kevin Bacon" });
	
	//Edges (id(null for autoassign), "source", "target", {meta});
	g.addEdge(null, "kspacey",   "swilliams");
	g.addEdge(null, "swilliams", "kbacon");
	g.addEdge(null, "bpitt",     "kbacon");
	g.addEdge(null, "hford",     "lwilson");
	g.addEdge(null, "lwilson",   "kbacon");
	
	var renderer = new dagreD3.Renderer();
	renderer.run(g, d3.select('svg g'));
	
	var layout = dagreD3.layout()
                    .nodeSep(20)
                    .rankDir("LR");
	renderer.layout(layout).run(g, d3.select("svg g"));
});