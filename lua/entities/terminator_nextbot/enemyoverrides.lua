
local MEMORY_WEAPONIZEDNPC = 32

local IsValid = IsValid
local LocalToWorld = LocalToWorld
local entMeta = FindMetaTable( "Entity" )

-- i love overoptimisation
local playersCache = {} -- not nil cause of autorefresh
local function doPlayersCache()
    playersCache = {}
    for _, ply in player.Iterator() do
        playersCache[ply] = true

    end
end
hook.Add( "terminator_nextbot_oneterm_exists", "setup_shouldbeenemy_playercache", function()
    doPlayersCache()
    timer.Create( "term_cache_players", 0.2, 0, function()
        doPlayersCache()
    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "setupshouldbeenemy_playercache", function()
    timer.Remove( "term_cache_players" )
    playersCache = {}

end )

-- i love overoptimisation x 2
local notEnemyCache = {} -- this cache is used to skip alot of _index calls, perf, on checking if props, static things are enemies
hook.Add( "terminator_nextbot_oneterm_exists", "setup_shouldbeenemy_notenemycache", function()
    timer.Create( "term_cache_isnotenemy", 5, 0, function()
        notEnemyCache = {}

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "setup_shouldbeenemy_notenemycache", function()
    timer.Remove( "term_cache_isnotenemy" )
    notEnemyCache = {}

end )

local fogRange
-- from CFC's LFS fork, code by reeedox
local function setFogRange()
    local fogController = ents.FindByClass( "env_fog_controller" )[1]
    if not IsValid( fogController ) then return end

    local fogRangeInt = fogController:GetKeyValues().farz
    if fogRangeInt == -1 then return end
    fogRange = fogRangeInt -- bit of leeway

end

hook.Add( "InitPostEntity", "terminator_nextbot_setfogrange", setFogRange )
setFogRange() -- autorefresh

local function isBeyondFog( _, dist )
    if not fogRange then return end
    return dist > fogRange

end

ENT.IsBeyondFog = isBeyondFog

local function pals( ent1, ent2 )
    return ent1.isTerminatorHunterChummy == ent2.isTerminatorHunterChummy

end

function ENT:EntShootPos( ent, random )
    local hitboxes = {}
    if not ent then return end

    local sets = entMeta.GetHitboxSetCount( ent )

    local isPly = playersCache[ent]
    local isPlayerInVehicle = isPly and ent:InVehicle()
    local isCrouchingPlayer = isPly and ent:Crouching()

    if isPlayerInVehicle then
        return self:getBestPos( ent:GetVehicle() )

    elseif not isCrouchingPlayer and sets then

        local data = ent.cachedHitboxData or nil

        if not data then
            for num1 = 0, sets - 1 do
                for num2 = 0, entMeta.GetHitBoxCount( ent, num1 ) - 1 do
                    local group = entMeta.GetHitBoxHitGroup( ent, num2, num1 )

                    hitboxes[group] = hitboxes[group] or {}
                    hitboxes[group][#hitboxes[group] + 1] = { entMeta.GetHitBoxBone( ent, num2, num1 ), entMeta.GetHitBoxBounds( ent, num2, num1 ) }

                end
            end

            if hitboxes[HITGROUP_HEAD] then
                data = hitboxes[HITGROUP_HEAD][ random and math.random( #hitboxes[HITGROUP_HEAD] ) or 1 ]

            elseif hitboxes[HITGROUP_CHEST] then
                data = hitboxes[HITGROUP_CHEST][ random and math.random( #hitboxes[HITGROUP_CHEST] ) or 1 ]

            elseif hitboxes[HITGROUP_GENERIC] then
                data = hitboxes[HITGROUP_GENERIC][ random and math.random( #hitboxes[HITGROUP_GENERIC] ) or 1 ]

            end
            ent.cachedHitboxData = data
            -- just in case their model changes
            timer.Simple( math.Rand( 5, 10 ), function()
                if not IsValid( self ) then return end
                if not IsValid( ent ) then return end
                ent.cachedHitboxData = nil

            end )
        end

        if data then
            local bonem = entMeta.GetBoneMatrix( ent, data[1] )
            local theCenter = data[2] + ( data[3] - data[2] ) / 2

            local pos = LocalToWorld( theCenter, angle_zero, bonem:GetTranslation(), bonem:GetAngles() )
            return pos

        end
    end

    --debugoverlay.Cross( ent:WorldSpaceCenter(), 5, 10, Color( 255,255,255 ), true )
    return ent:WorldSpaceCenter()

end


local standingOffset = Vector( 0, 0, 64 )
local crouchingOffset = Vector( 0, 0, 20 )
-- if alpha is below this, start the seeing calcs
local maxSeen = 150

local function shouldNotSeeEnemy( me, enemy )
    if not enemy.GetColor then return end

    local color = enemy:GetColor()
    local a = color.a
    if not a then return end
    if a == 255 then return end -- dont waste any more performance
    if a > maxSeen then return end
    if not me:CanSeePosition( enemy ) then return end
    if enemy:IsOnFire() then return end -- they are visible!

    local seen = math.abs( a - maxSeen )
    local enemDistSqr = me:GetPos():DistToSqr( enemy:GetPos() )

    local weapBite = 0
    local weap = nil
    if enemy.GetActiveWeapon then
        weap = enemy:GetActiveWeapon()
    end

    if weap and weap.GetHoldType and weap:GetHoldType() ~= "normal" then
        weapBite = 80
    end

    if enemy:FlashlightIsOn() or enemy.glee_Thirdperson_Flashlight then
        weapBite = weapBite + 80

    end

    local getEnemyResult = me:GetEnemy()
    local isAnOldEnemy = getEnemyResult == enemy
    local oldEnemyThatISee = isAnOldEnemy and me.IsSeeEnemy

    local doRandomSuspicious = nil
    local investigateRadius = nil

    local trulyInvisible = a < 15
    local randomSeed = math.random( 0, maxSeen ) + weapBite


    -- i see enemy, make the chance of losing them really small
    local obviousEnemy = oldEnemyThatISee and randomSeed > seen * 0.1

    -- seen
    if obviousEnemy then return end

    local seedIsGreater = math.random( 0, maxSeen ) > seen * 0.9

    local investigateNearby = doRandomSuspicious or ( enemDistSqr < 3000^2 and seedIsGreater )

    if investigateNearby then
        investigateRadius = investigateRadius or 500

        local randNoZ = VectorRand()
        randNoZ.z = 0

        local potentialPos = enemy:GetPos() + ( randNoZ * investigateRadius )

        if terminator_Extras.PosCanSee( enemy:GetShootPos(), potentialPos ) then
            me:UpdateEnemyMemory( enemy, potentialPos )
            me.EnemyLastPos = potentialPos
            me.EnemyLastHint = potentialPos

        end
    end

    if enemDistSqr < 75^2 then
        return

    elseif enemDistSqr < 45^2 then
        return

    -- NOT visible
    elseif randomSeed < seen or trulyInvisible then
        return true

    end

end

local ignorePlayers = GetConVar( "ai_ignoreplayers" )
function ENT:IgnoringPlayers()
    return ignorePlayers:GetBool()

end

local bearingToPos = terminator_Extras.BearingToPos
local math_abs = math.abs

local function PosIsInFov( self, myAng, myPos, checkPos, fov )
    fov = fov or self.Term_FOV
    if not fov or fov >= 180 then return true end

    myAng = myAng or self:GetEyeAngles()
    myPos = myPos or self:GetPos()
    -- this is dumb
    local fovInverse = bearingToPos( myPos, myAng, checkPos, myAng )
    return ( math_abs( fovInverse ) - 180 ) > -fov

end

ENT.PosIsInFov = PosIsInFov

local function IsInMyFov( self, ent, fov )
    fov = fov or self.Term_FOV
    if not fov or fov >= 180 then return true end

    return PosIsInFov( self, nil, self:GetPos(), ent:GetPos() )

end

ENT.IsInMyFov = IsInMyFov

local _IsFlagSet = entMeta.IsFlagSet

function ENT:ShouldBeEnemy( ent, fov, myTbl, entsTbl )
    if notEnemyCache[ent] then return false end
    if _IsFlagSet( ent, FL_NOTARGET ) then
        notEnemyCache[ent] = true
        return false

    end
    local isObject = _IsFlagSet( ent, FL_OBJECT )
    local isPly = playersCache[ent]

    local killer
    local krangledKiller

    if not ent.isTerminatorHunterKiller then
        local interesting = isPly or ent:IsNextBot() or ent:IsNPC()
        if not isObject and not interesting then
            notEnemyCache[ent] = true
            return false

        end
    else
        -- if an ent has killed terminators, we do more thurough checks on it!
        -- made to allow targeting nextbots/npcs that arent setup correctly, if they killed terminators!
        local class = ent:GetClass()
        if not ( isPly or ent:IsNextBot() or ent:IsNPC() or string.find( class, "npc" ) or string.find( class, "nextbot" ) ) then return false end
        krangledKiller = true

    end
    -- most ents never get past this point!

    entsTbl = entsTbl or entMeta.GetTable( ent )
    myTbl = myTbl or entMeta.GetTable( self )

    if isPly and myTbl.IgnoringPlayers( self ) then
        return false

    end

    local class = ent:GetClass()
    if class == "rpg_missile" then return false end
    if class == "env_flare" then return false end

    local isDeadNPC = ent:IsNPC() and ( ent:GetNPCState() == NPC_STATE_DEAD or class == "npc_barnacle" and ent:GetInternalVariable( "m_takedamage" ) == 0 )

    if not entsTbl.TerminatorNextBot and isDeadNPC then return false end
    if ( entsTbl.TerminatorNextBot or not ent:IsNPC() ) and ent:Health() <= 0 then return false end

    local killerNotChummy = killer and entsTbl.isTerminatorHunterChummy ~= myTbl.isTerminatorHunterChummy
    local memory, _ = myTbl.getMemoryOfObject( self, ent )
    local knowsItsAnEnemy = memory == MEMORY_WEAPONIZEDNPC or myTbl.GetRelationship( self, ent ) == D_HT or krangledKiller or killerNotChummy
    if not knowsItsAnEnemy then return false end

    if hook.Run( "terminator_blocktarget", self, ent ) == true then return false end

    local inFov = IsInMyFov( self, ent, fov )
    local rangeTo = self:GetRangeTo( ent )

    local maxSeeingDist = myTbl.MaxSeeEnemyDistance

    if not inFov and rangeTo > 200 then return false end -- ignore fov if really close

    if isPly then -- ignore maxSeeingDist for plys
        if isBeyondFog( nil, rangeTo ) then -- but dont ignore fog 
            return false

        end
    elseif rangeTo > maxSeeingDist then
        return false

    end

    -- if player then, if they are transparent, randomly don't see them, unless we already saw them.
    if isPly and shouldNotSeeEnemy( self, ent ) then return false end

    return true

end

function ENT:ClearEnemyMemory( enemy )
    enemy = enemy or self:GetEnemy()
    self.m_EnemiesMemory[enemy] = nil

    if self:GetEnemy() == enemy then
        self:SetEnemy( NULL )
        hook.Run( "terminator_engagedenemywasbad", self, enemy )
    end
end

local isentity = isentity

function ENT:CanSeePosition( check )
    local pos = check
    if isentity( check ) then
        pos = self:EntShootPos( check )

    end

    local tr = util.TraceLine( {
        start = self:GetShootPos(),
        endpos = pos,
        mask = self.LineOfSightMask,
        filter = self
    } )

    local seeBasic = not tr.Hit or ( isentity( check ) and tr.Entity == check )
    return seeBasic

end

function ENT:FindEnemies()
    local myTbl = self:GetTable()
    local ShouldBeEnemy = myTbl.ShouldBeEnemy
    local CanSeePosition = myTbl.CanSeePosition
    local UpdateEnemyMemory = myTbl.UpdateEnemyMemory
    local EntShootPos = myTbl.EntShootPos
    local myFov = myTbl.Term_FOV
    local found
    if myFov >= 180 then
        found = ents.FindInSphere( self:GetPos(), myTbl.MaxSeeEnemyDistance )

    else
        found = ents.FindInCone( self:GetShootPos(), self:GetEyeAngles():Forward(), myTbl.MaxSeeEnemyDistance, math.cos( math.rad( myFov ) ) )

    end

    for i = 1, #found do
        local ent = found[i]
        if ent ~= self and not notEnemyCache[ ent ] and ShouldBeEnemy( self, ent, myFov, myTbl, ent:GetTable() ) and CanSeePosition( self, ent ) then
            UpdateEnemyMemory( self, ent, EntShootPos( self, ent ), true )

        end
    end
end

function ENT:FindPriorityEnemy()
    local notsee = {}
    local enemy, bestRange, priority
    local ignorePriority = false

    for curr, _ in pairs( self.m_EnemiesMemory ) do
        if not IsValid( curr ) or not self:ShouldBeEnemy( curr ) then continue end

        if not self:CanSeePosition( curr ) then
            notsee[#notsee + 1] = curr
            continue
        end

        local rang = self:GetRangeSquaredTo( curr )
        local _, pr = self:GetRelationship( curr )

        if not ignorePriority and rang <= self.CloseEnemyDistance^2 then
            -- too close, ignore priority
            ignorePriority = true
        end

        if not enemy or Either( ignorePriority, rang < bestRange, Either( pr == priority, rang < bestRange, pr > priority ) ) then
            enemy, bestRange, priority = curr, rang, pr

        end
    end

    if not enemy then
        -- we dont see any enemy, but we know last position

        for _, curr in ipairs( notsee ) do
            local rang = self:GetRangeSquaredTo( self:GetLastEnemyPosition( curr ) )

            if not enemy or rang < bestRange then
                enemy, bestRange = curr, rang
            end
        end
    end

    return enemy or NULL
end

function ENT:SetupEntityRelationship( ent )
    local disp,priority,theirdisp = self:GetDesiredEnemyRelationship( ent )
    self:Term_SetEntityRelationship( ent, disp, priority )
    if not ( ent:IsNPC() or ent:IsNextBot() ) and not ( ent.AddEntityRelationship or ent.Term_SetEntityRelationship ) then return end
    timer.Simple( 0, function()
        if not IsValid( ent ) then return end
        if not IsValid( self ) then return end
        --print( ent, "has relation with", self, theirdisp )

        if ent.TerminatorNextBot then
            ent:Term_SetEntityRelationship( self, theirdisp, nil )
            return

        end
        if ent.AddEntityRelationship then
            ent:AddEntityRelationship( self, theirdisp, 0 )

        end

        -- stupid hack
        if ent.IsVJBaseSNPC == true then
            if not IsValid( ent ) or not IsValid( self ) or not istable( ent.CurrentPossibleEnemies ) then return end
            ent.CurrentPossibleEnemies[#ent.CurrentPossibleEnemies + 1] = self

        end
    end )
end

function ENT:GetDesiredEnemyRelationship( ent )
    local disp = D_HT
    local theirdisp = D_HT
    local priority = 1

    local hardCodedRelation = self.term_HardCodedRelations[ent:GetClass()]
    if hardCodedRelation then
        disp = hardCodedRelation[1] or disp
        theirdisp = hardCodedRelation[2] or theirdisp
        priority = hardCodedRelation[3] or priority
        return disp, priority, theirdisp

    end

    if ent.isTerminatorHunterChummy then
        if pals( self, ent ) then
            disp = D_LI
            theirdisp = D_LI

        else
            disp = D_HT
            theirdisp = D_HT

        end

    elseif ent:IsPlayer() then
        priority = 1000

    elseif ent:IsNPC() or ent:IsNextBot() then
        local memories = {}
        if self.awarenessMemory then
            memories = self.awarenessMemory

        end
        local key = self:getAwarenessKey( ent )
        local memory = memories[key]
        if memory == MEMORY_WEAPONIZEDNPC then
            priority = priority + 300

        else
            -- what usually happens, npc is flagged as boring
            disp = D_NU
            --print("boringent" )
            priority = priority + 100

        end
        if ent.Health and ent:Health() < self:Health() / 100 then
            theirdisp = D_FR

        end
    end
    return disp,priority,theirdisp

end

function ENT:SetupRelationships()
    for _, ent in ents.Iterator() do
        self:SetupEntityRelationship( ent )
    end

    local hookId = "term_terminator_relations_" .. self:GetCreationID()

    hook.Add( "OnEntityCreated", hookId, function( ent )
        if not IsValid( self ) then hook.Remove( "OnEntityCreated", hookId ) return end
        timer.Simple( 0.5, function()
            if not IsValid( self ) then return end
            if not IsValid( ent ) then return end
            self:SetupEntityRelationship( ent )
        end )
    end )
end

function ENT:MakeFeud( enemy )
    if not IsValid( enemy ) then return end
    if enemy == self then return end
    if not enemy.Health then return end
    if enemy:Health() <= 0 then return end
    if enemy:GetClass() == "rpg_missile" then return end -- crazy fuckin bug
    if enemy:GetClass() == "env_flare" then return end
    local maniacHunter = ( self:GetCreationID() % 15 ) == 1 or self.alwaysManiac
    local arePals = pals( self, enemy )
    if arePals and not maniacHunter then return end

    if enemy:IsPlayer() then
        self:Term_SetEntityRelationship( enemy, D_HT, 1000 ) -- hate players more than anything else

    elseif enemy:IsNPC() or enemy:IsNextBot() then
        self:Term_SetEntityRelationship( enemy, D_HT, 100 )

    else
        self:Term_SetEntityRelationship( enemy, D_HT, 1 )

    end

    if enemy:IsPlayer() then return end
    if enemy.GetActiveWeapon and IsValid( enemy:GetActiveWeapon() ) then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    elseif enemy:GetPos():DistToSqr( self:GetPos() ) > 200^2 then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    end

    if not enemy.Disposition then return end
    Disp = enemy:Disposition( self )
    if Disp == D_HT then return end
    if not enemy.AddEntityRelationship then return end
    enemy:AddEntityRelationship( self, D_HT )

end

-- used in shouldcrouch in motionoverrides
function ENT:HasToCrouchToSeeEnemy()
    local enemy = self:GetEnemy()
    local myPos = self:GetPos()
    local decreaseRate = -1

    if self.tryCrouchingToSeeEnemy and IsValid( enemy ) then
        local nextSeeCheck = self.nextCrouchWouldSeeEnemyCheck or 0

        if nextSeeCheck < CurTime() then
            self.nextCrouchWouldSeeEnemyCheck = CurTime() + 0.2

            local enemyCheckPos = enemy:GetPos() + crouchingOffset * enemy:GetModelScale()
            local standingShootPos = myPos + standingOffset * self:GetModelScale()

            local standingSeeTraceConfig = {
                start = standingShootPos,
                endpos = enemyCheckPos,
                filter = self,
                mask = self.LineOfSightMask,
            }

            local standingSeeTraceResult = util.TraceLine( standingSeeTraceConfig )
            local hitTheEnem = IsValid( standingSeeTraceResult.Entity ) and standingSeeTraceResult.Entity == enemy
            local standingWouldSee = hitTheEnem or not standingSeeTraceResult.Hit

            -- standing would see the enemy
            if standingWouldSee then
                self.shouldCrouchToSeeWeight = math.Clamp( self.shouldCrouchToSeeWeight + decreaseRate, 0, math.huge )

                -- dont stop crouching instantly!
                if self.shouldCrouchToSeeWeight >= 1 then
                    return true

                else
                    self.shouldCrouchToSeeWeight = nil
                    self.tryCrouchingToSeeEnemy = nil
                    return false

                end
            end

            local crouchingShootPos = myPos + crouchingOffset * self:GetModelScale()

            local crouchSeeTraceConfig = {
                start = crouchingShootPos,
                endpos = enemyCheckPos,
                filter = self,
                mask = self.LineOfSightMask,
            }

            local crouchSeeTraceResult = util.TraceLine( crouchSeeTraceConfig )
            local crouchHitTheEnem = IsValid( crouchSeeTraceResult.Entity ) and crouchSeeTraceResult.Entity == enemy
            local crouchWouldSee = crouchHitTheEnem or not crouchSeeTraceResult.Hit

            if crouchWouldSee ~= true then
                self.shouldCrouchToSeeWeight = math.Clamp( self.shouldCrouchToSeeWeight + decreaseRate, 0, math.huge )
                return self.shouldCrouchToSeeWeight >= 1

            end

            self.shouldCrouchToSeeWeight = 5

            return true

        else
            return self.shouldCrouchToSeeWeight >= 1

        end
    end

    if IsValid( enemy ) and not self.IsSeeEnemy then
        self.tryCrouchingToSeeEnemy = true
        self.shouldCrouchToSeeWeight = 0
    end
end

local _dirToPos = terminator_Extras.dirToPos
local _PosCanSeeComplex = terminator_Extras.PosCanSeeComplex
local vecUp25 = Vector( 0, 0, 25 )

function ENT:AnotherHunterIsHeadingToEnemy()
    local myEnemy = self:GetEnemy()
    if not IsValid( myEnemy ) then return end

    local enemysPos = myEnemy:GetPos()
    local enemysShootPos = self:EntShootPos( myEnemy )

    local otherHunters = ents.FindByClass( "terminator_nextbot*" )
    table.Shuffle( otherHunters )

    local myDirToEnemy = _dirToPos( self:GetPos(), enemysPos )

    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) and hunter:PathIsValid() then
            -- its not being sneaky!
            if hunter.IsSeeEnemy then continue end

            local path = hunter:GetPath()
            local pathEnd = path:GetEnd()
            local moveSpeed = hunter.MoveSpeed
            local distNeeded = moveSpeed * 6

            local pathEndDistToEnemy = pathEnd:DistToSqr( enemysPos )
            -- way too far to be going to enemy
            if pathEndDistToEnemy > distNeeded^2 then continue end

            -- is it coming in from another direction, or is it just going straight to enemy
            local dirDifference = ( myDirToEnemy - _dirToPos( pathEnd, enemysPos ) ):Length()
            if dirDifference < 0.25 and pathEndDistToEnemy > moveSpeed^2 then continue end

            -- finally
            if not _PosCanSeeComplex( pathEnd + vecUp25, enemysShootPos, { myEnemy } ) then continue end

            return true

        end
    end
end

function ENT:GetOtherHuntersProbableEntrance()
    local otherHunters = ents.FindByClass( "terminator_nextbot*" )
    table.Shuffle( otherHunters )

    -- find a long path
    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) and hunter:PathIsValid() and hunter:GetPath():GetLength() > 750 then
            return hunter:GetPathHalfwayPoint()

        end
    end
    -- no other long paths! just avoid the other guys if we can
    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) then
            if hunter.IsSeeEnemy and IsValid( hunter:GetEnemy() ) then
                -- between hunter and enemy
                return ( hunter:GetPos() + hunter:GetEnemy():GetPos() ) / 2

            else
                return hunter:GetPos()

            end
        end
    end
end

function ENT:SaveSoundHint( source, valuable, emitter )
    local soundHint = {}
    soundHint.emitter = emitter
    soundHint.source = source
    soundHint.valuable = valuable
    soundHint.time = CurTime()

    self.lastHeardSoundHint = soundHint

end

function ENT:validSoundHint()
    local hint = self.lastHeardSoundHint
    if not hint then return end

    local emitter = hint.emitter
    if IsValid( emitter ) then
        local interesting = emitter:IsPlayer() or emitter:IsNextBot() or emitter:IsNPC()
        if interesting then return true end

        local id = emitter:GetCreationID()
        local oldCount = self.heardThingCounts[ id ] or 0
        self.heardThingCounts[ id ] = oldCount + 1

        --print( emitter, oldCount )

        timer.Simple( 120, function()
            if not IsValid( self ) then return end
            self.heardThingCounts[ id ] = self.heardThingCounts[ id ] + -1

        end )

        if oldCount > 8 then
            self.lastHeardSoundHint = nil
            return false

        end
    end
    return true

end

function ENT:RegisterForcedEnemyCheckPos( enemy )
    if not IsValid( enemy ) then return end

    self.forcedCheckPositions = self.forcedCheckPositions or {}

    self.forcedCheckPositions[ enemy:GetCreationID() ] = enemy:GetPos()

end

function ENT:HandleFakeCrouching( data, enemy )
    -- disgusied terms crouch and jump at the same time as their disguise
    local copying = self:GetNWEntity( "disguisedterminatorsmimictarget", nil )
    if not IsValid( copying ) then
        copying = enemy

    end
    if not IsValid( enemy ) then return end
    if enemy.terminator_CantConvinceImFriendly then return end
    if not ( data.baitcrouching or enemy.terminator_crouchingbaited == self ) then return end

    if not data.distToEnemyOld then
        data.distToEnemyOld = self.DistToEnemy

    elseif self.DistToEnemy > data.distToEnemyOld then
        self.forcedShouldWalk = 0
        data.distToEnemyOld = math.Clamp( self.DistToEnemy, data.distToEnemyOld, data.distToEnemyOld + 5 )
        return

    elseif self.DistToEnemy < data.distToEnemyOld then
        data.distToEnemyOld = self.DistToEnemy
        self.forcedShouldWalk = CurTime() + 1

    end

    data.baitcrouching = data.baitcrouching or CurTime()
    data.crouchbaitcount = data.crouchbaitcount or 0
    data.unpromptedcrouches = data.unpromptedcrouches or 0
    data.foolingjumpcount = data.foolingjumpcount or 0
    data.nextfoolingjump = data.nextfoolingjump or 0
    data.dofoolingjump = data.dofoolingjump or math.huge
    local crouch = 0

    local timeSinceStart = CurTime() - data.baitcrouching

    if copying:IsOnGround() then
        data.wasOnGround = true

    end
    if timeSinceStart > 0.5 and not copying:IsOnGround() and data.wasOnGround and data.nextfoolingjump < CurTime() then
        data.dofoolingjump = CurTime() + 0.25
        data.foolingjumpcount = data.foolingjumpcount + 1
        data.nextfoolingjump = CurTime() + 1 + data.foolingjumpcount * 5

    elseif data.dofoolingjump < CurTime() then
        data.dofoolingjump = math.huge
        self:Jump( 40 )

    elseif timeSinceStart > 0.5 and copying:IsOnGround() and copying.Crouching and copying:Crouching() then
        data.unpromptedcrouches = 0
        if data.didanunpromptedcrouchtimeout and data.slinkAway then
            data.slinkAway = data.slinkAway + -10

        elseif data.slinkAway then
            data.slinkAway = data.slinkAway + 0.75
            data.foolingjumpcount = data.foolingjumpcount + -1

        end
        crouch = 0.25

    elseif timeSinceStart > data.crouchbaitcount + -data.unpromptedcrouches * 0.55 and data.unpromptedcrouches < 4 then
        data.foolingjumpcount = data.foolingjumpcount + -0.5
        data.unpromptedcrouches = data.unpromptedcrouches + 1
        data.resetunpromptedcrouches = CurTime() + 3
        if data.slinkAway then
            data.slinkAway = data.slinkAway + 0.75
        end
        crouch = 0.3

    elseif data.resetunpromptedcrouches and data.resetunpromptedcrouches < CurTime() then
        data.didanunpromptedcrouchtimeout = true
        data.unpromptedcrouches = 0
        data.foolingjumpcount = 0

    end
    if crouch > 0 then
        data.crouchbaitcount = data.crouchbaitcount + 1
        self.overrideCrouch = CurTime() + crouch

    end
end

function ENT:GetNearbyAllies()
    local allies = {}
    for _, ent in ipairs( ents.FindByClass( "terminator_nextbot*" ) ) do
        if ent == self or pals( self, ent ) or self:GetPos():DistToSqr( ent:GetPos() ) > self.InformRadius^2 then continue end

        table.insert( allies, ent )

    end
    return allies

end

local vec_up25 = Vector( 0, 0, 25 )

function ENT:Term_LookAround()
    local cur = CurTime()
    local myTbl = self:GetTable()
    local myPos = self:GetPos()

    local myArea = myTbl.GetTrueCurrentNavArea( self )
    local _, aheadSegment = myTbl.GetNextPathArea( self, myArea ) -- top of the jump
    if not aheadSegment then
        aheadSegment = self:GetPath():GetCurrentGoal()

    end
    local laddering = myTbl.terminator_HandlingLadder

    local lookAtGoalTime = myTbl.term_LookAtPathGoal or 0
    local lookAtGoal = lookAtGoalTime > cur and self:PathIsValid()

    local disrespecting = myTbl.GetCachedDisrespector( self )
    local speedToStopLookingFarAhead = terminator_Extras.term_DefaultSpeedToAimAtProps
    if IsValid( disrespecting ) then
        local myNearestPointToIt = self:NearestPoint( disrespecting:WorldSpaceCenter() )
        local itsNearestPointToMyNearestPoint = disrespecting:NearestPoint( myNearestPointToIt )
        if myNearestPointToIt:DistToSqr( itsNearestPointToMyNearestPoint ) < 8^2 then
            myTbl.PhysicallyPushEnt( self, disrespecting, 250 )

        end
        if not myTbl.LookAheadOnlyWhenBlocked and myTbl.EntIsInMyWay( self, disrespecting, 140, aheadSegment ) then
            speedToStopLookingFarAhead = terminator_Extras.term_InterruptedSpeedToAimAtProps

        end
    end

    local pathIsValid = myTbl.PathIsValid( self )
    local lookAtPos
    local myVelLengSqr = myTbl.loco:GetVelocity():LengthSqr()
    local movingSlow = myVelLengSqr < speedToStopLookingFarAhead
    local sndHint = myTbl.lastHeardSoundHint
    local genericHint = myTbl.term_GenericLookAtPos
    local curiosity = 0.5

    local lookAtEnemyLastPos = myTbl.LookAtEnemyLastPos or 0
    local shouldLookTime = lookAtEnemyLastPos > cur

    if sndHint and sndHint.valuable then
        curiosity = 2

    end

    local seeEnem = myTbl.IsSeeEnemy
    local lookAtType

    if not seeEnem and myTbl.interceptPeekTowardsEnemy and myTbl.lastInterceptTime + 2 > cur then
        lookAtPos = myTbl.lastInterceptPos
        lookAtType = "intercept"

    elseif not seeEnem and myTbl.TookDamagePos then
        lookAtPos = myTbl.TookDamagePos
        lookAtType = "tookdamage"

    elseif not seeEnem and sndHint and sndHint.time + curiosity > cur then
        lookAtPos = sndHint.source
        lookAtType = "soundhint"

    elseif not seeEnem and genericHint and genericHint.time + curiosity > cur then
        lookAtPos = genericHint.source
        lookAtType = "generichint"

    elseif lookAtGoal and pathIsValid and not seeEnem and ( shouldLookTime or ( math.random( 1, 100 ) < 4 and self:CanSeePosition( myTbl.EnemyLastPos ) ) ) then
        if not shouldLookTime then
            myTbl.LookAtEnemyLastPos = cur + curiosity

        end
        lookAtPos = myTbl.EnemyLastPos
        lookAtType = "enemylastpos"

    elseif lookAtGoal and pathIsValid and not seeEnem and laddering then
        lookAtPos = myPos + self:GetVelocity() * 100
        lookAtType = "laddering"

    elseif lookAtGoal and ( movingSlow or pathIsValid ) then
        lookAtPos = aheadSegment.pos + vec_up25
        lookAtType = "lookatpath1"

        if not self:IsOnGround() or movingSlow then
            if IsValid( disrespecting ) then
                lookAtPos = myTbl.getBestPos( self, disrespecting )
                lookAtType = "lookatpath_disrespector"

            else
                lookAtPos = aheadSegment.pos + vec_up25
                lookAtType = "lookatpath2"

            end
        elseif lookAtPos:DistToSqr( myPos ) < 400^2 then
            -- attempt to look farther ahead
            local _, segmentAheadOfUs = myTbl.GetNextPathArea( self, myArea, 3, true )
            if segmentAheadOfUs then
                lookAtPos = segmentAheadOfUs.pos + vec_up25
                lookAtType = "lookatpath3"

            end
        end
    end

    if lookAtPos then
        local myShoot = self:GetShootPos()
        if lookAtPos.z > myPos.z - 25 and lookAtPos.z < myPos.z + 25 then
            lookAtPos.z = myShoot.z

        end
        local ang = ( lookAtPos - myShoot ):Angle()
        local notADramaticHeightChange = ( lookAtPos.z > myPos.z + -100 ) or ( lookAtPos.z < myPos.z + 100 )
        if notADramaticHeightChange and not laddering and not IsValid( disrespecting ) then
            ang.p = 0

        end

        --print( "lookatpos", lookAtType, pathIsValid )

        self:SetDesiredEyeAngles( ang )

        return true

    end
end