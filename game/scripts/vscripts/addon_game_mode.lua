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
	PrecacheResource("particle", "particles/econ/items/oracle/oracle_ti10_immortal/oracle_ti10_immortal_purifyingflames_head_outline.vpcf", context)
	PrecacheResource("particle", "particles/neutral_fx/roshan_spawn.vpcf", context)
	PrecacheResource("particle", "particles/hw_fx/hw_roshan_death.vpcf", context)
	PrecacheResource("particle", "particles/awaken_aura.vpcf", context )
end

-- Create the game mode when we activate
function Activate()
	GameRules.AddonTemplate = CLet4Def()
	GameRules.AddonTemplate:InitGameMode()
end

function CLet4Def:InitGameMode()
	--print("Starting Let 4 Def...")
	-- game balance parameters
	self.timeLimitBase = 20*60 -- 20 minutes game length
	self.radiantRespawnMultiplier = 2 -- multiplied with the hero's level to get the respawn timer for radiant
	self.announcementFrequency = 5 --announcements cannot be made more frequently than this
	self.autoGatherInterval = 30
	self.autoDefendDistance = 1500
	self.xpMultiplier = 2
	self.goldMultiplierRadiant = 2
	-- initialise stuff
	GameRules:GetGameModeEntity():SetAnnouncerDisabled(true)
	self.timeLimit = self.timeLimitBase
	self.secondsPassed = nil
	self.spawnedList = {}
	self.stonedList = {}
	self.king = nil
	self.roshan = nil
	self.roshTarget = nil
	self.radiantPlayerCount = 4
	self.direPlayerCount = 1
	self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	self.lastHurtAnnouncement = -math.huge
	self.goldMultiplierDire = self.radiantPlayerCount
	local dummy = CreateUnitByName("dummy_unit", Vector(0,0,0), false, nil, nil, DOTA_TEAM_NEUTRALS)
	dummy:FindAbilityByName("dummy_passive"):SetLevel(1)
	self.modifiers = dummy:FindAbilityByName("modifier_collection")
	self.winners = nil
	self.botCheck = false
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
	GameRules:GetGameModeEntity():SetFreeCourierModeEnabled(true)
	GameRules:GetGameModeEntity():SetUseDefaultDOTARuneSpawnLogic(true)
	GameRules:GetGameModeEntity():SetTowerBackdoorProtectionEnabled(false)
	GameRules:SetUseBaseGoldBountyOnHeroes( false )
	-- create a filter to change gold bounty awards on the fly
	GameRules:GetGameModeEntity():SetModifyGoldFilter( Dynamic_Wrap( CLet4Def, "FilterGold" ), self )
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
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_PRE_GAME and self.botCheck == false then
		self:SpawnBots()
		self.botCheck = true
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
		
		--wake roshan early
		self:WakeUp(self.roshan)
			
		--remove backdoor protection
		 GameRules:GetGameModeEntity():SetTowerBackdoorProtectionEnabled(false)
		local allEntities = Entities:FindAllInSphere(Vector(0,0,0), 10000)
		for i=1, table.getn(allEntities) do
			if IsValidEntity(allEntities[i]) and allEntities[i].HasAbility then
				if allEntities[i]:HasAbility("backdoor_protection_in_base") then
					allEntities[i]:RemoveAbility("backdoor_protection_in_base")
					allEntities[i]:RemoveModifierByName("modifier_backdoor_protection_in_base")
				elseif allEntities[i]:HasAbility("backdoor_protection") then
					allEntities[i]:RemoveAbility("backdoor_protection")
					allEntities[i]:RemoveModifierByName("modifier_backdoor_protection")
				end
			end
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
	
	-- clean up spawnedList
	for i, unit in pairs(self.spawnedList) do
		if not IsValidEntity(unit) or not unit:IsAlive() then
			table.remove(self.spawnedList, i)
		end 
	end
	
	
	-- roshan bodyguard logic
	if IsValidEntity(self.roshan) and IsValidEntity(self.king) and self.roshan:FindAbilityByName("roshan_slam"):IsCooldownReady() then
		--print(self.roshTarget)
		if CalcDistanceBetweenEntityOBB(self.roshan, self.king) > self.autoDefendDistance then
			-- leash to dire hero
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_MOVE_TO_TARGET, TargetIndex = self.king:GetEntityIndex(), Queue = false} )			 
			self.roshTarget = nil
		elseif IsValidEntity(self.roshTarget) then
			-- attack attacker
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_CAST_NO_TARGET, AbilityIndex = self.roshan:FindAbilityByName("roshan_slam"):GetEntityIndex(), Queue = false} ) 
			ExecuteOrderFromTable( {UnitIndex=self.roshan:GetEntityIndex(), OrderType =  DOTA_UNIT_ORDER_ATTACK_TARGET, TargetIndex = self.roshTarget:GetEntityIndex(), Queue = true} )
		else
			self.roshTarget = nil
		end
	end
	
	-- dire hero wakeup aura
	if IsValidEntity(self.king) then
		local closeFriends = FindUnitsInRadius(DOTA_TEAM_BADGUYS, self.king:GetAbsOrigin(), nil, 1000, DOTA_UNIT_TARGET_TEAM_FRIENDLY, DOTA_UNIT_TARGET_BASIC, DOTA_UNIT_TARGET_FLAG_FOW_VISIBLE, 0, false) 
		--print(#closeFriends)
		if #closeFriends > 0 then
			local doneEffect = false			
			for i, unit in pairs(closeFriends) do
				if unit:HasModifier("dire_weakness_modifier") then
					self:WakeUp(unit)
					if not doneEffect then
						local effect_aura = ParticleManager:CreateParticle("particles/awaken_aura.vpcf", PATTACH_WORLDORIGIN, self.king)
						ParticleManager:SetParticleControl(effect_aura,0,self.king:GetAbsOrigin())
						ParticleManager:ReleaseParticleIndex(effect_aura)
						doneEffect = true
					end
				end
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
				-- give him the roshan items
				Timers:CreateTimer(1, function()
					if GameRules:State_Get() == DOTA_GAMERULES_STATE_PRE_GAME then
						spawnedUnit:AddItem(CreateItem("item_cheese", nil, nil))
						spawnedUnit:AddItem(CreateItem("item_refresher_shard", nil, nil))
						spawnedUnit:AddItem(CreateItem("item_ultimate_scepter_2", nil, nil))
					else
						return 1
					end
				end)
				-- give him his modifiers
				--self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "yolo_modifier", {duration=-1} )
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "maxcreep_modifier", {duration=-1})
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "gold_multiplier", {duration=-1})
				spawnedUnit:SetModifierStackCount("gold_multiplier", spawnedUnit, self.goldMultiplierDire)
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
		local creep = CreateUnitByName(spawnedUnit:GetUnitName(), spawnedUnit:GetAbsOrigin()+RandomVector(RandomInt(200,300)), false, nil, nil, DOTA_TEAM_NEUTRALS)
		Timers:CreateTimer(1, function()
			FindClearSpaceForUnit(creep, creep:GetAbsOrigin(), true)
			creep:AddNewModifier(spawnedUnit, nil, "modifier_phased", {duration = 1})
		end)
		spawnedUnit:RemoveSelf()
	end	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and not spawnedUnit:IsHero() and not spawnedUnit:IsConsideredHero() then
		-- dire courier haste
		if string.find(spawnedUnit:GetUnitName(), "courier") then
			spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_rune_haste", {duration = -1})
			IncrementalModelScale(spawnedUnit, 0.25, 1)
		elseif spawnedUnit:GetAttackCapability() > 0 then
			-- dire creep effects
			spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_stunned", {duration = -1}) 
			self.modifiers:ApplyDataDrivenModifier( spawnedUnit, spawnedUnit, "dire_weakness_modifier", {duration=-1} )
			spawnedUnit:SetHealth(1)
			spawnedUnit:SetDeathXP(spawnedUnit:GetDeathXP()*self.xpMultiplier)
			spawnedUnit:SetMinimumGoldBounty(spawnedUnit:GetMinimumGoldBounty()*self.goldMultiplierRadiant)
			spawnedUnit:SetMaximumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.goldMultiplierRadiant)
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
		Timers:CreateTimer(1, function()
			spawnedUnit:AddItem(CreateItem("item_aegis", nil, nil))
		end)
	end
