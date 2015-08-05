-- Generated from template

if CLet4Def == nil then
	CLet4Def = class({})
end

function Precache( context )
	--[[
		Precache things we know we'll use.  Possible file types include (but not limited to):
			PrecacheResource( "model", "*.vmdl", context )
			PrecacheResource( "soundfile", "*.vsndevts", context )
			PrecacheResource( "particle", "*.vpcf", context )
			PrecacheResource( "particle_folder", "particles/folder", context )
	]]
end

-- Create the game mode when we activate
function Activate()
	GameRules.AddonTemplate = CLet4Def()
	GameRules.AddonTemplate:InitGameMode()
end

function CLet4Def:InitGameMode()
	print( "Template addon is loaded." )
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, 4 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, 1 )
	GameRules:SetHeroSelectionTime(20)
	GameRules:SetPreGameTime(10)
	GameRules:SetPostGameTime(30)
	GameRules:SetGoldPerTick (0)
	self.secondsPassed = 0
	self.spawnedList = {}
	self.king = nil
	self.towerExtraBounty = 3000
	self.xpPerSecond = 12	-- level 16 in 20 minutes
	self.timeLimit = 20*60 -- 20 minutes game length
	self.weaknessDistance = 3000 -- how close to the king a unit must be to not suffer from weakness
	self.weaknessMultiplier = 0.2 -- how much dire unit life should be reduced
	self.creepBountyMultiplier = 1.5 -- how much extra gold should dire creeps give
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CLet4Def, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CLet4Def, 'OnEntityKilled' ), self )
	self.radiantTips = {"radiant_tip_1", "radiant_tip_2", "radiant_tip_3", "radiant_tip_4", "radiant_tip_5", "radiant_tip_6", "radiant_tip_7", "radiant_tip_8", "radiant_tip_9"}
	self.sizeTipsRadiant = 9
	self.direTips = {"dire_tip_1", "dire_tip_2", "dire_tip_3", "dire_tip_4", "dire_tip_5", "dire_tip_6", "dire_tip_7", "dire_tip_8"}
	self.sizeTipsDire = 8
end

-- Evaluate the state of the game
function CLet4Def:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		if GameRules:GetDOTATime(false, false) > self.secondsPassed then
			self.secondsPassed = math.floor(GameRules:GetDOTATime(false, false))
			self:DoOncePerSecond()			
		end
	elseif GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
		return nil
	end
	return 1
end

-- Execute this once per second
function CLet4Def:DoOncePerSecond()
	-- If time is up, game over for dire
	if self.secondsPassed >= self.timeLimit then
		GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
	end
	-- give everyone some xp, enough to reach a high level by 20 minutes
	local allHeroes = HeroList:GetAllHeroes()
	heroCount = 0
	for _, hero in pairs( allHeroes ) do
		hero:AddExperience(self.xpPerSecond, false, true)
		heroCount = heroCount + 1
	end
	-- re-apply weakness on dire units if needed
	for unit, i in pairs(self.spawnedList) do
		self.spawnedList[unit] = self.spawnedList[unit] + 1
		if unit:IsNull() then
			self.spawnedList[unit] = nil
		elseif unit:GetHealth() > self.weaknessMultiplier*unit:GetMaxHealth() and self.king ~= nil and CalcDistanceBetweenEntityOBB(self.king, unit) > self.weaknessDistance then
			unit:SetHealth(self.weaknessMultiplier*unit:GetMaxHealth())
		end
	end
	--spawn controllable bots if there are not enough people
	if (self.secondsPassed == 30 and heroCount < 5) then
		if self.king == nil then
			ShowGenericPopup("warning",  "no_dire_player", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
		else
			ShowGenericPopup("warning",  "not_enough_players", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
			-- increase radiant xp gain to compensate for fewer players
			self.xpPerSecond = self.xpPerSecond+(5-heroCount)*(5-heroCount)
		end
		SendToServerConsole("dota_bot_populate")
		self.spawnedBots = true
	end
end

-- Every time an npc is spawned do this:
function CLet4Def:OnNPCSpawned( event )
	local spawnedUnit = EntIndexToHScript( event.entindex )
	if spawnedUnit:IsRealHero() then
		-- Get dire hero to level 25
		if spawnedUnit:GetTeamNumber() == DOTA_TEAM_BADGUYS then
			for _ = 1, 24 do
				spawnedUnit:HeroLevelUp(false)
			end
			-- remember dire hero since we need this information elsewhere
			self.king = spawnedUnit
			-- tip for dire
			if self.secondsPassed <= 30 then
				ShowGenericPopupToPlayer(spawnedUnit:GetOwner(),  "tip_title",  self.direTips[RandomInt(1, self.sizeTipsDire)], "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
			end
		elseif self.secondsPassed <= 30 then -- tip for radiant
			ShowGenericPopupToPlayer(spawnedUnit:GetOwner(),  "tip_title",  self.radiantTips[RandomInt(1, self.sizeTipsRadiant)], "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
		end
	end
	-- Remove radiant creeps from the game
	if (spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_melee" or spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_ranged" or spawnedUnit:GetUnitName() == "npc_dota_goodguys_siege") then
		spawnedUnit:RemoveSelf()
	end	
	-- Remove XP bounties from the game
	spawnedUnit:SetDeathXP(0)
	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and spawnedUnit ~= self.king then
		-- Make dire units weaker than normal (put them on a list and use timer to re-apply weakness)
		self.spawnedList[spawnedUnit] = 0
		-- Increase gold bounty of dire units
		spawnedUnit:SetMinimumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.creepBountyMultiplier)
		spawnedUnit:SetMaximumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.creepBountyMultiplier)		
		-- Give full control of neutral units to dire
		if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS and self.king ~= nil then
			spawnedUnit:SetTeam(DOTA_TEAM_BADGUYS)
			spawnedUnit:SetOwner(self.king)
			spawnedUnit:SetControllableByPlayer(self.king:GetOwner():GetPlayerID(), true)		
		end		
	end
end

-- Every time an NPC is killed do this:
function CLet4Def:OnEntityKilled( event )
	local killedUnit = EntIndexToHScript( event.entindex_killed )
	local killedTeam = killedUnit:GetTeam()
	-- if king is killed, game over for dire
	if (killedUnit:IsRealHero() and killedTeam == DOTA_TEAM_BADGUYS and not killedUnit:IsReincarnating()) then
		GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
	end 
	-- if radiant tower is killed, give extra gold to dire
	if (killedUnit:IsTower() and killedTeam == DOTA_TEAM_GOODGUYS and self.king ~= nil) then
		self.king:ModifyGold(self.towerExtraBounty, true,  DOTA_ModifyGold_Building)
		GameRules:SendCustomMessage("Dire received <font color='#CCCC00'>"..self.towerExtraBounty.."</font> gold for destroying a tower!", DOTA_TEAM_BADGUYS, 1)
	end

end