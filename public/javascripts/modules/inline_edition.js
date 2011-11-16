/************************************************************************************************
 * To undestand the usage by example, visit these files and search for the content that follows
 *
 *   public/javascripts/application.js // Inline editions
 *   app/controllers/users.rb          def inline_edition
 *   app/views/user/show.html.haml     .profile_inline_editable{ "data-inline-object-key" =>
 *   config/locales/users/*.yml        users.inline_edition.{empty_bio,empty_description}
 *   this file                         function profileInlineEdition
 *
 *     Note: You may notice that data-inline-object-key is an empty string in the profile example. This
 *   is because we can optimize the case for profile edition since we have the 'current_user' variable.
 *   Usually this variable will contain the id for the edited object. However, this is needed because
 *   we want to be able to place the data-inline-object-key as high as we want in the DOM.
 *
 *     The double-click version is completely untested and out of date. It was left here as a TODO and
 *   will be refactored in future when needed ( Probably by the university/affiliation administration
 *   system ).
 *
 *************************************************************************************************/

window.inlineEdition = {

  /* this variable is used to provide communication between 'blur' and
   * 'keyup' events. */
  inline_edition_control : false,

  makeInlineEditable: function (prepare)
  {
    var settings = prepare.call(this);
    $(settings.selector).after("<img class=\"ajax_waiting_image\" src=\"/images/ajax-loader.gif\" />");

    /* When we want the inline edition to be controlled by "edit", "save"
    * and "cancel" links */
      if(settings.method == "links") {
        // Basic DOM changings
        $(settings.selector)
	  .addClass("inline_editable")
	  .after("<a class=\"edit_link inline_link\" href=\"javascript:return false\">" + I18n.edit + "</a>")
	  .after("<a class=\"cancel_link inline_link\" href=\"javascript:return false\">" + I18n.cancel + "</a>")
	  .after("<a class=\"save_link inline_link\" href=\"javascript:return false\">" + I18n.save + "</a>");

	$(settings.selector)
	  .parent()
	  .addClass("inline_editable_container");

	if(typeof(settings.adjustments) == "function") {
          settings.adjustments();
	}

        // Edit link
	$(".edit_link").live("click", function(event) {
	  $(event.target).siblings('a.inline_link')
            .addClass("active_inline_link")
	    .removeClass("inline_link");

	  // Making the input
	  var inp = inlineEdition.replaceByInput($(event.target)
	    .siblings('.inline_editable'));

	  if(typeof(settings.placeSaveAndCancelLinks) != "function" ||
             !settings.placeSaveAndCancelLinks($(event.target), inp)) {

	    // Positioning "save" and "cancel" buttons.
	    var spacing = 16; //Spacing between input and inline_links

	    var i_left = inp.offset().left;
	    var i_width = inp.width();
	    var s_width = $(event.target).siblings('a.save_link').width();

	    $(event.target).siblings('a.save_link')
	      .css("left", i_left + i_width + spacing)
              .css("top", inp.offset().top);

	    $(event.target).siblings('a.cancel_link')
	      .css("left", i_left + i_width + s_width + 2.5*spacing)
              .css("top", inp.offset().top);

	  }
	  // Hides the "edit"
	  $(event.target).removeClass('edit_link').addClass('inactive_edit_link');

      });

      // Cancel link
      $('.cancel_link').live('click',
        function(event) {
	  inlineEdition.cancel($(':input', $(event.target).parent()), settings);
          $(event.target).siblings('.active_inline_link')
	    .add(event.target)
	    .removeClass("active_inline_link")
	    .addClass('inline_link');

          $(event.target).siblings('.inactive_edit_link')
            .removeClass('inactive_edit_link')
            .addClass('edit_link');
      });

      // Save link
      $('.save_link').live('click',
        function(event) {
          var sentRequest = inlineEdition.save($(':input', $(event.target).parent()), settings,
	    function(elem) { //beforeChange
	      elem.parent().siblings('.inactive_edit_link')
                .removeClass('inactive_edit_link')
                .addClass('edit_link');

              elem.parent().siblings('.active_ajax_waiting_image')
	        .removeClass('.active_ajax_waiting_image')
                .addClass('ajax_waiting_image');
	    });

	  if(sentRequest)
            $('.ajax_waiting_image', $(event.target).parent())
              .removeClass('ajax_waiting_image')
              .addClass('active_ajax_waiting_image');
	  else
	    $(event.target).siblings('.inactive_edit_link')
	      .removeClass('inactive_edit_link')
              .addClass('edit_link');

          $(event.target).siblings('.active_inline_link')
	    .add(event.target)
	    .removeClass("active_inline_link")
	    .addClass('inline_link');
        }
      );
    }

    /* When we want the inline edition to be controlled by "double click"
     * "enter" and "blur"
     * TODO: dblclick needs refactoring */
    if(settings.method == "dblclick")
    {
      $(settings.selector).live("dblclick", function(event) {
        inlineEdition.replaceByInput($(event.target));
      }).addClass('inline_dblclick_editable');

      // Second, set the blur event (Will this be here?)
      $(settings.selector).live("blur", function(event) {
        if(inlineEdition.inline_edition_control)
          inlineEdition.inline_edition_control = false;
        else
	  $(event.target).parent().text($(event.target).attr("data-previous-value"));
        });

      // Third, set the keyup for save on enter
      $(settings.selector).live("keyup", function(event) {
	if(event.keyCode == "13") { //keyCode 13 is an enter
	  // Control to prevent onblur event to overwrite this results
	  inlineEdition.inline_edition_control = true;

          // Sets locally
	  inlineEdition.save($(event.target), settings);

          // Show ajax waiting image
          $('.ajax_waiting_image', $(event.target).parent().parent()).removeClass('ajax_waiting_image').addClass('active_ajax_waiting_image');
        }
      });
    }
  },

  cancel: function(elem, settings) {

    if(elem.parent().attr('data-inline-edition-markdown') &&
      !elem.parent().hasClass('empty_inline_editable_field'))
    {
      var converter = new Showdown.converter();
      elem.parent().html(converter.makeHtml(elem.attr("data-previous-value")));
    }
    else
      elem.parent().html(elem.attr("data-previous-value"));
  },

  save: function(elem, settings, beforeChange) {
    if(elem.val() == elem.attr('data-previous-value') ||
        (elem.parent().hasClass('empty_inline_editable_field') &&
	 elem.val()=='')) {
      inlineEdition.cancel(elem, settings);
      return false;
    }

    var parent = elem;
    while(parent.attr("data-inline-object-key") == undefined)
	parent = parent.parent();

    elem.attr('readonly','readonly');

    var ajaxParams = {
    url: settings.url,
      data: {
        name: elem.parent().attr("data-inline-name"),
        value: elem.val(),
        inline_object_key: parent.attr("data-inline-object-key")
      },

      type: "POST",

      error: function(data) {
	Utils.showMessage('sorry, something went wrong.', 'error');

	if(typeof(beforeChange) == "function")
	  beforeChange.call(null, elem);

	elem.parent().html(elem.attr('data-previous-value'));
      },

      success: function(data) {
	elem.removeAttr('readonly');

        if(data.error.length > 0)
	  Utils.showMessage(data.error, "error");

	if(data.empty_field)
	  elem.parent().addClass('empty_inline_editable_field');
	else
	  elem.parent().removeClass('empty_inline_editable_field');

        if(elem.parent().attr("data-inline-edition-editable-content"))
	  elem.parent().attr("data-inline-edition-editable-content", data.value);

	if(typeof(beforeChange) == "function")
	  beforeChange.call(null, elem);

        if(elem.parent().attr('data-inline-edition-markdown') &&
          !elem.parent().hasClass('empty_inline_editable_field')) {

	  elem.parent().attr('data-inline-edition-editable-content', data.value);

	  var converter = new Showdown.converter();
          elem.parent().html(converter.makeHtml(data.value));
	}
	else
	  elem.parent().html(data.value);
      }
    };
    $.ajax(ajaxParams);
    return true;
  },

  replaceByInput: function(elem) {
    var text = elem.attr("data-inline-edition-editable-content") || elem.text();

    var inputType = elem.attr('data-inline-edition-input');
    if(inputType == "textarea")
    {
      if(elem.hasClass('empty_inline_editable_field'))
        elem.html('<textarea resizable="resizable" style="height: 80px; width: 225px;"></textarea>');
      else
        elem.html('<textarea resizable="resizable" style="height: 80px; width: 225px;">'+text+'</textarea>');
    }
    else
    {
      if(elem.hasClass('empty_inline_editable_field'))
        elem.html('<input type="text"/>');
      else
        elem.html('<input value="'+text+'"type="text"/>');
    }

    return $(":input ", elem).attr("data-previous-value", text).focus();
  },

  resetView: function() {
    $('.active_inline_link').removeClass('active_inline_link');
    $('.active_ajax_waiting_image').removeClass('.active_ajax_waiting_image').addClass('ajax_waiting_image');
  }
};

