$(function() {

  jQuery.fn.toggleWarnings = function(id) {
    var id = id;
    this.bind("click", function() {
      if($("a#show_model_" + id + "_warnings").html()=="show") {
        $("dd#model_" + id + "_warnings").slideDown("slow");
        $("a#show_model_" + id + "_warnings").html("hide");
      }else{
        $("dd#model_" + id + "_warnings").slideUp("slow");
        $("a#show_model_" + id + "_warnings").html("show");
      }
    });
    return false;
  };

  checkStati = function(stati) {
    stati = stati.split(", ")
    $("body")
    var newstati = new Array;
    $.each(stati, function(){
      if(checkStatus(this) > 0) newstati.push(this);
    });  
    if (newstati.length > 0) var statusCheck = setTimeout('checkStati("' + newstati.join(", ") + '")',10000);
  };
  
  checkStatus = function(id) {
    if(id == "") return -1; 
    var opts = {method: 'get', action: 'model/' + id + '/status', id: id};
    var status_changed = $.ajax({
      type: opts.method,
      url: opts.action,
      async: false,
      dataType: 'html',
      data: {
        '_method': 'get'
      },
      success: function(data) {
        var erg = data.search(/Running/);
        status_changed = false;
        if(erg < 0) status_changed = true;        
        $("span#model_" + id + "_status").animate({"opacity": "0.1"},1000);
        $("span#model_" + id + "_status").animate({"opacity": "1"},1000);
        if( status_changed ) {
          $("span#model_" + id + "_status").html(data);        
          loadModel(id);
          id = -1;
        }        
      },
      error: function(data) {
        //alert("status check error");
        id = -1;
      }
    });
    return id;
  };

  loadModel = function(id) {
    if(id == "") return -1; 
    var opts = {method: 'get', action: 'model/' + id };
    var out = id;
    $.ajax({
      type: opts.method,
      url: opts.action,
      dataType: 'html',
      data: {
        '_method': 'get'
      },
      success: function(data) {
        $("div#model_" + id).html(data);
      },
      error: function(data) {
        alert("loadModel error");
      }
    });
    return false;
  };


});

jQuery.fn.deleteModel = function(type, options) {
  var defaults = {
    method: 'post',
    action: this.attr('href'),
    confirm_message: 'Are you sure?',
    trigger_on: 'click'
  };
  var opts = $.extend(defaults, options);
  this.bind(opts.trigger_on, function() {
    if(confirm(opts.confirm_message)) {
      $.ajax({
         type: opts.method,
         url:  opts.action,
         dataType: 'html',
         data: {
           '_method': 'delete'
         },
         success: function(data) {         
           $(opts.elem).fadeTo("slow",0).slideUp("slow");
         },
         error: function(data) {
           alert("model delete error!");
         }
       });
     }
     return false;
   });
};
