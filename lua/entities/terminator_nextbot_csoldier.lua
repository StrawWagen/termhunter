-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

local entMeta = FindMetaTable( "Entity" )
local navMeta = FindMetaTable( "CNavArea" )
local vecMeta = FindMetaTable( "Vector" )

local CurTime = CurTime
local IsValid = IsValid
local math = math

local coroutine_yield = coroutine.yield

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

if GetConVar( "developer" ):GetBool() then -- todo, MAKE THESE SPAWNABLE
    list.Set( "NPC", "terminator_nextbot_csoldier", {
        Name = "Combine Soldier",
        Class = "terminator_nextbot_csoldier",
        Category = "Terminator Nextbot",
        Weapons = ENT.DefaultWeapon,
    } )
end

ENT.PlayerColorVec = Vector( 0.4, 0.4, 0.6 ) -- used for player color

if CLIENT then
    language.Add( "terminator_nextbot_csoldier", ENT.PrintName )
    return

end

local function Distance2D( pos1, pos2 )
    local product = pos1 - pos2
    return product:Length2D()
end

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 10
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = true

ENT.JumpHeight = 50
ENT.DefaultStepHeight = 18
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1 -- used in crouch toggle in motionoverrides
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.SpawnHealth = 75
ENT.FriendlyFireMul = 0.5
ENT.DoMetallicDamage = false
ENT.DontShootThroughProps = true -- only attack if MASK_SHOT is clear
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_POOR
ENT.WalkSpeed = 75
ENT.MoveSpeed = 100
ENT.RunSpeed = 200
ENT.AccelerationSpeed = 1500
ENT.DeathDropHeight = 800

ENT.CanHolsterWeapons = true

ENT.CanSwim = true
ENT.BreathesAir = true
ENT.ThrowingForceMul = 0.5

ENT.neverManiac = true
ENT.HasBrains = true -- false hasbrains means REALLY STUPID for these guys

ENT.isTerminatorHunterChummy = "combine"
ENT.MetallicMoveSounds = false
ENT.ReallyStrong = false
ENT.ReallyHeavy = false
ENT.DuelEnemyDist = 1000
ENT.CloseEnemyDistance = 500 -- focus on closest enemy, not best, if below this dist

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
ENT.CanSpeak = true -- enable speaking thinker

ENT.term_SoundPitchShift = 0
ENT.term_SoundLevelShift = 0

ENT.term_LoseEnemySound = {
    "npc/combine_soldier/vo/lostcontact.wav",
    "npc/combine_soldier/vo/sightlineisclear.wav",
    "npc/combine_soldier/vo/stayalertreportsightlines.wav",
    "npc/combine_soldier/vo/stayalert.wav",
}
ENT.term_FindEnemySound = {
    "npc/combine_soldier/vo/contactconfim.wav",
    "npc/combine_soldier/vo/contact.wav",
    "npc/combine_soldier/vo/contactconfirmprosecuting.wav",
    "npc/combine_soldier/vo/bouncerbouncer.wav",
    "npc/combine_soldier/vo/sectorisnotsecure.wav",
    "npc/combine_soldier/vo/suppressing.wav",
}
ENT.term_DamagedSound = {
    "npc/combine_soldier/pain1.wav",
    "npc/combine_soldier/pain2.wav",
    "npc/combine_soldier/pain3.wav",
}
ENT.term_DieSound = {
    "npc/combine_soldier/die1.wav",
    "npc/combine_soldier/die2.wav",
    "npc/combine_soldier/die3.wav",
}
ENT.term_KilledEnemySound = {
    "npc/combine_soldier/vo/onecontained.wav",
    "npc/combine_soldier/vo/onedown.wav",
    "npc/combine_soldier/vo/overwatchtargetcontained.wav",
    "npc/combine_soldier/vo/flatline.wav",
    "npc/combine_soldier/vo/contained.wav",
    "npc/combine_soldier/vo/affirmativewegothimnow.wav",
}

ENT.IdleLoopingSounds = {}
ENT.AngryLoopingSounds = {}


local friendly = { D_LI, D_LI, 1000 }
local hate = { D_HT, D_HT, 1000 }