function universityInlineEdition() {
  return {
    //Can be either 'links' or 'dblclick' TODO: dblclick needs refactoring
    method: "dblclick",

    //The url that will be called to handle the edition
    url: "/universities/inline_edition"
  };
}

function profileInlineEdition() {
  return {
    // Can be either 'links' or 'dblclick' TODO: dblclick needs refactoring
    method: "links",

    // The url that will be called to handle the edition
    url: "/users/inline_edition",

    //
    selector: ".profile_inline_editable[data-inline-name], .profile_inline_editable *[data-inline-name]",

    placeSaveAndCancelLinks: function(elem, inp) {
      /* Place the "save" and "cancel" link in the bottom instead of after.
       * (only if is edition description)
       * Takes the edit link as the input as parameter. */

       if(elem.siblings("*[data-inline-name]").attr("data-inline-name") != "description")
	 return false;

       else if(elem.siblings("*[data-inline-name]").attr("data-inline-name") != "description")
	 return false;

       var spacing = 24; //Spacing between save and cancel links

       var e_left = elem.offset().left;
       var s_width = elem.siblings('a.save_link').width();

       elem.siblings('a.save_link')
         .css("left", e_left);

       elem.siblings('a.cancel_link')
	 .css("left", e_left + s_width + spacing);

      return true;

    }
  };
}
