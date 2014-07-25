$(document).ready(function() {
    $("#share-search").autocomplete({
        appendTo: "#share-result",
        source: function (request, response) {
            $.ajax({
                url: $("#share-search").data().path,
                dataType: 'html',
                data: { q: request.term },
                success: function (data) {
                    response([data]);
                }
            })
        }
    })
});