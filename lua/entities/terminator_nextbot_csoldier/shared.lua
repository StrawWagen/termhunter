-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

local entMeta = FindMetaTable( "Entity" )
local navMeta = FindMetaTable( "CNavArea" )

local CurTime = CurTime
local IsValid = IsValid
local math = math

local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running

ENT.DefaultWeapon = {
    "weapon_smg1",
    "weapon_ar2",
}

ENT.DefaultSidearms = {
    "weapon_frag",
}

ENT.TERM_FISTS = false

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Combine Soldier"
ENT.Spawnable = false -- dont show up in entity spawn category
ENT.SubCategory = "The Combine"

terminator_Extras.RegisterNPC( "terminator_nextbot_csoldier", ENT, {
    Weapons = ENT.DefaultWeapon,
} )

ENT.PlayerColorVec = Vector( 0.4, 0.4, 0.6 ) -- changes ENT:GetPlayerColor result

ENT.TermSoldier_CanMeleeAttack = true
ENT.TermSoldier_MeleeAttackRange = 60
ENT.TermSoldier_MeleeAttackDamage = 15
ENT.TermSoldier_MeleeAttackHull = 10
ENT.TermSoldier_MeleeAttackDmgType = DMG_CLUB
ENT.TermSoldier_MeleeAttackGesture = ACT_GMOD_GESTURE_MELEE_SHOVE_2HAND
ENT.TermSoldier_MeleeAttackHitDelay = 0.3
ENT.TermSoldier_MeleeAttackSound = "weapons/slam/throw.wav"
ENT.TermSoldier_MeleeAttackHitSound = "physics/body/body_medium_impact_hard6.wav"

ENT.MySpecialActions = {
    ["TermSoldier_Melee"] = {
        commandName = "impulse 100", -- flashlight
        drawHint = function( bot ) return bot.TermSoldier_CanMeleeAttack end,
        name = "Melee",
        desc = "Simple melee attack.", -- desc is unused for now
        ratelimit = 0.68,

        svAction = function( _drive, _driver, bot )
            bot:DoGesture( bot.TermSoldier_MeleeAttackGesture, 1, false )
            bot:BlockWeaponFiringUntil( CurTime() + 1 )
            timer.Simple( bot.TermSoldier_MeleeAttackHitDelay or 0.2, function()
                if not IsValid( bot ) then return end
                bot:EmitSound( bot.TermSoldier_MeleeAttackSound, 75, math.random( 95, 105 ), 1, CHAN_WEAPON )

                local hit = false
                bot:FireBullets( {
                    Attacker = bot,
                    Damage = bot.TermSoldier_MeleeAttackDamage,
                    Force = bot.TermSoldier_MeleeAttackDamage * 0.5,
                    Tracer = 0,
                    Num = 1,
                    Src = bot:GetShootPos(),
                    Dir = bot:GetAimVector(),
                    HullSize = bot.TermSoldier_MeleeAttackHull,
                    Distance = bot.TermSoldier_MeleeAttackRange,
                    Callback = function( attacker, tr, dmginfo )
                        hit = true
                        dmginfo:SetDamageType( bot.TermSoldier_MeleeAttackDmgType )
                    end,
                } )

                if not hit then return end
                bot:EmitSound( bot.TermSoldier_MeleeAttackHitSound, 75, math.random( 95, 105 ), 1, CHAN_WEAPON )

            end )
        end,
    },
}

if CLIENT then return end

local function Distance2D( pos1, pos2 )
    local product = pos1 - pos2
    return product:Length2D()
end

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 10
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = true

ENT.JumpHeight = 60
ENT.DefaultStepHeight = 18
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1 -- used in crouch toggle in motionoverrides
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.SpawnHealth = 75
ENT.FriendlyFireMul = 0.5
ENT.DoMetallicDamage = false
ENT.DontShootThroughProps = true -- only attack if MASK_SHOT is clear
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_AVERAGE
ENT.WalkSpeed = 75
ENT.MoveSpeed = 125
ENT.RunSpeed = 200
ENT.AccelerationSpeed = 1500
ENT.DeathDropHeight = 800

ENT.CanHolsterWeapons = true

ENT.CanSwim = true
ENT.BreathesAir = true
ENT.ThrowingForceMul = 0.5
ENT.Term_SecondsAttentionOnLostEnemy = 0.75

ENT.neverManiac = true
ENT.HasBrains = true -- false hasbrains means REALLY STUPID for these guys

ENT.isTerminatorHunterChummy = "combine"
ENT.MetallicMoveSounds = false
ENT.ReallyStrong = false
ENT.ReallyHeavy = false
ENT.DuelEnemyDist = 1000
ENT.MaxRunningGunningDist = 2000
ENT.CloseEnemyDistance = 750 -- focus on closest enemy, not best, if below this dist

ENT.FootstepClomping = false
ENT.Term_FootstepMode = "custom" -- custom sound mode
ENT.Term_FootstepSoundWalking = {
    {
        path = "NPC_CombineS.FootstepLeft",
    },
    {
        path = "NPC_CombineS.FootstepRight",
    },
}
ENT.Term_FootstepSound = { -- running sounds
    {
        path = "NPC_CombineS.RunFootstepLeft",
    },
    {
        path = "NPC_CombineS.RunFootstepRight",
    },
}

ENT.Term_BaseMsBetweenSteps = 900
ENT.Term_FootstepMsReductionPerUnitSpeed = 3

ENT.Models = {
    "models/player/combine_soldier.mdl",
}

ENT.TermSoldier_MaxFollowers = 6
ENT.TermSoldier_Fearless = nil -- set to true to make bot always just walk up to enemies, not take cover

-- overwatch tells the squad where the bodies are piling up
ENT.HeatAvoidance = { term_deaths = 2, term_hurt = 1 }

-- patrols spread out from where the squad's already looked, and drift toward where enemies were seen
local term_Heat = terminator_Extras.term_Heat

include( "sv_squads.lua" )
local term_Squads = terminator_Extras.term_Squads
term_Heat.RegisterLayer( "soldier_searched", { perFaction = true, cap = 10 } )
term_Heat.RegisterLayer( "soldier_enemyseen", { perFaction = true, cap = 10 } )
local noHeat = {}

local coverDebuggingVar = CreateConVar( "terminator_debug_soldiercover", 0, FCVAR_NONE, "Draw the soldiers' cover search, needs developer 1.", 0, 1 )
local coverDebugging = coverDebuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_debug_soldiercover", function( _, _, new )
    coverDebugging = tobool( new )

end, "updatedebugging" )

-- everyone watching the same enemy wants the same area, so only look it up once a second
local enemyAreas = setmetatable( {}, { __mode = "k" } )
local enemyAreasExpire = setmetatable( {}, { __mode = "k" } )
local function getEnemysArea( enemy )
    local cur = CurTime()
    if ( enemyAreasExpire[enemy] or 0 ) > cur then return enemyAreas[enemy] end

    local area = terminator_Extras.getNearestNav( entMeta.GetPos( enemy ) )
    enemyAreas[enemy] = area
    enemyAreasExpire[enemy] = cur + 1
    return area

end

local friendly = { D_LI, D_LI, 1000 }
local hate = { D_HT, D_HT, 1000 }

-- the Resistance Turret is a floor turret on the rebels' side
local function floorTurretRelation( _self, turret )
    if turret:HasSpawnFlags( SF_FLOOR_TURRET_CITIZEN ) then return hate end
    return friendly

end

-- spawnmenu's hacked variants, flag values from base_npcs.lua
local SF_MANHACK_HACKED = 2097152
local SF_ROLLERMINE_HACKED = 262144

local function manhackRelation( _self, manhack )
    if manhack:HasSpawnFlags( SF_MANHACK_HACKED ) then return hate end
    return friendly

end

local function rollermineRelation( _self, rollermine )
    if rollermine:HasSpawnFlags( SF_ROLLERMINE_HACKED ) then return hate end
    return friendly

end

ENT.Term_NPCCLASS = CLASS_COMBINE

function ENT:DoHardcodedRelations()
    self.term_HardCodedRelations = {
        ["npc_breen"] = friendly,
        ["npc_hunter"] = friendly,
        ["npc_stalker"] = friendly,
        ["npc_strider"] = friendly,
        ["npc_manhack"] = manhackRelation,
        ["npc_cscanner"] = friendly,
        ["npc_combine_s"] = friendly,
        ["npc_clawscanner"] = friendly,
        ["npc_helicopter"] = friendly,
        ["npc_rollermine"] = rollermineRelation,
        ["npc_metropolice"] = friendly,
        ["npc_turret_floor"] = floorTurretRelation,
        ["npc_turret_ceiling"] = friendly,
        ["npc_combine_camera"] = friendly,
        ["npc_combinegunship"] = friendly,
        ["npc_combinedropship"] = friendly,
        ["npc_citizen_rebel_enemy"] = friendly,
        ["npc_rollermine_friendly"] = friendly,

        ["npc_citizen"] = hate,
        ["npc_alyx"] = hate,
        ["npc_barney"] = hate,
        ["npc_dog"] = hate,
        ["npc_eli"] = hate,
        ["npc_fisherman"] = hate,
        ["npc_kleiner"] = hate,
        ["npc_magnusson"] = hate,
        ["npc_monk"] = hate,
        ["npc_mossman"] = hate,
        ["npc_vortigaunt"] = hate,

        ["npc_zombie"] = hate,
        ["npc_zombie_torso"] = hate,
        ["npc_fastzombie"] = hate,
        ["npc_fastzombie_torso"] = hate,
        ["npc_poisonzombie"] = hate,
        ["npc_zombine"] = hate,
        ["npc_headcrab"] = hate,
        ["npc_headcrab_fast"] = hate,
        ["npc_headcrab_black"] = hate,

        ["npc_antlion"] = hate,
        ["npc_antlionguard"] = hate,
    }
end

function ENT:canDoRun()
    local myTbl = entMeta.GetTable( self )
    return myTbl.canRunOnPath( self, myTbl )

end
function ENT:shouldDoWalk()
    local myTbl = entMeta.GetTable( self )
    return myTbl.shouldDoWalkOnPath( self, myTbl )

end

local upCrapCover = Vector( 0, 0, 15 )

local COVER_NONE = 1
local COVER_CRAPCOVER = 2
local COVER_SOFTCOVER = 4
local COVER_HARDCOVER = 8

local SnapVecToGrid
-- brainy and brainless bots trace differently, so they can't share answers
local coverposCaches

function ENT:GetCoverStatusOfPos( myTbl, coverPos, enemy, enemysShoot )
    if not SnapVecToGrid then
        SnapVecToGrid = terminator_Extras.SnapVecToGrid

    end
    local snappedCover = Vector( coverPos )
    local snappedShoot = Vector( enemysShoot )
    SnapVecToGrid( snappedCover, 16, 0 )
    SnapVecToGrid( snappedShoot, 16, 0 )
    local cacheStr = tostring( snappedCover ) .. tostring( snappedShoot )

    if not coverposCaches then
        coverposCaches = { [true] = {}, [false] = {} }
        terminator_Extras.terminator_csoldier_coverposCaches = coverposCaches -- put in _G for profilers
        timer.Simple( 30, function()
            coverposCaches = nil
            terminator_Extras.terminator_csoldier_coverposCaches = nil

        end )
    end

    local hasBrains = myTbl.HasBrains and true or false
    -- held locally, the timer can drop the global one while we yield
    local coverposCache = coverposCaches[ hasBrains ]
    local cached = coverposCache[ cacheStr ]
    if cached then
        return cached

    end

    local posIfStanding = coverPos + myTbl.GetViewOffset( self )

    local trStruc = {
        start = posIfStanding,
        endpos = enemysShoot,
        mask = MASK_SHOT,
        filter = { self, enemy },
    }

    coroutine_yield()

    local standingTr = util.TraceLine( trStruc )
    local willSeeEnemy = not standingTr.Hit or standingTr.Entity == enemy
    willSeeEnemy = willSeeEnemy and not standingTr.StartSolid

    local willSeeEnemyCrouching = willSeeEnemy
    if hasBrains then
        trStruc.start = coverPos + myTbl.GetCrouchViewOffset( self )

        coroutine_yield()
        local crouchingTr = util.TraceLine( trStruc )
        willSeeEnemyCrouching = not crouchingTr.Hit or crouchingTr.Entity == enemy
        willSeeEnemyCrouching = willSeeEnemyCrouching and not crouchingTr.StartSolid

    end

    if willSeeEnemy and not willSeeEnemyCrouching and coverPos.z >= ( entMeta.GetPos( self ).z + -40 ) then
        coverposCache[ cacheStr ] = COVER_SOFTCOVER
        return COVER_SOFTCOVER

    elseif not willSeeEnemy and not willSeeEnemyCrouching then
        if coverDebugging then debugoverlay.Line( posIfStanding, enemysShoot, 1, Color( 255, 0, 0 ), true ) end
        coverposCache[ cacheStr ] = COVER_HARDCOVER
        return COVER_HARDCOVER

    elseif hasBrains then -- brainy enemies can notice "crap" cover, otherwise treat all as no cover
        coroutine_yield()
        trStruc.start = coverPos + upCrapCover

        local crapCoverTr = util.TraceLine( trStruc )
        local notEvenCrapCover = not crapCoverTr.Hit or crapCoverTr.Entity == enemy
        notEvenCrapCover = notEvenCrapCover and not crapCoverTr.StartSolid
        if notEvenCrapCover then
            coverposCache[ cacheStr ] = COVER_NONE
            return COVER_NONE

        else
            coverposCache[ cacheStr ] = COVER_CRAPCOVER
            return COVER_CRAPCOVER

        end
    else
        coverposCache[ cacheStr ] = COVER_NONE
        return COVER_NONE

    end
end

local suppressedHealth = 35
local suppressedHealthMul = 35 / 100

function ENT:EnemyIsSuppressed( myTbl, enemy )
    myTbl = myTbl or entMeta.GetTable( self )
    enemy = enemy or myTbl.GetEnemy( self )
    if not IsValid( enemy ) then return false end

    local enemsSuppressedHealth = math.max( suppressedHealth, entMeta.GetMaxHealth( enemy ) * suppressedHealthMul )

    local enemyIsLowHealth = entMeta.Health( enemy ) <= enemsSuppressedHealth
    local enemyIsSuppressed = enemy.IsCrouching and enemy:IsCrouching() and enemy:OnGround() and enemy:GetVelocity():Length() <= 25

    return enemyIsLowHealth or enemyIsSuppressed

end

-- for positions from GetNearbyThreats, math.huge when there's none
local function nearestThreatDist( threats, pos )
    local nearestSqr = math.huge
    if not threats then return nearestSqr end
    for _, threatPos in ipairs( threats ) do
        local distSqr = pos:DistToSqr( threatPos )
        if distSqr < nearestSqr then
            nearestSqr = distSqr

        end
    end
    return math.sqrt( nearestSqr )

end

-- for ents from GetNearbyThreats, call right before building the path
local function avoidThreatAreas( self, myTbl, threatEnts, radius )
    if not threatEnts then return end
    for _, threatEnt in ipairs( threatEnts ) do
        if not IsValid( threatEnt ) then continue end
        local threatsArea = getEnemysArea( threatEnt )
        if IsValid( threatsArea ) then
            myTbl.flankAroundArea( self, threatsArea, radius )

        end
    end
end

local CROWD_COUNT = 2 -- this many others around our enemy and rushing in gets us swarmed

-- does our enemy have friends around it
-- always false for soldiers too dumb or too brave to care
local function enemyIsCrowded( self, myTbl, enemy )
    if not myTbl.HasBrains or myTbl.IsStupid or myTbl.TermSoldier_Fearless then return false end
    if not IsValid( enemy ) then return false end

    local enemysPos = entMeta.GetPos( enemy )
    local radiusSqr = ( myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.5 )^2
    local cur = CurTime()
    local count = 0
    for ent, memory in pairs( myTbl.m_EnemiesMemory ) do
        if ent == enemy or not IsValid( ent ) then continue end
        if cur - memory.lastupdate > 5 then continue end -- same staleness as GetNearbyThreats
        if memory.pos:DistToSqr( enemysPos ) > radiusSqr then continue end
        count = count + 1
        if count >= CROWD_COUNT then return true end

    end
    return false

