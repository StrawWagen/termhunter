AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local entMeta = FindMetaTable("Entity")

--[[-------------------------------------------------------
	NEXTBOT Settings
--]]-------------------------------------------------------

-- Default bot's weapon on spawn
ENT.DefaultWeapon = nil

-- Default bot's health
ENT.SpawnHealth = 100

-- Bot's desired move speed
ENT.MoveSpeed = 200

-- Bot's desired run speed
ENT.RunSpeed = 320

-- Bot's desired walk speed
ENT.WalkSpeed = 100

-- Bot's desired crouch walk speed
ENT.CrouchSpeed = 120

-- Bot's acceleration speed
ENT.AccelerationSpeed = 1000

-- Bot's deceleration speed
ENT.DecelerationSpeed = 3000

-- Bot's aiming speed, in degrees per second
ENT.AimSpeed = 180

-- Bot's collision bounds, min max
ENT.CollisionBounds = {Vector(-16,-16,0),Vector(16,16,72)}

ENT.MyPhysicsMass = 85

-- Can bot crouch
ENT.CanCrouch = true

-- Can bot always fit into NAV_CROUCH areas
ENT.AlwaysCrouching = nil

-- Max height the bot can step up
ENT.StepHeight = 18

-- Bot's jump height
ENT.JumpHeight = 70

-- Height limit for path finding.
ENT.MaxJumpToPosHeight = ENT.JumpHeight

-- Height the bot is scared to fall from
ENT.DeathDropHeight = 200

-- Default gravity for bot
ENT.DefaultGravity = 600

-- While moving along path, bot will jump after this time if it thinks it stuck
ENT.PathStuckJumpTime = 0.5

-- Solid mask used for raytracing when detecting collision while moving
ENT.SolidMask = MASK_NPCSOLID

-- Time need to forget enemy if bot doesn't see it
ENT.ForgetEnemyTime = 30

-- Distance at which enemy should be to make bot think enemy is very close
ENT.CloseEnemyDistance = 500

-- Max distance at which bot can see enemies
ENT.MaxSeeEnemyDistance = 3000

-- Default motion path minimum look ahead distance
ENT.PathMinLookAheadDistance = 15

-- Default motion path goal tolerance
ENT.PathGoalTolerance = 25

-- Default motion path goal tolerance on last segment
ENT.PathGoalToleranceFinal = 25

-- Default motion path recompute time
ENT.PathRecompute = 5

-- Draws path if valid. Used for debug
ENT.DrawPath = CreateConVar( "term_debugpath", 0, FCVAR_NONE, "Debug terminator paths? Requires sv_cheats to be 1" )

--[[-------------------------------------------------------
	NEXTBOT Meta Table Setup
--]]-------------------------------------------------------

local defaultModel = "models/player/kleiner.mdl"

