$ ->
  $("#share-search").autocomplete(
    appendTo: "#share-result",
    source: $("#share-search").data().path
    select: (event, ui) ->

  ).data('ui-autocomplete')._renderItem = (ul, item) ->
    ul.append($("<li>")
      .append $("<div>", class: 'thumb').append($("<img>", src: item.image))
      .append $("<div>", class: 'name').text item.label
      .append $("<div>", class: 'email').text item.email
    )

  $("#share-current").menu()
