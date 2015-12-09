require("statcollection/init")
require("libraries/timers")

if CLet4Def == nil then
	CLet4Def = class({})
end

function Precache( context )
	PrecacheResource("soundfile", "soundevents/game_sounds_roshan_halloween.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds_creeps.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds_ui.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/voscripts/game_sounds_vo_announcer.vsndevts", context)
	PrecacheResource("particle", "particles/items_fx/aura_hp_cap_ring.vpcf", context)
	PrecacheResource("particle", "particles/units/heroes/hero_oracle/oracle_purifyingflames_lines.vpcf", context)
	PrecacheResource("particle", "particles/units/heroes/hero_oracle/oracle_purifyingflames_head.vpcf", context)
	PrecacheResource("particle", "particles/neutral_fx/roshan_spawn.vpcf", context)
	PrecacheResource("particle", "particles/econ/courier/courier_roshan_lava/courier_roshan_lava.vpcf", context)
	PrecacheResource("particle", "particles/hw_fx/hw_roshan_death.vpcf", context)
end

-- Create the game mode when we activate
function Activate()
	GameRules.AddonTemplate = CLet4Def()
	GameRules.AddonTemplate:InitGameMode()
end

function CLet4Def:InitGameMode()
	print("Starting Let 4 Def...")
	-- game balance parameters
	self.towerExtraBounty = 2000
	self.towerExtraBountyIncrease = 200
	self.endgameXPTarget = 14400 -- how much XP each radiant hero must have by the end of the game
	self.timeLimitBase = 20*60 -- 20 minutes game length
	self.weaknessDistance = 1000 -- how close to the king a unit must be to not suffer from weakness
	self.hPCapIncreaseRate = 1.0/(self.timeLimitBase) -- how much the dire unit hp cap should be increased in proportion to their max hp per second
	self.radiantRespawnMultiplier = 2 -- multiplied with the hero's level to get the respawn timer for radiant
	self.announcementFrequency = 5 --announcements cannot be made more frequently than this
	self.autoGatherInterval = 30
	-- initialise stuff
	GameRules:GetGameModeEntity():SetAnnouncerDisabled(true)
	self.timeLimit = self.timeLimitBase
	self.secondsPassed = nil
	self.xpSoFar = 0
	self.maxRadiantLevel = 1
	self.spawnedList = {}
	self.king = nil
	self.checkHeroesPicked = false	
	self.radiantPlayerCount = 4
	self.direPlayerCount = 1
	self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	self.lastHurtAnnouncement = -math.huge
	local dummy = CreateUnitByName("dummy_unit", Vector(0,0,0), false, nil, nil, DOTA_TEAM_NEUTRALS)
	dummy:FindAbilityByName("dummy_passive"):SetLevel(1)
	self.modifiers = dummy:FindAbilityByName("modifier_collection")
	self.winners = nil
	self.autopilot = true
	self.autoRosh = 0
	self.aegisCarrier = nil
	self.aegisPickupTime = GameRules:GetGameTime()
	self.aegisExpirationDelay = 5*60+0.1
	self:DispatchChangeTimeLimitEvent()
	-- base rules
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, self.radiantPlayerCount )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, self.direPlayerCount )
	GameRules:SetHeroSelectionTime(30)
	GameRules:SetPreGameTime(30)
	GameRules:SetPostGameTime(30)
	GameRules:SetGoldPerTick (0)
	-- listen to some game events
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CLet4Def, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CLet4Def, 'OnEntityKilled' ), self )
	ListenToGameEvent( "entity_hurt", Dynamic_Wrap( CLet4Def, 'OnEntityHurt' ), self )
	ListenToGameEvent( "player_chat", Dynamic_Wrap( CLet4Def, 'OnChat' ), self )
	ListenToGameEvent( "dota_player_gained_level", Dynamic_Wrap( CLet4Def, 'OnLevelUp' ), self )
	ListenToGameEvent( "player_reconnected", Dynamic_Wrap( CLet4Def, 'OnReconnect' ), self )
	ListenToGameEvent( "dota_item_picked_up", Dynamic_Wrap( CLet4Def, 'OnItemPickedUp' ), self )
	--ListenToGameEvent( "dota_item_picked_up", PrintEventData, nil)
	CustomGameEventManager:RegisterListener("autopilot_off", function(id, ...) Dynamic_Wrap(self, "DisableAutopilot")(self, ...) end)
