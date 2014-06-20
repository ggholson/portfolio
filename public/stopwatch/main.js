function documentClicked() {

    var start = new Date();

    function FormatNumberLength(num, length) {
        var r = "" + num;
        while (r.length < length) {
            r = "0" + r;
        }
        return r;
    }

    setInterval(function() {
        var now = new Date();
        var msElapsed = now.getTime() - start.getTime();

        var timeDiv = document.querySelector(".time");
        minutes = parseInt(msElapsed / 60000);
        msElapsed -= minutes * 60000;
        seconds = parseInt(msElapsed / 1000);
        msElapsed -= seconds * 1000;
        ms = parseInt(msElapsed / 10);


        timeDiv.innerHTML = FormatNumberLength(minutes, 2) + ":" + FormatNumberLength(seconds, 2) + ":" + FormatNumberLength(ms, 2);
    }, 10);
}

document.addEventListener('click', documentClicked);