function ENT:DoHardcodedRelations()
    self.term_HardCodedRelations = {
        ["npc_breen"] = friendly,
        ["npc_hunter"] = friendly,
        ["npc_stalker"] = friendly,
        ["npc_strider"] = friendly,
        ["npc_manhack"] = friendly,
        ["npc_cscanner"] = friendly,
        ["npc_combine_s"] = friendly,
        ["npc_clawscanner"] = friendly,
        ["npc_helicopter"] = friendly,
        ["npc_rollermine"] = friendly,
        ["npc_metropolice"] = friendly,
        ["npc_turret_floor"] = friendly,
        ["npc_combinegunship"] = friendly,
        ["npc_turret_ceiling"] = friendly,
        ["npc_combine_camera"] = friendly,
        ["npc_combinegunship"] = friendly,
        ["npc_combinedropship"] = friendly,
        ["npc_citizen_rebel_enemy"] = friendly,
        ["npc_rollermine_friendly"] = friendly,

        ["npc_citizen"] = hate,
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
local coverposCache

function ENT:GetCoverStatusOfPos( myTbl, coverPos, enemy, enemysShoot )
    local cachePos = coverPos + enemysShoot
    if not SnapVecToGrid then
        SnapVecToGrid = terminator_Extras.SnapVecToGrid

    end
    SnapVecToGrid( cachePos, 16, 0 )
    local cacheStr = tostring( cachePos )
    if not coverposCache then
        coverposCache = {}
        timer.Simple( 30, function()
            coverposCache = nil

        end )
    end
    local cached = coverposCache[ cacheStr ]
    if cached then
        return cached

    end

    local hasBrains = myTbl.HasBrains

    local posIfStanding = coverPos + myTbl.GetViewOffset( self )

    local trStruc = {
        start = posIfStanding,
        endpos = enemysShoot,
        mask = MASK_SOLID,
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
        --debugoverlay.Line( posIfStanding, enemysShoot, 1, Color( 255, 0, 0 ), true )
        coverposCache[ cacheStr ] = COVER_HARDCOVER
        return COVER_HARDCOVER

    elseif hasBrains then -- brainy enemies can notice "crap" cover, otherwise treat all as no cover
        coroutine_yield()
        if not coverposCache then return COVER_NONE end -- edge case

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

local supressedHealth = 35
local supressedHealthMul = 35 / 100

function ENT:EnemyIsSupressed( myTbl, enemy )
    myTbl = myTbl or entMeta.GetTable( self )
    enemy = enemy or myTbl.GetEnemy( self )
    if not IsValid( enemy ) then return false end

    local enemsSupressedHealth = math.max( supressedHealth, entMeta.GetMaxHealth( enemy ) * supressedHealthMul )

    local enemyIsLowHealth = entMeta.Health( enemy ) <= enemsSupressedHealth
    local enemyIsSupressed = enemy.IsCrouching and enemy:IsCrouching() and enemy:OnGround() and enemy:GetVelocity():Length() <= 25

    return enemyIsLowHealth or enemyIsSupressed

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

function ENT:FindANearbyRecruitingLeader( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    local myPos = entMeta.GetPos( self )
    local myMaxHealth = entMeta.GetMaxHealth( self )

    local potentialLeaderTbls = {}
    local counts = {}
    local potentialLeaders = {}
    local allies = myTbl.GetNearbyAllies( self )
    for i, ally in ipairs( allies ) do
        if i % 20 == 15 then
            coroutine_yield()

        end
        if not IsValid( ally ) then continue end

        local allyTbl = entMeta.GetTable( ally )
        if allyTbl.isTerminatorHunterChummy ~= myTbl.isTerminatorHunterChummy then continue end -- only look for allies of the same type
        if IsValid( allyTbl.GetLeader( ally, allyTbl ) ) then continue end -- followers cant lead

        local allyMaxHealth = entMeta.GetMaxHealth( ally )
        if allyMaxHealth < myMaxHealth then continue end -- ignore allies with less health than us
        if allyMaxHealth > myMaxHealth * 10 then continue end -- ignore allies with >10x our health

        potentialLeaders[#potentialLeaders + 1] = ally
        potentialLeaderTbls[ally] = allyTbl
        counts[ally] = allyTbl.GetFollowerCount( ally, allyTbl ) or 0.1

    end

    coroutine_yield()
    local invalidLeaders = {}
    local leaderPositions = {}
    for _, leader in ipairs( potentialLeaders ) do
        if not IsValid( leader ) then invalidLeaders[leader] = true continue end
        leaderPositions[ leader ] = entMeta.GetPos( leader )

    end
    local Distance = vecMeta.Distance
    table.sort( potentialLeaders, function( a, b )
        if invalidLeaders[a] then return false end
        if invalidLeaders[b] then return true end
        return ( Distance( leaderPositions[a], myPos ) * counts[a] ) < ( Distance( leaderPositions[b], myPos ) * counts[b] )

    end )
    coroutine_yield()
    for _, leader in ipairs( potentialLeaders ) do
        if not IsValid( leader ) then continue end

        local leaderTbl = potentialLeaderTbls[leader]
        if leaderTbl.GetFollowerCount( leader, leaderTbl ) >= leaderTbl.TermSoldier_MaxFollowers then continue end -- this leader is full

        bestLeader = leader
        break

    end

    return bestLeader

end

function ENT:JoinLeader( myTbl, leader, leaderTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    leaderTbl = leaderTbl or entMeta.GetTable( leader )
    myTbl.TermSoldier_Leader = leader

    local oldCount = leaderTbl.TermSoldier_FollowerCount or 0
    leaderTbl.TermSoldier_FollowerCount = oldCount + 1

    myTbl.RunTask( self, "TermSoldier_OnJoinLeader", leader )
    leaderTbl.RunTask( leader, "TermSoldier_OnNewFollower", self )

    self:CallOnRemove( "TermSoldier_LeaveLeader", function()
        if not IsValid( leader ) then return end
        local oldCountLeaving = leaderTbl.TermSoldier_FollowerCount or 0
        leaderTbl.TermSoldier_FollowerCount = math.max( 0, oldCountLeaving - 1 )

    end )
end

function ENT:GetFollowerCount( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    return myTbl.TermSoldier_FollowerCount or 0

end

function ENT:GetLeader( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    return myTbl.TermSoldier_Leader

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
        ["playercontrol_handler"] = defaultTasks["playercontrol_handler"],
        ["movement_backthehellup"] = defaultTasks["movement_backthehellup"],

        ["soldier_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            OnStart = function( self, data )
                -- custom anim translation support
                IdleActivity = ACT_HL2MP_IDLE_PASSIVE
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
            end,
            TranslateActivity = function( self, data, act )
                local myTbl = data.myTbl

                if IsValid( myTbl.GetEnemy( self ) ) then return end
                if myTbl.IsAngry( self ) then return end
                if myTbl.TimeSinceEnemySpotted( self, myTbl ) < 4 + ( entMeta.GetCreationID( self ) % 5 ) then return end

                if not myTbl.ShouldWalk( self, myTbl ) and myTbl.ShouldRun( self, myTbl ) then return end

                local translation = data.passiveTranslations[act]
                if translation then return translation end
            
            end,
            
            EnemyLost = function( self, data )
                self:Term_SpeakSound( self.term_LoseEnemySound )
            end,
            EnemyFound = function( self, data )
                self:Term_SpeakSound( self.term_FindEnemySound )
            end,
            OnDamaged = function( self, data, damage )
                self:Term_ClearStuffToSay()
                self:Term_SpeakSound( self.term_DamagedSound )
            end,
            OnKilled = function( self, data, damage, rag )
                self:Term_SpeakSound( self.term_DieSound )
            end,
            OnKillEnemy = function( self, data ) 
                self:Term_SpeakSound( self.term_KilledEnemySound )
            end,
        },
    

        -- custom movement starter
        ["movement_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            OnStart = function( self, data )
                if data.myTbl.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.01, 0.05 ) -- wait a bit before starting this task

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.5 ) -- wait a bit before starting this task

                end
            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( "wait" )

                end
                local myTbl = data.myTbl
                local enemy = myTbl.GetEnemy( self )
                local canIntercept = myTbl.lastInterceptPos and myTbl.lastInterceptReachable and myTbl.lastInterceptTime > ( CurTime() - 10 ) -- last intercept pos is valid and was set less than 10 seconds ago
                local canWep, potentialWep = myTbl.canGetWeapon( self )
                local enemyLastPos = myTbl.EnemyLastPos
                if canWep and self:getTheWeapon( "movement_handler", potentialWep ) then
                    return

                elseif IsValid( myTbl.Target ) then
                    myTbl.TaskComplete( self, "movement_handler" )
                    myTbl.StartTask( self, "movement_followtarget", "something wants me to follow a target!" )

                elseif IsValid( enemy ) then
                    coroutine_yield()
                    local distToEnemy = myTbl.DistToEnemy
                    local seeEnemy = myTbl.IsSeeEnemy
                    if seeEnemy then
                        local hasBrains = myTbl.HasBrains
                        local enemysNav = terminator_Extras.getNearestNav( entMeta.GetPos( enemy ) )
                        local reachable = myTbl.areaIsReachable( self, enemysNav )
                        if myTbl.TermSoldier_Fearless then
                            myTbl.TaskComplete( self, "movement_handler" )
                            myTbl.StartTask( self, "movement_approachenemy", "i have an enemy and im fearless!" )

                        elseif hasBrains and ( not reachable or distToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) ) then
                            myTbl.TaskComplete( self, "movement_handler" )
                            myTbl.StartTask( self, "movement_shootfromcover", "i have an enemy and im close to em!" )

                        elseif not hasBrains and not reachable then
                            myTbl.TaskComplete( self, "movement_handler" )
                            myTbl.StartTask( self, "movement_standandshoot", "durr i have an enemy but i cant reach them!" )

                        elseif not hasBrains and reachable then
                            myTbl.TaskComplete( self, "movement_handler" )
                            myTbl.StartTask( self, "movement_walkslowtowardsenemy", "durr im gonna walk to my enemy" )

                        else
                            myTbl.TaskComplete( self, "movement_handler" )
                            myTbl.StartTask( self, "movement_approachenemy", "i have an enemy and im not close!" )

                        end
                    elseif canIntercept and myTbl.lastInterceptPos:Distance( myTbl.EnemyLastPos ) < 1500 then
                        myTbl.TaskComplete( self, "movement_handler" )
                        myTbl.StartTask( self, "movement_intercept", "i dont see my enemy but my buddy says they do!" )

                    else
                        myTbl.TaskComplete( self, "movement_handler" )
                        myTbl.StartTask( self, "movement_approachenemy", "i have an enemy but i dont see them!" )

                    end
                elseif canIntercept then
                    myTbl.TaskComplete( self, "movement_handler" )
                    myTbl.StartTask( self, "movement_intercept", "one of my buddies spotted an enemy, ill intercept!" )

                elseif myTbl.TimeSinceEnemySpotted( self, myTbl ) < 15 and ( not enemyLastPos or entMeta.GetPos( self ):Distance( enemyLastPos ) > 350 ) then
                    myTbl.TaskComplete( self, "movement_handler" )
                    myTbl.StartTask( self, "movement_approachenemy", "I just saw them right there!" )

                else
                    myTbl.TaskComplete( self, "movement_handler" )
                    myTbl.StartTask( self, "movement_patrol", "i have no enemy!" )

                end
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
                local myTbl = data.myTbl
                local enemy = myTbl.GetEnemy( self )

                local toPos = myTbl.EnemyLastPos
                if IsValid( enemy ) then
                    toPos = entMeta.GetPos( enemy )

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

                end

                local result = myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )

                coroutine_yield()

                local givenItAChance = data.ApproachAfter < CurTime() -- this schedule didn't JUST start.

                -- get WEAP
                local canWep, potentialWep
                if not IsValid( myTbl.GetWeapon( self ) ) then
                    canWep, potentialWep = myTbl.canGetWeapon( self )

                end
                if canWep and data.DontGetWepsForASec < CurTime() and self:getTheWeapon( "movement_approachenemy", potentialWep, "movement_approachenemy" ) then
                    return

                elseif ( self:MyPathLength() < 50 and Distance2D( self:GetPos(), self:GetPath():GetEnd() ) < 300 ) and givenItAChance then -- catch bot bugging out at an unreachable spot or something
                    self:TaskFail( "movement_approachenemy" )
                    self:StartTask( "movement_handler", "something failed" )

                elseif data.Unreachable then
                    self:TaskFail( "movement_approachenemy" )
                    self:StartTask( "movement_fanout", "i lost my enemy in an unreachable spot!" )

                elseif result == true and not myTbl.IsSeeEnemy then
                    self:TaskFail( "movement_approachenemy" )
                    self:StartTask( "movement_fanout", "damn, i lost them!" )

                elseif not myTbl.TermSoldier_Fearless and myTbl.IsSeeEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) then
                    if myTbl.term_ExpensivePath and myTbl.DistToEnemy * 1.15 > myTbl.GetPath( self ):GetLength() then return end -- if it's an important path, dont waste it
                    if myTbl.HasBrains then
                        self:TaskComplete( "movement_approachenemy" )
                        self:StartTask( "movement_shootfromcover", "i have approached my enemy!" )

                    else
                        self:TaskComplete( "movement_approachenemy" )
                        self:StartTask( "movement_walkslowtowardsenemy", "durr i have approached my enemy!" )

                    end
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
                local myTbl = data.myTbl
                if myTbl and myTbl.NothingOrBreakableBetweenEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.2 and myTbl.getLostHealth( self ) >= 5 then
                    self:TaskComplete( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_backthehellup", "i'm too exposed and i got hurt!" )

                end
            end,
            BehaveUpdatePriority = function( self, data ) -- bit of a hack, never stand still and "just take enemy shooting us"
                local myTbl = data.myTbl
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
                    pos = myPos + VectorRand() * 100

                end
                local floorOfPos = terminator_Extras.getFloorTr( pos ).HitPos
                if floorOfPos.z < myPos.z - 50 then return end -- dont go off cliffs

                myTbl.GotoPosSimple( self, myTbl, pos, 10 )

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = data.myTbl
                local myPos = entMeta.GetPos( self )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local distToEnemy = myTbl.DistToEnemy
                local clearOrBreakable = myTbl.NothingOrBreakableBetweenEnemy
                local scaryEnemy
                local enemysShoot = myTbl.LastEnemyShootPos
                local lastSpotTime = myTbl.LastEnemySpotTime
                local lastInterceptTime = myTbl.lastInterceptTime
                if not lastSpotTime or not lastInterceptTime then
                    enemysShoot = myTbl.LastEnemyShootPos

                elseif lastInterceptTime > lastSpotTime and myTbl.lastInterceptPos then
                    enemysShoot = myTbl.lastInterceptPos

                end

                coroutine_yield()

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
                if scaryEnemy then
                    hardMinRadius = math.max( duelEnemyDist * 0.5, 500 )
                    hardMaxRadius = math.max( duelEnemyDist * 1.5, hardMinRadius + 500 ) -- if the enemy is scary, we want to be further away

                end

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
                    data.GoalWasEverGood = not badGoalsCoverType
                    if data.GoalWasEverGood and badGoalsCoverType then
                        badGoal = true

                    end
                    if not badGoal and scaryEnemy and currPathGoal:Distance( enemysShoot ) < fearfullyCloseDistance then
                        badGoal = true -- going too close to the enemy

                    end
                    coroutine_yield()

                end

                if needReloadingCovertypes and myCoverType > COVER_CRAPCOVER then
                    myTbl.overrideCrouch = CurTime() + 0.25

                end

                local needToMoveCloser = distToEnemy > wepRange and not ( data.CurrentTaskGoalPos and data.CurrentTaskGoalPos:Distance( enemysShoot ) < wepRange )

                local needsNewPathGoal = not currPathGoal or badGoal or data.NeedsToChangePositions
                local needsNewCoverPos = needsNewPathGoal or needToMoveCloser

                local timeForANewCoverpos = data.NextCoverposFind < CurTime() or distToEnemy * 1.25 > data.LastCoverposDistToEnemy

                if needsNewCoverPos and timeForANewCoverpos then
                    coroutine_yield()
                    if not hasBrains and clearOrBreakable then
                        data.NextCoverposFind = CurTime() + math.Rand( 1, 4 ) -- wait a bit before finding a new cover pos

                    else
                        data.NextCoverposFind = CurTime() + math.Rand( 0.1, 0.25 )

                    end
                    data.LastCoverposDistToEnemy = distToEnemy

                    local searchRadius = math.Clamp( distToEnemy * 1.5, duelEnemyDist, duelEnemyDist * 3 )

                    local scoreData = {}
                    scoreData.blockRadiusEnd = true -- keep going if we hit the edge of the radius
                    scoreData.searchRadius = searchRadius
                    scoreData.canDoUnderWater = self:isUnderWater()
                    scoreData.decreasingScores = {}
                    scoreData.self = self
                    scoreData.myTbl = myTbl
                    scoreData.enemy = enemy
                    scoreData.enemysShoot = enemysShoot
                    scoreData.hardMinRadius = hardMinRadius
                    scoreData.hardMaxRadius = hardMaxRadius
                    scoreData.enemyDirToMe = terminator_Extras.dirToPos( enemysShoot, myPos ):Angle()
                    scoreData.hasBrains = hasBrains
                    scoreData.occupiedAreaCosts = {}
                    scoreData.OverusedAreaIds = data.OverusedAreaIds or {}
                    scoreData.DistToEnemy = distToEnemy
                    scoreData.minCoverposZ = math.max( myPos.z + -50, enemysShoot.z + -100 ) -- dont go below the enemy's shoot pos

                    if hasBrains and IsValid( enemysNav ) then
                        scoreData.occupiedAreaCosts[ enemysNav:GetID() ] = 100

                    end

                    myTbl.PopulateWithAreaOccupiedCounts( self, myTbl, scoreData.occupiedAreaCosts )

                    local bestCoverScore = 250 -- dont consider any areas with a score below this for cover
                    local bestCoverType = 0
                    local coverFound
                    coroutine_yield()

                    local scoreFunction = function( scoreData, area1, area2 )
                        local selfLocal = scoreData.self
                        if not scoreData.myTbl.areaIsReachable( selfLocal, area2 ) then return 0 end
                        if area2:IsBlocked() then return 0 end

                        local score = scoreData.decreasingScores[area1:GetID()] or 500
                        local area2sId = area2:GetID()

                        if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                            score = 1

                        end

                        if scoreData.hasBrains then
                            -- cant jump back up
                            local jumpHeight = scoreData.self.loco:GetMaxJumpHeight()
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

                        local currsDistToEnemy = closestToEnemy:Distance( enemysShootLocal )
                        local outsideDonut
                        if closestToEnemy.z < scoreData.minCoverposZ or currsDistToEnemy < scoreData.hardMinRadius or currsDistToEnemy > scoreData.hardMaxRadius then
                            if coverFound then
                                score = score / 10

                            else
                                score = score / 4

                            end
                            outsideDonut = true

                        elseif currsDistToEnemy > scoreData.DistToEnemy then
                            if hasBrains then
                                score = score / 2 -- always try and get closer to the enemy

                            else
                                score = score / 6 -- stupid ones really wanna get closer

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
                                if coverWeWant then
                                    wasAnythingWeWant = true

                                end
                                local betterCover = coverWeWant and itsCoverType >= bestCoverType
                                local atLeastSomething = not coverFound and itsCoverType <= COVER_CRAPCOVER
                                local good = atLeastSomething or betterCover
                                if not good then continue end

                                bestCoverScore = score
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
                        --debugoverlay.Text( area2:GetCenter(), tostring( score ), 3, true )

                        return score

                    end

                    coroutine_yield()
                    local fallbackCenter, foundArea = myTbl.findValidNavResult( self, scoreData, myPos, scoreData.searchRadius, scoreFunction )

                    data.NeedsToChangePositions = nil
                    if coverFound then
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

                elseif hasBrains and not seeEnemy and sinceLastSpotted > 4 then
                    lookAlongPath = true
                    self:SimpleSearchNearbyAreas( myPos, myTbl.GetShootPos( self ) )

                end

                coroutine_yield()

                local result = myTbl.ControlPath2( self, not seeEnemy and lookAlongPath )

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_shootfromcover", potentialWep ) then -- switch weapons
                    return

                elseif not goodEnemy and data.killedOurEnemy and sinceLastSpotted > 1 then
                    self:TaskFail( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_fanout", { Count = 1, FanDistance = distToEnemy }, "i killed my enemy!" )

                elseif hasBrains and goodEnemy and distToEnemy > fearfullyCloseDistance and data.NextAllowedRush < CurTime() and myTbl.areaIsReachable( self, enemysNav ) then
                    local enemyIsSupressed = myTbl.EnemyIsSupressed( self, myTbl, enemy )
                    if not exposedMoving and enemyIsSupressed and not needReloadingCovertypes then
                        self:TaskFail( "movement_shootfromcover" )
                        myTbl.StartTask( self, "movement_rushsmartandshoot", "enemy is low health, rush and shoot!" )

                    end
                elseif result == true and sinceLastSpotted > 6 then
                    self:TaskFail( "movement_shootfromcover" )
                    if enemysNav and myTbl.areaIsReachable( self, enemysNav ) then
                        if myTbl.HasBrains then
                            myTbl.StartTask( self, "movement_rushsmartandshoot", "i lost my enemy, ill flank to where i last saw em!" )

                        else
                            myTbl.StartTask( self, "movement_approachenemy", "i lost my enemy, ill go where i last saw em" )

                        end
                    else
                        myTbl.StartTask( self, "movement_handler", "got to the end of my path and i've lost my enemy!" )

                    end
                elseif hasBrains and result == true and self:enemyBearingToMeAbs() > 15 and not seeEnemy then
                    self:TaskFail( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_rushsmartandshoot", "i feel like flanking my enemy" )

                elseif distToEnemy > wepRange * 1.15 and not seeEnemy then
                    self:TaskComplete( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_rushsmartandshoot", "i'm way too far from this guy" )

                elseif not seeEnemy and sinceLastSpotted > 1 and not self:primaryPathIsValid() then
                    self:TaskFail( "movement_shootfromcover" )
                    if goodEnemy and myTbl.HasBrains and enemysNav and myTbl.areaIsReachable( self, enemysNav ) then
                        myTbl.StartTask( self, "movement_rushsmartandshoot", "i haven't seen my enemy in a bit, i'll flank to where i last saw em!" )

                    elseif enemysNav and not myTbl.areaIsReachable( self, enemysNav ) then
                        myTbl.StartTask( self, "movement_fanout", "i lost my enemy in an unreachable spot!" )

                    else
                        if not myTbl.HasBrains then
                            myTbl.StartTask( self, "movement_approachenemy", "i lost my enemy, ill go where i last saw em" )

                        else
                            myTbl.StartTask( self, "movement_handler", "i haven't seen my enemy in a bit!" )

                        end
                    end
                elseif hasBrains and distToEnemy < fearfullyCloseDistance and myTbl.getLostHealth( self ) >= 5 then
                    self:TaskComplete( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_backthehellup", "i gotta back up, they're tearing me apart!" )

                elseif data.GoalPosFailures >= 2 and goodEnemy and not clearOrBreakable and not scaryEnemy then
                    self:TaskFail( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_rushsmartandshoot", "i couldnt find a good cover position!" )

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
        ["movement_walkslowtowardsenemy"] = {
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = data.myTbl
                local myNav = myTbl.GetCurrentNavArea( self, myTbl )
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local distToEnemy = myTbl.DistToEnemy
                local enemysPos = myTbl.EnemyLastPos

                if IsValid( enemy ) then
                    enemysPos = entMeta.GetPos( enemy )

                end

                if not seeEnemy then
                    coroutine_yield()
                    if not IsValid( enemy ) then
                        self:TaskComplete( "movement_walkslowtowardsenemy" )
                        myTbl.StartTask( self, "movement_handler", "durr i lost my enemy!" )

                    else
                        self:TaskComplete( "movement_walkslowtowardsenemy" )
                        myTbl.StartTask( self, "movement_standandshoot", "durr i cant see them" )

                    end
                    return

                end

                coroutine_yield()

                local needsNewPathGoal = not data.CurrentTaskGoalPos or entMeta.GetPos( self ):Distance( data.CurrentTaskGoalPos ) < 25
                if needsNewPathGoal then
                    coroutine_yield()
                    local areasToCheck = myNav:GetAdjacentAreas()
                    local areasAlreadyAdded = { myNav = true }
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
                        myTbl.TaskFail( self, "movement_walkslowtowardsenemy" )
                        myTbl.StartTask( self, "movement_standandshoot", "durr i can't walk slow to my enemy, they're unreachable" )

                    end
                end

                if data.CurrentTaskGoalPos then
                    coroutine_yield()
                    myTbl.GotoPosSimple( self, myTbl, data.CurrentTaskGoalPos, 15 )

                end
            end,
            ShouldRun = function( self, data )
                local myTbl = data.myTbl
                return myTbl.DistToEnemy > myTbl.DuelEnemyDist

            end,
            ShouldWalk = function( self, data )
                local myTbl = data.myTbl
                if data.CurrentTaskGoalPos and self:GetRangeTo( data.CurrentTaskGoalPos ) < myTbl.MoveSpeed then return true end
                return myTbl.DistToEnemy < myTbl.DuelEnemyDist * 0.5

            end,
        },

        ["movement_standandshoot"] = { -- durr
            OnStart = function( self, data )
                data.NextReachableCheck = CurTime() + 1
                data.CurrentTaskGoalPos = nil

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = data.myTbl
                local enemy = myTbl.GetEnemy( self )

                local needsNewPathGoal = not myTbl.IsSeeEnemy and not data.CurrentTaskGoalPos and IsValid( enemy )
                if needsNewPathGoal then
                    coroutine_yield()
                    local myNav = myTbl.GetCurrentNavArea( self, myTbl )
                    local areasToCheck = myNav:GetAdjacentAreas()
                    local areasAlreadyAdded = { myNav = true }
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
                        myTbl.TaskFail( self, "movement_standandshoot" )
                        myTbl.StartTask( self, "movement_handler", "durr i can't find somewhere to shoot my enemy" )

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
                    local sinceLastSpotted = myTbl.TimeSinceEnemySpotted( self, myTbl )
                    if sinceLastSpotted < 5 then return end

                    self:TaskComplete( "movement_standandshoot" )
                    myTbl.StartTask( self, "movement_handler", "no enemy to shoot at!" )
                    return

                elseif data.NextReachableCheck < CurTime() then
                    data.NextReachableCheck = CurTime() + math.Rand( 2, 4 )
                    local enemysPos = entMeta.GetPos( enemy )
                    if math.abs( enemysPos.z - entMeta.GetPos( self ).z ) > myTbl.JumpHeight then return end

                    local enemysNav = terminator_Extras.getNearestNav( enemysPos )
                    local enemyIsReachable = myTbl.areaIsReachable( self, enemysNav )
                    if not enemyIsReachable then return end

                    myTbl.TaskComplete( self, "movement_standandshoot" )
                    myTbl.StartTask( self, "movement_walkslowtowardsenemy", "durr my enemy is reachable now" )

                end
            end,
        },

        -- try and surprise/kill weak enemy
        ["movement_rushsmartandshoot"] = {
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil
                data.StartedRush = CurTime()

            end,
            OnDamaged = function( self, data ) -- break out of our trance!
                local myTbl = data.myTbl
                if myTbl and myTbl.NothingOrBreakableBetweenEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) * 0.5 and myTbl.getLostHealth( self ) >= 5 then
                    self:TaskComplete( "movement_shootfromcover" )
                    myTbl.StartTask( self, "movement_backthehellup", "i'm too exposed and i got hurt!" )

                end
            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = data.myTbl
                local goodEnemy
                local enemy = myTbl.GetEnemy( self )
                local seeEnemy = myTbl.IsSeeEnemy
                local scaryEnemy 
                local clearOrBreakable = myTbl.NothingOrBreakableBetweenEnemy
                local enemysShoot = myTbl.LastEnemyShootPos
                local enemysNav
                local enemyIsReachable
                local enemyIsSupressed
                local enemysBearingToMe
                if IsValid( enemy ) then
                    coroutine_yield()
                    goodEnemy = entMeta.Health( enemy ) > 0
                    scaryEnemy = ( entMeta.Health( enemy ) > entMeta.Health( self ) * 5 ) or myTbl.EnemyIsLethalInMelee( self, enemy )
                    enemysShoot = myTbl.EntShootPos( self, enemy )
                    enemysNav = terminator_Extras.getNearestNav( enemysShoot )
                    enemyIsReachable = myTbl.areaIsReachable( self, enemysNav )
                    enemyIsSupressed = myTbl.EnemyIsSupressed( self, myTbl, enemy )
                    enemysBearingToMe = myTbl.enemyBearingToMeAbs( self, enemy )

                end

                local wepRange = math.huge
                local myWep = self:GetWeapon()
                if IsValid( myWep ) then
                    wepRange = myTbl.GetWeaponRange( self, myTbl )

                end

                local needsNewPathGoal = not data.CurrentTaskGoalPos or data.CurrentTaskGoalPos:Distance( enemysShoot )

                coroutine_yield()
                if needsNewPathGoal and enemyIsReachable and IsValid( enemysNav ) then
                    local furthestGoal
                    local furthestGoalDist = 0
                    local potenialGoals = { enemysNav }
                    local enemyNavsConnectedAreas = enemysNav:GetIncomingConnections()
                    if #enemyNavsConnectedAreas > 0 then
                        table.Add( potenialGoals, enemyNavsConnectedAreas )

                    end
                    for _, area in ipairs( potenialGoals ) do
                        if not myTbl.areaIsReachable( self, area ) then continue end
                        local closestToEnemy = area:GetClosestPointOnArea( enemysShoot )
                        local distToEnemy = closestToEnemy:Distance( enemysShoot )
                        if distToEnemy > furthestGoalDist then
                            furthestGoalDist = distToEnemy
                            furthestGoal = closestToEnemy

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

                local notFeelingSupressed = ( enemysBearingToMe and enemysBearingToMe < 8 and clearOrBreakable ) or ( not enemyIsSupressed and clearOrBreakable ) 
                local sinceStartedRush = CurTime() - data.StartedRush

                coroutine_yield()
                local validPath = myTbl.primaryPathIsValid( self )

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_shootfromcover", potentialWep ) then
                    return

                elseif sinceStartedRush > 4 and myTbl.HasBrains and notFeelingSupressed and myTbl.DistToEnemy < wepRange then
                    self:TaskFail( "movement_rushsmartandshoot" )
                    myTbl.StartTask( self, "movement_shootfromcover", "they aren't supressed anymore!" )

                elseif result == true then
                    if not seeEnemy then
                        self:TaskComplete( "movement_rushsmartandshoot" )
                        myTbl.StartTask( self, "movement_fanout", "i lost my enemy!" )

                    elseif goodEnemy and myTbl.DistToEnemy < myTbl.GetRealDuelEnemyDist( self, myTbl ) then -- we got close enough
                        self:TaskComplete( "movement_rushsmartandshoot" )
                        myTbl.StartTask( self, "movement_shootfromcover", "i rushed them, time to back off for a bit" )

                    end
                elseif goodEnemy and myTbl.HasBrains and clearOrBreakable and ( scaryEnemy or myTbl.DistToEnemy < wepRange * 0.25 ) then -- fallback
                    self:TaskComplete( "movement_rushsmartandshoot" )
                    myTbl.StartTask( self, "movement_backthehellup", "im way too close to em" )

                elseif not validPath and not goodEnemy and sinceLastSpotted > 6 then -- fallback
                    self:TaskComplete( "movement_rushsmartandshoot" )
                    myTbl.StartTask( self, "movement_handler", "i lost my enemy!" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
        ["movement_intercept"] = {
            OnStart = function( self, data )
                local myTbl = data.myTbl
                data.NextCheckIfSeeEnemy = CurTime() + 1
                data.CurrentTaskGoalPos = nil
                data.CheckIfWeCanJustSee = true
                if data.myTbl.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.25 )

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.5, 1 )

                end
            end,
            BehaveUpdatePriority = function( self, data ) -- break our trance
                if data.NextCheckIfSeeEnemy > CurTime() then return end
                data.NextCheckIfSeeEnemy = CurTime() + math.Rand( 0.9, 1.1 )

                local myTbl = data.myTbl
                if not myTbl.IsSeeEnemy then return end

                self:TaskComplete( "movement_patrol" )
                self:StartTask( "movement_handler", "i found an enemy!" )

            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( "wait" )

                end
                local myTbl = data.myTbl

                local lastInterceptPos = myTbl.lastInterceptPos
                if lastInterceptPos and data.CheckIfWeCanJustSee then
                    data.CheckIfWeCanJustSee = nil -- burn it
                    local canJustSee = self:CanSeePosition( lastInterceptPos + self:GetViewOffset() )
                    if canJustSee then
                        myTbl.TaskComplete( self, "movement_intercept" )
                        if myTbl.HasBrains then
                            myTbl.StartTask( self, "movement_shootfromcover", "my buddy found an enemy, im gonna shoot them from here!" )

                        else
                            myTbl.StartTask( self, "movement_standandshoot", "durr my buddy found an enemy and i can see them!" )

                        end
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
                            self:SetupFlankingPath( soundPos, result.area, flankBubble )

                        end
                    end
                    if not myTbl.primaryPathIsValid( self ) then
                        myTbl.SetupPathShell( self, data.CurrentTaskGoalPos )

                    end
                    if not myTbl.primaryPathIsValid( self ) then
                        data.Unreachable = true

                    end
                    myTbl.lastInterceptPos = nil -- burn this pos

                end

                coroutine_yield()

                local result = myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )

                if result == true then
                    data.CurrentTaskGoalPos = nil

                end

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:IsHolsteredWeap( potentialWep ) and self:getTheWeapon( "movement_shootfromcover", potentialWep ) then
                    return

                elseif result == true then
                    self:TaskComplete( "movement_intercept" )
                    myTbl.StartTask( self, "movement_fanout", { Count = 1 }, "this intercept was a dud!" )

                elseif not myTbl.primaryPathIsValid( self ) or ( data.Unreachable and not data.CurrentTaskGoalPos ) then
                    self:TaskFail( "movement_intercept" )
                    myTbl.StartTask( self, "movement_fanout", "i cant intercept that!" )

                elseif myTbl.IsSeeEnemy then
                    self:TaskComplete( "movement_intercept" )
                    myTbl.StartTask( self, "movement_handler", "good intercept!" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
        ["movement_fanout"] = { -- spread out in straight paths to unoccupied areas, after we get to a spot with no enemy
            OnStart = function( self, data )
                data.CurrentTaskGoalPos = nil
                data.Count = data.Count or math.random( 1, 2 )
                data.FanDistance = nil
                data.NextGoalGet = 0

                if data.myTbl.HasBrains then
                    data.StartTheTask = CurTime() + math.Rand( 0.1, 0.25 )

                else
                    data.StartTheTask = CurTime() + math.Rand( 0.5, 1 )

                end
            end,
            EnemyFound = function( self, data ) -- break our trance
                if not self.IsSeeEnemy then return end
                self:TaskComplete( "movement_fanout" )
                self:StartTask( "movement_handler", "i found an enemy!" )

            end,
            BehaveUpdateMotion = function( self, data )
                while data.StartTheTask > CurTime() do
                    coroutine_yield( "wait" )

                end
                local myTbl = data.myTbl
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

                local canIntercept = myTbl.lastInterceptPos and myTbl.lastInterceptReachable and myTbl.lastInterceptTime > ( CurTime() - 25 ) -- last intercept pos is valid and was set less than 25 seconds ago
                coroutine_yield()

                if result == true or ( data.CurrentTaskGoalPos and self:GetRangeTo( data.CurrentTaskGoalPos ) < 25 ) then
                    data.CurrentTaskGoalPos = nil
                    if data.Count > 0 then
                        data.Count = data.Count - 1

                    else
                        self:TaskFail( "movement_fanout" )
                        myTbl.StartTask( self, "movement_patrol", "ok i have no idea where they are" )

                    end
                elseif goodEnemy and myTbl.IsSeeEnemy then
                    self:TaskComplete( "movement_fanout" )
                    myTbl.StartTask( self, "movement_handler", "i found an enemy!" )

                elseif canIntercept then
                    self:TaskComplete( "movement_fanout" )
                    myTbl.StartTask( self, "movement_intercept", "one of my buddies found an enemy!" )

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
                local myTbl = data.myTbl
                data.OverrideWanderOff = 0
                data.NotSeeCount = 0
                data.WatchFromAreaCount = 0
                data.NotSeeToLookAround = 0
                data.WanderingOffStarePos = self.EnemyLastPos
                data.NextGoalGet = 0
                data.NextNewPath = 0
                data.AlreadyPatrolledAreas = {}
                data.NextCheckIfSeeEnemy = CurTime() + 1
                data.UpdateLeader = function()
                    local leader = myTbl.GetLeader( self )
                    if IsValid( leader ) then return leader end

                    local newLeader = myTbl.FindANearbyRecruitingLeader( self, myTbl )
                    if not IsValid( newLeader ) then return end

                    myTbl.JoinLeader( self, myTbl, newLeader, entMeta.GetTable( newLeader ) )
                    return newLeader

                end
                data.UpdateLeader()
            end,
            BehaveUpdatePriority = function( self, data ) -- break our trance
                if data.NextCheckIfSeeEnemy > CurTime() then return end
                data.NextCheckIfSeeEnemy = CurTime() + math.Rand( 0.9, 1.1 )

                local myTbl = data.myTbl
                if not myTbl.IsSeeEnemy then return end

                self:TaskComplete( "movement_patrol" )
                self:StartTask( "movement_handler", "i found an enemy!" )

            end,
            BehaveUpdateMotion = function( self, data )
                local myTbl = data.myTbl
                local myPos = entMeta.GetPos( self )
                local seeEnemy = myTbl.IsSeeEnemy

                local cur = CurTime()
                local followerCount = myTbl.GetFollowerCount( self, myTbl )
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
                        local leader = data.UpdateLeader()
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
                        local leader = myTbl.GetLeader( self )
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

                            if myTbl.hasBrains then
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

                local canIntercept = myTbl.lastInterceptPos and myTbl.lastInterceptReachable and myTbl.lastInterceptTime > ( CurTime() - 40 ) -- last intercept pos is valid and was set less than 40 seconds ago

                if myTbl.IsSeeEnemy then
                    self:TaskComplete( "movement_patrol" )
                    myTbl.StartTask( self, "movement_handler", "i found an enemy!" )

                elseif canIntercept then
                    self:TaskComplete( "movement_patrol" )
                    myTbl.StartTask( self, "movement_intercept", "i can intercept!" )

                elseif result == true then
                    data.CurrentTaskGoalPos = nil

                end
            end,
            ShouldRun = function( self, data )
                local myTbl = data.myTbl
                local followerCount = myTbl.GetFollowerCount( self, myTbl )
                if followerCount >= 1 then return false end

                return self:canDoRun() and self:IsAngry()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
    }
end