--[[------------------------------------
	NEXTBOT:Initialize
	Initialize our bot
--]]------------------------------------
function ENT:Initialize()
	local myTbl = entMeta.GetTable( self )
	entMeta.SetModel( self, defaultModel ) -- kliener of doom

	myTbl.IsNPCHackRegister( self )

	self:SetSolidMask( myTbl.SolidMask )
	entMeta.SetCollisionGroup( self, COLLISION_GROUP_PLAYER )

	local spawnHealth = myTbl.SpawnHealth
	if isfunction( spawnHealth ) then
		spawnHealth = spawnHealth()

	end
	entMeta.SetMaxHealth( self, spawnHealth )
	entMeta.SetHealth( self, spawnHealth )

	entMeta.AddFlags( self, FL_OBJECT ) -- make npcs see us

	local ct = CurTime()
	local pos = entMeta.GetPos( self )

	myTbl.BehaveInterval = 0
	myTbl.m_Path = Path("Follow")
	myTbl.m_PathPos = Vector()
	myTbl.m_PathOptions = {}
	myTbl.m_NavArea = navmesh.GetNearestNavArea(pos)
	myTbl.m_Capabilities = 0
	myTbl.m_ClassRelationships = {}
	myTbl.m_EntityRelationships = {}
	myTbl.m_EnemiesMemory = {}
	myTbl.m_FootstepFoot = false
	myTbl.m_FootstepTime = ct
	myTbl.m_LastMoveTime = ct
	myTbl.m_FallSpeed = 0
	myTbl.m_TaskList = {}
	myTbl.m_ActiveTasks = {}
	myTbl.m_Stuck = false
	myTbl.m_StuckTime = ct
	myTbl.m_StuckTime2 = 0
	myTbl.m_StuckPos = pos
	myTbl.m_HullType = HULL_HUMAN
	myTbl.m_DuckHullType = HULL_TINY
	myTbl.m_PitchAim = 0
	myTbl.m_Conditions = {}
	myTbl.m_PathUpdatesDemanded = 0

	local loco = myTbl.loco
	loco:SetGravity( myTbl.DefaultGravity )
	loco:SetAcceleration( myTbl.AccelerationSpeed )
	loco:SetDeceleration( myTbl.DecelerationSpeed )
	loco:SetStepHeight( myTbl.StepHeight )
	loco:SetJumpHeight( myTbl.JumpHeight )
	loco:SetDeathDropHeight( myTbl.DeathDropHeight )

	myTbl.SetupCollisionBounds( self, myTbl )
	myTbl.ReloadWeaponData( self )
	myTbl.SetDesiredEyeAngles( self, entMeta.GetAngles( self ) )
	self:SetupDefaultCapabilities()

	entMeta.AddCallback( self, "PhysicsCollide", myTbl.PhysicsObjectCollide )
end

--[[------------------------------------
	Name: NEXTBOT:GetFallDamage
	Desc: Returns fall damage that should applied to bot.
	Arg1: number | speed | Fall speed
	Ret1: number | Fall damage
--]]------------------------------------
function ENT:GetFallDamage(speed)
	return 10
end

--[[------------------------------------
	NEXTBOT:OnInjured
	Call task hooks
--]]------------------------------------
function ENT:OnInjured(dmg)
	self:RunTask("OnInjured",dmg)
end

--[[------------------------------------
	NEXTBOT:OnRemove
	Call task hooks
--]]------------------------------------
function ENT:OnRemove()
	self:RunTask("OnRemoved")
end

--[[------------------------------------
	NEXTBOT:KeyValue
	Handles KeyValue settings
--]]------------------------------------
function ENT:KeyValue(key,value)
	self.KeyValues = self.KeyValues or {}
	self.KeyValues[key] = value
end

--[[------------------------------------
	Name: NEXTBOT:GetKeyValue
	Desc: Returns KeyValue setting value.
	Arg1: string | key | Key of setting.
	Ret1: any | Value of setting.
--]]------------------------------------
function ENT:GetKeyValue(key)
	return self.KeyValues and self.KeyValues[key]
end