end

-- change gold bounty awards on the fly
function CLet4Def:FilterGold(filterTable)
    local gold = filterTable["gold"]
    local playerID = filterTable["player_id_const"]
    local reason = filterTable["reason_const"]
    local reliable = filterTable["reliable"] == 1

    -- Special handling of hero kill gold (both bounty and assist gold goes through here first)
    if PlayerResource:GetTeam(playerID) == DOTA_TEAM_BADGUYS then
		filterTable["gold"] = gold * self.goldMultiplierDire
	end
    return true
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
		else --if unit is coming back
			-- give dire hero his modifiers back
			if killedTeam == DOTA_TEAM_BADGUYS then
				Timers:CreateTimer(5.1, function()
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "maxcreep_modifier", {duration=-1})
				self.modifiers:ApplyDataDrivenModifier( self.king, self.king, "gold_multiplier", {duration=-1})
				self.king:SetModifierStackCount("gold_multiplier", self.king, self.goldMultiplierDire)
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
			-- rosh targets enemy who attacked dire hero
			self.roshTarget = attacker
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
	
	-- rosh targets same target as dire hero 
	if (IsValidEntity(attacker) and attacker:GetTeam() == DOTA_TEAM_BADGUYS and attacker:IsRealHero()) then
		self.roshTarget = hurtUnit
	end
	
	--wake up hurt dire creeps
	if (hurtUnit:HasModifier("dire_weakness_modifier")) then
		self:WakeUp(hurtUnit)
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
	local pivotLocation = Vector(0,0,0)
	local minDistance = math.huge
	
	if #self.spawnedList > 0 then			
		for i, buildingClassname in pairs({"npc_dota_tower", "npc_dota_barracks", "npc_dota_filler"}) do
			for _, tower in pairs (Entities:FindAllByClassname(buildingClassname)) do
				if tower:GetTeamNumber() == DOTA_TEAM_GOODGUYS and tower:GetInvulnCount() == 0 then
					local dist = CalcDistanceBetweenEntityOBB(tower, self.spawnedList[1])
					if dist < minDistance then
						minDistance = dist
						pivotLocation = tower:GetAbsOrigin()
					end
				end
			end
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
end