end

-- Evaluate the state of the game
function CLet4Def:OnThink()
	-- check if game is over
	if self.winners ~= nil and GameRules:State_Get() ~= DOTA_GAMERULES_STATE_POST_GAME then
		GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
		ancient = Entities:FindByName( nil, "dota_badguys_fort" )
		ancient:ForceKill(false)
		GameRules:SetGameWinner(self.winners)
		if self.winners == DOTA_TEAM_GOODGUYS then
			GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
		end
	end
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_PRE_GAME then
		-- punish late pickers
		self:MonitorHeroPicks()
		-- engage autopilot
		if self.autoRosh == 0 and self.autopilot then
			Timers:CreateTimer(function()
				if self.autopilot then
					self:AutopilotGather()
					return self.autoGatherInterval
				end
			end)
		end
	end
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS and self.secondsPassed == nil then
		Timers:CreateTimer(function()			
			self:DoOncePerSecond()			
			return 1
		end)
		if self.autopilot then
			Timers:CreateTimer(AutoPilotAttackWait(), function()			
				if self.autopilot then
					self:AutoPilotAttack()	
					return AutoPilotAttackWait()
				end
			end)
		end
	elseif GameRules:State_Get() >= DOTA_GAMERULES_STATE_POST_GAME then
		return nil
	end
	return 1
end

