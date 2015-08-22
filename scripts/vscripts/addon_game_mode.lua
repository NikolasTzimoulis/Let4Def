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
	print("Starting Let 4 Def...")
	-- game balance parameters
	self.towerExtraBounty = 3000
	self.endgameXPTarget = 14400 -- how much XP each radiant hero must have by the end of the game
	self.timeLimitBase = 20*60 -- 20 minutes game length
	self.weaknessDistance = 1500 -- how close to the king a unit must be to not suffer from weakness
	self.hPCapIncreaseRate = 1.0/(self.timeLimitBase) -- how much the dire unit hp cap should be increased in proportion to their max hp per second
	self.creepBountyMultiplier = 1.5 -- how much extra gold should dire creeps give
	self.radiantRespawnMultiplier = 1 -- multiplied with the hero's level to get the respawn timer for radiant
	self.pregametime = 30
	self.roshVulnerableTime = 30
	-- base rules
	GameRules:GetGameModeEntity():SetThink( "OnThink", self, "GlobalThink", 2 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_GOODGUYS, 4 )
	GameRules:SetCustomGameTeamMaxPlayers( DOTA_TEAM_BADGUYS, 1 )
	GameRules:SetHeroSelectionTime(30)
	GameRules:SetPreGameTime(self.pregametime)
	GameRules:SetPostGameTime(30)
	GameRules:SetGoldPerTick (0)
	-- initialise stuff
	self.timeLimit = self.timeLimitBase
	self.secondsPassed = 0
	self.xpSoFar = 0
	self.spawnedList = {}
	self.controlLaterList = {}
	self.king = nil
	self.checkHeroesPicked = false
	self.radiantPlayerCount = 4
	self.direPlayerCount = 1
	self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	local dummy = CreateUnitByName("dummy_unit", Vector(0,0,0), false, nil, nil, DOTA_TEAM_NEUTRALS)
	dummy:FindAbilityByName("dummy_passive"):SetLevel(1)
	self.direWeaknessAbility = dummy:FindAbilityByName("dire_weakness")
	-- generate tips
	self.sizeTipsRadiant = 14
	self.sizeTipsDire = 14
	self.radiantTips = {}
	for counter = 1, self.sizeTipsRadiant do
		table.insert(self.radiantTips, "radiant_tip_"..tostring(counter))
	end
	self.direTips = {}
	for counter = 1, self.sizeTipsDire do
		table.insert(self.direTips, "dire_tip_"..tostring(counter))
	end
	-- victory conditions UI
	self.victoryCondition1 = SpawnEntityFromTableSynchronous( "quest", { name = "", title = "quest_1" } )
	self.victoryCondition2 = SpawnEntityFromTableSynchronous( "quest", { name = "", title = "quest_2" } )
	self.victoryCondition3 = SpawnEntityFromTableSynchronous( "quest", { name = "", title = "quest_3" } )		
	-- listen to some game events
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CLet4Def, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CLet4Def, 'OnEntityKilled' ), self )
end