function CLet4Def:AutoPilotDefend(enemy)
	for i, unit in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and CalcDistanceBetweenEntityOBB(unit, enemy) < self.autoDefendDistance then
			ExecuteOrderFromTable( {UnitIndex=unit:GetEntityIndex(), OrderType = DOTA_UNIT_ORDER_ATTACK_MOVE, Position = enemy:GetAbsOrigin(), Queue = false} )
			self.autopilotList[unit] = nil
		end
	end
end

function CLet4Def:WakeUp(unit)
	-- wake dire units
	if IsValidEntity(unit) and unit:HasModifier("dire_weakness_modifier") then
		unit:RemoveModifierByName("modifier_stunned")
		unit:RemoveModifierByName("dire_weakness_modifier")
		--print("Unfreezing " .. unit:GetUnitName())
		EmitSoundOn("ui.shortwhoosh", unit)
		MinimapEvent(DOTA_TEAM_BADGUYS, unit, unit:GetAbsOrigin().x, unit:GetAbsOrigin().y, DOTA_MINIMAP_EVENT_TEAMMATE_TELEPORTING, 1)
		--MinimapEvent(DOTA_TEAM_GOODGUYS, unit, unit:GetAbsOrigin().x, unit:GetAbsOrigin().y,  DOTA_MINIMAP_EVENT_HINT_LOCATION, self.announcementFrequency)
		local effect_wake = ParticleManager:CreateParticle("particles/econ/items/oracle/oracle_ti10_immortal/oracle_ti10_immortal_purifyingflames_head_outline.vpcf", PATTACH_WORLDORIGIN, unit)
        ParticleManager:SetParticleControl(effect_wake,0,unit:GetAbsOrigin())
        ParticleManager:ReleaseParticleIndex(effect_wake)
		table.insert(self.spawnedList, unit)
	end