-- Execute this once per second
function CLet4Def:DoOncePerSecond()
	self.secondsPassed = math.floor(GameRules:GetDOTATime(false, false))
	-- announce start of game
	if (self.secondsPassed == 1) then
		GameRules:GetGameModeEntity():SetAnnouncerDisabled(false)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_21", DOTA_TEAM_GOODGUYS)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_22", DOTA_TEAM_BADGUYS)
	end
	-- Display messages about how much time remains
	local timeRemaining = (math.ceil(self.timeLimit) - self.secondsPassed)
	if timeRemaining == 0 then
		GameRules:SendCustomMessage("time_up", 0, 0)
	elseif timeRemaining >= 1 and timeRemaining <= 9 then
		EmitAnnouncerSound("announcer_ann_custom_countdown_0"..tostring(timeRemaining))
	elseif timeRemaining == 10 then
		EmitAnnouncerSound("announcer_ann_custom_countdown_10")
	elseif timeRemaining == 30 then
		EmitAnnouncerSound("announcer_ann_custom_timer_sec_30")
	elseif timeRemaining == 60 then
		GameRules:SendCustomMessage("1_minute", 0, 0)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_33", DOTA_TEAM_BADGUYS)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_29", DOTA_TEAM_GOODGUYS)
	elseif (math.round(self.timeLimit) - self.secondsPassed) % 60 == 0 then
		local minutesRemaining = math.round((self.timeLimit - self.secondsPassed)/60)
		GameRules:SendCustomMessage("x_minutes",0,  minutesRemaining)
		if minutesRemaining == 15 then
			EmitAnnouncerSound("announcer_ann_custom_timer_15")
		elseif minutesRemaining == 10 then
			EmitAnnouncerSound("announcer_ann_custom_timer_10")
		elseif minutesRemaining == 5 then
			EmitAnnouncerSound("announcer_ann_custom_timer_05")
		elseif minutesRemaining == 2 then
			EmitAnnouncerSound("announcer_ann_custom_timer_02")
		end
	end
	-- If time is up, game over for dire
	if self.secondsPassed >= self.timeLimit then
		self.winners = DOTA_TEAM_GOODGUYS
	end
	-- give radiant some xp, enough to reach a high level by 20 minutes
	local allHeroes = HeroList:GetAllHeroes()
	local xpPerSecond = (self.endgameXPTarget - self.xpSoFar) / (self.timeLimit - self.secondsPassed)
	for _, hero in pairs( allHeroes ) do
		if hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS and hero:IsAlive() then
			self.modifiers:ApplyDataDrivenModifier( hero, hero, "xp_aura_modifier", {duration=-1} )
			hero:AddExperience(xpPerSecond, false, true)
		end
	end
	self.xpSoFar = self.xpSoFar + xpPerSecond
	-- re-apply weakness on dire units if needed
	for unit, i in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			local hpCap = self:CalculateHPCap(unit)
			unit:SetMaximumGoldBounty(self:CalculateMaxBounty(unit))	
			if not self.spawnedList[unit] or not IsValidEntity(self.king) or CalcDistanceBetweenEntityOBB(self.king, unit) > self.weaknessDistance then
				if unit:GetHealth() > hpCap then
					unit:SetHealth(hpCap)
				end
				if not unit:HasModifier("dire_weakness_modifier") and unit:GetHealth() > 0 then
					ParticleManager:CreateParticle("particles/units/heroes/hero_oracle/oracle_purifyingflames_head.vpcf", PATTACH_ABSORIGIN_FOLLOW, unit)
				end
				self.modifiers:ApplyDataDrivenModifier( unit, unit, "dire_weakness_modifier", {duration=-1} )
				self.spawnedList[unit] = true
			elseif IsValidEntity(self.king) and CalcDistanceBetweenEntityOBB(self.king, unit) <= self.weaknessDistance and unit:HasModifier("dire_weakness_modifier") then
				unit:RemoveModifierByName("dire_weakness_modifier")
				ParticleManager:CreateParticle("particles/units/heroes/hero_oracle/oracle_purifyingflames_lines.vpcf", PATTACH_ABSORIGIN_FOLLOW, unit)
			elseif hpCap > 0.99*unit:GetMaxHealth() then
				unit:RemoveModifierByName("dire_weakness_modifier")
			end
		else
			self.spawnedList[unit] = nil
		end
	end
	--every minute
	if (self.secondsPassed % 60 == 1) then
		-- re-check number of players 
		local newRadiantPlayerCount = 0
		local newDirePlayerCount = 0
		for playerid = 0, DOTA_MAX_PLAYERS do
			if PlayerResource:IsValidPlayer(playerid) then
				player = PlayerResource:GetPlayer(playerid)
				if player ~= nil then
					if PlayerResource:GetTeam(playerid) == DOTA_TEAM_GOODGUYS then
						newRadiantPlayerCount = newRadiantPlayerCount + 1
					elseif PlayerResource:GetTeam(playerid) == DOTA_TEAM_BADGUYS then
						newDirePlayerCount = newDirePlayerCount + 1
					end
				end
			end
		end
		local newTotalPlayerCount = newRadiantPlayerCount + newDirePlayerCount
		if newTotalPlayerCount ~= self.totalPlayerCount then
			if newTotalPlayerCount == 1 then
				ShowGenericPopup("warning",  "1_player", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
			elseif newDirePlayerCount < 1 and self.secondsPassed == nil then
				ShowGenericPopup("warning",  "no_dire_player", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
				self:ForceOnePlayerToDire()
			elseif newRadiantPlayerCount ~= self.radiantPlayerCount and newRadiantPlayerCount > 0 and self.totalPlayerCount > 1 then
				-- change difficulty
				--ShowGenericPopup("warning",  "difficulty_changed", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 	
				self.timeLimit = self.timeLimit + math.sign(newRadiantPlayerCount-self.radiantPlayerCount) * math.abs(newRadiantPlayerCount-self.radiantPlayerCount)/5 * (self.timeLimitBase  - self.secondsPassed)
				self:DispatchChangeTimeLimitEvent()
				GameRules:SendCustomMessage("difficulty_changed", 0, 0)
				GameRules:SendCustomMessage("new_time", 0, math.round(self.timeLimit/60))
				EmitGlobalSound("ui.npe_objective_given")
			end
		end
		self.radiantPlayerCount = newRadiantPlayerCount
		self.direPlayerCount = newDirePlayerCount
		self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	end
end

-- Every time an npc is spawned do this:
function CLet4Def:OnNPCSpawned( event )
	local spawnedUnit = EntIndexToHScript( event.entindex )
	if spawnedUnit:IsRealHero() then		
		if spawnedUnit:GetTeamNumber() == DOTA_TEAM_BADGUYS then
			if not IsValidEntity(self.king) then
				-- remember dire hero since we need this information elsewhere
				self.king = spawnedUnit	
				-- Get dire hero to level 25
				Timers:CreateTimer( 0.1, function()
					MaxAbilities(spawnedUnit)
					return nil
				end)
				-- give him his modifiers
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "dire_strength_modifier", {duration=-1} )
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "yolo_modifier", {duration=-1} )
				-- change his colour to red
				PlayerResource:SetCustomPlayerColor(spawnedUnit:GetPlayerID(), 255, 0, 0)
				-- jungle fix
				if self.secondsPassed ~= nil and self.secondsPassed > 30 then
					SendToServerConsole("sv_cheats_1;dota_spawn_neutrals;sv_cheats 0")					
				end
			end
			-- make dire hero model bigger
			IncrementalModelScale(spawnedUnit, 0.2, 1)
		end
	end
	-- Remove radiant creeps from the game
	if (spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_melee" or spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_ranged" or spawnedUnit:GetUnitName() == "npc_dota_goodguys_siege") then
		spawnedUnit:RemoveSelf()
	end	
	-- Remake dire lane creeps	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_NEUTRALS and string.find(spawnedUnit:GetUnitName(), "badguys") and (string.find(spawnedUnit:GetUnitName(), "creep") or string.find(spawnedUnit:GetUnitName(), "siege")) then
		local creep = CreateUnitByName(spawnedUnit:GetUnitName(), spawnedUnit:GetAbsOrigin(), false, nil, nil, DOTA_TEAM_NEUTRALS)
		FindClearSpaceForUnit(creep, spawnedUnit:GetAbsOrigin(), true)
		spawnedUnit:RemoveSelf()
	end	
	-- Remove XP bounties from the game
	spawnedUnit:SetDeathXP(0)	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and not spawnedUnit:IsHero() and not spawnedUnit:IsConsideredHero() then
		-- Make most dire units weaker than normal (put them on a list and use timer to re-apply weakness)
		if string.find(spawnedUnit:GetUnitName(), "upgraded") == nil then
			self.spawnedList[spawnedUnit] = false	
		end
		-- Give full control of neutral units to dire
		if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS then
			self:giveDireControl(spawnedUnit)	
		end		
	end
	-- remake roshan
	if spawnedUnit:GetUnitName() == "npc_dota_roshan"  then
		CreateUnitByName("custom_npc_dota_roshan", spawnedUnit:GetAbsOrigin(), false, nil, nil, DOTA_TEAM_NEUTRALS)
		spawnedUnit:RemoveSelf()
	end
	-- give roshan aegis and cheese
	if spawnedUnit:GetUnitName() == "custom_npc_dota_roshan" then
		spawnedUnit:AddItem(CreateItem("item_aegis", nil, nil))
		spawnedUnit:AddItem(CreateItem("item_cheese", nil, nil))
	end
end

-- Every time an NPC is killed do this:
function CLet4Def:OnEntityKilled( event )
	local killedUnit = EntIndexToHScript( event.entindex_killed )
	local killedTeam = killedUnit:GetTeam()
	local attackerTeam = EntIndexToHScript( event.entindex_attacker ):GetTeam()
	-- if a hero is killed...
	if (killedUnit:IsRealHero()) then	
		if killedUnit:IsClone() then
			killedUnit = killedUnit:GetCloneSource()
		end
		if not killedUnit:IsReincarnating() then
			-- if their hero is killed, game over for dire
			if killedTeam == DOTA_TEAM_BADGUYS then
				self.winners = DOTA_TEAM_GOODGUYS
			-- if radiant hero is killed, give them a short respawn time and no buyback cooldown
			elseif killedTeam == DOTA_TEAM_GOODGUYS then 
				killedUnit:SetTimeUntilRespawn(self.radiantRespawnMultiplier*killedUnit:GetLevel())
				killedUnit:SetBuybackCooldownTime(0)
			end
			-- remove aegis buffs after hero death
			if killedUnit:HasAbility("roshan_spell_block") then
				self:RemoveAegisExtraBuffs(killedUnit)
			end
		else
			-- give dire hero his modifiers back
			if killedTeam == DOTA_TEAM_BADGUYS then
				Timers:CreateTimer(5.1, function()
					self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "dire_strength_modifier", {duration=-1} )
					self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "yolo_modifier", {duration=-1} )
				end)
			end
			-- apply special buffs if this is an aegis reincarnation
			if self.aegisCarrier == killedUnit and GameRules:GetGameTime() <= self.aegisPickupTime + self.aegisExpirationDelay and not killedUnit:HasItemInInventory("item_aegis") then
				self:ApplyAegisExtraBuffs(killedUnit, 5.1)
			end
		end
	end 
	-- if radiant tower is killed, give extra gold to dire
	if (killedUnit:IsTower() and killedTeam == DOTA_TEAM_GOODGUYS and IsValidEntity(self.king)) then
		self.king:ModifyGold(self.towerExtraBounty, true,  DOTA_ModifyGold_Building)
		GameRules:SendCustomMessage("tower_gold", 0, self.towerExtraBounty)
		self.towerExtraBounty = self.towerExtraBounty + self.towerExtraBountyIncrease
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_20", DOTA_TEAM_BADGUYS)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_26", DOTA_TEAM_GOODGUYS)
		EmitSoundOnLocationForAllies(killedUnit:GetOrigin(), "General.CoinsBig", self.king )
	end
	-- if rosh is killed, make him drop his items
	if killedUnit:GetUnitName() == "custom_npc_dota_roshan" then
		GameRules:SendCustomMessage("roshan_killed", 0, 0)
		if (attackerTeam == DOTA_TEAM_GOODGUYS) then
			EmitAnnouncerSound("announcer_announcer_roshan_fallen_rad")
		elseif (attackerTeam == DOTA_TEAM_BADGUYS) then
			EmitAnnouncerSound("announcer_announcer_roshan_fallen_dire")
		end
		for itemSlot = 0, 5, 1 do 
			local item = killedUnit:GetItemInSlot( itemSlot ) 
			if IsValidEntity(item) then 
				CreateItemOnPositionSync(killedUnit:GetOrigin(), CreateItem(item:GetName() , nil, nil)) 
			end
		end		
	end
