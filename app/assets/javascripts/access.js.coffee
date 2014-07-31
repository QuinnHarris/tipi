$ ->
  return unless $("#share-search").length
  makeItem = (item) ->
    $("<li>", id: item.value)
      .append $("<div>", class: 'thumb').append($("<img>", src: item.image))
      .append ($("<div>", class: 'detail')
        .append $("<div>", class: 'name').text item.label
        .append $("<div>", class: 'email').text item.email )

  $("#share-search").autocomplete(
    source: $("#share-search").data().path
    select: (event, ui) ->
      $("#share-search").val('')
      menu = $("#share-current")
      makeItem(ui.item).prependTo(menu)
      menu.menu('refresh')

      $.ajax('access/add',
        method: 'PUT',
        data: { id: ui.item.value })

      false
  ).data('ui-autocomplete')._renderItem = (ul, item) ->
    makeItem(item).appendTo ul

  $("#share-current").menu()

  $("#share-current a.remove").click (event) ->
    li = $(event.target).parents("li")
    $.ajax('access/remove',
      method: 'DELETE',
      data: { id: li.attr('id') })
    li.remove()