--[[------------------------------------
	Name: NEXTBOT:SetupDefaultCapabilities
	Desc: Used to set default capabilities 
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:SetupDefaultCapabilities()
	self:CapabilitiesAdd(bit.bor(CAP_MOVE_GROUND,CAP_USE_WEAPONS))
end

--[[------------------------------------
	Name: NEXTBOT:DissolveEntity
	Desc: Dissolving entity.
	Arg1: (optional) Entity | ent | Entity to dissolve. Without this will be used bot entity.
	Ret1: 
--]]------------------------------------
function ENT:DissolveEntity(ent)
	ent = ent or self

	local dissolver = ents.Create("env_entity_dissolver")
	dissolver:SetMoveParent(ent)
	dissolver:SetSaveValue("m_flStartTime",0)
	dissolver:Spawn()
	dissolver:AddEFlags(EFL_FORCE_CHECK_TRANSMIT)
	
	ent:SetSaveValue("m_flDissolveStartTime",0)
	ent:SetSaveValue("m_hEffectEntity",dissolver)
	ent:AddFlags(FL_DISSOLVING)
end

-- Handles Motion methods (Path, Speed, Activity)
include("motion.lua")

-- Handles Weapon methods (support of weapon usage)
include("weapons.lua")

-- Handles Enemy methods (relationships)
include("enemy.lua")

-- Handles Behaviour methods (bot's brain)
include("behaviour.lua")

-- Handles Player Control methods
AddCSLuaFile("cl_playercontrol.lua")
AddCSLuaFile("drive.lua")
include("drive.lua")
include("playercontrol.lua")

-- Handles Tasks methods
AddCSLuaFile("tasks.lua")
include("tasks.lua")

function ENT:SetCondition(condition) self.m_Conditions[condition] = true end
function ENT:HasCondition(condition) return self.m_Conditions[condition] or false end
function ENT:ClearCondition(condition) self.m_Conditions[condition] = nil end

-- NPC Stubs

function ENT:ConditionName(condition) return "" end

function ENT:ClearSchedule() end
function ENT:GetCurrentSchedule() return SCHED_NONE end
function ENT:IsCurrentSchedule(schedule) return schedule==SCHED_NONE end
function ENT:SetSchedule(schedule) end

function ENT:SetNPCState(state) end
function ENT:GetNPCState() return NPC_STATE_NONE end

function ENT:AddEntityRelationship(target,disposition,priority) self:Term_SetEntityRelationship(target,disposition,priority) end
function ENT:AddRelationship(str)
	local explode = string.Explode(" ",str)

	local class = explode[1]
	if !class then return end

	local d = explode[2]=="D_LI" and D_LI or explode[2]=="D_HT" and D_HT or explode[2]=="D_ER" and D_ER or explode[2]=="D_FR" and D_FR
	local priority = tonumber(explode[3])

	self:SetClassRelationship(class,d or D_NU,priority or 0)
end
function ENT:Disposition(ent) return self:GetRelationship(ent) end


local terms = {}
terminator_Extras.isNpcHack_Tbl = terms

local function onTermsTableUpdate()
	local count = 0

	for term, _ in pairs( terms ) do
		if not IsValid( term ) then
			terms[term] = nil

		else
			count = count + 1

		end
	end

	if count > 0 then
		terminator_Extras.setupExpensiveHacks()
		hook.Run( "terminator_nextbot_oneterm_exists" )

	else
		terminator_Extras.teardownExpensiveHacks()
		hook.Run( "terminator_nextbot_noterms_exist" )

	end
end

function ENT:IsNPCHackRegister()
	terms[self] = true
	onTermsTableUpdate()

	self:CallOnRemove( "term_cleanuptermcache", function( ent )
		terms[ent] = nil
		timer.Simple( 0, function()
			onTermsTableUpdate()

		end )
	end )
end

function ENT:DontRegisterAsNpc()
	terms[self] = nil
end

function ENT:ReRegisterAsNpc()
	terms[self] = true
end


--HACK because nothing really expects nextbots to be :USE ing them, sweps dont expect to be equipped by nextbots, but some expect to be picked up by npcs!
local meta = FindMetaTable( "Entity" )

meta.term_Old_IsNPC = meta.term_Old_IsNPC or meta.IsNPC

local function termIsNPCHack( ent )
	if terms[ent] then return true end
	return meta.term_Old_IsNPC( ent )

end

meta.term_Old_EyeAngles = meta.term_Old_EyeAngles or meta.EyeAngles

-- when the weapon uses eyeangles instead of aimvector....
local function termEyeAnglesHack( ent )
	if terms[ent] then return ent:GetEyeAngles() end
	return meta.term_Old_EyeAngles( ent )

end

local wasHacking

function terminator_Extras.setupExpensiveHacks()
	if wasHacking then return end
	wasHacking = true

	meta.IsNPC = termIsNPCHack
	meta.EyeAngles = termEyeAnglesHack

end
function terminator_Extras.teardownExpensiveHacks()
	if not wasHacking then return end
	wasHacking = nil

	meta.IsNPC = meta.term_Old_IsNPC
	meta.EyeAngles = meta.term_Old_EyeAngles

end