end

--- Every time an NPC is dealt damage do this:
function CLet4Def:OnEntityHurt( event )
	local hurtUnit = EntIndexToHScript(event.entindex_killed)
	local attacker = nil 
	if event.entindex_attacker ~= nil then
		attacker = EntIndexToHScript(event.entindex_attacker)
	end
	
	-- rosh changes teams if dire attacks him
	if hurtUnit:GetUnitName() == "custom_npc_dota_roshan" and hurtUnit:GetTeam() == DOTA_TEAM_BADGUYS and attacker~= nil and attacker:GetTeam() == DOTA_TEAM_BADGUYS then
		EmitGlobalSound("RoshanDT.Scream")
		self.spawnedList[hurtUnit] = nil
		hurtUnit:SetTeam(DOTA_TEAM_GOODGUYS)
		ExecuteOrderFromTable( {UnitIndex=hurtUnit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position=self.king:GetAbsOrigin(), Queue = false} )
		for playerid = 0, DOTA_MAX_PLAYERS do
			if PlayerResource:IsValidPlayer(playerid) then
				player = PlayerResource:GetPlayer(playerid)
				if player ~= nil then
					if PlayerResource:GetTeam(playerid) == DOTA_TEAM_GOODGUYS then
						hurtUnit:SetOwner(player)
						hurtUnit:SetControllableByPlayer(playerid, true)	
					end
				end
			end
		end
		EmitAnnouncerSoundForTeam("announcer_ann_custom_adventure_alerts_41", DOTA_TEAM_BADGUYS)
		EmitAnnouncerSoundForTeam("announcer_ann_custom_adventure_alerts_30", DOTA_TEAM_GOODGUYS)
		MinimapEvent(DOTA_TEAM_GOODGUYS, hurtUnit, hurtUnit:GetAbsOrigin().x, hurtUnit:GetAbsOrigin().y,   DOTA_MINIMAP_EVENT_HINT_LOCATION , self.announcementFrequency)
	end
	
	-- hurt announcements for dire hero and rosh
	if self.secondsPassed ~= nil and self.secondsPassed - self.lastHurtAnnouncement > self.announcementFrequency then
		if (hurtUnit:GetTeam() == DOTA_TEAM_BADGUYS and hurtUnit:IsRealHero() and hurtUnit:GetHealth() < hurtUnit:GetMaxHealth()/2 and hurtUnit:GetHealth() > 0) then
			EmitAnnouncerSoundForTeam("announcer_ann_custom_adventure_alerts_34", DOTA_TEAM_BADGUYS)
			MinimapEvent(DOTA_TEAM_BADGUYS, hurtUnit, hurtUnit:GetAbsOrigin().x, hurtUnit:GetAbsOrigin().y,  DOTA_MINIMAP_EVENT_HINT_LOCATION, self.announcementFrequency)
			self.lastHurtAnnouncement = self.secondsPassed
		elseif (hurtUnit:GetUnitName() == "custom_npc_dota_roshan" and hurtUnit:GetTeam() == DOTA_TEAM_BADGUYS and hurtUnit:GetHealth() < hurtUnit:GetMaxHealth()/2) then
			EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_02", DOTA_TEAM_BADGUYS)
			self.lastHurtAnnouncement = self.secondsPassed
			MinimapEvent(DOTA_TEAM_BADGUYS, hurtUnit, hurtUnit:GetAbsOrigin().x, hurtUnit:GetAbsOrigin().y,   DOTA_MINIMAP_EVENT_HINT_LOCATION , self.announcementFrequency)
		end
	end
