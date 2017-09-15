require("statcollection/init")
require("libraries/timers")

if CLet4Def == nil then
	CLet4Def = class({})
end

function Precache( context )
	PrecacheResource("soundfile", "soundevents/game_sounds_ui_imported.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds_roshan_halloween.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds_creeps.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/game_sounds_ui.vsndevts", context)
	PrecacheResource("soundfile", "soundevents/voscripts/game_sounds_vo_announcer.vsndevts", context)
	PrecacheResource("particle", "particles/neutral_fx/roshan_spawn.vpcf", context)
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
	self.timeLimitBase = 20*60 -- 20 minutes game length
	self.radiantRespawnMultiplier = 2 -- multiplied with the hero's level to get the respawn timer for radiant
	self.announcementFrequency = 5 --announcements cannot be made more frequently than this
	self.autoGatherInterval = 30
	self.autoDefendDistance = 1500
	self.maxCreepsAddInterval = 15
	self.addedIntervalPerMissingPlayer = 10
	self.xpMultiplier = 2
	self.goldMultiplier = 2
	-- initialise stuff
	GameRules:GetGameModeEntity():SetAnnouncerDisabled(true)
	self.timeLimit = self.timeLimitBase
	self.secondsPassed = nil
	self.spawnedList = {}
	self.stonedList = {}
	self.king = nil
	self.roshan = nil
	self.lastAttacker = nil
	self.maxCreeps = 0
	self.radiantPlayerCount = 4
	self.direPlayerCount = 1
	self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	self.missingPlayers = 0
	self.lastHurtAnnouncement = -math.huge
	local dummy = CreateUnitByName("dummy_unit", Vector(0,0,0), false, nil, nil, DOTA_TEAM_NEUTRALS)
	dummy:FindAbilityByName("dummy_passive"):SetLevel(1)
	self.modifiers = dummy:FindAbilityByName("modifier_collection")
	self.winners = nil
	self.autopilot = true
	self.autopilotList = {}
	-- base rules	
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, self.radiantPlayerCount )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, self.direPlayerCount )
	GameRules:SetHeroSelectionTime(30)
	GameRules:SetPreGameTime(30)
	GameRules:SetPostGameTime(30)
	GameRules:SetGoldPerTick (0)
	GameRules:GetGameModeEntity():SetCustomBuybackCooldownEnabled(true)
	GameRules:GetGameModeEntity():SetCustomBuybackCostEnabled(true)
	-- listen to some game events
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CLet4Def, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CLet4Def, 'OnEntityKilled' ), self )
	ListenToGameEvent( "entity_hurt", Dynamic_Wrap( CLet4Def, 'OnEntityHurt' ), self )
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

	end
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS and self.secondsPassed == nil then
		-- activate once per second think function
		Timers:CreateTimer(function()			
			self:DoOncePerSecond()			
			return 1
		end)
		-- engage autopilot gather timer
		if self.autopilot then
			Timers:CreateTimer(function()
				if self.autopilot then
					self:AutopilotGather()
					return self.autoGatherInterval
				end
			end)
		end
		-- activate autopilot timer
		if self.autopilot then
			Timers:CreateTimer(AutoPilotAttackWait(), function()			
				if self.autopilot then
					self:AutoPilotAttack()	
					return AutoPilotAttackWait()
				end
			end)
		end
		-- activate max creep incrementing
		Timers:CreateTimer(self.maxCreepsAddInterval, function()			
				self.maxCreeps = self.maxCreeps + 1	
				local dur = self.maxCreepsAddInterval + self.missingPlayers * self.addedIntervalPerMissingPlayer
				if IsValidEntity(self.king) then
					self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "maxcreep_modifier", {duration=dur} )
					self.king:SetModifierStackCount("maxcreep_modifier", self.king, self.maxCreeps)
				end
				return dur
			end)
		
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
	
	-- clean up spawnedList
	for i, unit in pairs(self.spawnedList) do
		if not IsValidEntity(unit) or not unit:IsAlive() then
			table.remove(self.spawnedList, i)
		end 
	end
	
	-- wake dire units if needed
	if table.getn(self.spawnedList) < self.maxCreeps then
		local unit = self.stonedList[1]
		table.remove(self.stonedList, 1)		
		if IsValidEntity(unit) then
			unit:RemoveModifierByName("modifier_medusa_stone_gaze_stone")
			unit:RemoveModifierByName("modifier_phased")
			unit:RemoveModifierByName("dire_weakness_modifier")
			--print("Unfreezing " .. unit:GetUnitName())
			EmitSoundOn("ui.shortwhoosh", unit)
			MinimapEvent(DOTA_TEAM_BADGUYS, unit, unit:GetAbsOrigin().x, unit:GetAbsOrigin().y, DOTA_MINIMAP_EVENT_TEAMMATE_TELEPORTING, 1)
			--MinimapEvent(DOTA_TEAM_GOODGUYS, unit, unit:GetAbsOrigin().x, unit:GetAbsOrigin().y,  DOTA_MINIMAP_EVENT_HINT_LOCATION, self.announcementFrequency)
			table.insert(self.spawnedList, unit)
		end
	end
	
	-- roshan bodyguard logic
	if IsValidEntity(self.roshan) and IsValidEntity(self.king) and self.roshan:FindAbilityByName("roshan_slam"):IsCooldownReady() then
		--print(self.lastAttacker)
		if CalcDistanceBetweenEntityOBB(self.roshan, self.king) > self.autoDefendDistance then
			-- leash to dire hero
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_MOVE_TO_TARGET, TargetIndex = self.king:GetEntityIndex(), Queue = false} )			 
			self.lastAttacker = nil
		elseif IsValidEntity(self.lastAttacker) then
			-- attack attacker
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_CAST_NO_TARGET, AbilityIndex = self.roshan:FindAbilityByName("roshan_slam"):GetEntityIndex(), Queue = false} ) 
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_ATTACK_TARGET, TargetIndex = self.lastAttacker:GetEntityIndex(), Queue = true} )
		else
			self.lastAttacker = nil
		end
	end
	
	--every minute re-check number of players 
	if (self.secondsPassed % 60 == 1) then
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
				self.missingPlayers = self.radiantPlayerCount - newRadiantPlayerCount
				GameRules:SendCustomMessage("difficulty_changed", 0, 0)
			end
		end
	end
