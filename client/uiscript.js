var cpanel = 0;
var cur = 1;
var slide = [3, 2, 3];

function setSlide(num, row) {
    slide[row - 1] = num;
}

$(window).on("scroll resize", function() {
    var pos = $('#window').offset();
    $('.opanel').each(function() {
        if (pos.top >= $(this).offset().top && pos.top <= $(this).next().offset().top) {

            cur = parseInt($(this).attr('id').match(/\d+/)[0]);

            if (cpanel != cur) {

                if (cur === 1) {
                    $('#slide1').attr("class", "slide");
                    $('#slide2').attr("class", "slidedown");
                    $('#slide3').attr("class", "slidehideb");
                } else if (cur === 2) {
                    $('#slide1').attr("class", "slideup");
                    $('#slide2').attr("class", "slide");
                    $('#slide3').attr("class", "slidedown");
                } else if (cur === 3) {
                    $('#slide1').attr("class", "slidehidet");
                    $('#slide2').attr("class", "slideup");
                    $('#slide3').attr("class", "slide");

                }

                cpanel = cur;

            }

            return; //break the loop
        }
    });
});

$(document).ready(function() {
    $(window).trigger('scroll'); // init the value

    $.get('/r1', function(data) {
        $('#slide1').html(data);
    });

    $.get('/r2', function(data) {
        $('#slide2').html(data);
    });

    $.get('/r3', function(data) {
        $('#slide3').html(data);
    });

    $("#overlaybutton").click(function() {
        if (cur === 1) {
            if (slide[0] === 1) {
                $("#overlay").addClass("overlayshow");
                $('#overlaywindow').html("<iframe src=\"/stopwatch/index.html\" width=\"100%\" height=\"100%\" frameborder=\"0\" scrolling=\"auto\" marginwidth=\"0\" marginheight=\"0\"></iframe>")
            }
            if (slide[0] === 2) {
                $("#overlay").addClass("overlayshow");
                $('#overlaywindow').html("<iframe src=\"/ttt/index.html\" width=\"100%\" height=\"100%\" frameborder=\"0\" scrolling=\"auto\" marginwidth=\"0\" marginheight=\"0\"></iframe>")
            }
        } else if (cur === 2) {
            if (slide[1] === 1) {
                $("#overlay").addClass("overlayshow");
                $('#overlaywindow').html("<iframe src=\"http://localhost:3001\" width=\"100%\" height=\"100%\" frameborder=\"0\" scrolling=\"auto\" marginwidth=\"0\" marginheight=\"0\"></iframe>")
            }
        } else {
            if (slide[2] === 1) {
                $("#overlay").addClass("overlayshow");
                $.get('/shell', function(data) {
                    $("#overlaywindow").html("<pre style=\"background-color:black;overflow-y:scroll\"><span style=\"color:white;overflow-y:scroll\">" + data + "</span></pre>")
                });
                $("#overlaywindow").html("<pre style=\"background-color:black;overflow-y:scroll\"><span style=\"color:white;overflow-y:scroll\">" + data + "</span></pre>")
            } else if (slide[2] === 2) {
                $("#overlay").addClass("overlayshow");
                $.get('/robot', function(data) {
                    $("#overlaywindow").html("<pre style=\"background-color:black;overflow-y:scroll\"><span style=\"color:white;overflow-y:scroll\">" + data + "</span></pre>")
                });
            } else {
                $("#overlay").addClass("overlayshow");
                $.get('/sgp', function(data) {
                    $("#overlaywindow").html("<pre style=\"background-color:black;overflow-y:scroll\"><span style=\"color:white;overflow-y:scroll\">" + data + "</span></pre>")
                });
            }
        }

    });

    $(".btnclose").click(function() {
        $("#overlay").removeClass("overlayshow");
    })
});