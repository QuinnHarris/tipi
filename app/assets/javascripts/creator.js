/* Place all the behaviors and hooks related to the matching controller here.
  All this logic will automatically be available in application.js.
  You can use CoffeeScript in this file: http://coffeescript.org/
*/
$( document ).ready(function() {

data = [4, 8, 15, 16, 23, 42];

x = d3.scale.linear()
    .domain([0, d3.max(data)])
    .range([0, 420]);

d3.select(".chart")
  .selectAll("div")
    .data(data)
  .enter().append("div")
<<<<<<< HEAD:app/assets/javascripts/creator.js.coffee
    .style("width", (d) -> x(d) + "px")
    .text(d) -> return d
=======
    .style("width", function(d) { return x(d) + "px"; })
    .text(function(d) { return d; });
});
>>>>>>> 793795fb32e3e9e488fc651fff5fc415efdf789c:app/assets/javascripts/creator.js