end

function CLet4Def:CalculateHPCap( unit )
	return math.max(1, 0.01*unit:GetMaxHealth() ,self.hPCapIncreaseRate*self.secondsPassed*unit:GetMaxHealth())
end

function CLet4Def:CalculateMaxBounty( unit )
	local minutes = (GameRules:GetGameTime()-unit:GetCreationTime())/60
	return unit:GetMinimumGoldBounty() * (1 + (math.pow(minutes,3)/100))
end

function CLet4Def:giveDireControl(unit)
	if IsValidEntity(self.king) and IsValidEntity(unit) then
		unit:SetTeam(DOTA_TEAM_BADGUYS)
		unit:SetOwner(self.king)
		unit:SetControllableByPlayer(self.king:GetOwner():GetPlayerID(), true)					
	elseif IsValidEntity(unit) and unit:GetUnitName() == "custom_npc_dota_roshan" then
		Timers:CreateTimer(1, function()
			self:giveDireControl(unit)
			return nil
		end)
	else
		unit:RemoveSelf()
	end
end

function CLet4Def:MonitorHeroPicks()
	-- find radiant players who did not pick their heroes in time
	if not self.checkHeroesPicked then
		self.checkHeroesPicked = true
		for playerid = 0, DOTA_MAX_PLAYERS do
			if PlayerResource:IsValidPlayer(playerid) and not PlayerResource:HasSelectedHero(playerid) and PlayerResource:GetTeam(playerid) == DOTA_TEAM_GOODGUYS then
				-- punish them
				EmitAnnouncerSoundForPlayer("announcer_ann_custom_sports_04", playerid)
				PlayerResource:ModifyGold(playerid, -PlayerResource:GetGold(playerid),  false, DOTA_ModifyGold_SelectionPenalty)
			end
		end
	end
