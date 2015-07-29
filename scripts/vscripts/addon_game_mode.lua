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
	GameRules:SetHeroSelectionTime(10)
	GameRules:SetPreGameTime(0)
	GameRules:SetPostGameTime(30)
	GameRules:SetGoldPerTick (0)
	self.secondsPassed = 0
	self.spawnedList = {}
	self.king = nil
	self.spawnedBots = false
	self.towerExtraBounty = 2500
	self.xpPerSecond = 18	-- level 20 in 20 minutes
	self.timeLimit = 20*60 -- 20 minutes game length
	self.weakenessDuration = 30 -- 30 seconds of weakness
	ListenToGameEvent( "npc_spawned", Dynamic_Wrap( CLet4Def, "OnNPCSpawned" ), self )
	ListenToGameEvent( "entity_killed", Dynamic_Wrap( CLet4Def, 'OnEntityKilled' ), self )
end

-- Evaluate the state of the game
function CLet4Def:OnThink()
	if GameRules:State_Get() == DOTA_GAMERULES_STATE_GAME_IN_PROGRESS then
		--print( "Template addon script is running." )
		if GameRules:GetDOTATime(false, false) > self.secondsPassed then
			self.secondsPassed = GameRules:GetDOTATime(false, false)
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
		GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
	end
	-- give everyone some xp, enough to reach a high level by 20 minutes
	local allHeroes = HeroList:GetAllHeroes()
	heroCount = 0
	for _, hero in pairs( allHeroes ) do
		hero:AddExperience(self.xpPerSecond, false, true)
		heroCount = heroCount + 1
	end
	-- re-apply weakness on dire units for the specified duration
	for unit, i in pairs(self.spawnedList) do
		self.spawnedList[unit] = self.spawnedList[unit] + 1
		if unit:IsNull() or self.spawnedList[unit] > self.weakenessDuration then
			self.spawnedList[unit] = nil
		end
		if unit:GetHealth() > unit:GetMaxHealth()/10 then
			unit:SetHealth(unit:GetMaxHealth()/10)
		end
	end
	--spawn controllable bots if there are not enough people
	if (not self.spawnedBots and heroCount < 5) then
		SendToServerConsole("dota_bot_populate")
		self.spawnedBots = true
	end
end

-- Every time an npc is spawned do this:
function CLet4Def:OnNPCSpawned( event )
	local spawnedUnit = EntIndexToHScript( event.entindex )
	-- Get dire hero to level 25
	if (spawnedUnit:IsRealHero() and spawnedUnit:GetTeamNumber() == DOTA_TEAM_BADGUYS) then
		for _ = 1, 24 do
			spawnedUnit:HeroLevelUp(false)
		end
		self.king = spawnedUnit
	end
	-- Remove radiant creeps from the game
	if (spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_melee" or spawnedUnit:GetUnitName() == "npc_dota_creep_goodguys_ranged" or spawnedUnit:GetUnitName() == "npc_dota_goodguys_siege") then
		spawnedUnit:RemoveSelf()
	end	
	-- Remove XP bounties from the game
	spawnedUnit:SetDeathXP(0)
	
	if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_GOODGUYS and spawnedUnit ~= self.king then
		-- Make dire units weaker than normal (use timer)
		self.spawnedList[spawnedUnit] = 0
		spawnedUnit:SetHealth(spawnedUnit:GetMaxHealth()/10)
		--spawnedUnit:SetBaseMoveSpeed(spawnedUnit:GetBaseMoveSpeed()/4)
		--spawnedUnit:SetBaseAttackTime(spawnedUnit:GetBaseAttackTime()*4)
		--spawnedUnit:SetBaseHealthRegen(spawnedUnit:GetBaseHealthRegen()-spawnedUnit:GetMaxHealth()/75)
		-- Increase gold bounty of dire units
		spawnedUnit:SetMinimumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*2)
		spawnedUnit:SetMaximumGoldBounty(spawnedUnit:GetMaximumGoldBounty()*2)		
		-- Give full control of neutral units to dire
		if spawnedUnit:GetTeamNumber() ~= DOTA_TEAM_BADGUYS and self.king ~= nil then
			spawnedUnit:SetTeam(DOTA_TEAM_BADGUYS)
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
		GameRules:SetGameWinner(DOTA_TEAM_GOODGUYS)
	end 
	-- if radiant tower is killed, give extra gold to dire
	if (killedUnit:IsTower() and killedTeam == DOTA_TEAM_GOODGUYS and self.king ~= nil) then
		self.king:ModifyGold(self.towerExtraBounty, true,  DOTA_ModifyGold_Building)
		GameRules:SendCustomMessage("Dire received <font color='#CCCC00'>"..self.towerExtraBounty.."</font> gold for destroying a tower!", DOTA_TEAM_BADGUYS, 1)
	end

end