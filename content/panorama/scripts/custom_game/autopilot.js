"use strict";

var isDire = Game.GetLocalPlayerInfo().player_team_id == DOTATeam_t.DOTA_TEAM_BADGUYS;

function OnAutopilotSwitched()
{
	$("#AutopilotContainer").style.visibility = 'collapse';
	if (isDire)
	{
		GameEvents.SendCustomGameEventToServer("autopilot_off", null)
	}
}

(function() {
	if (isDire)
	{
		$("#AutopilotContainer").style.visibility = 'visible';
		$("#autopilot_switch").checked = true;
	}	
})();