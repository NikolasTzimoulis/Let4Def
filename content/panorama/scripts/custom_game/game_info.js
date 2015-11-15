"use strict";

function UpdateInfo() {


	if (Game.GetState() !=  DOTA_GameState.DOTA_GAMERULES_STATE_HERO_SELECTION)
	{
		$.Schedule(1.0, UpdateInfo);
	}	
	else
	{
		var localTeam = Game.GetLocalPlayerInfo().player_team_id;
		$('#notyethints').style.visibility = 'collapse';
		if (localTeam == DOTATeam_t.DOTA_TEAM_GOODGUYS)
		{
			$('#RadiantTips').style.visibility = 'visible';
		}
		else if (localTeam == DOTATeam_t.DOTA_TEAM_BADGUYS)
		{
			$('#DireTips').style.visibility = 'visible';
		}		
	}

}

/* Initialization */
(function() {
	$('#RadiantTips').style.visibility = 'collapse';
	$('#DireTips').style.visibility = 'collapse';
    UpdateInfo();
})();