end

-- Every time an npc is spawned do this:
function CLet4Def:OnNPCSpawned( event )
	local spawnedUnit = EntIndexToHScript( event.entindex )
	if spawnedUnit:IsRealHero() then		
		if spawnedUnit:GetTeamNumber() == DOTA_TEAM_BADGUYS then
			if not IsValidEntity(self.king) then
				-- make dire hero model bigger
				IncrementalModelScale(spawnedUnit, 0.4, 1)
				-- remember dire hero since we need this information elsewhere
				self.king = spawnedUnit	
				-- Get dire hero to level 25
				Timers:CreateTimer( 0.1, function()
					MaxAbilities(spawnedUnit)
					return nil
				end)
				-- give him the cheese
				spawnedUnit:AddItem(CreateItem("item_cheese", nil, nil))
				-- give him his modifiers
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "yolo_modifier", {duration=-1} )
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "maxcreep_modifier", {duration=-1} )
				spawnedUnit:SetModifierStackCount("maxcreep_modifier", spawnedUnit, self.maxCreeps)
				-- change his colour to white
				PlayerResource:SetCustomPlayerColor(spawnedUnit:GetPlayerID(), 255, 255, 255)
				-- jungle fix
				if self.secondsPassed ~= nil and self.secondsPassed > 30 then
					SendToServerConsole("sv_cheats_1;dota_spawn_neutrals;sv_cheats 0")					
				end
			end
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
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and not spawnedUnit:IsHero() and not spawnedUnit:IsConsideredHero() then
		-- dire courier haste
		if string.find(spawnedUnit:GetUnitName(), "courier") then
			spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_rune_haste", {duration = -1})
			IncrementalModelScale(spawnedUnit, 0.3, 1)
		else		
			-- dire creep effects
			table.insert(self.stonedList, spawnedUnit)
			spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_medusa_stone_gaze_stone", {duration = -1}) 
			self.modifiers:ApplyDataDrivenModifier( spawnedUnit, spawnedUnit, "dire_weakness_modifier", {duration=-1} )
			Timers:CreateTimer(5, function()
				if IsValidEntity(spawnedUnit) then
					spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_phased", {duration = -1}) 
				end
			end)
			spawnedUnit:SetHealth(1)
			spawnedUnit:SetDeathXP(spawnedUnit:GetDeathXP()*self.xpMultiplier)
			spawnedUnit:SetMinimumGoldBounty(spawnedUnit:GetMinimumGoldBounty()*self.goldMultiplier)
			spawnedUnit:SetMaximumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.goldMultiplier)
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
	-- roshan spawned 
	if spawnedUnit:GetUnitName() == "custom_npc_dota_roshan" then
		self.roshan = spawnedUnit
		-- give him aegis
		spawnedUnit:AddItem(CreateItem("item_aegis", nil, nil))
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
			-- if radiant hero is killed, change their respawn time and buyback mechanics
			elseif killedTeam == DOTA_TEAM_GOODGUYS then 
				local killedPlayerID = killedUnit:GetOwner():GetPlayerID()
				killedUnit:SetTimeUntilRespawn(self.radiantRespawnMultiplier*killedUnit:GetLevel())
				killedUnit:SetBuybackCooldownTime(0)
				PlayerResource:SetCustomBuybackCost(killedPlayerID, math.pow(killedUnit:GetLevel(),2)+0.5*PlayerResource:GetGold(killedPlayerID))
			end
		else
			-- give dire hero his modifiers back
			if killedTeam == DOTA_TEAM_BADGUYS then
				Timers:CreateTimer(5.1, function()
					self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "yolo_modifier", {duration=-1} )
					self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "maxcreep_modifier", {duration=-1} )
					self.king:SetModifierStackCount("maxcreep_modifier", self.king, self.maxCreeps)
				end)
			end
		end
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
	
	-- hurt announcements for dire hero and rosh
	if self.secondsPassed ~= nil and self.secondsPassed - self.lastHurtAnnouncement > self.announcementFrequency then
		if (hurtUnit:GetTeam() == DOTA_TEAM_BADGUYS and hurtUnit:IsRealHero()) then
			self.lastAttacker = attacker
			if hurtUnit:GetHealth() < hurtUnit:GetMaxHealth()/2 and hurtUnit:GetHealth() > 0 then
				EmitAnnouncerSoundForTeam("announcer_ann_custom_adventure_alerts_34", DOTA_TEAM_BADGUYS)
				MinimapEvent(DOTA_TEAM_BADGUYS, hurtUnit, hurtUnit:GetAbsOrigin().x, hurtUnit:GetAbsOrigin().y,  DOTA_MINIMAP_EVENT_HINT_LOCATION, self.announcementFrequency)
				self.lastHurtAnnouncement = self.secondsPassed
			end
		elseif (hurtUnit:GetUnitName() == "custom_npc_dota_roshan" and hurtUnit:GetTeam() == DOTA_TEAM_BADGUYS and hurtUnit:GetHealth() < hurtUnit:GetMaxHealth()/2) then
			EmitAnnouncerSoundForTeam("announcer_ann_custom_generic_alert_02", DOTA_TEAM_BADGUYS)
			self.lastHurtAnnouncement = self.secondsPassed
			MinimapEvent(DOTA_TEAM_BADGUYS, hurtUnit, hurtUnit:GetAbsOrigin().x, hurtUnit:GetAbsOrigin().y,   DOTA_MINIMAP_EVENT_HINT_LOCATION , self.announcementFrequency)
		end
	end
