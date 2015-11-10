"use strict";
var TimeLimit     = 20*60;

var humanTime = function(time) {
    time = Math.floor(time);
    var minutes = Math.floor(time / 60);
    var seconds = time - (minutes * 60);

    if (seconds < 10)
        seconds = '0' + seconds;

    return minutes + ':' + seconds;
};

function UpdateRoundTimer() {
    var secondsPassed = Game.GetDOTATime(false,false);
    var TimeLeft = Math.min(TimeLimit, Math.max(TimeLimit - secondsPassed+1, 0) );
    var NextRoundPercent = TimeLeft > 0 ? Math.floor((TimeLeft / TimeLimit) * 10000) / 100 : 0;

    $('#RoundTimerCountDownText').text = humanTime(TimeLeft);
    $('#RoundTimerBarPercentage').style.width = NextRoundPercent + '%';

    $('#RoundTimerRoundText').text = $.Localize('timer');

    $.Schedule(1.0, UpdateRoundTimer);
}

function ChangeTimeLimit(event) {
    TimeLimit = event.timelimit;
}

/* Initialization */
(function() {
    GameEvents.Subscribe( "time_limit_change", ChangeTimeLimit);
    UpdateRoundTimer();
})();