end

local exposedTrOutput = {}
local exposedFilter = {}
local exposedTr = {
    mask = MASK_SHOT,
    filter = exposedFilter,
    output = exposedTrOutput,
}

-- can any threat see us at coverPos, even crouched
-- one trace per threat, so keep the list short
local function exposedToThreats( self, myTbl, coverPos, threats, threatEnts )
    if not threats then return false end
    exposedTr.start = coverPos + myTbl.GetCrouchViewOffset( self )
    exposedFilter[1] = self
    for i, threatPos in ipairs( threats ) do
        exposedFilter[2] = threatEnts[i]
        exposedTr.endpos = threatPos
        util.TraceLine( exposedTr )
        if not exposedTrOutput.Hit and not exposedTrOutput.StartSolid then return true end

    end
    return false

end

function ENT:PopulateWithAreaOccupiedCounts( myTbl, toPopulate )
    myTbl = myTbl or entMeta.GetTable( self )
    if not toPopulate or not istable( toPopulate ) then return end

    local hasBrains = myTbl.HasBrains
    local myShootPos = myTbl.GetShootPos( self )
    local spreadOutWeight = hasBrains and 1 or 0.1
    for i, ally in ipairs( myTbl.GetNearbyAllies( self ) ) do
        if i % 20 == 5 then
            coroutine_yield()

        end
        if not IsValid( ally ) then continue end
        local allysTbl = entMeta.GetTable( ally )
        if not terminator_Extras.PosCanSee( myShootPos, allysTbl.GetShootPos( ally ) ) then continue end

        local allyPathEndArea
        local allyArea = allysTbl.GetCurrentNavArea( ally, allysTbl )
        if math.random( 0, 100 ) < 50 and allysTbl.primaryPathIsValid( ally ) then
            allyPathEndArea = terminator_Extras.getNearestNav( allysTbl.GetPath( ally ):GetEnd() )

        end

        if IsValid( allyPathEndArea ) then
            local areaId = allyPathEndArea:GetID()
            local oldCount = toPopulate[ areaId ] or 1
            toPopulate[ areaId ] = oldCount + spreadOutWeight / 2

        end
        if IsValid( allyArea ) then
            local areaId = allyArea:GetID()
            local oldCount = toPopulate[ areaId ] or 1
            toPopulate[ areaId ] = oldCount + spreadOutWeight

        end
    end
end

local SQUAD_JOIN_DIST = 2000 -- anyone getting a new leader has to be this close to them
local SQUAD_LEAVE_DIST = 4500 -- same measure, bigger so nobody flickers in and out at the edge

-- mid push vote, pushing, or falling back, merging would throw that away
-- a squad of 1 has no orders to lose
local function squadBusy( squad )
    if #squad.members <= 1 then return false end
    local cur = CurTime()
    return squad.pushWanted ~= nil or ( squad.pushUntil or 0 ) > cur or ( squad.fallbackUntil or 0 ) > cur

end

local function allWithin( squad, pos, dist )
    for _, member in ipairs( squad.members ) do
        if entMeta.GetPos( member ):DistToSqr( pos ) > dist ^ 2 then return false end

    end
    return true

end

-- a nearby squad to fold ours into, nil if none fits
-- a soldier on their own is a squad of 1, so this is joining too
-- smaller goes into bigger, ties go to the lower EntIndex leader, so two leaders never pick each other
function ENT:TermSoldier_FindSquadToMerge( myTbl )
    local mySquad = myTbl.term_Squad
    if squadBusy( mySquad ) then return end -- only ours goes away, theirs can be busy

    local myCount = #mySquad.members
    local myPos = entMeta.GetPos( self )
    local myMaxHealth = entMeta.GetMaxHealth( self )
    local myIndex = entMeta.EntIndex( self )

    local best
    local bestDistSqr
    for squad in pairs( term_Squads.All ) do
        if squad == mySquad or squad.faction ~= mySquad.faction then continue end
        local leader = squad.leader
        if not IsValid( leader ) then continue end

        local count = #squad.members
        if count < myCount then continue end -- they come to us
        if count == myCount and entMeta.EntIndex( leader ) > myIndex then continue end

        local leaderMaxHealth = entMeta.GetMaxHealth( leader )
        if math.max( leaderMaxHealth, myMaxHealth ) > math.min( leaderMaxHealth, myMaxHealth ) * 10 then continue end -- too mismatched to fight together

        -- the toughest leads and ties keep theirs, see electLeader
        local newLeader = leader
        local gettingNewLeader = mySquad
        if myMaxHealth > leaderMaxHealth then
            newLeader = self
            gettingNewLeader = squad

        end
        if count + myCount - 1 > entMeta.GetTable( newLeader ).TermSoldier_MaxFollowers then continue end
        if not allWithin( gettingNewLeader, entMeta.GetPos( newLeader ), SQUAD_JOIN_DIST ) then continue end

        local distSqr = myPos:DistToSqr( entMeta.GetPos( leader ) )
        if not bestDistSqr or distSqr < bestDistSqr then
            best = squad
            bestDistSqr = distSqr

        end
    end
    return best

end

-- runs every few seconds, keeps us in a squad with soldiers we're near
-- followers stay put, leaders fold the whole squad into others, so squads don't steal each other's members
function ENT:TermSoldier_UpdateSquad( myTbl )
    local squad = myTbl.term_Squad
    if squad and squad.leader ~= self and entMeta.GetPos( self ):DistToSqr( entMeta.GetPos( squad.leader ) ) > SQUAD_LEAVE_DIST ^ 2 then
        term_Squads.Leave( self )
        squad = nil

    end
    squad = squad or term_Squads.Found( self ) -- on our own is a squad of 1
    if squad.leader ~= self then return end

    local toMerge = myTbl.TermSoldier_FindSquadToMerge( self, myTbl )
    if toMerge then
        term_Squads.Merge( toMerge, squad )

    end
end

-- our squad's leader, nil if we lead it or have no squad
function ENT:TermSoldier_GetLeader( myTbl )
    local squad = myTbl.term_Squad
    if not squad or squad.leader == self then return end
    return squad.leader

end

-- how many soldiers follow us, 0 if we don't lead
function ENT:TermSoldier_FollowerCount( myTbl )
    local squad = myTbl.term_Squad
    if not squad or squad.leader ~= self then return 0 end
    return #squad.members - 1

end

function ENT:AdditionalOnKilled()
    term_Squads.Leave( self ) -- dont let the squad follow a corpse

end

