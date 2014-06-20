var turn = "X";
var win = false;
var change;
var counter = 0;
var cpuTurn = false;

function getSquare(sq) {
    return $('#sq' + sq).html();
}

function getRow(sq1, sq2, sq3) {
    var s1, s2, s3;

    if ($('#sq' + sq1).html() === '') {
        s1 = ' ';
    } else {
        s1 = $('#sq' + sq1).html();
    }

    if ($('#sq' + sq2).html() === '') {
        s2 = ' ';
    } else {
        s2 = $('#sq' + sq2).html();
    }

    if ($('#sq' + sq3).html() === '') {
        s3 = ' ';
    } else {
        s3 = $('#sq' + sq3).html();
    }

    return s1 + s2 + s3;
}

function check(str) {
    if (str === 'XXX' || str === 'OOO') {
        return true;
    } else return false;
}

function winLogic() {

    if (check(getRow(1, 2, 3)) || check(getRow(1, 5, 9)) || check(getRow(1, 4, 7)) || check(getRow(2, 5, 8)) || check(getRow(3, 6, 9)) || check(getRow(3, 5, 7)) || check(getRow(4, 5, 6)) || check(getRow(7, 8, 9))) {
        $('#header').html(turn + " WINS!!!");
        win = true;
    } else if (counter > 8) {
        $('#header').html("DRAW!!!");
        win = true;
    } else if (change === true) {
        if (win === false) {
            if (turn === "X") turn = "O";
            else turn = "X";
            $('#header').html(turn + "'s turn");
        }
    }

}

function xo(str) {
    var count = 0;
    var arr = [];

    arr = str.split('');
    for (i = 0; i < 3; i++) {
        if (arr[i] === 'X') count += 1;
        else if (arr[i] === 'O') count -= 1;
    }

    return count;
}

function cpuCheck(s1, s2, s3) {
    if (xo(getRow(s1, s2, s3)) === 2) {
        if (getSquare(s1) === '') {
            $('#sq' + s1).html('O');
            return true;
        } else if (getSquare(s2) === '') {
            $('#sq' + s2).html('O');
            return true;
        } else if (getSquare(s3) === '') {
            $('#sq' + s3).html('O');
            return true;
        } else {
            return false;
        }
    }
}

function cpuLogic() {

    if (cpuCheck(1, 2, 3)) {
        return;
    } else if (cpuCheck(1, 4, 7)) {
        return;
    } else if (cpuCheck(1, 5, 9)) {
        return;
    } else if (cpuCheck(2, 5, 8)) {
        return;
    } else if (cpuCheck(3, 6, 9)) {
        return;
    } else if (cpuCheck(3, 5, 7)) {
        return;
    } else if (cpuCheck(4, 5, 6)) {
        return;
    } else if (cpuCheck(7, 8, 9)) {
        return;
    } else {
        if (getSquare(5) === '') {
            $('#sq5').html('O');
        } else {
            if (getSquare(1) === 'X' && getSquare(7) === 'X') {
                $('#sq4').html('O');
            } else if (getSquare(3) === 'X' && getSquare(9) === 'X') {
                $('#sq6').html('O');
            } else {
                for (i = 1; i < 10; i += 2) {
                    if (getSquare(i) === '') {
                        $('#sq' + i).html('O');
                        return;
                    }
                }
                for (i = 2; i < 9; i += 2) {
                    if (getSquare(i) === '') {
                        $('#sq' + i).html('O');
                        return;
                    }
                }
            }
        }


    }
}

$(document).ready(function() {


    $('.square').click(function() {

        if (win === true) {
            turn = "";
        } else {



            if ($(this).html() === "") {
                $(this).html(turn);
                change = true;
                counter++;
                winLogic();
                cpuLogic();
                counter++;
                change = true;
            } else change = false;

        }

        if (win === false) {
            winLogic();
        }

        //cpuMove();

        if (win === true) {
            $('button').css('opacity', '1');
        }

    });

    $('button').click(function() {
        $('#sq1').html('');
        $('#sq2').html('');
        $('#sq3').html('');
        $('#sq4').html('');
        $('#sq5').html('');
        $('#sq6').html('');
        $('#sq7').html('');
        $('#sq8').html('');
        $('#sq9').html('');
        win = false;
        cpuTurn = false;
        counter = 0;
        turn = 'X';
        $('button').css('opacity', '0');
        $('#header').html(turn + "'s turn");
    });

});