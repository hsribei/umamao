function signUpAjaxRequest(){var a=$(this).parents("form");$("#affiliation_submit").attr("readonly","readonly");$("#ajax-loader").removeClass("hidden");$("input#affiliation_email").attr("readonly","readonly");return{url:"/affiliations?format=js",data:a.serialize(),success:function(b){if(b.url){window.location.href=b.url}},complete:function(){$("#ajax-loader").addClass("hidden");$("#affiliation_submit").removeAttr("readonly");$("input#affiliation_email").removeAttr("readonly")}}}function emailtooltip(){$("#email-help").hover(function(a){$("#help-box").css({left:a.pageX-290,top:a.pageY-50});$("#help-box").show()},function(){$("#help-box").hide()})};