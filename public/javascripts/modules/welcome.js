$(document).ready(function() {
  $("#signup-wizard .topic-title a").live("click", function() {
    $(this).attr("target", "_blank");
  });

  $(".close-link").click(function(event) {
    event.preventDefault();
    var link = $(this);
    $.ajax({
      url: $(this).attr("href"),
      dataType: "json",
      type: "GET",
      success: function(data) {
        $('#getting_started_div').slideUp("slow", function () {
          $(this).remove();
        });
      }
    });
  });

  $('#url_field_wrapper').delegate('.url_field', 'click', function() {
    $(this).select();
  });
});