end

function CLet4Def:OnChat(event)
	if event.text == 'bots' then
		self:EnableBots()
	end
end

function CLet4Def:EnableBots()
	SendToServerConsole("dota_bot_populate")
	GameRules:GetGameModeEntity():SetBotThinkingEnabled(true)
	GameRules:GetGameModeEntity():SetBotsInLateGame(true)
	for _, hero in pairs( HeroList:GetAllHeroes() ) do
		if hero:GetTeamNumber() == DOTA_TEAM_GOODGUYS then
			hero:SetBotDifficulty(3)
		elseif hero:GetTeamNumber() == DOTA_TEAM_BADGUYS then
			hero:SetBotDifficulty(4)
		end
	end
end

function CLet4Def:OnLevelUp(event)
	team = EntIndexToHScript(event.player):GetTeamNumber()
	if event.level > self.maxRadiantLevel and team == DOTA_TEAM_GOODGUYS then
		EmitAnnouncerSoundForTeam("announcer_ann_custom_adventure_alerts_02", DOTA_TEAM_BADGUYS)
		self.maxRadiantLevel = event.level
	end
end

function CLet4Def:OnReconnect(event)
	self:DispatchChangeTimeLimitEvent()
end

function CLet4Def:DispatchChangeTimeLimitEvent()
	CustomGameEventManager:Send_ServerToAllClients( "time_limit_change", {timelimit = self.timeLimit})