end

function CLet4Def:giveDireControl(unit)
	if IsValidEntity(self.king) and IsValidEntity(unit) then
		unit:SetTeam(DOTA_TEAM_BADGUYS)
		unit:SetOwner(self.king)
		if unit:GetUnitName() ~= "custom_npc_dota_roshan" then
			unit:SetControllableByPlayer(self.king:GetOwner():GetPlayerID(), true)					
		end
	elseif IsValidEntity(unit) and unit:GetUnitName() == "custom_npc_dota_roshan" then
		Timers:CreateTimer(1, function()
			self:giveDireControl(unit)
			return nil
		end)
	elseif IsValidEntity(unit) then
		unit:SetTeam(DOTA_TEAM_BADGUYS)
	end
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

function CLet4Def:DisableAutopilot(event)
	self.autopilot = false
	EmitAnnouncerSoundForTeam("General.Cancel", DOTA_TEAM_BADGUYS)	
	for i, unit in pairs(self.spawnedList) do
		if IsValidEntity(unit) then
			ExecuteOrderFromTable({UnitIndex = unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_STOP, Queue = false})
		end
	end
end

function CLet4Def:AutopilotGather()
	local gatherLocation = Vector(RandomInt(0, 6000),RandomInt(0, 6000),0)
	--print("Gathering " .. tostring(table.getn(self.spawnedList)) .. " units")
	for i, unit in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			if string.find(unit:GetUnitName(), "courier") == nil and unit:GetUnitName() ~= "custom_npc_dota_roshan" and not self.autopilotList[unit] then
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_MOVE_TO_POSITION, Position = gatherLocation, Queue = false} )
				self.autopilotList[unit] = 0
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
	--print("Attacking with " .. tostring(table.getn(self.spawnedList)) .. " units")
	for i, unit in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			if unit:GetUnitName() ~= "custom_npc_dota_roshan" and self.autopilotList[unit] == 0 then
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = pivotLocation, Queue = false} )
				ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = Vector(-5700,-5200,0), Queue = true} )
				self.autopilotList[unit] = 1
			end
		end
	end
end

function CLet4Def:AutoPilotDefend(enemy)
	for i, unit in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and CalcDistanceBetweenEntityOBB(unit, enemy) < self.autoDefendDistance then
			ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = enemy:GetAbsOrigin(), Queue = false} )
			self.autopilotList[unit] = nil
		end
	end
end

function AutoPilotAttackWait()
	local wait = RandomInt(120, 180)
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