-- Evaluate the state of the game
function CLet4Def:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_PRE_GAME and not self.checkHeroesPicked then
		-- force random heroes on radiant if they do not select their heroes in time
		self.checkHeroesPicked = true
		for playerid = 0, DOTA_MAX_PLAYERS do
			if PlayerResource:IsValidPlayer(playerid) then
				player = PlayerResource:GetPlayer(playerid)
				if player ~= nil and not PlayerResource:HasSelectedHero(playerid) and PlayerResource:GetTeam(playerid) == DOTA_TEAM_GOODGUYS then
					player:MakeRandomHeroSelection()
				end
			end
		end
	elseif GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		if math.floor(GameRules:GetDOTATime(false, false)) > self.secondsPassed then
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
	-- hide victory conditions and start progressbar
	if (self.secondsPassed == 1) then
		self.victoryCondition1:CompleteQuest()
		self.victoryCondition2:CompleteQuest()
		self.victoryCondition3:CompleteQuest()
		self.gameOverTimer = SpawnEntityFromTableSynchronous( "quest", { name = "timer", title = "timer" } )
		self.gameOverTimer.EndTime = 30 
		self.gameOverProgressbar = SpawnEntityFromTableSynchronous( "subquest_base", {show_progress_bar = true, progress_bar_hue_shift = -119 } )
		self.gameOverTimer:AddSubquest( self.gameOverProgressbar )
		self.gameOverProgressbar:SetTextReplaceValue( SUBQUEST_TEXT_REPLACE_VALUE_CURRENT_VALUE, self.timeLimit )
		self.gameOverProgressbar:SetTextReplaceValue( SUBQUEST_TEXT_REPLACE_VALUE_TARGET_VALUE, self.timeLimit )
	end
	-- Display messages about how much time remains
	if (math.ceil(self.timeLimit) - self.secondsPassed) == 0 then
		GameRules:SendCustomMessage("time_up", 0, 0)
	elseif (math.ceil(self.timeLimit) - self.secondsPassed) == 60 then
		GameRules:SendCustomMessage("1_minute", 0, 0)
	elseif (math.round(self.timeLimit) - self.secondsPassed) % 60 == 0 then
		GameRules:SendCustomMessage("x_minutes",0,  math.ceil((self.timeLimit - self.secondsPassed)/60))
	end
	-- If time is up, game over for dire
	if self.secondsPassed >= self.timeLimit then
		GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
		self.gameOverTimer:CompleteQuest()
		GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
	end
	-- give everyone some xp, enough to reach a high level by 20 minutes
	local allHeroes = HeroList:GetAllHeroes()
	local xpPerSecond = (self.endgameXPTarget - self.xpSoFar) / (self.timeLimit - self.secondsPassed)
	for _, hero in pairs( allHeroes ) do
		hero:AddExperience(xpPerSecond, false, true)
	end
	self.xpSoFar = self.xpSoFar + xpPerSecond
	-- re-apply weakness on dire units if needed
	for unit, i in pairs(self.spawnedList) do
		if IsValidEntity(unit) and unit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS then
			local hpCap = self:CalculateHPCap(unit)
			if not self.spawnedList[unit] or not IsValidEntity(self.king) or CalcDistanceBetweenEntityOBB(self.king, unit) > self.weaknessDistance then
				if unit:GetHealth() > hpCap then
					unit:SetHealth(hpCap)
				end
				self.direWeaknessAbility:ApplyDataDrivenModifier( unit, unit, "dire_weakness_modifier", {duration=-1} )
				self.spawnedList[unit] = true
			elseif IsValidEntity(self.king) and CalcDistanceBetweenEntityOBB(self.king, unit) <= self.weaknessDistance then
				unit:RemoveModifierByName("dire_weakness_modifier")
				-- turn rosh against dire if dire hero comes too close
				if unit:GetUnitName() == "custom_npc_dota_roshan" then
					self.spawnedList[unit] = nil
					unit:SetTeam(DOTA_TEAM_NEUTRALS)
					unit:SetOwner(nil)
					unit:SetControllableByPlayer(-1, true)	
					unit:MoveToTargetToAttack(self.king)
					GameRules:SendCustomMessage("roshan_control", 0, 0)
				end
			elseif hpCap > 0.99*unit:GetMaxHealth() then
				unit:RemoveModifierByName("dire_weakness_modifier")
			end
		else
			self.spawnedList[unit] = nil
		end
	end
	-- re-check number of players every minute
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
			elseif newDirePlayerCount < 1 then
				ShowGenericPopup("warning",  "no_dire_player", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
			elseif newRadiantPlayerCount ~= self.radiantPlayerCount and newRadiantPlayerCount > 0 and self.totalPlayerCount > 1 then
				-- change difficulty
				--ShowGenericPopup("warning",  "difficulty_changed", "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 	
				self.timeLimit = self.timeLimit + math.sign(newRadiantPlayerCount-self.radiantPlayerCount) * math.abs(newRadiantPlayerCount-self.radiantPlayerCount)/5 * (self.timeLimitBase  - self.secondsPassed)
				GameRules:SendCustomMessage("difficulty_changed", 0, 0)
				GameRules:SendCustomMessage("new_time", 0, math.round(self.timeLimit/60))
			end
		end
		self.radiantPlayerCount = newRadiantPlayerCount
		self.direPlayerCount = newDirePlayerCount
		self.totalPlayerCount = self.radiantPlayerCount + self.direPlayerCount
	end
	-- update progress bar
	self.gameOverProgressbar:SetTextReplaceValue( QUEST_TEXT_REPLACE_VALUE_CURRENT_VALUE, self.timeLimit-self.secondsPassed )
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
			-- give dire control of units that were spawned before the dire hero
			for _, unit in pairs(self.controlLaterList) do 
				self:giveDireControl(unit)
			end 
			-- tip for dire
			if self.secondsPassed == 0 then
				ShowGenericPopupToPlayer(spawnedUnit:GetOwner(),  "tip_title",  self.direTips[RandomInt(1, self.sizeTipsDire)], "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
			end
		elseif self.secondsPassed == 0 then -- tip for radiant
			ShowGenericPopupToPlayer(spawnedUnit:GetOwner(),  "tip_title",  self.radiantTips[RandomInt(1, self.sizeTipsRadiant)], "", "", DOTA_SHOWGENERICPOPUP_TINT_SCREEN) 
		end
	end
	-- Remove radiant creeps from the game
	if (spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_melee" or spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_ranged" or spawnedUnit:GetUnitName() == "npc_dota_goodguys_siege") then
		spawnedUnit:RemoveSelf()
	end	
	-- Remove XP bounties from the game
	spawnedUnit:SetDeathXP(0)	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and not spawnedUnit:IsHero() and not spawnedUnit:IsConsideredHero() and string.find(spawnedUnit:GetUnitName(), "upgraded") == nil then
		-- Make most dire units weaker than normal (put them on a list and use timer to re-apply weakness)
		self.spawnedList[spawnedUnit] = false
		-- Increase gold bounty of dire units
		spawnedUnit:SetMinimumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.creepBountyMultiplier)
		spawnedUnit:SetMaximumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*self.creepBountyMultiplier)		
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
	-- give roshan aegis and cheese and make him invulnerable for a while
	if spawnedUnit:GetUnitName() == "custom_npc_dota_roshan" then
		spawnedUnit:AddItem(CreateItem("item_aegis", nil, nil))
		spawnedUnit:AddItem(CreateItem("item_cheese", nil, nil))
		invulDuration = max(1,-GameRules:GetDOTATime(false, true) + self.roshVulnerableTime)
		spawnedUnit:AddNewModifier(spawnedUnit, nil, "modifier_invulnerable", {duration = invulDuration}) 
	end
end

-- Every time an NPC is killed do this:
function CLet4Def:OnEntityKilled( event )
	local killedUnit = EntIndexToHScript( event.entindex_killed )
	local killedTeam = killedUnit:GetTeam()
	-- if a hero is killed...
	if (killedUnit:IsRealHero() and not killedUnit:IsReincarnating() and not killedUnit:IsClone()) then
		-- if dire/king is killed, game over for dire
		if killedTeam == DOTA_TEAM_BADGUYS then
			GameRules:GetGameModeEntity():SetFogOfWarDisabled(true)
			GameRules:MakeTeamLose(DOTA_TEAM_BADGUYS)
		-- if radiant hero is killed, give them a short respawn time
		elseif killedTeam == DOTA_TEAM_GOODGUYS then 
			killedUnit:SetTimeUntilRespawn(self.radiantRespawnMultiplier*killedUnit:GetLevel())
		end
	end 
	-- if radiant tower is killed, give extra gold to dire
	if (killedUnit:IsTower() and killedTeam == DOTA_TEAM_GOODGUYS and IsValidEntity(self.king)) then
		self.king:ModifyGold(self.towerExtraBounty, true,  DOTA_ModifyGold_Building)
		GameRules:SendCustomMessage("tower_gold", 0, self.towerExtraBounty)
	end
	-- if rosh is killed, make him drop his items
	if killedUnit:GetUnitName() == "custom_npc_dota_roshan" then
		GameRules:SendCustomMessage("roshan_killed", 0, 0)
		for itemSlot = 0, 5, 1 do 
			local item = killedUnit:GetItemInSlot( itemSlot ) 
			if IsValidEntity(item) then 
				CreateItemOnPositionSync(killedUnit:GetOrigin(), CreateItem(item:GetName() , nil, nil)) 
			end
		end		
	end
end

function CLet4Def:CalculateHPCap( unit )
	return math.max(1,self.hPCapIncreaseRate*self.secondsPassed*unit:GetMaxHealth())
end

function CLet4Def:giveDireControl(unit)
	if IsValidEntity(self.king) and IsValidEntity(unit)then
		unit:SetTeam(DOTA_TEAM_BADGUYS)
		unit:SetOwner(self.king)
		unit:SetControllableByPlayer(self.king:GetOwner():GetPlayerID(), true)		
	elseif not IsValidEntity(self.king) then
		table.insert(self.controlLaterList, unit)
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