end

function CLet4Def:ForceOnePlayerToDire()
	for playerid = 0, DOTA_MAX_PLAYERS do
		if PlayerResource:IsValidPlayer(playerid) then
			player = PlayerResource:GetPlayer(playerid)
			if player ~= nil and PlayerResource:GetTeam(playerid) == DOTA_TEAM_GOODGUYS then
				Timers:CreateTimer(function()
					hero = PlayerResource:GetSelectedHeroEntity(playerid)
					if hero == nil then
						return 1
					else
						hero:AddNewModifier(hero, nil, "modifier_invulnerable", {duration = 1}) 
						PlayerResource:SetCustomTeamAssignment(player:GetEntityIndex(), DOTA_TEAM_BADGUYS)
						player:SetTeam(DOTA_TEAM_BADGUYS)
						hero:SetTeam(DOTA_TEAM_BADGUYS)
						FindClearSpaceForUnit(hero, Vector(7000,7000,0), true)
						PlayerResource:ReplaceHeroWith(playerid, hero:GetClassname(), PlayerResource:GetGold(playerid), 0)
						return nil
					end
				end)
			end
		end
	end
end

function CLet4Def:ApplyAegisExtraBuffs( unit, delay )	
	Timers:CreateTimer(delay, function()
		abil = unit:AddAbility("roshan_spell_block")
		abil:SetLevel(abil:GetMaxLevel())
		abil:SetHidden(true)
		abil = unit:AddAbility("roshan_devotion")
		abil:SetLevel(abil:GetMaxLevel())
		abil:SetHidden(true)
		EmitAnnouncerSoundForPlayer("announcer_ann_custom_adventure_alerts_06", unit:GetOwner():GetPlayerID())
		ParticleManager:CreateParticle("particles/neutral_fx/roshan_spawn.vpcf", PATTACH_ABSORIGIN_FOLLOW, unit)
		self.buffEffect = ParticleManager:CreateParticle("particles/econ/courier/courier_roshan_lava/courier_roshan_lava.vpcf", PATTACH_ABSORIGIN_FOLLOW, unit)
		IncrementalModelScale(unit, 0.2, 3)
		--Timers:CreateTimer(self.aegisExtraBuffsDuration, function() ParticleManager:DestroyParticle(buffEffect, true) end)
	end)
	EmitGlobalSound("RoshanDT.Scream")
	ParticleManager:CreateParticle("particles/hw_fx/hw_roshan_death.vpcf", PATTACH_ABSORIGIN_FOLLOW, unit)