end

function CLet4Def:SpawnBots() 
	self.botHeroes = {'npc_dota_hero_bane', 'npc_dota_hero_bounty_hunter', 'npc_dota_hero_bloodseeker', 'npc_dota_hero_bristleback', 'npc_dota_hero_chaos_knight', 'npc_dota_hero_crystal_maiden', 'npc_dota_hero_dazzle', 'npc_dota_hero_death_prophet', 'npc_dota_hero_drow_ranger', 'npc_dota_hero_earthshaker', 'npc_dota_hero_jakiro', 'npc_dota_hero_kunkka', 'npc_dota_hero_lina', 'npc_dota_hero_lion', 'npc_dota_hero_luna', 'npc_dota_hero_necrolyte', 'npc_dota_hero_omniknight', 'npc_dota_hero_oracle', 'npc_dota_hero_phantom_assassin', 'npc_dota_hero_pudge', 'npc_dota_hero_sand_king', 'npc_dota_hero_nevermore', 'npc_dota_hero_skywrath_mage', 'npc_dota_hero_sniper', 'npc_dota_hero_sven', 'npc_dota_hero_tiny', 'npc_dota_hero_viper', 'npc_dota_hero_warlock', 'npc_dota_hero_windrunner', 'npc_dota_hero_zuus'}
	missingRadiant = self.radiantPlayerCount - PlayerResource:GetPlayerCountForTeam(DOTA_TEAM_GOODGUYS)
	missingDire = self.direPlayerCount - PlayerResource:GetPlayerCountForTeam(DOTA_TEAM_BADGUYS)
	Tutorial:StartTutorialMode()	
	
	if missingDire > 0 then
		local heroNumber = RandomInt(1, #self.botHeroes)	
		--Tutorial:AddBot(self.botHeroes[heroNumber], "mid", "unfair", false)
		local bot = GameRules:AddBotPlayerWithEntityScript(self.botHeroes[heroNumber], string.sub(self.botHeroes[heroNumber], 15), DOTA_TEAM_BADGUYS, "", false)
		Timers:CreateTimer(1, function()	
			bot:SetBotDifficulty(4)
			FindClearSpaceForUnit(bot, Vector(6900, 6400, 400), false)
		end)
		table.remove(self.botHeroes, heroNumber)
	end
	
	for _ = 1, missingRadiant do
		local heroNumber = RandomInt(1, #self.botHeroes)	
		--Tutorial:AddBot(self.botHeroes[heroNumber], "mid", "unfair", true)
		local bot = GameRules:AddBotPlayerWithEntityScript(self.botHeroes[heroNumber], string.sub(self.botHeroes[heroNumber], 15), DOTA_TEAM_GOODGUYS, "", false)
		Timers:CreateTimer(1, function()	
			bot:SetBotDifficulty(4)
			FindClearSpaceForUnit(bot, Vector(-6900, -6400, 400), false)
		end)
		table.remove(self.botHeroes, heroNumber)
	end
	
	Timers:CreateTimer(1, function()			
		GameRules:GetGameModeEntity():SetBotThinkingEnabled(true)
		GameRules:GetGameModeEntity():SetBotsInLateGame(true)
		GameRules:GetGameModeEntity():SetBotsAlwaysPushWithHuman(true)
		if missingDire == 0 then
			GameRules:GetGameModeEntity():SetBotsMaxPushTier(0)
		end
	end)
end

function AutoPilotAttackWait()
	local wait = RandomInt(30, 90)
	return wait
end

function MaxAbilities( hero )
	for _ = 1, 29 do
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