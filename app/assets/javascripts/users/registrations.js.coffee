# Place all the behaviors and hooks related to the matching controller here.
# All this logic will automatically be available in application.js.
# You can use CoffeeScript in this file: http://coffeescript.org/

//= require mailcheck

$ ->
  $('#user_email').on 'blur', () ->
    $(this).mailcheck(
      suggested: (element, suggestion) ->
        $('#did-you-mean a').html('Did you mean \<span>'+suggestion.full+'\</span>?');
        $('#did-you-mean').slideDown()
        $('#did-you-mean a').on 'click', () ->
          $('#user_email').val(suggestion.full)
          $('#did-you-mean').slideUp()
    )
