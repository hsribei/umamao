$(document).ready(function() {
  var request_ip = $('meta[name=request_ip]').attr('content');
  var user_id = $('meta[name=user_id]').attr('content');
  var user_name = $('meta[name=user_name]').attr('content');
  var properties = { ip: request_ip, id: user_id };

  mpq.name_tag(user_name);

  $('#url_share #twitter').delegate('a', 'click', function() {
    mpq.track('clicked_to_share_url_invitation_via_twitter', properties);
    mpq.track('any_action', properties);
  });

  $('#url_share #facebook').delegate('a', 'click', function() {
    mpq.track('clicked_to_share_url_invitation_via_facebook', properties);
    mpq.track('any_action', properties);
  });
});
