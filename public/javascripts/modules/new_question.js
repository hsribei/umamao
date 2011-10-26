$(document).ready(function() {
  initTopicAutocompleteForForms('question');

  initQuestionAutocomplete();

  $("label#rqlabel").hide();

  $(".text_field#question_title").focus( function() {
    highlightEffect($("#sidebar .help"));
  });

  $("input#question_title").focus();

});
