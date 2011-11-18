$(document).ready(function() {
  $('#url_share #twitter').delegate('a', 'click', function() {
    mpq.track('twitter_share_clicked');
  });

  $('#url_share #facebook').delegate('a', 'click', function() {
    mpq.track('facebook_share_clicked');
  });
});