function ENT:LikesToSuppress( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    if myTbl.TermSoldier_Fearless then
        return false

    elseif IsValid( myTbl.TermSoldier_GetLeader( self, myTbl ) ) then
        return false

    else
        return ( self:GetCreationID() % 2 ) == 0

    end
end

local KILLZONE_DEATHS = 3 -- about three recent deaths in one spot
local CONTAIN_DEATHS = 6 -- too many to keep trying, wait for them to come out instead

-- deaths at the deadliest spot on our path, and that spot's area
local function killzoneAlongPath( self, myTbl )
    -- not primaryPathIsValid, that says yes while unstucking with no path at all
    local path = myTbl.GetPath( self, myTbl )
    if not path or not path:IsValid() then return 0 end

    local areas = {}
    for _, segment in ipairs( path:GetAllSegments() ) do
        areas[#areas + 1] = segment.area

    end
    return term_Heat.GetMaxAlong( "term_deaths", myTbl.isTerminatorHunterChummy, areas )

end

-- heat steers paths around killzones, but can't stop a path that has no other way in
function ENT:PathCrossesKillzone( myTbl )
    return killzoneAlongPath( self, myTbl ) >= KILLZONE_DEATHS

end

local function posInKillzone( myTbl, pos )
    local area = terminator_Extras.getNearestNav( pos )
    if not IsValid( area ) then return false end
    return term_Heat.Get( "term_deaths", myTbl.isTerminatorHunterChummy, area ) >= KILLZONE_DEATHS

end

local CONTAIN_MIN_DIST = 300 -- not right on top of it

-- somewhere near us with a view of watchPos, that isn't a killzone itself
-- nil if there's nowhere, the caller holds where it is
local function findContainSpot( self, myTbl, watchPos )
    local deaths = term_Heat.GetHeatTable( "term_deaths", myTbl.isTerminatorHunterChummy ) or noHeat
    local maxDist = myTbl.GetRealDuelEnemyDist( self, myTbl )
    local viewOffset = myTbl.GetViewOffset( self )
    local occupied = {}
    myTbl.PopulateWithAreaOccupiedCounts( self, myTbl, occupied )

    local scoreData = { blockRadiusEnd = true, decreasingScores = {} }
    local scoreFunction = function( _scoreData, area1, area2 )
        if area2:IsBlocked() or not myTbl.areaIsReachable( self, area2 ) then return 0 end
        local id = area2:GetID()
        if ( deaths[id] or 0 ) >= KILLZONE_DEATHS then return 0 end

        local score = ( scoreData.decreasingScores[area1:GetID()] or 1000 ) - 10 -- closest first
        scoreData.decreasingScores[id] = score
        if ( occupied[id] or 0 ) > 1 then return score end

        local center = area2:GetCenter()
        local dist = center:Distance( watchPos )
        if dist < CONTAIN_MIN_DIST or dist > maxDist then return score end

        coroutine_yield()
        if not terminator_Extras.PosCanSee( center + viewOffset, watchPos ) then return score end
        return math.huge

    end
    local pos, area = myTbl.findValidNavResult( self, scoreData, entMeta.GetPos( self ), maxDist, scoreFunction )
    if not IsValid( area ) then return end
    if not terminator_Extras.PosCanSee( pos + viewOffset, watchPos ) then return end -- ran out of options, it gave us its best guess
    return pos

end

local function canReach( self, myTbl, area )
    return area and myTbl.areaIsReachable( self, area )

end

local PUSH_SHARE = 0.5 -- push once this much of the squad wants to
local PUSH_WAIT = 10 -- or once someone's been waiting this long
local PUSH_TIME = 12 -- seconds rushing is allowed for, after the squad pushes

local KILLZONE_ENGAGED_TIME = 20 -- how long being stopped by a killzone counts as being in the fight

local CONTACT_TIME = 20 -- how long the squad remembers where one of them last saw an enemy
local CONTACT_ARRIVED_DIST = 500 -- we're already there, nothing to go help with

local FANOUT_LEG_TIME = 10 -- fanout gives up after this long per leg
local FANOUT_LEAD_AGE = 5 -- fanout's already searching, only a sighting this fresh is worth dropping it for

local INVESTIGATE_TIME = 30 -- how long something the squad heard is worth checking out
local INVESTIGATE_ARRIVED_DIST = 300

local FALLBACK_HEALTH = 0.4 -- fall back once the squad's down to this share of its health
local FALLBACK_TIME = 14
local FALLBACK_BACKUP_TIME = 5 -- backthehellup keeps going past this while they're still close

-- in a squad that can tell us what to do, nil for soldiers on their own
local function orderableSquad( self, myTbl )
    if not myTbl.TermSoldier_CanBeOrdered( self, myTbl ) then return end
    local squad = myTbl.term_Squad
    if not squad or #squad.members <= 1 then return end
    return squad

end

local function fallingBack( squad )
    return ( squad.fallbackUntil or 0 ) > CurTime()

end

-- where our squad last saw an enemy, nil if it's old news or we're already there
-- ally informs only come from someone who can see the enemy right now, this covers the gaps
-- maxAge can only make it pickier than CONTACT_TIME
local function squadContactPos( self, myTbl, maxAge )
    local squad = orderableSquad( self, myTbl )
    local contactPos = squad and squad.contactPos
    if not contactPos or squad.contactTime + math.min( maxAge or CONTACT_TIME, CONTACT_TIME ) < CurTime() then return end
    if fallingBack( squad ) then return end
    if entMeta.GetPos( self ):DistToSqr( contactPos ) < CONTACT_ARRIVED_DIST ^ 2 then return end
    if not myTbl.areaIsReachable( self, squad.contactArea ) then return end -- or intercept gives up and we come right back
    return contactPos

end

-- where our squad heard something worth checking out, nil if it's old news
-- squads of 1 count, it's their own ears
local function squadInvestigatePos( self, myTbl )
    local squad = myTbl.term_Squad
    local pos = squad and squad.investigatePos
    if not pos or squad.investigateTime + INVESTIGATE_TIME < CurTime() then return end
    if not myTbl.areaIsReachable( self, squad.investigateArea ) then return end
    return pos

end

-- someone else saw an enemy in the last maxAge seconds, returns the why and whyData to decide with
-- nil if nobody did
local function allyLead( self, myTbl, maxAge )
    if myTbl.lastInterceptPos and myTbl.lastInterceptReachable and myTbl.lastInterceptTime > CurTime() - maxAge then
        return "allyspotted"

    end
    local contactPos = squadContactPos( self, myTbl, maxAge )
    if contactPos then return "squadcontact", contactPos end

end

-- soldiers in a squad rush together or not at all, one at a time is how they end up in a pile on the stairs
local function squadAllowsRush( self, myTbl )
    local squad = orderableSquad( self, myTbl )
    if not squad then return true end
    return ( squad.pushUntil or 0 ) > CurTime() and not fallingBack( squad )

end

local function wantPush( self, squad )
    squad.pushWanted = squad.pushWanted or {}
    squad.pushWanted[self] = squad.pushWanted[self] or CurTime()

end

-- squad orders skip soldiers without brains, and anyone a player is driving
function ENT:TermSoldier_CanBeOrdered( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    return myTbl.HasBrains and not self:IsControlledByPlayer()

end

-- close enough to our enemy to be in the fight, further out a rush is just closing the distance
-- a killzone in the way counts too, that's the front line, see killzoneahead
function ENT:TermSoldier_IsEngaged( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    if not IsValid( myTbl.GetEnemy( self ) ) then return false end
    if ( myTbl.term_KillzoneEngagedUntil or 0 ) > CurTime() then return true end
    return myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl )

end

-- who counts towards a push, and who gets pulled into one
-- containing soldiers stay put, they're watching a killzone that's too hot to push through
function ENT:TermSoldier_CanPush( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    if not myTbl.TermSoldier_CanBeOrdered( self, myTbl ) then return false end
    if myTbl.IsTaskActive( self, "movement_contain" ) then return false end
    return myTbl.TermSoldier_IsEngaged( self, myTbl )

end

-- the freshest enemy sighting anyone in the squad has
local function updateContact( squad )
    local bestTime
    local bestPos
    for _, member in ipairs( squad.members ) do
        local membersTbl = entMeta.GetTable( member )
        local spotTime = membersTbl.LastEnemySpotTime
        if not spotTime or ( bestTime and spotTime <= bestTime ) then continue end
        if not IsValid( membersTbl.GetEnemy( member ) ) then continue end
        bestTime = spotTime
        bestPos = membersTbl.EnemyLastPos

    end
    if not bestPos then return end
    squad.contactPos = bestPos
    squad.contactArea = terminator_Extras.getNearestNav( bestPos ) -- here so members don't each look it up every tick
    squad.contactTime = bestTime

end

-- the freshest worthwhile thing anyone in the squad heard, gunfire and the like
-- weaker than contact, we go take a look instead of going in shooting
local function updateInvestigate( squad )
    if squad.contactPos and squad.contactTime + CONTACT_TIME > CurTime() then
        squad.investigatePos = nil -- already fighting, whatever we heard is probably them
        return

    end
    local bestTime = squad.investigateTime or -math.huge -- so a sound we already checked doesn't come back
    local bestPos
    for _, member in ipairs( squad.members ) do
        local hint = entMeta.GetTable( member ).lastHeardSoundHint
        if not hint or not hint.valuable or hint.time <= bestTime then continue end
        bestTime = hint.time
        bestPos = hint.source

    end
    if not bestPos then return end
    squad.investigatePos = bestPos
    squad.investigateArea = terminator_Extras.getNearestNav( bestPos )
    squad.investigateTime = bestTime

end

local function thinkPush( squad )
    if not squad.pushWanted then return end

    local cur = CurTime()
    if ( squad.pushUntil or 0 ) > cur or fallingBack( squad ) then return end

    local canPush, wanting, since = term_Squads.PushVotes( squad )
    if wanting <= 0 then -- everyone who wanted it left, or isn't in the fight anymore
        squad.pushWanted = nil
        return

    end

    local enoughWant = wanting >= canPush * PUSH_SHARE
    local waitedEnough = since + PUSH_WAIT < cur
    if not enoughWant and not waitedEnough then return end

    squad.pushWanted = nil
    squad.pushUntil = cur + PUSH_TIME

    for _, member in ipairs( squad.members ) do
        local membersTbl = entMeta.GetTable( member )
        if not membersTbl.TermSoldier_CanPush( member, membersTbl ) then continue end
        if membersTbl.IsTaskActive( member, "movement_rushsmartandshoot" ) then continue end

        membersTbl.KillAllTasksWith( member, "movement" )
        membersTbl.TermSoldier_Decide( member, membersTbl, nil, "squadpush" )
        member:RestartMotionCoroutine()

    end
end

-- the squad's been torn up, everyone backs off then regroups
-- health is measured against the most the squad had this fight, so deaths count, not just wounds
local function thinkFallback( squad )
    local cur = CurTime()
    if squad.fallbackUntil then
        if squad.fallbackUntil > cur then return end
        squad.fallbackUntil = nil
        squad.peakMaxHealth = nil -- whoever's left is the squad now, or we'd fall back again straight away

    end

    local health = 0
    local maxHealth = 0
    for _, member in ipairs( squad.members ) do
        health = health + math.max( entMeta.Health( member ), 0 )
        maxHealth = maxHealth + entMeta.GetMaxHealth( member )

    end

    local contactPos = squad.contactPos
    if not contactPos or squad.contactTime + CONTACT_TIME < cur then -- not fighting, start counting from here next fight
        squad.peakMaxHealth = maxHealth
        return

    end
    squad.peakMaxHealth = math.max( squad.peakMaxHealth or 0, maxHealth )
    if #squad.members <= 1 or health >= squad.peakMaxHealth * FALLBACK_HEALTH then return end

    squad.fallbackUntil = cur + FALLBACK_TIME
    squad.pushWanted = nil
    squad.pushUntil = nil

    for _, member in ipairs( squad.members ) do
        local membersTbl = entMeta.GetTable( member )
        if membersTbl.TermSoldier_Fearless then continue end
        if not membersTbl.TermSoldier_CanBeOrdered( member, membersTbl ) then continue end

        membersTbl.KillAllTasksWith( member, "movement" )
        membersTbl.TermSoldier_Decide( member, membersTbl, nil, "fallback" )
        member:RestartMotionCoroutine()

    end
end

-- once a second on the squad's leader, see sv_squads.lua
function ENT:TermSoldier_SquadThink()
    local squad = entMeta.GetTable( self ).term_Squad
    if not squad then return end
    updateContact( squad )
    updateInvestigate( squad )
    thinkFallback( squad )
    thinkPush( squad )

end

-- what each why leads to, returns task, reason, task data
-- whyData is whatever the task knows that we can't work out here, the comment on each why says what it is
local whyChoices = {
    -- seeing, finding, losing the enemy
    spottedenemy = function()
        return "movement_handler", "i found an enemy!"

    end,
    allyspotted = function()
        return "movement_intercept", "one of my buddies found an enemy!"

    end,
    seeenemyagain = function( _self, myTbl )
        if myTbl.HasBrains then
            return "movement_shootfromcover", "i can see em again!"

        end
        return "movement_standandshoot", "durr i can see em again!"

    end,
    noenemy = function()
        return "movement_handler", "i lost my enemy!"

    end,
    lostsight = function()
        return "movement_standandshoot", "durr i cant see them"

    end,
    arrivedenemygone = function()
        return "movement_fanout", "damn, i lost them!"

    end,
    -- whyData is where the task thinks the enemy is, it may be an old position
    lostenemypathdone = function( self, myTbl, enemysNav )
        if canReach( self, myTbl, enemysNav ) then
            return "movement_rushsmartandshoot", "i lost my enemy, ill flank to where i last saw em!"

        end
        return "movement_handler", "got to the end of my path and i've lost my enemy!"

    end,
    -- whyData is where the task thinks the enemy is, it may be an old position
    lostenemy = function( self, myTbl, enemysNav )
        local enemy = myTbl.GetEnemy( self )
        local goodEnemy = IsValid( enemy ) and entMeta.Health( enemy ) > 0
        if goodEnemy and canReach( self, myTbl, enemysNav ) then
            return "movement_rushsmartandshoot", "i haven't seen my enemy in a bit, i'll flank to where i last saw em!"

        elseif enemysNav and not myTbl.areaIsReachable( self, enemysNav ) then
            return "movement_fanout", "i lost my enemy in an unreachable spot!"

        elseif not myTbl.HasBrains then
            return "movement_approachenemy", "i lost my enemy, ill go where i last saw em"

        end
        return "movement_handler", "i haven't seen my enemy in a bit!"

    end,
    rushlostenemy = function()
        return "movement_handler", "i lost my enemy!"

    end,
    killedenemy = function( _self, myTbl )
        return "movement_fanout", "i killed my enemy!", { Count = 1, FanDistance = myTbl.DistToEnemy }

    end,
    fanoutdone = function()
        return "movement_patrol", "ok i have no idea where they are"

    end,

    -- getting to the enemy
    approached = function( _self, myTbl )
        if myTbl.HasBrains then
            return "movement_shootfromcover", "i have approached my enemy!"

        end
        return "movement_walkslowtowardsenemy", "durr i have approached my enemy!"

    end,
    enemyreachable = function()
        return "movement_walkslowtowardsenemy", "durr my enemy is reachable now"

    end,
    enemyunreachable = function( _self, _myTbl, _whyData, currentTask )
        if currentTask == "movement_walkslowtowardsenemy" then
            return "movement_standandshoot", "durr i can't walk slow to my enemy, they're unreachable"

        end
        return "movement_fanout", "i lost my enemy in an unreachable spot!"

    end,
    nosimplepath = function( self, myTbl )
        -- approachenemy would just call this approached and send us straight back
        if myTbl.IsSeeEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) then
            return "movement_standandshoot", "durr i cant get any closer, ill shoot from here"

        end
        return "movement_approachenemy", "durr i couldnt find a simple way to the enemy"

    end,
    pathstuck = function()
        return "movement_handler", "something failed"

    end,
    -- whyData is where to look, the spot our buddy saw them
    interceptvisible = function( _self, myTbl, lookAt )
        if myTbl.HasBrains then
            return "movement_shootfromcover", "my buddy found an enemy, im gonna shoot them from here!"

        end
        return "movement_standandshoot", "durr my buddy found an enemy and i can see them!", { LookAt = lookAt }

    end,
    interceptdud = function()
        return "movement_fanout", "this intercept was a dud!", { Count = 1 }

    end,
    -- in a squad, ask to cross it, the rush gate holds us until everyone goes together
    -- too deadly to cross at all, watch it instead, heat fades so we'll try again later
    killzoneahead = function( self, myTbl )
        local deaths, killzone = killzoneAlongPath( self, myTbl )
        if deaths >= CONTAIN_DEATHS and IsValid( killzone ) then
            local watchPos = killzone:GetCenter() + myTbl.GetViewOffset( self )
            return "movement_contain", "too many of us died getting in there, ill wait for them to come out", { WatchPos = watchPos }

        end
        if not orderableSquad( self, myTbl ) then
            return "movement_shootfromcover", "my buddies keep dying on the way there, im holding here"

        end
        myTbl.term_KillzoneEngagedUntil = CurTime() + KILLZONE_ENGAGED_TIME
        return "movement_rushsmartandshoot", "my buddies keep dying on the way there, we go together"

    end,

    -- rushing
    enemysuppressed = function()
        return "movement_rushsmartandshoot", "enemy is low health, rush and shoot!"

    end,
    flankchance = function()
        return "movement_rushsmartandshoot", "i feel like flanking my enemy"

    end,
    outofrange = function()
        return "movement_rushsmartandshoot", "i'm way too far from this guy"

    end,
    nocover = function()
        return "movement_rushsmartandshoot", "i couldnt find a good cover position!"

    end,
    notsuppressed = function()
        return "movement_shootfromcover", "they aren't suppressed anymore!"

    end,

    -- squad
    squadpush = function()
        return "movement_rushsmartandshoot", "my squad is pushing!"

    end,
    holdover = function()
        return "movement_handler", "im done waiting for my squad"

    end,
    holdhurt = function()
        return "movement_shootfromcover", "im getting shot while i wait, finding better cover"

    end,
    fallback = function()
        local data = {
            BackupUntil = CurTime() + FALLBACK_BACKUP_TIME,
            AfterwardsTask = "movement_regroup",
        }
        return "movement_backthehellup", "we're getting torn apart, fall back!", data

    end,
    fallbackover = function()
        return "movement_handler", "regrouped, back at it"

    end,
    containover = function()
        return "movement_handler", "nobody came out, time to rethink"

    end,
    -- whyData is where the squad last saw them
    squadcontact = function( _self, _myTbl, contactPos )
        return "movement_intercept", "my squad's fighting, im going to help", { InterceptPos = contactPos }

    end,
    -- whyData is where we heard it
    heardsomething = function( _self, _myTbl, heardPos )
        return "movement_investigate", "i heard something, going to take a look", { Pos = heardPos }

    end,
    investigated = function()
        return "movement_fanout", "nothing here, ill look around", { Count = 1 }

    end,
    investigatedud = function()
        return "movement_patrol", "i couldnt get to where i heard it"

    end,
    rushedclose = function()
        return "movement_shootfromcover", "i rushed them, time to back off for a bit"

    end,
    -- also where decide sends any rush at a crowded enemy
    crowded = function( self, myTbl )
        if myTbl.TermSoldier_IsEngaged( self, myTbl ) then
            return "movement_shootfromcover", "they've got friends, im picking em off from here"

        end
        return "movement_approachenemy", "they've got friends, getting in range first"

    end,

    -- suppressing
    suppresschance = function( _self, myTbl )
        if myTbl.HasBrains then
            return "movement_suppress", "i feel like supressing my enemy"

        end
        return "movement_suppress", "durr, no enemy to shoot at, i'll shoot where i last saw them!"

    end,
    suppressdone = function( _self, myTbl )
        if myTbl.HasBrains then
            return "movement_approachenemy", "im done suppressing"

        end
        return "movement_standandshoot", "durr im done suppressing"

    end,
    suppressspothidden = function( _self, myTbl )
        if myTbl.HasBrains then
            return "movement_approachenemy", "i cant see where i last saw em"

        end
        return "movement_standandshoot", "durr i cant see where i last saw em"

    end,
    allyinway = function()
        return "movement_approachenemy", "durr one of my dumb allies got in the way, no more suppress"

    end,
    tooclosetosuppress = function()
        return "movement_handler", "durr im too close to what i want to suppress"

    end,
    nostandpos = function()
        return "movement_handler", "durr i can't find somewhere to shoot my enemy"

    end,

    -- staying alive
    tooclosehurt = function()
        return "movement_backthehellup", "i gotta back up, they're tearing me apart!"

    end,
    exposedhurt = function()
        return "movement_backthehellup", "i'm too exposed and i got hurt!"

    end,
    tooclose = function()
        return "movement_backthehellup", "im way too close to em"

    end,
    -- whyData is the danger sound hint
    -- the backup task starts afterwards itself, so it skips the rush gate in decide, check it here
    grenade = function( self, myTbl, scarySound )
        local afterwards = "movement_standandshoot"
        if myTbl.HasBrains and squadAllowsRush( self, myTbl ) then
            afterwards = "movement_rushsmartandshoot"

        elseif myTbl.HasBrains then
            afterwards = "movement_handler"

        end
        local backupData = {
            BackupFromPos = scarySound.origin,
            BackupFromEnt = scarySound.owner,
            BackupUntil = scarySound.expiration + 1,
            AfterwardsTask = afterwards,
        }
        return "movement_backthehellup_frompos", "aaaah! grenade!", backupData

    end,
}

-- what to do when there's no why, or the task just wants a fresh look at things
local function chooseGeneral( self, myTbl )
    local enemy = myTbl.GetEnemy( self )
    local canIntercept = myTbl.lastInterceptPos and myTbl.lastInterceptReachable and myTbl.lastInterceptTime > ( CurTime() - 5 ) -- last intercept pos is valid and was set less than 5 seconds ago
    local enemyLastPos = myTbl.EnemyLastPos

    if IsValid( myTbl.Target ) then
        return "movement_followtarget", "something wants me to follow a target!"

    elseif IsValid( enemy ) then
        if coroutine_running() then coroutine_yield() end -- may be called outside the motion coroutine
        local distToEnemy = myTbl.DistToEnemy
        if myTbl.IsSeeEnemy then
            local hasBrains = myTbl.HasBrains
            local enemysNav = terminator_Extras.getNearestNav( entMeta.GetPos( enemy ) )
            local reachable = myTbl.areaIsReachable( self, enemysNav )
            if myTbl.TermSoldier_Fearless then
                return "movement_approachenemy", "i have an enemy and im fearless!"

            elseif hasBrains and ( not reachable or distToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) ) then
                return "movement_shootfromcover", "i have an enemy and im close to em!"

            elseif not hasBrains and not reachable then
                return "movement_standandshoot", "durr i have an enemy but i cant reach them!"

            elseif not hasBrains and reachable then
                return "movement_walkslowtowardsenemy", "durr im gonna walk to my enemy"

            end
            return "movement_approachenemy", "i have an enemy and im not close!"

        elseif canIntercept and myTbl.lastInterceptPos:Distance( myTbl.EnemyLastPos ) < 1500 then
            return "movement_intercept", "i dont see my enemy but my buddy says they do!"

        end
        return "movement_approachenemy", "i have an enemy but i dont see them!"

    elseif canIntercept then
        return "movement_intercept", "one of my buddies spotted an enemy, ill intercept!"

    elseif myTbl.TimeSinceEnemySpotted( self, myTbl ) < 15 and ( not enemyLastPos or entMeta.GetPos( self ):Distance( enemyLastPos ) > 350 ) then
        return "movement_approachenemy", "I just saw them right there!"

    end
    local contactPos = squadContactPos( self, myTbl )
    if contactPos then
        return whyChoices.squadcontact( self, myTbl, contactPos )

    end
    local heardPos = squadInvestigatePos( self, myTbl )
    if heardPos then
        return whyChoices.heardsomething( self, myTbl, heardPos )

    end
    return "movement_patrol", "i have no enemy!"

end

-- what a falling back squad won't do, see thinkFallback
local closingIn = {
    ["movement_approachenemy"] = true,
    ["movement_rushsmartandshoot"] = true,
    ["movement_intercept"] = true,
}

local function decide( self, myTbl, currentTask, why, whyData, failed )
    local task, reason, data
    local whyChoice = why and whyChoices[why]
    if whyChoice then
        task, reason, data = whyChoice( self, myTbl, whyData, currentTask )

    else
        if why then ErrorNoHaltWithStack( "TermSoldier_Decide got an unknown why \"" .. tostring( why ) .. "\"" ) end
        task, reason, data = chooseGeneral( self, myTbl )

    end

    -- before the squad gate, so a rush we wont take doesn't vote for a push
    if task == "movement_rushsmartandshoot" and enemyIsCrowded( self, myTbl, myTbl.GetEnemy( self ) ) then
        task, reason, data = whyChoices.crowded( self, myTbl )

    end

    if task == "movement_rushsmartandshoot" and not squadAllowsRush( self, myTbl ) then
        if myTbl.TermSoldier_IsEngaged( self, myTbl ) then
            wantPush( self, myTbl.term_Squad )
            task, reason, data = "movement_squadhold", "waiting for my squad to push", nil

        else -- approachenemy stops at duel range, then we're engaged and wait with everyone else
            task, reason, data = "movement_approachenemy", "closing in, my squad pushes together", nil

        end
    end

    -- after the squad gate, it turns rushes into approaches
    if closingIn[task] and not myTbl.TermSoldier_Fearless then
        local squad = orderableSquad( self, myTbl )
        if squad and fallingBack( squad ) then
            task, reason, data = "movement_regroup", "we're falling back, not closing in", nil

        end
    end

    if failed then
        myTbl.TaskFail( self, currentTask )

    else
        myTbl.TaskComplete( self, currentTask )

    end
    myTbl.StartTask( self, task, data, reason )
    return true

end

function ENT:TermSoldier_Decide( myTbl, currentTask, why, whyData )
    -- every soldier task change should go through here, it completes currentTask and starts the next one
    -- use TermSoldier_DecideFailed when currentTask didn't do its job
    -- why is what the task saw happen, see whyChoices, nil for a fresh look
    -- currentTask can be nil if the caller already ended its tasks
    -- returns true if it switched, return right after calling it
    return decide( self, myTbl, currentTask, why, whyData, false )

end

function ENT:TermSoldier_DecideFailed( myTbl, currentTask, why, whyData )
    -- TermSoldier_Decide, but fails currentTask
    return decide( self, myTbl, currentTask, why, whyData, true )

end

local CONTAIN_SPOT_DIST = 50

-- path to pos and take a step along it, false if there's no way there
-- give avoidPos to go around it, like where the enemy was
local function walkTowards( self, myTbl, data, pos, avoidPos )
    if data.NextNewPath < CurTime() and myTbl.primaryPathInvalidOrOutdated( self, pos ) then
        data.NextNewPath = CurTime() + 1
        myTbl.InvalidatePath( self, "new path to walk towards" )
        local avoidArea = avoidPos and terminator_Extras.getNearestPosOnNav( avoidPos ).area
        if IsValid( avoidArea ) then
            myTbl.SetupFlankingPath( self, pos, avoidArea, entMeta.GetPos( self ):Distance( avoidPos ) * 0.8 )

        else
            myTbl.SetupPathShell( self, pos )

        end
        if not myTbl.primaryPathIsValid( self ) then return false end

    end
    coroutine_yield()
    myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )
    return true

end

function ENT:CanSuppress( myTbl )
    return terminator_Extras.PosCanSeeComplex( self:GetShootPos(), myTbl.LastEnemyShootPos, self )

end

local LastFileSaveTime
local developer = GetConVar( "developer" )
if developer:GetBool() then
    LastFileSaveTime = SysTime()

end

function ENT:DoCustomTasks( defaultTasks )
    self.TaskList = {
        ["enemy_handler"] = defaultTasks["enemy_handler"],
        ["shooting_handler"] = defaultTasks["shooting_handler"],
        ["awareness_handler"] = defaultTasks["awareness_handler"],
        ["reallystuck_handler"] = defaultTasks["reallystuck_handler"],

        ["inform_handler"] = defaultTasks["inform_handler"],
        ["movement_wait"] = defaultTasks["movement_wait"],
        ["movement_getweapon"] = defaultTasks["movement_getweapon"],
        ["movement_followtarget"] = defaultTasks["movement_followtarget"],
        ["movement_backthehellup"] = defaultTasks["movement_backthehellup"],
        ["movement_backthehellup_frompos"] = defaultTasks["movement_backthehellup_frompos"],

        ["soldier_fearsounds_handler"] = {
            StartsOnInitialize = true,
            StopsWhenPlayerControlled = true,
            OnStart = function( self, data )
                data.nextSoundListen = 0

            end,
            BehaveUpdatePriority = function( self, data )
                if data.nextSoundListen > CurTime() then return end
                data.nextSoundListen = CurTime() + math.Rand( 0.5, 1 )

                local scarySound = sound.GetLoudestSoundHint( SOUND_DANGER, entMeta.GetPos( self ) )
                if not scarySound then return end
                if not IsValid( scarySound.owner ) then return end

                local myTbl = entMeta.GetTable( self )

                myTbl.KillAllTasksWith( self, "movement" )
                myTbl.TermSoldier_Decide( self, myTbl, nil, "grenade", scarySound )
                self:RestartMotionCoroutine()

            end,
        },

        ["soldier_heat_handler"] = {
            StartsOnInitialize = true,
            OnStart = function( self, data )
                data.nextHeatUpdate = 0

            end,
            BehaveUpdatePriority = function( self, data )
                if data.nextHeatUpdate > CurTime() then return end
                data.nextHeatUpdate = CurTime() + 1

                local myTbl = entMeta.GetTable( self )
                local faction = myTbl.isTerminatorHunterChummy
                if myTbl.IsSeeEnemy then
                    local enemy = myTbl.GetEnemy( self )
                    if not IsValid( enemy ) then return end
                    term_Heat.AddToArea( "soldier_enemyseen", faction, getEnemysArea( enemy ), 1 )

                else
                    term_Heat.AddToArea( "soldier_searched", faction, myTbl.GetCurrentNavArea( self, myTbl ), 1 )

                end
            end,
        },

        ["soldier_meleeattack_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            StopsWhenPlayerControlled = true,
            OnStart = function( self, data )
                data.NextMeleeAttack = 0

            end,
            BehaveUpdatePriority = function( self, data )
                local myTbl = entMeta.GetTable( self )
                if not myTbl.TermSoldier_CanMeleeAttack then
                    myTbl.TaskComplete( self, "soldier_meleeattack_handler" )
                    return

                end

                if not myTbl.IsSeeEnemy then return end
                if myTbl.DistToEnemy > myTbl.TermSoldier_MeleeAttackRange * math.Rand( 1, 1.25) then return end

                if data.NextMeleeAttack > CurTime() then
                    return

                end

                local delay = ( myTbl.SpecialActions["TermSoldier_Melee"].ratelimit or 1 ) * 1.1
                data.NextMeleeAttack = CurTime() + delay

                if math.random( 0, 100 ) < 15 then -- dont melee attack every time
                    return

                end

                myTbl.PreventShooting = true
                timer.Simple( delay, function()
                    if not IsValid( self ) then return end
                    myTbl.PreventShooting = nil

                end )
                self:TakeAction( "TermSoldier_Melee" )

            end,
        },

        ["soldier_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            StopsWhenPlayerControlled = true,
            CanPickupWeapon = function( self, _data, wep )
                -- whoever dropped it died there, it's bait
                if posInKillzone( entMeta.GetTable( self ), entMeta.GetPos( wep ) ) then return false end

            end,
            OnStart = function( self, data )
                if developer:GetBool() then
                    permaPrint( LastFileSaveTime )

                end
                -- custom anim translation support
                local IdleActivity = ACT_HL2MP_IDLE_PASSIVE
                data.passiveTranslations = {
                    [ACT_MP_STAND_IDLE]                 = IdleActivity,
                    [ACT_MP_WALK]                       = IdleActivity + 1,
                    [ACT_MP_RUN]                        = IdleActivity + 2,
                    [ACT_MP_CROUCH_IDLE]                = IdleActivity + 3,
                    [ACT_MP_CROUCHWALK]                 = IdleActivity + 4,
                    [ACT_MP_ATTACK_STAND_PRIMARYFIRE]   = IdleActivity + 5,
                    [ACT_MP_ATTACK_CROUCH_PRIMARYFIRE]  = IdleActivity + 5,
                    [ACT_MP_RELOAD_STAND]               = IdleActivity + 6,
                    [ACT_MP_RELOAD_CROUCH]              = IdleActivity + 7,
                    [ACT_MP_SWIM]                       = IdleActivity + 9,
                }

                data.nextSquadUpdate = CurTime()

            end,
            TranslateActivity = function( self, data, act )
                local myTbl  = entMeta.GetTable( self )

                if self:IsControlledByPlayer() then return end
                if IsValid( myTbl.GetEnemy( self ) ) then return end
                if myTbl.IsAngry( self ) then return end
                if myTbl.TimeSinceEnemySpotted( self, myTbl ) < 4 + ( entMeta.GetCreationID( self ) % 5 ) then return end

                if not myTbl.ShouldWalk( self, myTbl ) and myTbl.ShouldRun( self, myTbl ) then return end

                local translation = data.passiveTranslations[act]
                if translation then return translation end

            end,
            BehaveUpdatePriority = function( self, data )
                local myTbl = entMeta.GetTable( self )
                if not myTbl.HasBrains then return end

                if data.nextSquadUpdate > CurTime() then return end
                data.nextSquadUpdate = CurTime() + 5

                myTbl.TermSoldier_UpdateSquad( self, myTbl )

            end,
            -- TODO; death sounds and stuff
        },

        -- custom movement starter
        ["movement_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            OnStart = function( self, data )
                if self.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.01, 0.05 ) -- wait a bit before starting this task

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.5 ) -- wait a bit before starting this task

                end
            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.WAIT )

                end
                local myTbl  = entMeta.GetTable( self )
                local canWep, potentialWep = myTbl.canGetWeapon( self )
                if canWep and self:getTheWeapon( "movement_handler", potentialWep ) then
                    return

                end
                myTbl.TermSoldier_Decide( self, myTbl, "movement_handler" )

            end,
        },

        -- approach enemy or their last known position
        ["movement_approachenemy"] = {
            OnStart = function( self, data )
                data.Unreachable = false
                data.DontGetWepsForASec = CurTime() + 1
                data.ApproachAfter = CurTime() + 0.5
                data.NextPathBuild = 0
                self:InvalidatePath( "starting approachenemy" )

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local enemy = myTbl.GetEnemy( self )

                local toPos = myTbl.EnemyLastPos
                if IsValid( enemy ) then
                    toPos = entMeta.GetPos( enemy )

                end

                coroutine_yield()

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_approachenemy", potentialWep ) then
                    return

                end

                coroutine_yield()

                local somewhereToPathTo = toPos and not data.Unreachable
                local canDoNewPath = somewhereToPathTo and myTbl.primaryPathInvalidOrOutdated( self, toPos )
                if canDoNewPath and data.NextPathBuild < CurTime() then

                    coroutine_yield()
                    data.NextPathBuild = CurTime() + math.Rand( 0.1, 0.25 )
                    local snappedResult = terminator_Extras.getNearestPosOnNav( toPos )
                    local posOnNav = snappedResult.pos

                    local reachable = myTbl.areaIsReachable( self, snappedResult.area )
                    if not reachable then data.Unreachable = true return end

                    myTbl.InvalidatePath( self, "new approachenemy path" )
                    coroutine_yield()

                    -- try and approach from a different entrance
                    local otherHuntersHalfwayPoint
                    if myTbl.HasBrains then
                        otherHuntersHalfwayPoint = myTbl.GetOtherHuntersProbableEntrance( self )

                    end

                    if otherHuntersHalfwayPoint then
                        myTbl.SetupFlankingPath( self, posOnNav, snappedResult.area )
                        if not myTbl.primaryPathIsValid( self ) then data.Unreachable = true return end

                    end
                    coroutine_yield()

                    if not myTbl.primaryPathIsValid( self ) then
                        myTbl.SetupPathShell( self, posOnNav )
                        if not myTbl.primaryPathIsValid( self ) then data.Unreachable = true return end

                    end
                    coroutine_yield()

                    if myTbl.HasBrains and not myTbl.TermSoldier_Fearless and myTbl.PathCrossesKillzone( self, myTbl ) then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_approachenemy", "killzoneahead" )
                        return

                    end
                end

                local result = myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )

                coroutine_yield()

                local givenItAChance = data.ApproachAfter < CurTime() -- this schedule didn't JUST start.

                -- get WEAP
                if not IsValid( myTbl.GetWeapon( self ) ) then
                    canWep, potentialWep = myTbl.canGetWeapon( self )

                end
                if canWep and data.DontGetWepsForASec < CurTime() and self:getTheWeapon( "movement_approachenemy", potentialWep, "movement_approachenemy" ) then
                    return

                elseif ( self:MyPathLength() < 50 and Distance2D( self:GetPos(), self:GetPath():GetEnd() ) < 300 ) and givenItAChance then -- catch bot bugging out at an unreachable spot or something
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_approachenemy", "pathstuck" )

                elseif data.Unreachable then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_approachenemy", "enemyunreachable" )

                elseif result == true and not myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_approachenemy", "arrivedenemygone" )

                elseif not myTbl.TermSoldier_Fearless and myTbl.IsSeeEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) then
                    if myTbl.term_ExpensivePath and myTbl.DistToEnemy * 1.15 > myTbl.GetPath( self ):GetLength() then return end -- if it's an important path, dont waste it
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_approachenemy", "approached" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },

        -- take soft cover, duel enemy
        ["movement_shootfromcover"] = {
            OnStart = function( self, data )
                self:InvalidatePath( "new shootfromcover path" )
                data.CurrentTaskGoalPos = nil
                data.GoalWasEverGood = nil
                data.GoalPosFailures = 0
                data.NextNewPath = 0
                data.NeedsToChangePositions = nil
                data.OverusedAreaIds = {}

                data.NextTooCloseCheck = CurTime() + 0.25
                data.LastSpottedDiv = 1 -- increase if you want it to do covering for longer
                data.NextCoverposFind = 0
                data.NextThreatsRefresh = 0
                data.NextAllowedRush = data.NextAllowedRush or CurTime() + 3 -- time until we can rush the enemy again
                data.cachedAllHardcoverAreas = {}

            end,
            OnAllyTakingCoverBehindMe = function( self, data )
                data.NeedsToChangePositions = true

            end,
            OnKillEnemy = function( self, data )
                data.killedOurEnemy = true

            end,
            OnInstantKillEnemy = function( self, data )
                data.killedOurEnemy = true

            end,
            OnDamaged = function( self, data ) -- break out of our trance!
                local myTbl  = entMeta.GetTable( self )
                if myTbl and myTbl.NothingOrBreakableBetweenEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.2 and myTbl.getLostHealth( self ) >= 5 then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_shootfromcover", "exposedhurt" )
                    self:RestartMotionCoroutine()

                end
            end,
            BehaveUpdatePriority = function( self, data ) -- bit of a hack, never stand still and "just take enemy shooting us"
                local myTbl = entMeta.GetTable( self )
                if not myTbl then return end -- ?????
                if not myTbl.HasBrains then return end
                if not myTbl.IsSeeEnemy then return end
                if myTbl.primaryPathIsValid( self ) then return end

                local enemy = myTbl.GetEnemy( self )
                if not IsValid( enemy ) then return end
                if myTbl.enemyBearingToMeAbs( self, enemy ) > 15 then return end

                local myPos = entMeta.GetPos( self )
                local pos
                local myVel = self:GetVelocity()
                if myVel:Length() >= 25 then
                    pos = myPos + myVel:GetNormalized() * 100

                end
                if pos and pos:Distance( entMeta.GetPos( enemy ) ) < self.DistToEnemy then -- dont go towards them
                    pos = nil

                end
                if not pos then
                    local randVec = VectorRand()
                    randVec.z = randVec.z * 0.1
                    pos = myPos + randVec * 100

                end
                local floorOfPos = terminator_Extras.getFloorTr( pos ).HitPos
                if floorOfPos.z < myPos.z - 50 then return end -- dont go off cliffs

                myTbl.GotoPosSimple( self, myTbl, pos, 10 )

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local myPos = entMeta.GetPos( self )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local distToEnemy = myTbl.DistToEnemy
                local clearOrBreakable = myTbl.NothingOrBreakableBetweenEnemy
                local scaryEnemy
                local enemysShoot = myTbl.LastEnemyShootPos
                local lastSpotTime = myTbl.LastEnemySpotTime
                local lastInterceptTime = myTbl.lastInterceptTime
                local hasBrains = myTbl.HasBrains
                if not lastSpotTime or not lastInterceptTime then
                    enemysShoot = myTbl.LastEnemyShootPos

                elseif lastInterceptTime > lastSpotTime and myTbl.lastInterceptPos then
                    enemysShoot = myTbl.lastInterceptPos

                end

                local myWep = self:GetWeapon()
                local wepRange = math.huge
                local needReloadingCovertypes = myTbl.IsReloadingWeapon -- we're actively reloading
                if IsValid( myWep ) then -- see if we need to reload, take cover
                    wepRange = myTbl.GetWeaponRange( self, myTbl )
                    local maxClip = myWep:GetMaxClip1()
                    if maxClip >= 10 then
                        needReloadingCovertypes = myWep:Clip1() <= maxClip * 0.25

                    else
                        needReloadingCovertypes = myWep:Clip1() <= 1

                    end
                end


                local duelEnemyDist = myTbl.GetRealDuelEnemyDist( self, myTbl )

                local hardMaxRadius = math.max( duelEnemyDist, distToEnemy )
                hardMaxRadius = math.min( wepRange, hardMaxRadius )

                local hardMinRadius = math.min( duelEnemyDist * 0.25, hardMaxRadius * 0.5 )

                local fearfullyCloseDistance = hardMinRadius * 0.25


                local goodEnemy
                local enemysNav
                local enemysBearingToMe
                if IsValid( enemy ) then -- yup, enemy is valid
                    goodEnemy = entMeta.Health( enemy ) > 0
                    scaryEnemy = ( entMeta.Health( enemy ) > entMeta.Health( self ) * 5 ) or myTbl.EnemyIsLethalInMelee( self, enemy )
                    enemysShoot = myTbl.EntShootPos( self, enemy )
                    enemysBearingToMe = myTbl.enemyBearingToMeAbs( self, enemy )

                end
                if enemysShoot then
                    enemysNav = terminator_Extras.getNearestNav( enemysShoot )

                end
                if scaryEnemy then
                    hardMinRadius = math.max( duelEnemyDist * 0.5, 500 )
                    hardMaxRadius = math.max( duelEnemyDist * 1.5, hardMinRadius + 500 ) -- if the enemy is scary, we want to be further away

                end

                local searchRadius = math.Clamp( distToEnemy * 1.5, duelEnemyDist, duelEnemyDist * 3 )

                -- everyone else who wants us dead, so cover from one doesn't land us next to another
                if data.NextThreatsRefresh < CurTime() then
                    data.NextThreatsRefresh = CurTime() + 0.5
                    data.Threats, data.ThreatEnts = myTbl.GetNearbyThreats( self, myTbl, enemy, searchRadius + hardMinRadius, 3 )

                end
                local threats = data.Threats
                local threatEnts = data.ThreatEnts

                local myCoverType = myTbl.GetCoverStatusOfPos( self, myTbl, myPos, enemy, enemysShoot )
                coroutine_yield()

                -- update our desired covertype for the upcoming cover find
                local minCoverType = COVER_CRAPCOVER -- please at least have like a tire in front of us
                local maxCoverType = COVER_SOFTCOVER -- but go somewhere that has line of sight
                if needReloadingCovertypes then
                    minCoverType = COVER_SOFTCOVER -- reload from behind a low wall
                    maxCoverType = COVER_HARDCOVER -- or around a corner
                    -- force a reload, shooting_handler only really reloads if the clip is empty
                    if ( myCoverType >= maxCoverType or not clearOrBreakable ) and not myTbl.IsReloadingWeapon then
                        myTbl.WeaponReload( self )

                    end
                end

                local lostHealth = myTbl.getLostHealth( self )

                local feelingExposed = myCoverType < minCoverType or myCoverType > maxCoverType
                local exposedMoving
                -- go back to cover, even with a full clip, if we're "feeling exposed"
                if feelingExposed and clearOrBreakable and ( scaryEnemy or ( enemysBearingToMe and enemysBearingToMe < 8 ) or lostHealth > 5 ) then
                    exposedMoving = true
                    minCoverType = COVER_SOFTCOVER
                    maxCoverType = COVER_HARDCOVER

                end
                coroutine_yield()

                local currPathGoal = data.CurrentTaskGoalPos
                local goalsCoverType
                local badGoal
                -- also keep track of our path goal, the enemy might move, throw our taking cover plans in disarray
                if currPathGoal then
                    goalsCoverType = myTbl.GetCoverStatusOfPos( self, myTbl, currPathGoal, enemy, enemysShoot )
                    local badGoalsCoverType = goalsCoverType < minCoverType or goalsCoverType > maxCoverType
                    data.GoalWasEverGood = data.GoalWasEverGood or not badGoalsCoverType
                    if data.GoalWasEverGood and badGoalsCoverType then
                        badGoal = true

                    end
                    if not badGoal and scaryEnemy and currPathGoal:Distance( enemysShoot ) < fearfullyCloseDistance then
                        badGoal = true -- going too close to the enemy

                    end
                    if not badGoal and nearestThreatDist( threats, currPathGoal ) < hardMinRadius then
                        badGoal = true -- someone else got there first

                    end
                    coroutine_yield()

                end

                if needReloadingCovertypes and myCoverType > COVER_CRAPCOVER then
                    myTbl.overrideCrouch = CurTime() + 0.25

                end

                local needToMoveCloser = distToEnemy > wepRange and not ( data.CurrentTaskGoalPos and data.CurrentTaskGoalPos:Distance( enemysShoot ) < wepRange )

                local needsNewPathGoal = not currPathGoal or badGoal or data.NeedsToChangePositions
                local needsNewCoverPos = needsNewPathGoal or needToMoveCloser

                local nearestDangerDist = math.min( distToEnemy, nearestThreatDist( threats, myPos ) )
                local timeForANewCoverpos = data.NextCoverposFind < CurTime() or nearestDangerDist * 1.25 < data.LastCoverposDangerDist -- they closed in on us

                if needsNewCoverPos and timeForANewCoverpos then
                    coroutine_yield()
                    if not hasBrains and clearOrBreakable then
                        data.NextCoverposFind = CurTime() + math.Rand( 1, 4 ) -- wait a bit before finding a new cover pos

                    else
                        data.NextCoverposFind = CurTime() + math.Rand( 0.1, 0.25 )

                    end
                    data.LastCoverposDangerDist = nearestDangerDist

                    local scoreData = {}
                    scoreData.blockRadiusEnd = true -- keep going if we hit the edge of the radius
                    scoreData.searchRadius = searchRadius
                    scoreData.canDoUnderWater = self:isUnderWater()
                    scoreData.decreasingScores = {}
                    scoreData.self = self
                    scoreData.myTbl = myTbl
                    scoreData.enemy = enemy
                    scoreData.enemysShoot = enemysShoot
                    scoreData.hardMinRadiusSqr = hardMinRadius ^ 2
                    scoreData.hardMaxRadiusSqr = hardMaxRadius ^ 2
                    scoreData.jumpHeight = self.loco:GetMaxJumpHeight()
                    scoreData.enemyDirToMe = terminator_Extras.dirToPos( enemysShoot, myPos ):Angle()
                    scoreData.hasBrains = hasBrains
                    scoreData.occupiedAreaCosts = {}
                    scoreData.OverusedAreaIds = data.OverusedAreaIds or {}
                    scoreData.DistToEnemySqr = distToEnemy ^ 2
                    scoreData.minCoverposZ = math.max( myPos.z + -50, enemysShoot.z + -100 ) -- dont go below the enemy's shoot pos

                    if hasBrains and IsValid( enemysNav ) then
                        scoreData.occupiedAreaCosts[ enemysNav:GetID() ] = 100

                    end
                    if threatEnts then
                        for _, threatEnt in ipairs( threatEnts ) do
                            if not IsValid( threatEnt ) then continue end
                            local threatsArea = getEnemysArea( threatEnt )
                            if IsValid( threatsArea ) then
                                scoreData.occupiedAreaCosts[ threatsArea:GetID() ] = 100

                            end
                        end
                    end

                    myTbl.PopulateWithAreaOccupiedCounts( self, myTbl, scoreData.occupiedAreaCosts )

                    local bestCoverScore = 250 -- dont consider any areas with a score below this for cover
                    local bestCoverType = 0
                    local coverFound
                    coroutine_yield()

                    local scoreFunction = function( scoreData, area1, area2 )
                        local selfLocal = scoreData.self

                        coroutine_yield()
                        if not scoreData.myTbl.areaIsReachable( selfLocal, area2 ) then return 0 end
                        coroutine_yield()

                        if area2:IsBlocked() then return 0 end

                        local score = scoreData.decreasingScores[area1:GetID()] or 500
                        local area2sId = area2:GetID()

                        if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                            score = 1

                        end

                        coroutine_yield()

                        if scoreData.hasBrains then
                            -- cant jump back up
                            local jumpHeight = scoreData.jumpHeight
                            local heightDiff = area1:ComputeAdjacentConnectionHeightChange( area2 )
                            if heightDiff < -jumpHeight * 0.5 then
                                score = 1

                            elseif heightDiff > jumpHeight then
                                return 1

                            end
                        end

                        coroutine_yield()

                        local enemysShootLocal = scoreData.enemysShoot
                        local closestToEnemy = area2:GetClosestPointOnArea( enemysShootLocal )

                        local currsDistToEnemySqr = closestToEnemy:DistToSqr( enemysShootLocal )
                        local outsideDonut
                        if closestToEnemy.z < scoreData.minCoverposZ or currsDistToEnemySqr < scoreData.hardMinRadiusSqr or currsDistToEnemySqr > scoreData.hardMaxRadiusSqr then
                            if coverFound then
                                score = score / 10

                            else
                                score = score / 4

                            end
                            outsideDonut = true

                        elseif currsDistToEnemySqr > scoreData.DistToEnemySqr then
                            if hasBrains then
                                score = score / 2 -- always try and get closer to the enemy

                            else
                                score = score / 6 -- stupid ones really wanna get closer

                            end
                        end

                        -- treat getting close to anyone else like leaving the donut
                        if not outsideDonut and threats then
                            for _, threatPos in ipairs( threats ) do
                                if area2:GetClosestPointOnArea( threatPos ):DistToSqr( threatPos ) < scoreData.hardMinRadiusSqr then
                                    if coverFound then
                                        score = score / 10

                                    else
                                        score = score / 4

                                    end
                                    outsideDonut = true
                                    break

                                end
                            end
                        end

                        if scoreData.occupiedAreaCosts[ area2sId ] then
                            local occupiedCount = scoreData.occupiedAreaCosts[ area2sId ]
                            if occupiedCount and occupiedCount > 1 then
                                score = score / occupiedCount

                            end
                        end
                        if scoreData.OverusedAreaIds[area2sId] then -- make us try and find somewhere new
                            local overusedCount = scoreData.OverusedAreaIds[area2sId]
                            if overusedCount and overusedCount > 1 then
                                score = score / overusedCount

                            end
                        end

                        if not outsideDonut and score >= bestCoverScore then
                            local wasAnythingWeWant
                            local toCheck = { closestToEnemy }

                            -- stupid enemies only check area's nearest point, smart ones all corners + nearest point
                            if scoreData.hasBrains and math.min( area2:GetSizeX(), area2:GetSizeY() ) >= 25 then
                                for i = 0, 3 do
                                    toCheck[#toCheck + 1] = area2:GetCorner( i )

                                end
                            end
                            for _, coverPosToCheck in ipairs( toCheck ) do
                                coroutine_yield()
                                local itsCoverType = scoreData.myTbl.GetCoverStatusOfPos( selfLocal, scoreData.myTbl, coverPosToCheck, scoreData.enemy, enemysShootLocal )

                                local coverWeWant = itsCoverType >= minCoverType and itsCoverType <= maxCoverType
                                -- only spots we'd actually take, the traces add up
                                if coverWeWant and itsCoverType >= bestCoverType and exposedToThreats( selfLocal, scoreData.myTbl, coverPosToCheck, threats, threatEnts ) then
                                    itsCoverType = COVER_NONE
                                    coverWeWant = false

                                end
                                if coverWeWant then
                                    wasAnythingWeWant = true

                                end
                                local betterCover = coverWeWant and itsCoverType >= bestCoverType
                                local atLeastSomething = not coverFound and itsCoverType <= COVER_CRAPCOVER
                                local good = atLeastSomething or betterCover
                                if not good then continue end

                                -- a placeholder doesn't raise the bar, or it'd stop us looking further out for real cover
                                if betterCover then
                                    bestCoverScore = score

                                end
                                bestCoverType = itsCoverType
                                coverFound = coverPosToCheck

                            end
                            if not wasAnythingWeWant then
                                score = score - math.random( 5, 10 ) -- decrease faster if this is leading nowhere

                            end
                        end

                        if coverFound and score < bestCoverScore - math.random( 50, 150 ) then
                            return math.huge

                        end

                        scoreData.decreasingScores[area2sId] = score - math.random( 1, 5 )
                        if coverDebugging then debugoverlay.Text( area2:GetCenter(), tostring( score ), 3, true ) end

                        return score

                    end

                    coroutine_yield()
                    local fallbackCenter, foundArea = myTbl.findValidNavResult( self, scoreData, myPos, scoreData.searchRadius, scoreFunction )

                    data.NeedsToChangePositions = nil
                    if coverFound then
                        if coverDebugging then debugoverlay.Cross( coverFound, 20, 3, Color( 0, 255, 0 ), true ) end
                        data.CurrentTaskGoalPos = coverFound
                        data.GoalWasEverGood = nil
                        data.GoalPosFailures = 0

                    elseif fallbackCenter then
                        data.CurrentTaskGoalPos = fallbackCenter
                        data.GoalWasEverGood = nil
                        data.GoalPosFailures = 0

                    elseif not fallbackCenter then
                        data.GoalPosFailures = data.GoalPosFailures + 1

                    end

                    if IsValid( foundArea ) then
                        local areaId = foundArea:GetID()
                        local oldOverused = data.OverusedAreaIds[areaId] or 0
                        data.OverusedAreaIds[areaId] = oldOverused + 1

                    end

                    coroutine_yield()

                end

                local needsNewPath = data.CurrentTaskGoalPos and myTbl.primaryPathInvalidOrOutdated( self, data.CurrentTaskGoalPos )
                if needsNewPath and data.NextNewPath < CurTime() then
                    coroutine_yield()
                    data.NextNewPath = CurTime() + math.Rand( 0.1, 0.25 )
                    myTbl.InvalidatePath( self, "new shootfromcover path" )
                    if myTbl.HasBrains then -- really strongly avoid areas we were damaged in
                        myTbl.AddAreasToAvoid( self, myTbl.hazardousAreas, 50 )
                        avoidThreatAreas( self, myTbl, threatEnts, hardMinRadius )
                        myTbl.SetupFlankingPath( self, data.CurrentTaskGoalPos, enemysNav, hardMinRadius ) -- make sure the path doesnt bring us too close to enem

                    else
                        myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )

                    end

                    if enemysShoot then-- tell our allies to GET OUT THA WAY!
                        local maxs = Vector( 50, 50, 50 )
                        local entsIMightFriendlyFire = ents.FindAlongRay( data.CurrentTaskGoalPos + myTbl.GetViewOffset( self ), enemysShoot, -maxs, maxs )
                        for _, ent in ipairs( entsIMightFriendlyFire ) do
                            if ent == self then continue end
                            local entsChummy = ent.isTerminatorHunterChummy
                            if not entsChummy then continue end
                            if entsChummy ~= myTbl.isTerminatorHunterChummy then continue end

                            ent:RunTask( "OnAllyTakingCoverBehindMe" )

                        end
                    end
                    coroutine_yield()

                end

                local lastSpottedDiv = data.LastSpottedDiv
                if IsValid( enemysNav ) and not myTbl.areaIsReachable( self, enemysNav ) then
                    lastSpottedDiv = 2 -- if we cant reach the enemy, wait longer

                end

                local sinceLastSpotted = myTbl.TimeSinceEnemySpotted( self, myTbl )
                sinceLastSpotted = sinceLastSpotted / lastSpottedDiv
                local lookAlongPath = sinceLastSpotted > math.Rand( 2, 3 )

                if not seeEnemy and not myTbl.primaryPathIsValid( self ) then
                    self:justLookAt( myTbl.LastEnemyShootPos )
                    myTbl.lastShootingType = "soldierfromcover_aimwheretheywere"
                    lookAlongPath = false

                elseif not seeEnemy and sinceLastSpotted > 4 then
                    lookAlongPath = true
                    self:SimpleSearchNearbyAreas( myPos, myTbl.GetShootPos( self ) )

                end

                coroutine_yield()

                local result = myTbl.ControlPath2( self, not seeEnemy and lookAlongPath )

                coroutine_yield()

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_shootfromcover", potentialWep ) then -- switch weapons
                    return

                elseif not goodEnemy and data.killedOurEnemy and sinceLastSpotted > 1 then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "killedenemy", enemysNav )

                elseif goodEnemy and not exposedMoving and not needReloadingCovertypes and distToEnemy > fearfullyCloseDistance and data.NextAllowedRush < CurTime() and myTbl.areaIsReachable( self, enemysNav ) and myTbl.EnemyIsSuppressed( self, myTbl, enemy ) and not enemyIsCrowded( self, myTbl, enemy ) then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "enemysuppressed", enemysNav )

                elseif ( result == true or not self:primaryPathIsValid() ) and sinceLastSpotted > 6 then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "lostenemypathdone", enemysNav )

                elseif result == true and self:enemyBearingToMeAbs() > 15 and not seeEnemy then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "flankchance", enemysNav )

                elseif self:enemyBearingToMeAbs() > 15 and not seeEnemy and myTbl.LikesToSuppress( self, myTbl ) and myTbl.CanSuppress( self, myTbl ) then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "suppresschance", enemysNav )

                elseif distToEnemy > wepRange * 1.15 and not seeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_shootfromcover", "outofrange", enemysNav )

                elseif not seeEnemy and sinceLastSpotted > 1 and not self:primaryPathIsValid() then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "lostenemy", enemysNav )

                elseif hasBrains and distToEnemy < fearfullyCloseDistance and myTbl.getLostHealth( self ) >= 5 then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_shootfromcover", "tooclosehurt", enemysNav )

                elseif data.GoalPosFailures >= 2 and goodEnemy and not clearOrBreakable and not scaryEnemy then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_shootfromcover", "nocover", enemysNav )

                elseif result == true then
                    data.CurrentTaskGoalPos = nil

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },

        -- let brainless npcs walk slowly towards enemy, using gotopossimple
        ["movement_walkslowtowardsenemy"] = { -- durr
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local myNav = myTbl.GetCurrentNavArea( self, myTbl )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local distToEnemy = myTbl.DistToEnemy
                local enemysPos = myTbl.EnemyLastPos

                if IsValid( enemy ) then
                    enemysPos = entMeta.GetPos( enemy )

                end

                coroutine_yield()

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_walkslowtowardsenemy", potentialWep ) then
                    return

                end

                coroutine_yield()

                if not seeEnemy then
                    local sinceLastSpotted = myTbl.TimeSinceEnemySpotted( self, myTbl )
                    if not IsValid( enemy ) then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_walkslowtowardsenemy", "noenemy" )
                        return

                    elseif myTbl.LikesToSuppress( self, myTbl ) and sinceLastSpotted < 4 and myTbl.CanSuppress( self, myTbl ) then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_walkslowtowardsenemy", "suppresschance" )
                        return

                    else
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_walkslowtowardsenemy", "lostsight" )
                        return

                    end
                end

                coroutine_yield()

                local needsNewPathGoal = not data.CurrentTaskGoalPos
                needsNewPathGoal = needsNewPathGoal or entMeta.GetPos( self ):Distance( data.CurrentTaskGoalPos ) < 35

                if needsNewPathGoal then
                    coroutine_yield()
                    local areasToCheck = myNav:GetAdjacentAreas()
                    areasToCheck[#areasToCheck + 1] = myNav
                    local areasAlreadyAdded = {}
                    for _, area in ipairs( areasToCheck ) do
                        areasAlreadyAdded[area] = true

                    end
                    coroutine_yield()
                    local finalAreasToCheck = {}
                    for _, area in ipairs( areasToCheck ) do
                        local areasNeighbors = area:GetAdjacentAreas()
                        for _, neighbor in ipairs( areasNeighbors ) do
                            if areasAlreadyAdded[neighbor] then continue end
                            areasAlreadyAdded[neighbor] = true
                            finalAreasToCheck[#finalAreasToCheck + 1] = neighbor

                        end
                    end
                    local myViewOffset = myTbl.GetViewOffset( self )
                    local myShoot = myTbl.GetShootPos( self )
                    local bestChargePos
                    local bestChargeDist = distToEnemy
                    for _, area in ipairs( finalAreasToCheck ) do
                        local roughConnectHeight = area:GetCenter().z - myNav:GetCenter().z
                        if roughConnectHeight > myTbl.JumpHeight then continue end

                        coroutine_yield()
                        local posOnArea
                        if area:Contains( enemysPos ) then
                            posOnArea = area:GetClosestPointOnArea( enemysPos )

                        else
                            posOnArea = area:GetRandomPoint()

                        end

                        local myShootWhenImThere = posOnArea + myViewOffset
                        if not terminator_Extras.PosCanSeeComplex( myShoot, myShootWhenImThere, self ) then continue end

                        local chargeDist = posOnArea:Distance( enemysPos )

                        if not bestChargeDist or chargeDist < bestChargeDist then
                            bestChargeDist = chargeDist
                            bestChargePos = posOnArea

                        end
                    end

                    coroutine_yield()

                    if bestChargePos then
                        data.CurrentTaskGoalPos = bestChargePos

                    else
                        local enemysNav = terminator_Extras.getNearestNav( enemysPos )
                        if enemysNav == myNav then
                            data.CurrentTaskGoalPos = enemysPos
                            return

                        end
                        local enemyIsReachable = myTbl.areaIsReachable( self, enemysNav )
                        if not enemyIsReachable then
                            myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_walkslowtowardsenemy", "enemyunreachable" )

                        else
                            myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_walkslowtowardsenemy", "nosimplepath" )

                        end
                        return
                    end
                end

                if data.CurrentTaskGoalPos then
                    coroutine_yield()
                    myTbl.GotoPosSimple( self, myTbl, data.CurrentTaskGoalPos, 1 )

                end
            end,
            ShouldRun = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                return myTbl.DistToEnemy > myTbl.DuelEnemyDist

            end,
            ShouldWalk = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                if data.CurrentTaskGoalPos and self:GetRangeTo( data.CurrentTaskGoalPos ) < myTbl.MoveSpeed then return true end
                return myTbl.DistToEnemy < myTbl.DuelEnemyDist * 0.5

            end,
        },

        ["movement_standandshoot"] = { -- durr
            OnStart = function( self, data )
                data.NextReachableCheck = CurTime() + 1
                data.CurrentTaskGoalPos = nil
                data.LookAt = data.LookAt or self.EnemyLastPos

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local enemy = myTbl.GetEnemy( self )

                coroutine_yield()

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_standandshoot", potentialWep ) then
                    return

                end

                coroutine_yield()

                local needsNewPathGoal = not myTbl.IsSeeEnemy and not data.CurrentTaskGoalPos and IsValid( enemy )
                if needsNewPathGoal then
                    coroutine_yield()
                    local myNav = myTbl.GetCurrentNavArea( self, myTbl )
                    local areasToCheck = myNav:GetAdjacentAreas()
                    local areasAlreadyAdded = { [myNav] = true }
                    for _, area in ipairs( areasToCheck ) do
                        areasAlreadyAdded[area] = true

                    end
                    coroutine_yield()
                    local finalAreasToCheck = {}
                    for _, area in ipairs( areasToCheck ) do
                        local areasNeighbors = area:GetAdjacentAreas()
                        for _, neighbor in ipairs( areasNeighbors ) do
                            if areasAlreadyAdded[neighbor] then continue end
                            areasAlreadyAdded[neighbor] = true
                            finalAreasToCheck[#finalAreasToCheck + 1] = neighbor

                        end
                    end
                    local myViewOffset = myTbl.GetViewOffset( self )
                    local myShoot = myTbl.GetShootPos( self )
                    local enemysShoot = myTbl.EntShootPos( self, enemy )
                    local bestStandPos

                    for _, area in ipairs( finalAreasToCheck ) do
                        local roughConnectHeight = area:GetCenter().z - myNav:GetCenter().z
                        if roughConnectHeight > myTbl.JumpHeight then continue end

                        coroutine_yield()
                        local visible, visiblePos = area:IsVisible( enemysShoot )
                        if not visible then continue end

                        if not terminator_Extras.PosCanSeeComplex( myShoot, visiblePos + myViewOffset, self ) then continue end
                        bestStandPos = visiblePos
                        break

                    end

                    coroutine_yield()

                    if bestStandPos then
                        data.CurrentTaskGoalPos = bestStandPos

                    else
                        myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_standandshoot", "nostandpos" )
                        return

                    end
                end
                if data.CurrentTaskGoalPos then
                    coroutine_yield()
                    if self:GetRangeTo( data.CurrentTaskGoalPos ) < 15 then
                        data.CurrentTaskGoalPos = nil

                    else
                        myTbl.GotoPosSimple( self, myTbl, data.CurrentTaskGoalPos, 5 )

                    end
                end

                coroutine_yield()

                if not IsValid( enemy ) or not myTbl.IsSeeEnemy then
                    if myTbl.LikesToSuppress( self, myTbl ) and myTbl.CanSuppress( self, myTbl ) then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_standandshoot", "suppresschance" )
                        return

                    else
                        local sinceLastSpotted = myTbl.TimeSinceEnemySpotted( self, myTbl )
                        if sinceLastSpotted < 5 then return end

                        if data.LookAt then
                            self:justLookAt( data.LookAt )
                            self.lastShootingType = "soldierstandandshoot_aimwheretheywere"

                        end

                        myTbl.TermSoldier_Decide( self, myTbl, "movement_standandshoot", "noenemy" )
                        return

                    end
                elseif data.NextReachableCheck < CurTime() then
                    data.NextReachableCheck = CurTime() + math.Rand( 2, 4 )
                    local enemysPos = entMeta.GetPos( enemy )
                    if math.abs( enemysPos.z - entMeta.GetPos( self ).z ) > myTbl.JumpHeight then return end

                    local enemysNav = terminator_Extras.getNearestNav( enemysPos )
                    local enemyIsReachable = myTbl.areaIsReachable( self, enemysNav )
                    if not enemyIsReachable then return end

                    myTbl.TermSoldier_Decide( self, myTbl, "movement_standandshoot", "enemyreachable" )

                end
            end,
        },

        -- durr shoot at where we last saw the enemy and maintain LOS
        ["movement_suppress"] = { -- durr
            OnStart = function( self, data )
                data.StopSuppressing = CurTime() + math.Rand( 6, 12 )
                data.CurrentTaskGoalPos = nil
                data.PausedUntil = 0
                data.NextAllyCheck = CurTime() + 0.5

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local enemysShoot = myTbl.LastEnemyShootPos

                coroutine_yield()

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_suppress", potentialWep ) then
                    return

                end

                coroutine_yield()

                local myShoot = myTbl.GetShootPos( self )
                local canSeeSpot = myTbl.ClearOrBreakable( self, myShoot, enemysShoot, true )

                -- durr just keep blasting where we last saw em
                if canSeeSpot then
                    local aimPos = enemysShoot
                    local wep = myTbl.GetActiveLuaWeapon( self, myTbl )
                    if wep and wep.terminatorAimingFunc then
                        aimPos = wep:terminatorAimingFunc()

                    end
                    local prevent = not canSeeSpot
                    self:shootAt( aimPos, prevent )
                    myTbl.lastShootingType = "soldiersuppress_aimwheretheywere"

                end

                if data.NextAllyCheck < CurTime() then
                    data.NextAllyCheck = CurTime() + math.Rand( 0.5, 1.5 )
                    local _, allyCheckResult = myTbl.ClearOrBreakable( self, myShoot, enemysShoot, nil, 0.5 )
                    if IsValid( allyCheckResult.Entity ) and allyCheckResult.Entity.isTerminatorHunterChummy == myTbl.isTerminatorHunterChummy then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_suppress", "allyinway" )
                        return

                    end
                end

                coroutine_yield()

                if seeEnemy then -- i can see em again, go fight properly
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_suppress", "seeenemyagain" )
                    return

                elseif data.StopSuppressing < CurTime() then -- done blasting, figure out what to do
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_suppress", "suppressdone" )
                    return

                elseif not IsValid( enemy ) then -- durr i lost my enemy, go find em
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_suppress", "noenemy" )
                    return

                elseif myShoot:Distance( enemysShoot ) < myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.25 then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_suppress", "tooclosetosuppress" )
                    return

                end

                coroutine_yield()

                -- durr keep shuffling to a new spot that can still see where we last saw em
                local myPos = entMeta.GetPos( self )

                -- reached our goal? stop and catch our breath for a couple secs before pushing on
                if data.CurrentTaskGoalPos and myPos:Distance( data.CurrentTaskGoalPos ) < 35 then
                    data.CurrentTaskGoalPos = nil
                    data.PausedUntil = CurTime() + math.Rand( 1.5, 2.5 )

                end

                if canSeeSpot and data.PausedUntil > CurTime() then return end -- holding still, just keep blasting

                local myNav = myTbl.GetCurrentNavArea( self, myTbl )
                local needsNewPathGoal = not data.CurrentTaskGoalPos

                if needsNewPathGoal then
                    coroutine_yield()
                    local areasToCheck = myNav:GetAdjacentAreas()
                    local areasAlreadyAdded = { [myNav] = true }
                    for _, area in ipairs( areasToCheck ) do
                        areasAlreadyAdded[area] = true

                    end
                    coroutine_yield()
                    local finalAreasToCheck = {}
                    for _, area in ipairs( areasToCheck ) do
                        local areasNeighbors = area:GetAdjacentAreas()
                        for _, neighbor in ipairs( areasNeighbors ) do
                            if areasAlreadyAdded[neighbor] then continue end
                            areasAlreadyAdded[neighbor] = true
                            finalAreasToCheck[#finalAreasToCheck + 1] = neighbor

                        end
                    end
                    local myViewOffset = myTbl.GetViewOffset( self )
                    local goodStandPositions = {}

                    for _, area in ipairs( finalAreasToCheck ) do
                        local roughConnectHeight = area:GetCenter().z - myNav:GetCenter().z
                        if roughConnectHeight > myTbl.JumpHeight then continue end

                        coroutine_yield()
                        local visible, visiblePos = area:IsVisible( enemysShoot )
                        if not visible then continue end

                        local myShootWhenImThere = area:GetRandomPoint() + myViewOffset
                        if not terminator_Extras.PosCanSeeComplex( myShoot, myShootWhenImThere, self ) then continue end

                        if not terminator_Extras.PosCanSeeComplex( visiblePos + myViewOffset, enemysShoot, self ) then continue end
                        goodStandPositions[#goodStandPositions + 1] = visiblePos

                    end

                    coroutine_yield()

                    if #goodStandPositions > 0 then
                        data.CurrentTaskGoalPos = goodStandPositions[math.random( #goodStandPositions )]

                    elseif not canSeeSpot then -- durr cant see em and nowhere to shuffle to, give up suppressing
                        myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_suppress", "suppressspothidden" )
                        return

                    else -- durr nowhere new to go, just hold here and keep blasting
                        data.CurrentTaskGoalPos = nil

                    end
                end

                if data.CurrentTaskGoalPos then
                    coroutine_yield()
                    myTbl.GotoPosSimple( self, myTbl, data.CurrentTaskGoalPos, 5 )

                end
            end,
            ShouldRun = function( self, data )
                -- if we see enemy, override default behaviour
                if not self.NothingOrBreakableBetweenEnemy then
                    return false

                end

            end,
            ShouldWalk = function( self, data )
                if not self.NothingOrBreakableBetweenEnemy then
                    return true

                end
            end,
        },

        -- try and surprise/kill weak enemy
        ["movement_rushsmartandshoot"] = {
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil
                data.StartedRush = CurTime()
                data.TriesCrouchingAmbush = self:EntIndex() % 10 <= 4
                data.NextCrowdCheck = 0

            end,
            OnDamaged = function( self, data ) -- break out of our trance!
                local myTbl  = entMeta.GetTable( self )
                if myTbl and myTbl.NothingOrBreakableBetweenEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.5 and myTbl.getLostHealth( self ) >= 5 then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_rushsmartandshoot", "exposedhurt" )
                    self:RestartMotionCoroutine()

                end
            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local goodEnemy
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local scaryEnemy
                local clearOrBreakable = myTbl.NothingOrBreakableBetweenEnemy
                local enemysShoot = myTbl.LastEnemyShootPos
                local enemysNav
                local enemyIsReachable
                local enemyIsSuppressed
                local enemysBearingToMe
                if IsValid( enemy ) then
                    coroutine_yield()
                    goodEnemy = entMeta.Health( enemy ) > 0
                    scaryEnemy = ( entMeta.Health( enemy ) > entMeta.Health( self ) * 5 ) or myTbl.EnemyIsLethalInMelee( self, enemy )
                    enemysShoot = myTbl.EntShootPos( self, enemy )
                    enemysNav = terminator_Extras.getNearestNav( enemysShoot )
                    enemyIsReachable = myTbl.areaIsReachable( self, enemysNav )
                    enemyIsSuppressed = myTbl.EnemyIsSuppressed( self, myTbl, enemy )
                    enemysBearingToMe = myTbl.enemyBearingToMeAbs( self, enemy )

                end

                local wepRange = math.huge
                local myWep = self:GetWeapon()
                if IsValid( myWep ) then
                    wepRange = myTbl.GetWeaponRange( self, myTbl )

                end

                local needsNewPathGoal = not data.CurrentTaskGoalPos or data.CurrentTaskGoalPos:Distance( enemysShoot ) > 250

                coroutine_yield()
                if needsNewPathGoal and enemyIsReachable and IsValid( enemysNav ) then
                    local furthestGoal
                    local furthestGoalDist = 0
                    local potenialGoals = { enemysNav }
                    local enemyNavsConnectedAreas = enemysNav:GetIncomingConnections()
                    if #enemyNavsConnectedAreas > 0 then
                        terminator_Extras.tableAdd( potenialGoals, enemyNavsConnectedAreas )

                    end
                    for _, area in ipairs( potenialGoals ) do
                        if not myTbl.areaIsReachable( self, area ) then continue end
                        local closestToEnemy = area:GetClosestPointOnArea( enemysShoot )
                        local distToEnemy = closestToEnemy:Distance( enemysShoot )
                        if distToEnemy > furthestGoalDist then
                            furthestGoalDist = distToEnemy
                            furthestGoal = closestToEnemy
                            debugoverlay.Cross( furthestGoal, 10, 5, color_white, true )

                        end
                    end
                    data.CurrentTaskGoalPos = furthestGoal

                end
                local needsNewPath = data.CurrentTaskGoalPos and myTbl.primaryPathInvalidOrOutdated( self, data.CurrentTaskGoalPos )
                if needsNewPath then
                    coroutine_yield()
                    myTbl.InvalidatePath( self, "new rushandshoot path" )
                    if myTbl.HasBrains and math.random( 0, 100 ) < 50 then
                        myTbl.AddAreasToAvoid( self, myTbl.hazardousAreas, 50 ) -- really strongly avoid areas we were damaged in
                        local duelDist = myTbl.GetRealDuelEnemyDist( self, myTbl )
                        local _, threatEnts = myTbl.GetNearbyThreats( self, myTbl, enemy, duelDist, 3 )
                        avoidThreatAreas( self, myTbl, threatEnts, duelDist * 0.25 )

                        -- build flanking path with avoidbubble between us and enemy
                        -- so we try and take some weird route to surprise them
                        myTbl.SetupFlankingPath( self, data.CurrentTaskGoalPos, enemysNav )

                    else -- stupid bot, charge enemy
                        myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )

                    end
                    coroutine_yield()

                end

                local sinceLastSpotted = myTbl.TimeSinceEnemySpotted( self, myTbl )
                local lookAlongPath = sinceLastSpotted > math.Rand( 2, 3 ) and not seeEnemy and goodEnemy

                coroutine_yield()
                local result = myTbl.ControlPath2( self, lookAlongPath )

                if not seeEnemy and not myTbl.primaryPathIsValid( self ) then
                    self:justLookAt( myTbl.LastEnemyShootPos )
                    myTbl.lastShootingType = "soldierrushsmart_aimwheretheywere"

                elseif not seeEnemy and myTbl.TimeSinceEnemySpotted( self, myTbl ) > 4 then
                    coroutine_yield()
                    self:SimpleSearchNearbyAreas( entMeta.GetPos( self ), myTbl.GetShootPos( self ) )

                end

                local notFeelingSuppressed = ( enemysBearingToMe and enemysBearingToMe < 8 and clearOrBreakable ) or ( not enemyIsSuppressed and clearOrBreakable ) 
                local sinceStartedRush = CurTime() - data.StartedRush

                coroutine_yield()
                local validPath = myTbl.primaryPathIsValid( self )

                local crowded
                if data.NextCrowdCheck < CurTime() then
                    data.NextCrowdCheck = CurTime() + 0.5
                    crowded = enemyIsCrowded( self, myTbl, enemy )

                end

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_rushsmartandshoot", potentialWep ) then
                    return

                elseif crowded and goodEnemy then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_rushsmartandshoot", "crowded" )

                elseif sinceStartedRush > 4 and myTbl.HasBrains and notFeelingSuppressed and myTbl.DistToEnemy < wepRange then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_rushsmartandshoot", "notsuppressed" )

                elseif result == true then
                    if not seeEnemy then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_rushsmartandshoot", "arrivedenemygone" )

                    elseif goodEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) then -- we got close enough
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_rushsmartandshoot", "rushedclose" )

                    end
                elseif goodEnemy and myTbl.HasBrains and clearOrBreakable and ( scaryEnemy or myTbl.DistToEnemy < wepRange * 0.15 ) then -- fallback
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_rushsmartandshoot", "tooclose" )

                elseif not validPath and not goodEnemy and sinceLastSpotted > 6 then -- fallback
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_rushsmartandshoot", "rushlostenemy" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
            ShouldCrouch = function( self, data )
                if not data.TriesCrouchingAmbush then return end

                local myTbl = entMeta.GetTable( self )
                if not myTbl.HasBrains then return end

                local duelDist = myTbl.GetRealDuelEnemyDist( self, myTbl )
                if self:GetPathDistanceToGoal() < duelDist / 4 then return true end -- TODO; confirm this works

            end,
        },
        -- stay put while the squad gets ready to push
        ["movement_squadhold"] = {
            OnStart = function( self, data )
                self:InvalidatePath( "holding for my squad" )
                data.HoldUntil = CurTime() + math.Rand( 15, 20 ) -- squads push after PUSH_WAIT, this is for a push that never comes

            end,
            CanPickupWeapon = function() return false end, -- stay put
            OnDamaged = function( self, data, dmg ) -- we're holding somewhere they can hit us
                if dmg:GetDamage() <= 1 then return end
                local myTbl = entMeta.GetTable( self )
                myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_squadhold", "holdhurt" )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = entMeta.GetTable( self )
                if myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_squadhold", "seeenemyagain" )
                    return

                end

                if data.HoldUntil < CurTime() or not orderableSquad( self, myTbl ) then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_squadhold", "holdover" )
                    return

                end

                self:justLookAt( myTbl.LastEnemyShootPos )
                myTbl.lastShootingType = "soldiersquadhold_aimwheretheywere"

            end,
        },
        -- after backing off, get close to a squadmate and wait out the fallback, see thinkFallback
        ["movement_regroup"] = {
            OnStart = function( self, data )
                self:InvalidatePath( "regrouping" )
                data.NextNewPath = 0

            end,
            CanPickupWeapon = function() return false end, -- stay with the squad
            BehaveUpdateMotion = function( self, data )
                local myTbl = entMeta.GetTable( self )
                local squad = orderableSquad( self, myTbl )
                if not squad or not fallingBack( squad ) then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_regroup", "fallbackover" )
                    return

                end

                -- regrouped once one of them is close and we can see each other, a chain of us is fine
                local myPos = entMeta.GetPos( self )
                local myShoot = myTbl.GetShootPos( self )
                local nearest
                local nearestDistSqr = math.huge
                for _, member in ipairs( squad.members ) do
                    if member == self or not IsValid( member ) then continue end
                    local distSqr = myPos:DistToSqr( entMeta.GetPos( member ) )
                    if distSqr < myTbl.CloseEnemyDistance ^ 2 and terminator_Extras.PosCanSeeComplex( myShoot, member:GetShootPos(), self ) then
                        nearest = nil
                        break

                    end
                    if distSqr < nearestDistSqr then
                        nearest = member
                        nearestDistSqr = distSqr

                    end
                end

                if nearest then
                    if myTbl.IsSeeEnemy then -- ran into them on the way, back off again
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_regroup", "fallback" )
                        return

                    end
                    if walkTowards( self, myTbl, data, entMeta.GetPos( nearest ), myTbl.LastEnemyShootPos ) then return end

                end

                if myTbl.IsSeeEnemy then -- they followed us
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_regroup", "seeenemyagain" )
                    return

                end
                self:justLookAt( myTbl.LastEnemyShootPos )
                myTbl.lastShootingType = "soldierregroup_aimwheretheywere"

            end,
            ShouldRun = function( self )
                return self:canDoRun()

            end,
        },
        -- go check out something the squad heard, see updateInvestigate
        ["movement_investigate"] = {
            OnStart = function( self, data )
                self:InvalidatePath( "investigating" )
                data.NextNewPath = 0
                data.GiveUpAt = CurTime() + INVESTIGATE_TIME

            end,
            OnDamaged = function( self, data, dmg ) -- shot by someone we can't see, don't wait for their noise to reach the squad
                if dmg:GetDamage() <= 1 then return end
                local myTbl = entMeta.GetTable( self )
                if not IsValid( myTbl.GetEnemy( self ) ) then return end -- or decide just sends us back here
                myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_investigate" )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = entMeta.GetTable( self )
                if myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_investigate", "spottedenemy" )
                    return

                end

                -- someone actually saw them, that beats a noise
                local leadWhy, leadData = allyLead( self, myTbl, 20 )
                if leadWhy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_investigate", leadWhy, leadData )
                    return

                end

                -- the squad only ever swaps in newer sounds, closer to where they are now
                local heardPos = squadInvestigatePos( self, myTbl )
                if heardPos and heardPos ~= data.Pos then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_investigate", "heardsomething", heardPos )
                    return

                end

                local arrived = entMeta.GetPos( self ):DistToSqr( data.Pos ) < INVESTIGATE_ARRIVED_DIST ^ 2
                local gaveUp = not arrived and ( data.GiveUpAt < CurTime() or not walkTowards( self, myTbl, data, data.Pos ) )
                if not arrived and not gaveUp then return end

                -- done with it either way, or the squad keeps sending us back
                local squad = myTbl.term_Squad
                if squad and squad.investigatePos == data.Pos then
                    squad.investigatePos = nil

                end
                if arrived then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_investigate", "investigated" )

                else
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_investigate", "investigatedud" )

                end
            end,
            ShouldRun = function( self )
                return self:canDoRun()

            end,
        },
        -- watch a killzone too deadly to push through, for whoever comes out of it
        ["movement_contain"] = {
            OnStart = function( self, data )
                self:InvalidatePath( "containing" )
                data.ContainUntil = CurTime() + math.Rand( 20, 30 )
                data.NextNewPath = 0

            end,
            CanPickupWeapon = function() return false end, -- stay on watch
            OnDamaged = function( self, data, dmg )
                if dmg:GetDamage() <= 1 then return end
                local myTbl = entMeta.GetTable( self )
                myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_contain", "holdhurt" )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = entMeta.GetTable( self )
                if myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_contain", "seeenemyagain" )
                    return

                end
                if data.ContainUntil < CurTime() then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_contain", "containover" )
                    return

                end

                local myPos = entMeta.GetPos( self )
                if not data.Spot then
                    data.Spot = findContainSpot( self, myTbl, data.WatchPos ) or myPos

                end
                if myPos:DistToSqr( data.Spot ) > CONTAIN_SPOT_DIST ^ 2 then
                    if not walkTowards( self, myTbl, data, data.Spot ) then
                        data.Spot = myPos

                    end
                    return

                end

                self:justLookAt( data.WatchPos )
                myTbl.lastShootingType = "soldiercontain_watchkillzone"
                myTbl.overrideCrouch = CurTime() + 0.25

            end,
            ShouldRun = function( self )
                return self:canDoRun()

            end,
        },
        ["movement_intercept"] = {
            OnStart = function( self, data )
                data.NextCheckIfSeeEnemy = CurTime() + 1
                data.CurrentTaskGoalPos = nil
                data.CheckIfWeCanJustSee = true
                data.TriesCrouchingAmbush = self:EntIndex() % 10 <= 4
                if self.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.25 )

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.5, 1 )

                end
            end,
            BehaveUpdatePriority = function( self, data ) -- break our trance
                if data.NextCheckIfSeeEnemy > CurTime() then return end
                data.NextCheckIfSeeEnemy = CurTime() + math.Rand( 0.9, 1.1 )

                local myTbl  = entMeta.GetTable( self )
                if not myTbl.IsSeeEnemy then return end

                myTbl.TermSoldier_Decide( self, myTbl, "movement_intercept", "spottedenemy" )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.WAIT )

                end
                local myTbl  = entMeta.GetTable( self )

                local lastInterceptPos = data.InterceptPos or myTbl.lastInterceptPos -- squad contacts come in as data.InterceptPos
                if lastInterceptPos and data.CheckIfWeCanJustSee then
                    data.CheckIfWeCanJustSee = nil -- burn it
                    local canJustSee = self:CanSeePosition( lastInterceptPos + self:GetViewOffset() )
                    if canJustSee then
                        myTbl.lastInterceptPos = nil
                        data.InterceptPos = nil
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_intercept", "interceptvisible", lastInterceptPos + self:GetViewOffset() )
                        return

                    end
                end

                local needNewGoal = not data.CurrentTaskGoalPos
                local canDoNewGoal = lastInterceptPos
                if needNewGoal and canDoNewGoal then
                    local posOnNav = terminator_Extras.getNearestPosOnNav( lastInterceptPos )
                    local reachable = myTbl.areaIsReachable( self, posOnNav.area )
                    if not reachable then
                        data.Unreachable = true
                        return

                    end
                    self.LastEnemyShootPos = posOnNav.pos + self:GetViewOffset()
                    data.CurrentTaskGoalPos = posOnNav.pos

                end
                if data.Unreachable then
                    myTbl.lastInterceptPos = nil
                    data.InterceptPos = nil
                    data.CurrentTaskGoalPos = nil

                end

                coroutine_yield()

                local needsNewPath = data.CurrentTaskGoalPos and myTbl.primaryPathInvalidOrOutdated( self, data.CurrentTaskGoalPos )
                if needsNewPath then
                    myTbl.InvalidatePath( self, "new intercept path" )
                    -- BOX IT IN
                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()

                    -- only do this when sound is confirmed from something dangerous, and there is another hunter pathing
                    if otherHuntersHalfwayPoint then
                        local result = terminator_Extras.getNearestPosOnNav( otherHuntersHalfwayPoint )
                        if IsValid( result.area ) then
                            local flankBubble = entMeta.GetPos( self ):Distance( otherHuntersHalfwayPoint ) * 0.7
                            -- create path, avoid simplest path
                            self:SetupFlankingPath( data.CurrentTaskGoalPos, result.area, flankBubble )

                        end
                    end
                    if not myTbl.primaryPathIsValid( self ) then
                        myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )

                    end
                    if not myTbl.primaryPathIsValid( self ) then
                        data.Unreachable = true

                    end
                    myTbl.lastInterceptPos = nil -- burn this pos
                    data.InterceptPos = nil

                    if myTbl.HasBrains and not data.Unreachable and myTbl.PathCrossesKillzone( self, myTbl ) then
                        myTbl.TermSoldier_Decide( self, myTbl, "movement_intercept", "killzoneahead" )
                        return

                    end
                end

                coroutine_yield()

                local result = myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )

                if result == true then
                    data.CurrentTaskGoalPos = nil

                end

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_intercept", potentialWep ) then
                    return

                elseif result == true then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_intercept", "interceptdud" )

                elseif not myTbl.primaryPathIsValid( self ) or ( data.Unreachable and not data.CurrentTaskGoalPos ) then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_intercept", "enemyunreachable" )

                elseif myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_intercept", "spottedenemy" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
            ShouldCrouch = function( self, data )
                if not data.TriesCrouchingAmbush then return end

                local myTbl = entMeta.GetTable( self )
                if not myTbl.HasBrains then return end

                local duelDist = myTbl.GetRealDuelEnemyDist( self, myTbl )
                if self:GetPathDistanceToGoal() < duelDist / 4 then return true end

            end,
        },
        ["movement_fanout"] = { -- spread out in straight paths to unoccupied areas, after we get to a spot with no enemy
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil
                data.Count = data.Count or math.random( 1, 2 )
                data.FanDistance = nil
                data.NextGoalGet = 0
                data.GiveUpAt = CurTime() + ( data.Count + 1 ) * FANOUT_LEG_TIME -- it walks Count + 1 legs, or loops forever when it can't find or path to one

                if self.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.25 )

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.5, 1 )

                end
            end,
            EnemyFound = function( self, data ) -- break our trance
                if not self.IsSeeEnemy then return end
                self:TermSoldier_Decide( entMeta.GetTable( self ), "movement_fanout", "spottedenemy" )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.WAIT )

                end
                local myTbl  = entMeta.GetTable( self )
                local myPos = entMeta.GetPos( self )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local goodEnemy
                if IsValid( enemy ) then
                    goodEnemy = true

                end

                if not data.CurrentTaskGoalPos and data.NextGoalGet < CurTime() then
                    coroutine_yield()
                    data.NextGoalGet = CurTime() + math.Rand( 0.1, 0.25 )
                    local scoreData = {}
                    scoreData.blockRadiusEnd = nil -- stop if we hit the edge of the radius
                    scoreData.searchRadius = data.FanDistance or myTbl.GetRealDuelEnemyDist( self, myTbl ) * math.Rand( 1.5, 2.5 )
                    scoreData.canDoUnderWater = self:isUnderWater()
                    scoreData.increasingScores = {}
                    scoreData.lastMoveDir = myTbl.EnemyLastMoveDir
                    scoreData.self = self
                    scoreData.myTbl = myTbl

                    local dirToPos = terminator_Extras.dirToPos

                    scoreData.occupiedAreaCosts = {}
                    myTbl.PopulateWithAreaOccupiedCounts( self, myTbl, scoreData.occupiedAreaCosts )

                    local scoreFunction = function( scoreData, area1, area2 )
                        local selfLocal = scoreData.self
                        if not scoreData.myTbl.areaIsReachable( selfLocal, area2 ) then return 0 end
                        if area2:IsBlocked() then return 0 end
                        coroutine_yield()

                        local score = scoreData.increasingScores[area1:GetID()] or 1000
                        local area2sId = area2:GetID()

                        if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                            score = 0

                        end

                        -- apply a bonus or penalty based on alignment with the last enemy move direction
                        if scoreData.lastMoveDir then
                            local moveDir = dirToPos( navMeta.GetCenter( area1 ), navMeta.GetCenter( area2 ) )
                            local alignment = moveDir:Dot( scoreData.lastMoveDir )
                            score = math.max( score + alignment * 50, 1 )

                        end

                        if scoreData.occupiedAreaCosts[area2sId] then
                            local occupiedCount = scoreData.occupiedAreaCosts[area2sId]
                            if occupiedCount and occupiedCount > 1 then
                                score = math.max( score / occupiedCount, 1 )

                            end
                        end

                        if score >= 100 then
                            local connectionHeight = area1:ComputeAdjacentConnectionHeightChange( area2 )
                            if math.abs( connectionHeight ) > self.loco:GetStepHeight() then
                                score = score / connectionHeight

                            end
                        end

                        --debugoverlay.Text( area2:GetCenter(), tostring( score ), 5, true )

                        scoreData.increasingScores[area2sId] = score + math.random( 5, 10 )

                        return score

                    end
                    coroutine_yield()
                    local finalFanoutCenter, finalFanoutArea = myTbl.findValidNavResult( self, scoreData, myPos, scoreData.searchRadius, scoreFunction )
                    if IsValid( finalFanoutArea ) then
                        data.CurrentTaskGoalPos = finalFanoutCenter
                        --debugoverlay.Cross( data.CurrentTaskGoalPos, 5, 1, Color( 0, 255, 0 ), true )

                    else
                        --debugoverlay.Cross( self:GetPos(), 50, 1, Color( 255, 0, 0 ), true )
                        data.CurrentTaskGoalPos = nil

                    end
                end

                coroutine_yield()

                local needsNewPath = myTbl.primaryPathInvalidOrOutdated( self, data.CurrentTaskGoalPos )
                if needsNewPath then
                    coroutine_yield()
                    myTbl.InvalidatePath( self, "new fanout path" )
                    myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )
                    coroutine_yield()

                end

                local result = myTbl.ControlPath2( self, not seeEnemy )

                if myTbl.HasBrains and not seeEnemy and myTbl.TimeSinceEnemySpotted( self, myTbl ) > 6 then
                    self:SimpleSearchNearbyAreas( myPos, myTbl.GetShootPos( self ) )
                    coroutine_yield()

                end

                local leadWhy, leadData = allyLead( self, myTbl, FANOUT_LEAD_AGE )
                coroutine_yield()

                if result == true or ( data.CurrentTaskGoalPos and self:GetRangeTo( data.CurrentTaskGoalPos ) < 25 ) then
                    data.CurrentTaskGoalPos = nil
                    if data.Count > 0 then
                        data.Count = data.Count - 1

                    else
                        myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_fanout", "fanoutdone" )

                    end
                elseif goodEnemy and myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_fanout", "spottedenemy" )

                elseif leadWhy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_fanout", leadWhy, leadData )

                elseif data.GiveUpAt < CurTime() then
                    myTbl.TermSoldier_DecideFailed( self, myTbl, "movement_fanout", "fanoutdone" )

                elseif not myTbl.primaryPathIsValid( self ) and data.CurrentTaskGoalPos then
                    data.CurrentTaskGoalPos = nil

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
        ["movement_patrol"] = { -- wander the map, walking around, looking for enemies.
            -- switch between following a leader for like 20s, then wandering to a random spot and looking in the distance.
            OnStart = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                data.OverrideWanderOff = 0
                data.NotSeeCount = 0
                data.WatchFromAreaCount = 0
                data.NotSeeToLookAround = 0
                data.WanderingOffStarePos = self.EnemyLastPos
                data.NextGoalGet = 0
                data.NextNewPath = 0
                data.AlreadyPatrolledAreas = {}
                data.NextCheckIfSeeEnemy = CurTime() + 1

            end,
            BehaveUpdatePriority = function( self, data ) -- break our trance
                if data.NextCheckIfSeeEnemy > CurTime() then return end
                data.NextCheckIfSeeEnemy = CurTime() + math.Rand( 0.9, 1.1 )

                local myTbl  = entMeta.GetTable( self )
                if myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_patrol", "spottedenemy" )
                    self:RestartMotionCoroutine()
                    return

                end

                if allyLead( self, myTbl, 20 ) then return end -- the motion picks that up, it beats a noise
                local heardPos = squadInvestigatePos( self, myTbl )
                if not heardPos then return end
                myTbl.TermSoldier_Decide( self, myTbl, "movement_patrol", "heardsomething", heardPos )
                self:RestartMotionCoroutine()

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local myPos = entMeta.GetPos( self )
                local seeEnemy = myTbl.IsSeeEnemy

                local cur = CurTime()
                local followerCount = myTbl.TermSoldier_FollowerCount( self, myTbl )
                local myClk = cur + entMeta.EntIndex( self )
                local shouldWanderOff = followerCount >= 1 -- leaders always wander
                if not shouldWanderOff then
                    shouldWanderOff = ( myClk % 20 ) < 10 -- follow leader for 10 seconds, then wander for 10 seconds
                    shouldWanderOff = shouldWanderOff or data.OverrideWanderOff > cur

                end

                local shouldFollowLeader = not shouldWanderOff

                if data.NextGoalGet < cur then
                    data.NextGoalGet = cur + math.Rand( 0.25, 0.5 )
                    if shouldFollowLeader then -- follow leader
                        coroutine_yield()
                        --debugoverlay.Text( self:GetShootPos(), "getgoal1", 1, false )
                        data.WatchFromArea = nil
                        local leader = myTbl.TermSoldier_GetLeader( self, myTbl )
                        if not IsValid( leader ) then
                            data.OverrideWanderOff = cur + math.Rand( 20, 40 ) -- dont check again for a while
                            shouldWanderOff = true -- no leader, wander off

                        else
                            local canSeeLeader = myTbl.CanSeePosition( self, leader, myTbl )
                            if canSeeLeader and self:GetRangeTo( leader ) < myTbl.DuelEnemyDist then
                                data.OverrideWanderOff = cur + math.Rand( 10, 20 ) -- we checked in, wander off

                            elseif math.Rand( 0, 100 ) < 75 and leader:primaryPathIsValid() then
                                data.CurrentTaskGoalPos = leader:GetPath():GetEnd() -- go where leader is going

                            else
                                data.CurrentTaskGoalPos = entMeta.GetPos( leader ) -- follow leader

                            end
                        end
                    end
                    if not data.CurrentTaskGoalPos and shouldWanderOff and IsValid( data.WatchFromArea ) then
                        coroutine_yield()
                        --debugoverlay.Text( self:GetShootPos(), "getgoal2", 1, false )
                        data.NotSeeCount = data.NotSeeCount + 1
                        local onTopOfTheArea = data.WatchFromArea:GetClosestPointOnArea( myPos ):Distance( myPos ) < 100
                        local badWatch = followerCount >= 1 or not onTopOfTheArea or data.WatchFromAreaCount <= 0
                        if badWatch then
                            data.WatchFromArea = nil

                        end
                        local bite = 1
                        local leader = myTbl.TermSoldier_GetLeader( self, myTbl )
                        if IsValid( leader ) and not myTbl.CanSeePosition( self, leader, myTbl ) then -- far from leader, don't stick around
                            bite = 2

                        end
                        data.WatchFromAreaCount = data.WatchFromAreaCount - bite
                        if not data.WanderingOffStarePos or data.NotSeeCount > data.NotSeeToLookAround then -- look around for a bit
                            local myShootPos = myTbl.GetShootPos( self )
                            local didOne
                            for _ = 1, 4 do
                                coroutine_yield()
                                local offset = VectorRand()
                                offset.z = math.Clamp( offset.z, -0.1, 0.1 )
                                offset:Normalize()
                                offset = offset * 500
                                local offsetted = myShootPos + offset
                                if terminator_Extras.PosCanSeeComplex( myShootPos, offsetted, self ) then
                                    --debugoverlay.Line( myShootPos, offsetted, 10, color_white, true )
                                    data.WanderingOffStarePos = offsetted
                                    didOne = true
                                    break

                                end
                            end

                            if myTbl.HasBrains then
                                if not didOne then
                                    data.WatchFromArea = nil

                                else
                                    data.NotSeeToLookAround = data.NotSeeToLookAround + math.random( 10, 15 )

                                end
                            else
                                data.NotSeeToLookAround = data.NotSeeToLookAround + math.random( 5, 10 )

                            end

                        end
                        if data.WanderingOffStarePos then
                            self:justLookAt( data.WanderingOffStarePos )
                            myTbl.lastShootingType = "soldierpatrol_ambientlook"

                        end
                    end
                    if not data.CurrentTaskGoalPos and shouldWanderOff and not IsValid( data.WatchFromArea ) then
                        coroutine_yield()
                        --debugoverlay.Text( self:GetShootPos(), "getgoal3", 1, false )
                        local scoreData = {}
                        scoreData.blockRadiusEnd = nil -- stop if we hit the edge of the radius
                        scoreData.searchRadius = myTbl.GetRealDuelEnemyDist( self, myTbl ) * math.Rand( 3, 6 )
                        scoreData.canDoUnderWater = self:isUnderWater()
                        scoreData.increasingScores = {}
                        scoreData.AlreadyPatrolledAreas = data.AlreadyPatrolledAreas
                        scoreData.searchedHeat = term_Heat.GetHeatTable( "soldier_searched", myTbl.isTerminatorHunterChummy ) or noHeat
                        scoreData.enemySeenHeat = term_Heat.GetHeatTable( "soldier_enemyseen", myTbl.isTerminatorHunterChummy ) or noHeat
                        scoreData.self = self
                        scoreData.myTbl = myTbl

                        scoreData.occupiedAreaCosts = {}
                        myTbl.PopulateWithAreaOccupiedCounts( self, myTbl, scoreData.occupiedAreaCosts )

                        local scoreFunction = function( scoreData, area1, area2 )
                            local selfLocal = scoreData.self
                            if not scoreData.myTbl.areaIsReachable( selfLocal, area2 ) then return 0 end
                            if area2:IsBlocked() then return 0 end

                            coroutine_yield()

                            local score = scoreData.increasingScores[area1:GetID()] or 1000
                            local area2sId = area2:GetID()

                            if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                                score = 0

                            end

                            if scoreData.AlreadyPatrolledAreas[ area2sId ] then
                                score = score / math.random( 2, 3 ) -- avoid already patrolled areas

                            end

                            local searched = scoreData.searchedHeat[area2sId]
                            if searched then
                                score = score / ( 1 + searched )

                            end
                            local enemySeen = scoreData.enemySeenHeat[area2sId]
                            if enemySeen then
                                score = score * ( 1 + enemySeen )

                            end

                            if scoreData.occupiedAreaCosts[area2sId] then
                                local occupiedCount = scoreData.occupiedAreaCosts[area2sId]
                                if occupiedCount and occupiedCount > 1 then
                                    score = score / occupiedCount

                                end
                            end

                            if score >= 100 then
                                local connectionHeight = area1:ComputeAdjacentConnectionHeightChange( area2 )
                                if math.abs( connectionHeight ) > self.loco:GetStepHeight() then
                                    score = score / connectionHeight

                                end
                            end

                            --debugoverlay.Text( area2:GetCenter(), tostring( score ), 5, true )

                            scoreData.increasingScores[area2sId] = score + math.random( 5, 10 )

                            return score

                        end
                        local finalPatrolCenter, finalPatrolArea = myTbl.findValidNavResult( self, scoreData, myPos, scoreData.searchRadius, scoreFunction )
                        if IsValid( finalPatrolArea ) then
                            data.AlreadyPatrolledAreas[ finalPatrolArea:GetID() ] = true
                            data.CurrentTaskGoalPos = finalPatrolCenter
                            if followerCount <= 0 then
                                data.WatchFromArea = finalPatrolArea -- im not a leader, so i'll watch from this area
                                data.WatchFromAreaCount = myTbl.campingTolerance( self ) -- watch longer if this spot can see really far
                                data.NotSeeToLookAround = math.random( 1, 4 ) -- look around as soon as we get there

                            end
                            --debugoverlay.Cross( finalPatrolCenter, 5, true )

                        end
                    end
                end

                coroutine_yield()

                local needsNewPath = myTbl.primaryPathInvalidOrOutdated( self, data.CurrentTaskGoalPos )
                if needsNewPath and data.NextNewPath < CurTime() then
                    --debugoverlay.Text( self:GetShootPos() + Vector( 0,0,10 ), "new path", 1, false )
                    --debugoverlay.Line( myPos, data.CurrentTaskGoalPos, 1, color_white, true )
                    data.NextNewPath = CurTime() + math.Rand( 0.25, 0.5 )
                    myTbl.InvalidatePath( self, "new patrol path" )
                    myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )

                end

                coroutine_yield()
                local result = myTbl.ControlPath2( self, not seeEnemy )
                coroutine_yield()

                if myTbl.HasBrains and myTbl.IsAngry( self ) and myTbl.TimeSinceEnemySpotted( self, myTbl ) > 6 then
                    coroutine_yield()
                    self:SimpleSearchNearbyAreas( myPos, myTbl.GetShootPos( self ) )

                end

                local leadWhy, leadData = allyLead( self, myTbl, 20 )

                if myTbl.IsSeeEnemy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_patrol", "spottedenemy" )

                elseif leadWhy then
                    myTbl.TermSoldier_Decide( self, myTbl, "movement_patrol", leadWhy, leadData )

                elseif result == true then
                    data.CurrentTaskGoalPos = nil

                end
            end,
            ShouldRun = function( self, data )
                local myTbl  = entMeta.GetTable( self )
                local followerCount = myTbl.TermSoldier_FollowerCount( self, myTbl )
                if followerCount >= 1 then return false end

                return self:canDoRun() and self:IsAngry()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
    }
end