end

function CLet4Def:RemoveAegisExtraBuffs( unit )	
	unit:RemoveAbility("roshan_spell_block")
	unit:RemoveAbility("roshan_devotion")
	IncrementalModelScale(unit, -0.2, 1)
	ParticleManager:DestroyParticle(self.buffEffect, true)
end

function CLet4Def:OnItemPickedUp(event)
	if event.itemname == "item_aegis" then
		self.aegisCarrier = EntIndexToHScript(event.HeroEntityIndex)
		self.aegisPickupTime = GameRules:GetGameTime()
		Timers:CreateTimer(self.aegisExpirationDelay, function()
			if self.aegisCarrier:HasModifier("modifier_aegis_regen") then
				self:ApplyAegisExtraBuffs(self.aegisCarrier, 0)
			end
		end)
	end
end

function CLet4Def:DisableAutopilot(event)
	self.autopilot = false
	EmitAnnouncerSoundForTeam("General.Acknowledge", DOTA_TEAM_BADGUYS)	
end

function CLet4Def:AutopilotGather()
	local gatherLocation = Vector(RandomInt(0, 6000),RandomInt(0, 6000),0)
	for unit, i in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			if unit:GetUnitName() ~= "custom_npc_dota_roshan" and GameRules:GetGameTime()-unit:GetCreationTime() <= self.autoGatherInterval then
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION, Position = gatherLocation, Queue = false} )
			elseif unit:GetUnitName() == "custom_npc_dota_roshan" and self.autoRosh == 0 then
				self.autoRosh = 1
				Timers:CreateTimer(function()
					if IsValidEntity(self.king) then
						ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION, Position = Vector(7000,6400,0), Queue = false} )
					else 
						return 1
					end
				end)
			end
		end
	end
end

function CLet4Def:AutoPilotAttack()		
	local  pivotID = RandomInt(1,3)
	local pivotLocation = Vector(0,0,0)
	if pivotID == 2 then
		pivotLocation = Vector(-4500,6000, 0)
	elseif pivotID == 3 then
		pivotLocation = Vector(5800, -5400, 0)
	end
	for unit, i in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			if unit:GetUnitName() ~= "custom_npc_dota_roshan" or self.secondsPassed > 10*60 then
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = pivotLocation, Queue = false} )
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = Vector(-5700,-5200,0), Queue = true} )
			end
		end
	end
end

function AutoPilotAttackWait()
	local wait = RandomInt(90, 180)
	return wait
end

function MaxAbilities( hero )
	for _ = 1, 24 do
		hero:HeroLevelUp(false)
	end
    for i=0, hero:GetAbilityCount()-1 do
        local abil = hero:GetAbilityByIndex(i)
        while abil ~= nil and abil:CanAbilityBeUpgraded() == 0 and abil:GetLevel() < abil:GetMaxLevel() do
			local oldlevel = abil:GetLevel()
			hero:UpgradeAbility(abil)
			if oldlevel == abil:GetLevel() then 
				--fix problematic abilities
				abil:SetLevel(abil:GetMaxLevel())
			end
		end
    end
end

function IncrementalModelScale(unit, scaleDif, duration)
	for i = 1,10*duration do
		Timers:CreateTimer(i/10, function()
			unit:SetModelScale(unit:GetModelScale()+scaleDif/10/duration)			
		end)
	end
end

function math.sign(x)
   if x<0 then
     return -1
   elseif x>0 then
     return 1
   else
     return 0
   end
end

function math.round(num, idp)
  local mult = 10^(idp or 0)
  return math.floor(num * mult + 0.5) / mult
end

function PrintEventData(event)
	for k, v in pairs( event ) do
        print(k .. " " .. tostring(v).." ("..type(v)..")" )
    end
end