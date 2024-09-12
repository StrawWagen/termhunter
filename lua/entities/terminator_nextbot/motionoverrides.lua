local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local function yieldIfWeCan( reason, skipCheck )
    if not skipCheck and not coroutine_running() then return end
    coroutine_yield( reason )

end

local gapJumpHull = Vector( 5, 5, 5 )
local down = Vector( 0, 0, -1 )
local vector_up = Vector( 0, 0, 1 )
local vec_up25 = Vector( 0, 0, 25 )
local vec_up15 = Vector( 0, 0, 15 )
local simpleJumpMinHeight = 64

local function TraceHit( tr )
    return tr.Hit-- or !tr.HitNoDraw and tr.HitTexture!="**empty**"
end

local CurTime = CurTime
local math_Rand = math.Rand

local function TrFilterNoSelf( me )
    local filterTbl = me:GetChildren()
    table.insert( filterTbl, me )

    return filterTbl

end

local singleplayer = game.SinglePlayer()

function ENT:SetPosNoTeleport( pos )
    if not singleplayer then self:PhysicsDestroy() end -- HACK to fix stupid buggy movement that's plauged the bots for years, literally just CTRL-V'ed it from drgbase
    self:SetPos( pos )
    if not singleplayer then self:PhysicsInitShadow() end

end

local smallHull = Vector( 1, 1, 1 )

function ENT:ClearOrBreakable( start, endpos, doSmallHull, hullMul )
    local b1
    local b2
    if doSmallHull then
        b1 = -smallHull
        b2 = smallHull

    else
        hullMul = hullMul or 0.5
        b1, b2 = self:BoundsAdjusted( hullMul )

    end
    local traceStruct = {
        start = start,
        endpos = endpos,
        mask = MASK_SOLID,
        filter = TrFilterNoSelf( self ),
        mins = b1,
        maxs = b2,
    }

    local traceRes = util.TraceHull( traceStruct )

    local hitNothingOrHitBreakable = true
    local hitNothing = true
    local hitEntity = traceRes.Entity
    if traceRes.Hit or traceRes.StartSolid then
        hitNothing = nil
        hitNothingOrHitBreakable = nil

    end
    if IsValid( hitEntity ) then
        local enemy = self:GetEnemy()
        local isVehicle = hitEntity:IsVehicle() and hitEntity:GetDriver() and hitEntity:GetDriver() == enemy
        if self:hitBreakable( traceStruct, traceRes ) then
            hitNothingOrHitBreakable = true

        elseif enemy == hitEntity or isVehicle then
            hitNothingOrHitBreakable = true
            hitNothing = true

        end
    end

    return hitNothingOrHitBreakable, traceRes, hitNothing

end

-- should we assume that we will break this upon doing our path?
function ENT:hitBreakable( traceStruct, traceResult, skipDistCheck )
    local hitEnt = traceResult.Entity
    if traceResult.MatType == MAT_GLASS and ( skipDistCheck or traceResult.HitPos:DistToSqr( traceStruct.endpos ) < 40^2 ) then
        if IsValid( hitEnt ) then
            local class = hitEnt:GetClass()
            local isSurf = class == "func_breakable_surf"
            local hasHealth = isnumber( hitEnt:Health() ) and hitEnt:Health() < 2000

            local hpOrBreakableSurf = isSurf or hasHealth

            if hpOrBreakableSurf then
                return true

            else
                return false

            end
        -- we cant break it if its not an entity!
        else
            return nil

        end
    -- hey its breakable!
    elseif IsValid( hitEnt ) then
        local class = hitEnt:GetClass()
        local isDoor = string.find( class, "door" ) and hitEnt:IsSolid()
        if self:memorizedAsBreakable( hitEnt ) or hitEnt:IsNPC() or hitEnt:IsPlayer() or isDoor then
            if isDoor and class == "prop_door_rotating" and not terminator_Extras.CanBashDoor( hitEnt ) then
                return nil

            elseif hitEnt.isTerminatorHunterChummy == self.isTerminatorHunterChummy then
                return nil

            else
                return true

            end
        else
            local obj = hitEnt:GetPhysicsObject()
            if obj and IsValid( obj ) and obj:IsMoveable() and obj:IsMotionEnabled() and obj:GetMass() <= 100 then
                return true

            else
                return nil

            end
        end
    else
        return nil

    end
end

local aiDisabled = GetConVar( "ai_disabled" )
function ENT:DisabledThinking()
    return aiDisabled:GetBool()

end

--[[------------------------------------
Name: NEXTBOT:DisableBehaviour
Desc: Decides should behaviour be disabled.
Arg1: 
Ret1: bool | Return true to disable.
--]]------------------------------------
function ENT:DisableBehaviour()
    return self:IsPostureActive() or self:IsGestureActive( true ) or self:DisabledThinking() and not self:IsControlledByPlayer() or self:RunTask( "DisableBehaviour" )
end

function ENT:PhysicallyPushEnt( ent, strength )
    local itsObj = ent:GetPhysicsObject()
    if not IsValid( itsObj ) or not itsObj:IsMotionEnabled() then return end

    local myNearestPointToIt = self:NearestPoint( itsObj:GetMassCenter() )
    local itsNearestPointToMyNearestPoint = ent:NearestPoint( myNearestPointToIt )
    local forceStart = self:WorldSpaceCenter()
    local awayFromMe = terminator_Extras.dirToPos( forceStart, itsNearestPointToMyNearestPoint )
    itsObj:ApplyForceOffset( ( self:GetForward() + awayFromMe ) * strength, itsNearestPointToMyNearestPoint )

end

--[[------------------------------------
    Name: NEXTBOT:StuckCheck
    Desc: (INTERNAL) Updates bot stuck status.
    Arg1: 
    Ret1: 
--]]------------------------------------
local vertOffs = Vector( 0,0,5 )

function ENT:StuckCheck()
    if self:DisabledThinking() then return end
    if CurTime() >= self.m_StuckTime then
        local added = math_Rand( 0.15, 0.50 )
        self.m_StuckTime = CurTime() + added

        local loco = self.loco
        local myPos = self:GetPos()
        local moving

        if self.m_StuckPos ~= myPos then
            self.m_StuckPos = myPos
            self.m_StuckTime2 = 0
            moving = true

            if self.m_Stuck then
                self:OnUnStuck()
            end
        end

        local b1,b2 = self:GetCollisionBounds()

        local sizeIncrease = 0
        local checkOrigin = myPos

        if not loco:IsOnGround() then
            sizeIncrease = sizeIncrease + 6

        else
            checkOrigin = checkOrigin + vertOffs

        end
        if self.isUnstucking then
            sizeIncrease = sizeIncrease + 1

        end
        if loco:GetVelocity():Length2DSqr() < 5^2 then
            sizeIncrease = sizeIncrease + 2

        end

        if sizeIncrease > 0 then
            -- prevents getting stuck in air, and getting stuck in doors that slide into us
            b1.x = b1.x - sizeIncrease
            b1.y = b1.y - sizeIncrease
            b2.x = b2.x + sizeIncrease
            b2.y = b2.y + sizeIncrease

        end

        local tr = util.TraceHull( {
            start = checkOrigin,
            endpos = checkOrigin,
            filter = TrFilterNoSelf( self ),
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
            mins = b1,
            maxs = b2,
        } )

        --debugoverlay.Box( pos, b1, b2, 0.5, Color( 255, 255, 255, 150 ) )

        -- push thing out the way!
        local hitEnt = tr.Entity
        if IsValid( hitEnt ) then
            self:PhysicallyPushEnt( hitEnt, 15000 )
        end

        local hit = TraceHit( tr )
        if hit then
            -- fix bot getting stuck running up stairs ( by not running up stairs.. )
            local mul = 1.1
            local oldWalk = self.forcedShouldWalk or 0
            self.forcedShouldWalk = math.max( oldWalk + added * mul, CurTime() + added * mul )

            local overrideCr = ( self.overrideCrouch or 0 ) + 0.3
            overrideCr = math.Clamp( overrideCr, 0, CurTime() + 3 )
            self.overrideCrouch = math.max( CurTime() + -1, overrideCr )

        end

        if not moving and not self.m_Stuck then
            if hit then
                self.m_StuckTime2 = self.m_StuckTime2 + math_Rand( 0.5, 0.75 )

                if self.m_StuckTime2 >= 1 then -- changed from 5 to 1
                    self:OnStuck()
                    --print( "onstuck" )

                end
            else
                self.lastNotStuckPos = myPos
                self.m_StuckTime2 = 0
            end
        else
            if not hit then
                self:OnUnStuck()
            end
        end
    end
end

local function TryStuck( self, endPos, t, tr )
    -- check if we can fit
    t.start = endPos
    t.endpos = endPos

    util.TraceHull( t )

    if not tr.Hit then
        -- simple check to see if we're going through something to get there
        local centerOffset = self:OBBCenter()
        local traceStruct = {
            start = self:GetPos() + centerOffset,
            endpos = endPos + centerOffset,
            mask = MASK_SOLID,
            filter = TrFilterNoSelf( self ),
        }
        local traceRes = util.TraceHull( traceStruct )

        local clearPath = traceRes.StartSolid or not traceRes.Hit

        if clearPath then
            self:SetPosNoTeleport( endPos )
            self.loco:ClearStuck()

            self:OnUnStuck()

            return true

        end
    end

    return false
end

--[[------------------------------------
    NEXTBOT:OnStuck
    Trying teleport if we stuck
--]]------------------------------------
function ENT:OnStuck()
    self.m_Stuck = true
    self:InvalidatePath( "onstuck" )

    self:RunTask( "OnStuck" )

    if IsValid( self.terminatorStucker ) then return end

    local pos = self:GetPos()
    local b1, b2 = self:GetCollisionBounds()

    b1.x = b1.x - 4
    b1.y = b1.y - 4
    b2.x = b2.x + 4
    b2.y = b2.y + 4

    local tr = {}
    local t = {
        mask = self:GetSolidMask(),
        collisongroup = self:GetCollisionGroup(),
        output = tr,
        filter = TrFilterNoSelf( self ),
        mins = b1,
        maxs = b2,

    }

    local w = b2.x-b1.x
    local skipCheck = coroutine_running()

    for z = 0, w * 1.2, w * 0.2 do
        yieldIfWeCan( nil, skipCheck )
        for x = 0, w * 1.2, w * 0.2 do
            yieldIfWeCan( nil, skipCheck )
            for y = 0, w * 1.2, w * 0.2 do
                if TryStuck( self, pos + Vector( x, y, z ),     t, tr ) then return end
                if TryStuck( self, pos + Vector( -x, y, z ),    t, tr ) then return end
                if TryStuck( self, pos + Vector( x, -y, z ),    t, tr ) then return end
                if TryStuck( self, pos + Vector( -x, -y, z ),   t, tr ) then return end
                if TryStuck( self, pos + Vector( x, y, -z ),    t, tr ) then return end
                if TryStuck( self, pos + Vector( -x, y, -z ),   t, tr ) then return end
                if TryStuck( self, pos + Vector( x, -y, -z ),   t, tr ) then return end
                if TryStuck( self, pos + Vector( -x, -y, -z ),  t, tr ) then return end
            end
        end
    end
end

function ENT:IsSilentStepping()
    return false

end

function ENT:GetFootstepSoundTime()
    local time = 400
    local speed = self.loco:GetVelocity():Length()

    time = time - ( speed * 0.6 )

    if self:IsCrouching() then
        time = time + 100
    end

    return time
end

--[[------------------------------------
    Name: NEXTBOT:ProcessFootsteps
    Desc: (INTERNAL) Called to update footstep data.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:ProcessFootsteps()
    if not self.loco:IsOnGround() then return end

    local time = self.m_FootstepTime
    local curspeed = self:GetCurrentSpeed()

    if curspeed > self.WalkSpeed * 0.5 and CurTime() - time >= self:GetFootstepSoundTime() / 1000 then
        local walk = curspeed < self.RunSpeed

        local tr = util.TraceEntity( {
            start = self:GetPos(),
            endpos = self:GetPos() - Vector( 0, 0, 5 ),
            filter = TrFilterNoSelf( self ),
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
        }, self )

        local surface = util.GetSurfaceData( tr.SurfaceProps )
        local vol = 1
        if surface then
            local m = surface.material

            if m == MAT_CONCRETE then
                vol = walk and 0.8 or 1
            elseif m == MAT_METAL then
                vol = walk and 0.8 or 1
            elseif m == MAT_DIRT then
                vol = walk and 0.4 or 0.6
            elseif m == MAT_VENT then
                vol = 1
            elseif m == MAT_GRATE then
                vol = walk and 0.6 or 0.8
            elseif m == MAT_TILE then
                vol = walk and 0.8 or 1
            elseif m == MAT_SLOSH then
                vol = walk and 0.8 or 1
            end

        end

        self:MakeFootstepSound( vol, tr.SurfaceProps )
    end
end

local sndFlags = bit.bor( SND_CHANGE_PITCH, SND_CHANGE_VOL )

function ENT:MakeFootstepSound( volume, surface, mul )
    mul = mul or 1
    local foot = self.m_FootstepFoot
    self.m_FootstepFoot = not foot
    self.m_FootstepTime = CurTime()

    if not surface then
        local tr = util.TraceEntity( {
            start = self:GetPos(),
            endpos = self:GetPos() - Vector( 0, 0, 5 ),
            filter = TrFilterNoSelf( self ),
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
        }, self )

        surface = tr.SurfaceProps
    end

    if not surface then return end

    surface = util.GetSurfaceData( surface )
    if not surface then return end

    local sound = foot and surface.stepRightSound or surface.stepLeftSound

    if sound then
        local pos = self:GetPos()

        local filter = RecipientFilter()
        filter:AddAllPlayers()

        if not self:OnFootstep( pos, foot, sound, volume, filter ) then
            local intVolume = volume or 1
            local clompingLvl = 86
            if self:GetVelocity():LengthSqr() < self.RunSpeed^2 then
                clompingLvl = 76

            end
            clompingLvl = clompingLvl * mul

            self:EmitSound( "npc/zombie_poison/pz_left_foot1.wav", clompingLvl, math.random( 20, 30 ) / mul, intVolume / 1.5, CHAN_STATIC )
            self:EmitSound( sound, 88 * mul, 85 * mul, intVolume, CHAN_STATIC, sndFlags )

        end
    end
end

function ENT:isUnderWater()
    local currentNavArea = self:GetCurrentNavArea()
    if not currentNavArea then return false end
    if not currentNavArea:IsValid() then return false end
    return currentNavArea:IsUnderwater()

end

local vectorPositive125Z = Vector( 0,0,125 )

function ENT:confinedSlope( area1, area2 )
    if not area1 and area1:IsValid() then return end
    local ConfinedSlope = nil
    local HistoricArea1 = self.HistoricCSlopeArea1Id or -1
    if HistoricArea1 ~= area1:GetID() then
        self.HistoricCSlopeArea1Id = area1:GetID()
        self.IsConfined1 = self:isConfinedSlope( area1 )
    end
    if self.IsConfined1 then
        ConfinedSlope = true
        --print( ConfinedSlope )
    end

    if not area2 or not area2:IsValid() or area1 == area2 then return ConfinedSlope end
    local difference = math.abs( area1:GetCenter().z - area2:GetCenter().z )
    if difference < 5 then return end

    local HistoricArea2 = self.HistoricCSlopeArea2Id or -1
    if HistoricArea2 ~= area2:GetID() then
        self.HistoricCSlopeArea2Id = area2:GetID()
        self.IsConfined2 = self:isConfinedSlope( area2 )
    end
    if self.IsConfined2 then
        ConfinedSlope = true
    end
    return ConfinedSlope
end

function ENT:isConfinedSlope( area )
    if not area then return end
    local myShootPos = self:GetShootPos()
    local areaCenterOffsetted = area:GetCenter() + vectorPositive125Z
    local endZ = math.max( myShootPos.z, areaCenterOffsetted.z )
    local traceCheckPos = Vector( areaCenterOffsetted.x, areaCenterOffsetted.y, endZ )
    local traceData = {
        start = areaCenterOffsetted,
        endpos = traceCheckPos,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local trace = util.TraceLine( traceData )

    --debugoverlay.Line( areaC, trace.HitPos )
    if not trace.Hit then return end
    if trace.HitPos.z >= myShootPos.z then return end
    if trace.HitPos:DistToSqr( myShootPos ) > self.MoveSpeed^2 then return end

    local normal = trace.HitNormal
    local angle = normal:Angle()
    if math.cos( angle.p ) < 0 then return end

    return true

end

function ENT:ReallyAnger( time )
    local reallyAngryTime = self.terminator_ReallyAngryTime or CurTime()
    if reallyAngryTime < CurTime() then
        self:RunTask( "OnReallyAnger" )

    end
    self.terminator_ReallyAngryTime = math.max( reallyAngryTime + time, CurTime() )

end

function ENT:IsReallyAngry()
    local reallyAngryTime = self.terminator_ReallyAngryTime or CurTime()
    local checkIsReallyAngry = self.terminator_CheckIsReallyAngry

    if checkIsReallyAngry < CurTime() then
        self.terminator_CheckIsReallyAngry = CurTime() + 1
        local oldReallyAngryTime = reallyAngryTime
        local enemy = self:GetEnemy()

        if enemy and enemy.isTerminatorHunterKiller then
            reallyAngryTime = reallyAngryTime + 60

        elseif self:Health() < ( self:GetMaxHealth() * 0.5 ) then
            reallyAngryTime = reallyAngryTime + 10

        elseif self.isUnstucking then
            reallyAngryTime = reallyAngryTime + 20

        elseif self:inSeriousDanger() then
            reallyAngryTime = reallyAngryTime + 60

        elseif self:EnemyIsUnkillable() then
            reallyAngryTime = reallyAngryTime + 10

        end
        if reallyAngryTime ~= oldReallyAngryTime and oldReallyAngryTime <= CurTime() then
            self:RunTask( "OnReallyAnger" )

        end
    end

    local reallyAngry = reallyAngryTime > CurTime()
    self.terminator_ReallyAngryTime = math.max( reallyAngryTime, CurTime() )

    return reallyAngry

end


function ENT:Anger( time )
    local angryTime = self.terminator_AngryTime or CurTime()
    if angryTime < CurTime() then
        self:RunTask( "OnAnger" )

    end
    self.terminator_AngryTime = math.max( angryTime + time, CurTime() )

end

function ENT:IsAngry()
    local permaAngry = self.terminator_PermanentAngry

    if permaAngry then return true end
    local angryTime = self.terminator_AngryTime or CurTime()
    local checkIsAngry = self.terminator_CheckIsAngry

    if checkIsAngry < CurTime() then
        self.terminator_CheckIsAngry = CurTime() + math_Rand( 0.9, 1.1 )
        local oldAngryTime = angryTime
        local enemy = self:GetEnemy()

        if enemy and ( enemy.isTerminatorHunterKiller or enemy.terminator_CantConvinceImFriendly ) then
            self.terminator_PermanentAngry = true

        elseif self:Health() < ( self:GetMaxHealth() * 0.9 ) or self:IsOnFire() then
            self.terminator_PermanentAngry = true

        elseif self.isUnstucking then
            angryTime = angryTime + 6

        elseif self:inSeriousDanger() or self:EnemyIsUnkillable() then
            angryTime = angryTime + math.random( 5, 15 )

        elseif self:getLostHealth() > 0.5 then
            angryTime = angryTime + math.random( 1, 10 )

        elseif enemy and ( not self.IsSeeEnemy or self.DistToEnemy > self.MoveSpeed * 10 ) then
            angryTime = angryTime + 1.1

        elseif not IsValid( enemy ) and self:GetPath() and self:GetPath():GetLength() > 1000 then
            angryTime = angryTime + 3

        elseif self.terminator_FellOffPath then
            angryTime = angryTime + 8
            self.terminator_FellOffPath = nil

        elseif self.DistToEnemy > 0 and self.terminator_AngryNotSeeing and self.terminator_AngryNotSeeing > 60 then
            self.terminator_PermanentAngry = true

        end

        if not self.IsSeeEnemy then
            local angrynotseeing_Increment = self.terminator_AngryNotSeeing or 0
            self.terminator_AngryNotSeeing = angrynotseeing_Increment + 1

        end
        if angryTime ~= oldAngryTime and oldAngryTime <= CurTime() then
            self:RunTask( "OnAnger" )

        end
    end

    local angry = angryTime > CurTime()
    self.terminator_AngryTime = math.max( angryTime, CurTime() )

    return angry

end

function ENT:canDoRun()
    local angry = self:IsAngry()
    if not angry and self.IsSeeEnemy and self:Health() == self:GetMaxHealth() then return end

    if self.forcedShouldWalk and self.forcedShouldWalk > CurTime() then return end
    if self.isInTheMiddleOfJump then return end
    local nearObstacleBlockRunning = self.nearObstacleBlockRunning or 0
    if nearObstacleBlockRunning > CurTime() and not self.IsSeeEnemy then return end
    local area = self:GetCurrentNavArea()
    if not area then return end
    if area:HasAttributes( NAV_MESH_CLIFF ) then return end
    if area:HasAttributes( NAV_MESH_CROUCH ) then return end
    local nextArea = self:GetNextPathArea()
    if self:getMaxPathCurvature( area, self.MoveSpeed ) > 0.45 then return end
    if self:confinedSlope( area, nextArea ) == true then return end
    if not nextArea then return true end
    if not nextArea:IsValid() then return true end
    local myPos = self:GetPos()
    if myPos:DistToSqr( nextArea:GetClosestPointOnArea( myPos ) ) > ( self.MoveSpeed * 1.25 ) ^ 2 then return true end
    if nextArea:HasAttributes( NAV_MESH_CLIFF ) then return end
    if nextArea:HasAttributes( NAV_MESH_CROUCH ) then return end
    local minSizeNext = math.min( nextArea:GetSizeX(), nextArea:GetSizeY() )
    if minSizeNext < 25 then return end
    return true

end

function ENT:shouldDoWalk()
    if self.IsSeeEnemy and self:Health() == self:GetMaxHealth() then return true end
    if self.forcedShouldWalk and self.forcedShouldWalk > CurTime() then return true end

    local area = self:GetCurrentNavArea()
    if not area then return end
    if not area:IsValid() then return end
    local minSize = math.min( area:GetSizeX(), area:GetSizeY() )
    if minSize < 45 then return true end
    local nextArea = self:GetNextPathArea()
    if self:confinedSlope( area, nextArea ) then return true end
    if self:getMaxPathCurvature( area, self.WalkSpeed, true ) > 0.85 then return true end
    if not nextArea then return end
    if not nextArea:IsValid() then return end
    return true

end

local Squared60 = 60^2
local sideOffs = 8
local aboveHead = 70
local belowHead = 40

local headclearanceOffsets = {
    Vector( sideOffs, sideOffs, aboveHead ),
    Vector( -sideOffs, sideOffs, aboveHead ),
    Vector( -sideOffs, -sideOffs, aboveHead ),
    Vector( sideOffs, -sideOffs, aboveHead ),
    Vector( sideOffs, sideOffs, belowHead ),
    Vector( -sideOffs, sideOffs, belowHead ),
    Vector( -sideOffs, -sideOffs, belowHead ),
    Vector( sideOffs, -sideOffs, belowHead ),

}

function ENT:ShouldCrouch()
    if not self.CanCrouch then return false end

    if self:IsControlledByPlayer() then
        if self:ControlPlayerKeyDown( IN_DUCK ) then
            return true
        end

        return false
    else
        if self.overrideCrouch and self.overrideCrouch > CurTime() then return true end

        if self.m_Jumping then return true end

        local myPos = self:GetPos()

        local blockedCount = 0
        for _, check in ipairs( headclearanceOffsets ) do
            --debugoverlay.Cross( myPos + check, 1, 0.1 )
            if not util.IsInWorld( myPos + check ) then
                blockedCount = blockedCount + 1

            end
            if blockedCount >= 2 then
                self.overrideCrouch = CurTime() + 0.75 -- dont check as soon!
                return true

            end
        end

        if self:PathIsValid() then
            local currArea = self:GetCurrentNavArea()
            local nextArea, goalPathPoint = self:GetNextPathArea()
            if currArea and currArea:IsValid() and currArea:HasAttributes( NAV_MESH_CROUCH ) then
                self.overrideCrouch = CurTime() + 0.35
                return true
            elseif nextArea and nextArea:IsValid() and nextArea:HasAttributes( NAV_MESH_CROUCH ) and goalPathPoint.pos:DistToSqr( myPos ) < Squared60 then
                self.overrideCrouch = CurTime() + 0.35
                return true
            end
        end

        local hasToCrouchToSee = self:HasToCrouchToSeeEnemy()
        if hasToCrouchToSee == true then
            return true

        end

        return self:RunTask( "ShouldCrouch" ) or false
    end
end

local fivePositiveZ = Vector( 0,0,5 )
local fiftyZOffset = Vector( 0,0,50 )
local vector25Z = Vector( 0, 0, 25 )

function ENT:BoundsAdjusted( hullSizeMul, assumeCrouch )
    hullSizeMul = hullSizeMul or 1
    local b1, b2 = self:GetCollisionBounds()

    b1.x = b1.x * hullSizeMul
    b1.y = b1.y * hullSizeMul
    b2.x = b2.x * hullSizeMul
    b2.y = b2.y * hullSizeMul

    local zSquash = 0.35
    if self:IsCrouching() or assumeCrouch then
        zSquash = zSquash * 0.5

    end

    b1.z = b1.z * zSquash
    b2.z = b2.z * zSquash

    return b1, b2

end

local color_green = Color( 0, 255, 0 )
local color_red = Color( 255, 0, 0 )

local random1 = Vector( 0, 0, 0 )
local random2 = Vector( 0, 0, 0 )

-- find pos to path to, for geting around any kind of obstacle
function ENT:PosThatWillBringUsTowards( startPos, aheadPos, maxAttempts )
    maxAttempts = maxAttempts or 250
    local timerName = "terminator_obliteratetowardscache_" .. self:GetCreationID()
    timer.Remove( timerName )
    timer.Create( timerName, 0.9, 1, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        self.cachedBringUsTowards = nil
        self.nextBringUsTowardsCache = nil

    end )

    -- lots of traces ahead, use caching please!
    local nextCache = self.nextBringUsTowardsCache or 0
    if nextCache > CurTime() and self.cachedBringUsTowards then return self.cachedBringUsTowards end
    self.nextBringUsTowardsCache = CurTime() + 0.8

    local b1,b2 = self:BoundsAdjusted( 0.75 )
    local mask = self:GetSolidMask()
    local cgroup = self:GetCollisionGroup()

    local aheadPosOffGround = aheadPos + vec_up15
    local dir = terminator_Extras.dirToPos( startPos, aheadPosOffGround )

    local trLength = math.Clamp( startPos:Distance( aheadPosOffGround ), 100, 400 )
    local defEndPos = startPos + ( dir * trLength )

    -- do a trace in the dir we goin, likely flattened direction to next segment
    -- starts even more traces if this trace hits something
    local dirConfig = {
        start = startPos,
        endpos = defEndPos,
        mins = b1,
        maxs = b2,
        filter = self,
        mask = mask,
        collisiongroup = cgroup,
    }

    local dirResult = util.TraceHull( dirConfig )

    if dirResult.Hit then

        -- table of scores for table.maxn
        local potentialClearPositionsScored = {}
        local bestScore = 0
        local wasAClearBestScore

        -- the positions
        local potentialClearHitPositions = {}
        -- table of fractions for checks, to see if they actually get us "there"
        local potentialClearPositionFractions = {}

        local attempts = 1
        local traceDist = 1
        local jumpHeight = self.loco:GetMaxJumpHeight()
        local stepHeight = self.loco:GetStepHeight()

        local nextYield = 50

        -- most of these will fail, allow lots!
        while attempts < maxAttempts do
            yieldIfWeCan()
            attempts = attempts + 0.25

            -- if we're just at the start, try to stay close in case we're in a hallway or something
            -- after a while just go all out, big traces
            local doBigTraces = attempts > 55
            local zMul = 0.65
            local randCompDivisor = 7
            if doBigTraces then
                -- allow bigger Z offsets, divide the random components less
                zMul = 0.8
                randCompDivisor = 4

            end

            local offsetScale = math.log( traceDist, 10 ) * 150

            random1:Random( -1, 1 )
            random2:Random( -1, 1 )

            local trueRandComp = random1 * offsetScale / randCompDivisor
            local offset = random2
            offset = dir:Cross( offset ) * offsetScale
            offset = offset + trueRandComp
            offset.z = offset.z * zMul
            local newStartPos = startPos + offset

            local diff = ( newStartPos.z - startPos.z )
            if diff > jumpHeight then
                newStartPos.z = newStartPos.z + ( jumpHeight - diff )

            end

            if not util.IsInWorld( newStartPos ) then
                if doBigTraces then
                    traceDist = traceDist + 2

                else
                    traceDist = traceDist + -1

                end
                continue

            end

            -- proper attempt, we're about to do a trace
            attempts = attempts + 1

            if doBigTraces then
                traceDist = traceDist + 0.5

            else
                traceDist = traceDist + 0.1

            end

            if nextYield < attempts then
                nextYield = attempts + 50
                yieldIfWeCan()

            end

            if not self:ClearOrBreakable( startPos, newStartPos ) then
                if doBigTraces then
                    traceDist = traceDist + 2

                else
                    traceDist = traceDist + -1

                end
                continue

            end

            --debugoverlay.Line( startPos, newStartPos, 5, color_white, true )

            local newEndPos = defEndPos + offset
            local haveToJump = math.abs( newStartPos.z - startPos.z ) > stepHeight

            dirConfig.start = newStartPos
            dirConfig.endpos = newEndPos

            dirResult = util.TraceHull( dirConfig )

            local currScore

            -- perfect trace!
            if not dirResult.Hit and self:ClearOrBreakable( dirResult.HitPos, aheadPosOffGround, false, 2 ) and not haveToJump then
                --debugoverlay.Line( startPos, newStartPos, 5, color_green, true )
                --debugoverlay.Line( newStartPos, newEndPos, 5, color_green, true )
                self.cachedBringUsTowards = newStartPos
                return newStartPos

            end
            -- imperfect, rank it!
            if not dirResult.StartSolid then
                currScore = dirResult.Fraction
                -- bonus score, it hit something passable!
                local hitPassable = self:hitBreakable( dirConfig, dirResult )
                if hitPassable then
                    currScore = currScore + 1

                end
                -- only do the trace check if this is a contender for the best fraction
                if currScore > bestScore then
                    -- if there's a doorway, start picking ones that only go through the doorway
                    local isATrulyClearTrace = self:ClearOrBreakable( dirResult.HitPos, aheadPosOffGround )
                    if isATrulyClearTrace or wasAClearBestScore then
                        currScore = math.Clamp( currScore, 0, math_Rand( 1.4, 1.5 ) )

                    end
                    if isATrulyClearTrace and not wasAClearBestScore then
                        wasAClearBestScore = true
                        bestScore = 0

                    end
                elseif not haveToJump then
                    currScore = currScore * 2

                end
            end
            if currScore then
                potentialClearPositionsScored[ currScore ] = newStartPos

                potentialClearHitPositions[ currScore ] = dirResult.HitPos
                potentialClearPositionFractions[ currScore ] = fractionCurr
                bestScore = table.maxn( potentialClearPositionsScored )

            end
        end
        local bestFraction = potentialClearPositionsScored[ bestScore ]
        local bestHitPosition = potentialClearHitPositions[ bestScore ]

        if not bestHitPosition then return nil, true end

        local clear = self:ClearOrBreakable( bestHitPosition, aheadPosOffGround )
        -- best fraction doesnt get us there
        if not bestFraction or ( bestScore < 0.35 ) or not clear then
            --debugoverlay.Line( bestHitPosition, aheadPosOffGround, 5, color_red, true )
            --debugoverlay.Cross( aheadPosOffGround, 10, 5, color_red, true )
            return bestFraction, true

        else
            --debugoverlay.Line( startPos, bestFraction, 5, color_green, true )

        end

        --debugoverlay.Box( bestFraction, b1, b2, 2, color_white )

        self.cachedBringUsTowards = bestFraction
        return bestFraction

    else
        self.cachedBringUsTowards = dirResult.HitPos
        return dirResult.HitPos

    end
end

local scalar = 0.75

-- simple check, can the bot exist left/right in the direction of the goal.
function ENT:CanStepAside( dir, goal )

    -- attempt to make bot ignore this when stuck in stuff
    local crouch = self.overrideCrouch or 0
    if crouch > CurTime() then return false end

    local pos = self:GetPos() + vec_up15
    local b1,b2 = self:BoundsAdjusted( scalar )
    local mask = self:GetSolidMask()
    local cgroup = self:GetCollisionGroup()

    local distToTrace = ( pos - goal ):Length2D()
    distToTrace = math.Clamp( distToTrace, 32, 64 )

    local defEndPos = pos + dir * distToTrace

    local myRight = self:GetRight()
    local rightOffset = ( myRight * distToTrace )

    local filter = TrFilterNoSelf( self )

    -- do a trace in the dir we goin, likely flattened direction to next segment
    local dirConfigLeft = {
        start = pos - rightOffset,
        endpos = defEndPos - rightOffset,
        mins = b1,
        maxs = b2,
        filter = filter,
        mask = mask,
        collisiongroup = cgroup,
    }

    local leftResult = util.TraceHull( dirConfigLeft )

    --local color = Color( 255, 255, 255, 25 )
    --if leftResult.Hit then color = Color( 255,0,0, 25 ) end
    --debugoverlay.Box( leftResult.HitPos, dirConfigLeft.mins, dirConfigLeft.maxs, 4, color )

    if not leftResult.Hit or self:hitBreakable( dirConfigLeft, leftResult ) then
        return true

    end

    local dirConfigRight = {
        start = pos + rightOffset,
        endpos = defEndPos + rightOffset,
        mins = b1,
        maxs = b2,
        filter = filter,
        mask = mask,
        collisiongroup = cgroup,
    }

    local rightResult = util.TraceHull( dirConfigRight )

    --local color = Color( 255, 255, 255, 25 )
    --if rightResult.Hit then color = Color( 255,0,0, 25 ) end
    --debugoverlay.Box( rightResult.HitPos, dirConfigRight.mins, dirConfigRight.maxs, 4, color )

    if not rightResult.Hit or self:hitBreakable( dirConfigRight, rightResult ) then
        return true

    end
    return false

end

-- rewrite this because the old logic was not working
-- return 0 when no blocker
-- returns 1 when its blocked but it can jump over
-- returns 2 when there's an obstacle that can't be jumped over, bot should respond by stepping back
function ENT:GetJumpBlockState( dir, goal )

    local enemy = self:GetEnemy()
    local pos = self:GetPos() + vec_up15
    local b1,b2 = self:BoundsAdjusted( scalar )
    local step = self.loco:GetStepHeight() * scalar
    local mask = self:GetSolidMask()
    local cgroup = self:GetCollisionGroup()

    local distToTrace = ( pos - goal ):Length2D()
    distToTrace = math.Clamp( distToTrace, 32, 64 )

    local defEndPos = pos + dir * distToTrace

    local filter = { enemy, self }

    -- do a trace in the dir we goin, likely flattened direction to next segment
    -- starts even more traces if this trace hits something
    local dirConfig = {
        start = pos,
        endpos = defEndPos,
        mins = b1,
        maxs = b2,
        filter = filter,
        mask = mask,
        collisiongroup = cgroup,
    }

    local dirResult = util.TraceHull( dirConfig )

    local didSight
    local sightResult

    -- if there's nothing to jump up to then just rely on dirResult
    -- this was added to detect if we're underneath like a overhanging ledge or catwalk we have to jump onto
    if goal.z > pos.z + 50 then
        didSight = true
        local sightConfig = {
            start = pos + fiftyZOffset,
            endpos = goal + fiftyZOffset,
            mins = b1,
            maxs = b2,
            filter = filter,
            mask = mask,
            collisiongroup = cgroup,
        }

        sightResult = util.TraceHull( sightConfig )

    end

    local checksThatHit = 0

    -- we got up to enemy, dont jump over them....
    if dirResult.Hit and IsValid( enemy ) and dirResult.Entity == enemy then
        return 0

    end

    -- ok something is blocking us, or we need to jump up to something
    if dirResult.Hit or ( didSight and sightResult.Hit ) then
        -- final trace to see if a jump at height will actually take us all the way to goal
        local finalCheckConfig = {
            mins = b1 * scalar,
            maxs = b2 * scalar,
            filter = filter,
            mask = mask,
            collisiongroup = cgroup,
        }
        local finalCheckResult

        -- do a trace from our pos to the jump offset's starting pos, finds ceilings, etc
        local vertConfig = {
            start = pos + fiftyZOffset,
            endpos = pos + fiftyZOffset,
            mins = b1 * 1.25,
            maxs = b2 * 1.25,
            filter = filter,
            mask = mask,
            collisiongroup = cgroup,
        }
        local vertResult

        local maxjump = self.JumpHeight * 2

        local height = 0

        local offset = Vector( 0, 0, height )
        local goalWithOverriddenZ = Vector( goal.x, goal.y, 0 )

        while height <= maxjump do
            yieldIfWeCan()

            offset.z = height
            height = math.Round( math.min( height + step, maxjump ) )

            local newEndPos = defEndPos + offset
            local newStartPos = pos + offset

            vertConfig.endPos = newStartPos
            vertResult = util.TraceHull( vertConfig )
            -- vertConfig goes from the last start of the can step check, to the next start, so it checks if there's vertical space
            vertConfig.start = newStartPos

            -- ceiling, we cant jump up here
            if vertResult.Hit and not self:hitBreakable( vertConfig, vertResult ) then
                --local color = Color( 255, 255, 255, 25 )
                --if vertResult.Hit then color = Color( 255,0,0, 25 ) end
                --debugoverlay.Box( vertResult.HitPos, vertConfig.mins, vertConfig.maxs, 4, color )
                return 2 -- step back bot!
            end

            dirConfig.start = newStartPos
            dirConfig.endpos = newEndPos

            dirResult = util.TraceHull( dirConfig )

            local hitThingWeCanBreak = self:hitBreakable( dirConfig, dirResult )

            -- final check!
            goalWithOverriddenZ.z = math.max( dirConfig.start.z, goal.z + 30 )
            finalCheckConfig.start = newStartPos
            finalCheckConfig.endpos = goalWithOverriddenZ

            finalCheckResult = util.TraceHull( finalCheckConfig )

            -- if we are above the goal or, if we can see it
            -- stops bot from jumping in hallways
            local thisCheckCanCompleteJump = newStartPos.z >= goal.z

            --debugoverlay.Line( dirConfig.start, finalCheckResult.HitPos, 2 )

            -- if we hit a wall, checks hitnormal so it doesnt try to jump up slopes as often, or try to jump over walls that are diagonal to direction it's moving in
            local checkHit = dirResult.Hit and dirResult.HitNormal:Dot( dir ) < -0.5 and dirResult.HitNormal:Dot( vector_up ) < 0.5 and not hitThingWeCanBreak

            --local color = Color( 255, 255, 255, 25 )
            --if checkHit then color = Color( 255,0,0, 25 ) end
            --debugoverlay.Box( dirResult.HitPos, dirConfig.mins, dirConfig.maxs, 1, color )

            if checkHit then
                checksThatHit = checksThatHit + 1

            end
            if ( not checkHit and thisCheckCanCompleteJump ) or not finalCheckResult.Hit then
                -- obstacle to jump over!
                if checksThatHit >= 1 then
                    return 1, dirConfig.start, height, dirConfig.endpos

                -- never hit anything, proceed as normal
                else
                    return 0

                end
            end

            if height >= maxjump then break end
        end

        return 2 -- step back bot!
    end

    --local color = Color( 255, 255, 255, 25 )
    --if dirResult.Hit then color = Color( 255,0,0, 25 ) end
    --debugoverlay.Box( dirResult.HitPos, dirConfig.mins, dirConfig.maxs, 4, color )

    return 0
end

function ENT:ChooseBasedOnVisible( check, potentiallyVisible )
    local b1, b2 = self:BoundsAdjusted()
    local mask = self:GetSolidMask()
    local collisiongroup = nil
    collisiongroup = self:GetCollisionGroup()

    local minsBelow = b1 * 0.5
    local maxsBelow = b2 * 0.5
    local minsAbove = b1 * 1.25
    local maxsAbove = b2 * 1.25

    local theTrace = {
        filter = TrFilterNoSelf( self ),
        start = check,
        endpos = nil,
        mask = mask,
        collisiongroup = collisiongroup,
    }

    for index, potentialVisible in ipairs( potentiallyVisible ) do
        if potentialVisible then
            if potentialVisible.z < check.z then
                theTrace.mins = minsBelow
                theTrace.maxs = maxsBelow

            -- be more strict with gaps when the goal is above us!
            -- stops spam jumping into walls, legacy issue
            else
                theTrace.mins = minsAbove
                theTrace.maxs = maxsAbove

            end

            theTrace.endpos = potentialVisible
            local result = util.TraceHull( theTrace )
            local hitBreakable = self:hitBreakable( theTrace, result )
            if not result.Hit or hitBreakable then
                --debugoverlay.Line( check, potentialVisible, 1, Color( 255,255,255 ), true )
                return potentialVisible, index, hitBreakable

            else
                --debugoverlay.Box( result.HitPos, theTrace.mins, theTrace.maxs, 1, Color( 255,255,255 ) )

            end
        end
    end
    return nil

end

function ENT:MoveInAirTowardsVisible( toChoose, destinationArea )
    local myPos = self:GetPos()
    local nextPos, indexThatWasVisible, hitBreakable = self:ChooseBasedOnVisible( myPos, toChoose )

    if nextPos then
        local myVel = self.loco:GetVelocity()
        local subtProduct = nextPos - myPos
        local subtFlattened = subtProduct
        subtFlattened.z = 0

        local dir = ( subtProduct ):GetNormalized()
        local dist2d = subtFlattened:Length2D()
        local dist2dMaxed = math.Clamp( dist2d, 0, self.RunSpeed )

        local dirProportional = dir * math.Clamp( self.RunSpeed * 0.8, self.RunSpeed / 5, dist2dMaxed + 50 )


        myVel.x = dirProportional.x
        myVel.y = dirProportional.y
        -- only touch z of vel if goal is below us!
        if dir.z < -0.75 then
            myVel.z = math.Clamp( myVel.z, -math.huge, myVel.z * 0.9 )

        end

        if self:IsReallyAngry() then
            self.overrideCrouch = CurTime() + 0.15

        else
            self.overrideCrouch = CurTime() + 0.75

        end

        local beginSetposCrouchJump = IsValid( destinationArea ) and indexThatWasVisible <= 4 and destinationArea:HasAttributes( NAV_MESH_CROUCH ) and not hitBreakable
        local justSetposUsThere = IsValid( destinationArea ) and ( self.WasSetposCrouchJump or beginSetposCrouchJump ) and myPos:DistToSqr( destinationArea:GetClosestPointOnArea( myPos ) ) < 40^2

        -- i HATE VENTS!
        if justSetposUsThere then
            local setPosDist = math.Clamp( dist2d, 5, 35 )
            self:SetPosNoTeleport( myPos + dir * setPosDist )
            self.loco:SetVelocity( dir * setPosDist )
            self.WasSetposCrouchJump = true

        else
            self.loco:SetVelocity( myVel )

        end
        return true

    else
        return false

    end
end

local cheats = GetConVar( "sv_cheats" )

-- used in determining whether to look at and therefore beat up an inert entity
function ENT:EntIsInMyWay( ent, tolerance, aheadSegment )
    local myPos = self:GetPos()
    local segmentAheadOfMe = aheadSegment
    local _
    if not istable( segmentAheadOfMe ) then
        _, segmentAheadOfMe = self:GetNextPathArea( self:GetTrueCurrentNavArea() )

    end
    if not istable( segmentAheadOfMe ) then return end -- we tried

    local angleToAhead = terminator_Extras.dirToPos( myPos, segmentAheadOfMe.pos ):Angle()
    local entsNearestPosToMe = ent:NearestPoint( self:GetShootPos() )
    local bearingToEnt = terminator_Extras.BearingToPos( myPos, angleToAhead, entsNearestPosToMe, angleToAhead )
    bearingToEnt = math.abs( bearingToEnt )

    if bearingToEnt > tolerance then
        return true, bearingToEnt

    end
    return false, bearingToEnt

end

local speedToConsiderSmallJumps = 30^2
local defaultSpeedToAimAtProps = 30^2
local interruptedSpeedToAimAtProps = 100^2

--[[------------------------------------
    Name: NEXTBOT:MoveAlongPath
    Desc: (INTERNAL) Process movement along path.
    Arg1: bool | lookatgoal | Should bot look at goal while moving.
    Ret1: bool | Path was completed right now
    overriden to fuck with the broken jumping, hopefully making it more reliable.
--]]------------------------------------
function ENT:MoveAlongPath( lookatgoal )
    local myTbl = self:GetTable()
    local path = self:GetPath()
    --local drawingPath

    if self.DrawPath:GetBool() and cheats:GetBool() == true then
        path:Draw()
        --drawingPath = true

    end
    local myPos = self:GetPos()
    local myArea = self:GetTrueCurrentNavArea()
    local iAmOnGround = myTbl.loco:IsOnGround()
    local _, aheadSegment = self:GetNextPathArea( myArea ) -- top of the jump
    local currSegment = path:GetCurrentGoal() -- maybe bottom of the jump, paths are stupid

    if not aheadSegment then
        aheadSegment = currSegment
    end

    if not currSegment then return false end

    local cur = CurTime()

    local aheadType = aheadSegment.type
    local currType = currSegment.type

    local aheadArea = aheadSegment.area

    local laddering = aheadType == 4 or currType == 4 or aheadType == 5 or currType == 5
    local disrespecting = self:GetCachedDisrespector()
    local speedToStopLookingFarAhead = defaultSpeedToAimAtProps
    if IsValid( disrespecting ) then
        local myNearestPointToIt = self:NearestPoint( disrespecting:WorldSpaceCenter() )
        local itsNearestPointToMyNearestPoint = disrespecting:NearestPoint( myNearestPointToIt )
        if myNearestPointToIt:DistToSqr( itsNearestPointToMyNearestPoint ) < 8^2 then
            self:PhysicallyPushEnt( disrespecting, 250 )

        end
        if not myTbl.LookAheadOnlyWhenBlocked and self:EntIsInMyWay( disrespecting, 140, aheadSegment ) then
            speedToStopLookingFarAhead = interruptedSpeedToAimAtProps

        end
    end
    local lookAtPos
    local myVelLengSqr = myTbl.loco:GetVelocity():LengthSqr()
    local movingSlow = myVelLengSqr < speedToStopLookingFarAhead
    local hint = myTbl.lastHeardSoundHint
    local curiosity = 0.5

    local lookAtEnemyLastPos = myTbl.LookAtEnemyLastPos or 0
    local shouldLookTime = lookAtEnemyLastPos > cur

    if hint and hint.valuable then
        curiosity = 2

    end

    if not myTbl.IsSeeEnemy and myTbl.interceptPeekTowardsEnemy and myTbl.lastInterceptTime + 2 > cur then
        lookAtPos = myTbl.lastInterceptPos

    elseif myTbl.TookDamagePos then
        lookAtPos = myTbl.TookDamagePos

    elseif lookatgoal and not myTbl.IsSeeEnemy and hint and hint.time + curiosity > cur then
        lookAtPos = hint.source

    elseif lookatgoal and not myTbl.IsSeeEnemy and ( shouldLookTime or ( math.random( 1, 100 ) < 3 and self:CanSeePosition( myTbl.EnemyLastPos ) ) ) then
        if not shouldLookTime then
            myTbl.LookAtEnemyLastPos = cur + curiosity

        end
        lookAtPos = myTbl.EnemyLastPos

    elseif lookatgoal and laddering then
        lookAtPos = myPos + self:GetVelocity() * 100

    elseif ( lookatgoal or movingSlow ) and self:PathIsValid() then
        lookAtPos = aheadSegment.pos + vec_up25

        if not self:IsOnGround() or movingSlow then
            if IsValid( disrespecting ) then
                lookAtPos = self:getBestPos( disrespecting )
                --debugoverlay.Cross( lookAtPos, 10, 10, color_white, true )

            else
                lookAtPos = aheadSegment.pos + vec_up25

            end
        elseif lookAtPos:DistToSqr( myPos ) < 400^2 then
            -- attempt to look farther ahead
            local _, segmentAheadOfUs = self:GetNextPathArea( myArea, 3, true )
            if segmentAheadOfUs then
                lookAtPos = segmentAheadOfUs.pos  + vec_up25

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

        self:SetDesiredEyeAngles( ang )

    end

    if laddering then
        local result = self:TermHandleLadder( aheadSegment, currSegment )
        if result == false then
            return result

        end
        return
    end

    if myTbl.terminator_HandlingLadder then
        self:ExitLadder( aheadSegment.pos )
        myTbl.terminator_HandlingLadder = nil

    end

    -- respect transient areas!
    if aheadArea:HasAttributes( NAV_MESH_TRANSIENT ) and not self:transientAreaPathable( aheadArea, aheadArea:GetID() ) then
        self:Anger( 10 )
        self:InvalidatePath( "was going into untraversable transient area" )
        return

    end

    local doPathUpdate = nil
    local obstacleAvoid = myTbl.m_PathObstacleAvoidPos
    if obstacleAvoid then
        local obstacleTarget = myTbl.m_PathObstacleAvoidTarget

        local obstacleGoal = myTbl.m_PathObstacleGoal
        if not obstacleGoal then
            obstacleGoal = aheadSegment.pos
            myTbl.m_PathObstacleGoal = obstacleGoal

        end

        -- it got us along the path
        local progressed = obstacleGoal and obstacleGoal ~= aheadSegment.pos
        if progressed then
            if myTbl.m_PathObstacleRebuild then
                self:InvalidatePath( "obstacle avoid 1" )
                return

            end
            myTbl.m_PathObstacleGoal = nil
            myTbl.m_PathObstacleAvoidPos = nil
            myTbl.m_PathObstacleAvoidTarget = nil
            myTbl.m_PathObstacleAvoidTimeout = 0
            return

        end

        -- failed
        local _, _, seePos = self:ClearOrBreakable( myPos + vec_up15, obstacleAvoid + vec_up15 )
        local _, _, seeGoal = self:ClearOrBreakable( myPos + vec_up15, obstacleTarget + vec_up15 )

        if not seePos or seeGoal then
            --debugoverlay.Line( myPos + vec_up15, obstacleAvoid + vec_up15, 0.5, color_white, true )
            --debugoverlay.Line( myPos + vec_up15, obstacleTarget + vec_up15, 0.5, color_green, true )
            self:InvalidatePath( "obstacle avoid 2" )
            return

        end

        local goingTo = obstacleAvoid

        -- cut the corner if we can
        if seeGoal then
            local offsetDist = math.Clamp( myPos:Distance( obstacleAvoid ), 50, math.huge ) * 2
            local offset = terminator_Extras.dirToPos( obstacleAvoid, obstacleTarget ) * offsetDist
            local correctedPos = obstacleAvoid + offset
            goingTo = correctedPos

        end

        local distToPos = self:NearestPoint( goingTo ):DistToSqr( goingTo )
        local atAvoidPos = not seeGoal and distToPos < 1
        if seeGoal then
            myTbl.m_PathObstacleAvoidTimeout = myTbl.m_PathObstacleAvoidTimeout + -0.2

        end

        local timeout = myTbl.m_PathObstacleAvoidTimeout < cur

        if timeout or atAvoidPos then
            if myTbl.m_PathObstacleRebuild then
                self:InvalidatePath( "obstacle avoid 3" )
                return

            end
            myTbl.m_PathObstacleGoal = nil
            myTbl.m_PathObstacleRebuild = nil
            myTbl.m_PathObstacleAvoidPos = nil
            myTbl.m_PathObstacleAvoidTarget = nil
            myTbl.m_PathObstacleAvoidTimeout = 0

        else
            --debugoverlay.Line( myPos, goingTo, 0.5, color_white, true )
            --debugoverlay.Line( myPos, obstacleAvoid, 0.5, color_green, true )
            --debugoverlay.Cross( obstacleAvoid, 15, 0.5, color_white, true )

            self:GotoPosSimple( goingTo, 0, true )
            return

        end
    end

    local checkTolerance = myTbl.PathGoalTolerance * 4

    --figuring out what kind of terrian we passing
    -- filter with me + my children
    local filterTbl = TrFilterNoSelf( self )

    -- check if normal path is actually gap
    local reallyJustAGap = nil
    local middle = ( aheadSegment.pos + currSegment.pos ) / 2
    if currType == 0 then
        local floorTraceDat = {
            start = middle + vector_up * 50,
            endpos = middle + down * 125,
            filter = filterTbl,
            maxs = gapJumpHull,
            mins = -gapJumpHull,
        }

        local result = util.TraceHull( floorTraceDat )
        local lowestSegmentsZ = math.min( currSegment.pos.z, aheadSegment.pos.z )

        if not result.Hit then
            reallyJustAGap = true

        elseif result.HitPos.z < lowestSegmentsZ + -myTbl.loco:GetStepHeight() * 2 then
            reallyJustAGap = true
            --debugoverlay.Cross( aheadSegment.pos, 10, 10, color_white, true )
            --debugoverlay.Cross( middle, 10, 10, color_white, true )
            --debugoverlay.Cross( result.HitPos, 10, 10, color_white, true )

        end
        -- if hit but started solid?
        if result.StartSolid then
            reallyJustAGap = nil

        end

    end

    -- check if dropping down is actually a gap
    local droppingType = aheadType == 1 or currType == 1
    local dropIsReallyJustAGap = nil
    if droppingType then
        local _, jumpBottomSeg = self:GetNextPathArea( myArea )
        local _, segAfterTheDrop = self:GetNextPathArea( myArea, 1 )
        if jumpBottomSeg and segAfterTheDrop then
            local middleWeighted = ( currSegment.pos + ( jumpBottomSeg.pos * 0.5 ) ) / 1.5

            local floorTraceDat = {
                start = middleWeighted + vec_up25,
                endpos = middleWeighted + down * 3000,
                filter = filterTbl,
                maxs = gapJumpHull,
                mins = -gapJumpHull,
            }

            local result = util.TraceHull( floorTraceDat )
            local hitBelowDest = result.HitPos.z < ( segAfterTheDrop.pos.z + -65 )

            --debugoverlay.Line( floorTraceDat.start, result.HitPos, 10, color_white, true )
            --debugoverlay.Cross( segAfterTheDrop.pos, 10, 10 )

            if hitBelowDest and not result.StartSolid then
                dropIsReallyJustAGap = true
                aheadSegment = segAfterTheDrop
                myTbl.m_PathObstacleAvoidPos = nil
                myTbl.wasADropTypeInterpretedAsAGap = true

            end
            -- landed jump, recalculate
            if iAmOnGround and myPos.z < segAfterTheDrop.pos.z + 25 and myTbl.wasADropTypeInterpretedAsAGap then
                self:InvalidatePath( "did a fake dropdown gap jump" )
                return false

            end
        end
    end

    -- check if jumping over a gap is ACTUALLY jumping over a gap, should stop jumping up krangled stairs.
    local realGapJump = nil
    if aheadType == 3 or currType == 3 then

        local middleOfGapHighestPoint = middle
        middleOfGapHighestPoint.z = math.max( currSegment.pos.z, aheadSegment.pos.z )

        local noWallToJumpOverTrace = {
            start = myPos + vec_up25,
            endpos = middleOfGapHighestPoint,
            filter = filterTbl,
            maxs = gapJumpHull,
            mins = -gapJumpHull,
        }

        local noWallResult = util.TraceHull( noWallToJumpOverTrace )

        if noWallResult.Hit then
            realGapJump = noWallResult.HitPos:DistToSqr( noWallToJumpOverTrace.start ) < 40^2 -- well there's something to jump over!

        else
            local floorTraceDat = {
                start = middleOfGapHighestPoint,
                endpos = middle + down * 40,
                filter = filterTbl,
                maxs = gapJumpHull,
                mins = -gapJumpHull,
            }

            local result = util.TraceHull( floorTraceDat )
            --debugoverlay.Cross( middle, 10, 1, color_white, true )

            if not result.Hit then
                realGapJump = true

            end
            -- if hit but started solid?
            if result.StartSolid then
                realGapJump = nil

            end

            if result.HitPos.z < aheadSegment.pos.z + -myTbl.loco:GetStepHeight() then
                realGapJump = true

            end
        end
    end

    local sqrDistToGoal = myPos:DistToSqr( currSegment.pos )
    local closeToGoal = sqrDistToGoal < ( checkTolerance ^ 2 )
    local validDroptypeInterpretedAsGap = dropIsReallyJustAGap and ( sqrDistToGoal < ( checkTolerance * 3 ) ^ 2 )
    local gapping = realGapJump or reallyJustAGap or validDroptypeInterpretedAsGap
    if gapping then
        checkTolerance = checkTolerance * 0.25

    end

    local isHandlingJump = false
    local doingJump = nil

    local jumptype = aheadType == 2 or currType == 2 or realGapJump or reallyJustAGap or validDroptypeInterpretedAsGap
    local droptype = droppingType and not dropIsReallyJustAGap
    local dropTypeToDealwith = droptype and closeToGoal

    local good = self:PathIsValid() and iAmOnGround
    local areaSimple = self:GetCurrentNavArea()

    local myHeightToNext = aheadSegment.pos.z - myPos.z
    local jumpableHeight = myHeightToNext < myTbl.JumpHeight

    if areaSimple and good then

        -- dont jump if we're trying to jump up stairs!
        local tryingToJumpUpStairs = areaSimple and areaSimple:HasAttributes( NAV_MESH_STAIRS )
        if tryingToJumpUpStairs and aheadArea ~= areaSimple then
            tryingToJumpUpStairs = aheadArea:IsFlat() or areaSimple:IsFlat() or aheadArea:HasAttributes( NAV_MESH_STAIRS )

        end
        local blockJump = areaSimple:HasAttributes( NAV_MESH_NO_JUMP ) or tryingToJumpUpStairs or prematureGapJump

        if IsValid( areaSimple ) and jumpableHeight and not blockJump and ( myTbl.nextPathJump or 0 ) < cur then
            local dir = aheadSegment.pos-myPos
            dir.z = 0
            dir:Normalize()

            local jumpstate, jumpBlockerJumpOver, jumpingHeight, jumpBlockClearPos = self:GetJumpBlockState( dir, aheadSegment.pos )

            myTbl.moveAlongPathJumpingHeight = jumpingHeight or myTbl.moveAlongPathJumpingHeight
            myTbl.jumpBlockerJumpOver = jumpBlockerJumpOver or myTbl.jumpBlockerJumpOver

            -- jump height that matches gap we're jumping over
            if gapping and aheadSegment then
                jumpingHeight = ( myPos - aheadSegment.pos ):Length2D() * 0.8
                if jumpingHeight > 0 then
                    jumpingHeight = jumpingHeight + myHeightToNext

                end
                --debugoverlay.Line( currSegment.pos, aheadSegment.pos, 10, color_white, true )

            end
            -- jumping and GetJumpBlockState didnt give us a jump height
            if jumptype and not jumpingHeight then
                jumpingHeight = myHeightToNext

            end
            -- finally, got a height, clamp it to at LEAST the height diff to next area
            if jumpingHeight and myHeightToNext then
                jumpingHeight = math.Clamp( jumpingHeight, myHeightToNext, math.huge )

            end

            local smallObstacle = jumpstate == 1 and jumpingHeight
            local smallObstacleBlocking = smallObstacle and ( myVelLengSqr < speedToConsiderSmallJumps or myTbl.wasDoingJumpOverSmallObstacle ) and not self:CanStepAside( dir, aheadSegment.pos )
            local needsToFeelAround
            if jumpstate == 2 then
                local nextAreasClosestPoint = aheadArea:GetClosestPointOnArea( myPos )
                local myAreasClosestPointToNext = areaSimple:GetClosestPointOnArea( nextAreasClosestPoint )
                needsToFeelAround = ( nextAreasClosestPoint.z - myAreasClosestPointToNext.z ) > myTbl.loco:GetStepHeight()

            end

            --print( myHeightToNext, myTbl.loco:GetStepHeight() )
            --print( aheadType == 2, currType == 2, realGapJump, reallyJustAGap, validDroptypeInterpretedAsGap )
            --print( jumpstate, smallObstacle, jumptype, dropTypeToDealwith, smallObstacleBlocking, areaSimple:HasAttributes( NAV_MESH_JUMP ), droptype and jumpstate == 1, myTbl.m_PathJump and jumpstate == 1, jumpstate == 2, needsToFeelAround )
            if
                jumptype or                                                     -- jump segment
                dropTypeToDealwith or
                smallObstacleBlocking or
                areaSimple:HasAttributes( NAV_MESH_JUMP ) or                    -- jump area
                droptype and jumpstate == 1 or                                  -- dropping down and there's obstacle
                myTbl.m_PathJump and jumpstate == 1 or
                jumpstate == 2 or
                needsToFeelAround

            then
                local beenCloseToTheBottomOfTheJump = closeToGoal or myTbl.beenCloseToTheBottomOfTheJump
                myTbl.beenCloseToTheBottomOfTheJump = beenCloseToTheBottomOfTheJump

                -- obstacle, we have to move around if we want to go past it
                if jumpstate == 2 then
                    local _, bitFurtherAheadSegment = self:GetNextPathArea( myArea, 1 )
                    if not bitFurtherAheadSegment then
                        bitFurtherAheadSegment = aheadSegment

                    end

                    --debugoverlay.Cross( bitFurtherAheadSegment.pos, 10, 5, color_white, true )

                    local reverseOffs = -dir * 15
                    local goodPosToGoto, wasNothingGreat = self:PosThatWillBringUsTowards( myPos + reverseOffs + vec_up15, bitFurtherAheadSegment.pos )
                    myTbl.m_PathJump = true
                    myTbl.m_PathObstacleAvoidPos = goodPosToGoto
                    myTbl.m_PathObstacleAvoidTarget = bitFurtherAheadSegment.pos
                    myTbl.m_PathObstacleAvoidTimeout = cur + 4
                    if not goodPosToGoto or wasNothingGreat then
                        -- speed up the connection flagging unstucker, we cant get thru here
                        self:OnHardBlocked()
                        myTbl.m_PathObstacleRebuild = true

                    end

                -- droptypes have a habit of being over-generated, find a path "downwards" even if it's not a direct path
                elseif dropTypeToDealwith then
                    myTbl.m_PathJump = true
                    local _, segDropdownBottom = self:GetNextPathArea( aheadArea, 1 )
                    local segAfterTheDrop = segDropdownBottom or aheadSegment

                    local dropdownClearPos = self:PosThatWillBringUsTowards( myPos + vec_up15, segAfterTheDrop.pos )

                    if not dropdownClearPos or wasNothingGreat then
                        -- speed up the connection flagging unstucker, we cant get thru here
                        self:OnHardBlocked()

                    else
                        myTbl.m_PathObstacleAvoidPos = dropdownClearPos
                        myTbl.m_PathObstacleAvoidTarget = segAfterTheDrop.pos
                        myTbl.m_PathObstacleAvoidTimeout = cur + 4

                        myTbl.m_PathObstacleRebuild = true

                    end

                -- nothing is stopping us from jumping!
                elseif jumpstate == 1 or ( ( gapping or jumptype ) and beenCloseToTheBottomOfTheJump ) or ( droptype and jumpstate == 1 ) then
                    -- Performing jump

                    myTbl.wasDoingJumpOverSmallObstacle = smallObstacle
                    myTbl.jumpBlockClearPos = jumpBlockClearPos

                    self:Jump( jumpingHeight )
                    doPathUpdate = true

                end

                -- Trying deal with jump, don't update path
                isHandlingJump = true
                doingJump = closeToGoal
            elseif iAmOnGround and jumpstate == 0 then
                -- was jumping
                if myTbl.m_PathJump then
                    myTbl.m_PathJump = false
                    myTbl.wasDoingJumpOverSmallObstacle = nil
                    myTbl.jumpBlockClearPos = nil

                end

                -- GetJumpBlockState is expensive! dont spam it!
                local time = 0.2
                if self.IsFodder then
                    time = 0.75

                end
                myTbl.nextPathJump = cur + time

            elseif jumpstate ~= 0 then
                -- GetJumpBlockState is expensive! dont spam it!
                local time = 0.10
                if self.IsFodder then
                    time = 0.5

                end
                myTbl.nextPathJump = cur + time

            end
        end
    end

    local inAirNoDestination = nil
    -- off ground
    if not iAmOnGround and aheadSegment then
        if self:IsJumping() then
            local nextPathArea = self:GetNextPathArea( self:GetTrueCurrentNavArea() )

            local smallJumpEnd = nil
            local desiredSegmentPos = nil
            local nextAreaCenter = nil
            local closestPoint = nil
            local closestPointForgiving = nil
            local jumpingDestinationOffset = nil
            local destinationRelativeToBot = nil
            local validJumpableBotRelative = nil
            local validJumpablePathRelative = nil
            local validJumpableHeightOffset = myTbl.moveAlongPathJumpingHeight

            if myTbl.wasDoingJumpOverSmallObstacle then
                smallJumpEnd = myTbl.jumpBlockClearPos

            end
            if aheadSegment.pos then
                desiredSegmentPos = aheadSegment.pos

            elseif currSegment.pos then
                desiredSegmentPos = currSegment.pos

            end

            if IsValid( nextPathArea ) then
                local alreadyInTheArea = myArea and nextPathArea == myArea and myArea:Contains( myPos )
                if not alreadyInTheArea then
                    nextAreaCenter = nextPathArea:GetCenter() + ( fivePositiveZ * 2 )
                    local big = math.max( nextPathArea:GetSizeX(), nextPathArea:GetSizeY() ) > 35

                    if big then
                        desiredSegmentPos = nil
                        closestPoint = nextPathArea:GetClosestPointOnArea( myPos )
                        closestPointForgiving = closestPoint + vector25Z
                    end
                    if big and ( nextAreaCenter.z - 20 ) < myPos.z then
                        destinationRelativeToBot = Vector( nextAreaCenter.x, nextAreaCenter.y, myPos.z + 20 )

                    end
                end
            end
            if validJumpableHeightOffset then
                local offset = Vector( 0, 0, validJumpableHeightOffset + simpleJumpMinHeight )
                validJumpableBotRelative = myPos + offset
                if desiredSegmentPos then
                    validJumpablePathRelative = desiredSegmentPos + offset

                end
                if nextAreaCenter then
                    jumpingDestinationOffset = nextAreaCenter + offset

                end
            end

            -- build choose table, smaller num ones are checked first
            -- each check here was added to fix bot traversing some kind of jump shape
            local toChoose = {}
            table.insert( toChoose, smallJumpEnd )
            table.insert( toChoose, desiredSegmentPos )
            table.insert( toChoose, nextAreaCenter )
            table.insert( toChoose, closestPoint )
            table.insert( toChoose, closestPointForgiving )
            table.insert( toChoose, jumpingDestinationOffset )
            table.insert( toChoose, destinationRelativeToBot )
            table.insert( toChoose, validJumpableBotRelative )
            table.insert( toChoose, validJumpablePathRelative )

            local didMove = self:MoveInAirTowardsVisible( toChoose, nextPathArea )

            if didMove ~= true then
                inAirNoDestination = true

            end
        else
            inAirNoDestination = true

        end
    elseif not isHandlingJump and iAmOnGround then
        myTbl.WasSetposCrouchJump = nil
        myTbl.wasADropTypeInterpretedAsAGap = nil
        doPathUpdate = true
        --debugoverlay.Cross( aheadSegment.pos, 100, 0.1, color_white, true )

    elseif isHandlingJump and not droptype and iAmOnGround then
        doPathUpdate = true

    end

    if doPathUpdate then
        local distAhead = myPos:DistToSqr( currSegment.pos )

        -- blegh
        local catchupAfterAJump = aheadSegment.type ~= 0 and distAhead < myPos:DistToSqr( aheadSegment.pos ) and aheadSegment.length^2 < distAhead and terminator_Extras.PosCanSee( self:GetShootPos(), currSegment.pos )

        -- don't backtrack, we're already here!
        if catchupAfterAJump or invalidJump then
            self:InvalidatePath( "did a fake dropdown gap jump" )
            return false -- pls recalculate path!

        else
            local ang = self:GetAngles()
            path:Update( self )
            -- if this doesnt run then bot always looks toward next path seg, doesn't aim at ply
            self:SetAngles( ang )

            local phys = self:GetPhysicsObject()
            if IsValid( phys ) then
                phys:SetAngles( angle_zero )

            end

            -- detect when bot falls down and we need to repath
            local maxHeightChange = math.max( math.abs( currSegment.pos.z - aheadSegment.pos.z ), myTbl.loco:GetMaxJumpHeight() * 1.5 )
            local changeToSegment = math.abs( myPos.z - currSegment.pos.z )

            if changeToSegment > maxHeightChange * 1.25 then
                --print( "invalid", changeToSegment, maxHeightChange * 2 )
                myTbl.terminator_FellOffPath = true
                self:InvalidatePath( "i fell off my path" )

            end
        end
    end

    if inAirNoDestination == true then
        if closeToGoal then
            doingJump = true

        end

        -- dampen sideways vel when in air
        local myVel = myTbl.loco:GetVelocity()
        local newVel = myVel * 1
        newVel.x = newVel.x * 0.9
        newVel.y = newVel.y * 0.9

        myTbl.loco:SetVelocity( newVel )

    end

    local oldPathSegment = myTbl.oldWasClosePathSegment
    if oldPathSegment ~= aheadSegment then
        myTbl.oldWasClosePathSegment = aheadSegment
        myTbl.beenCloseToTheBottomOfTheJump = nil

    end

    myTbl.isInTheMiddleOfJump = doingJump

    local range = self:GetRangeTo( self:GetPathPos() )

    if not path:IsValid() and range <= myTbl.m_PathOptions.tolerance or range < myTbl.PathGoalToleranceFinal then
        self:InvalidatePath( "i reached the end of my path!" )
        return true -- reached end

    elseif path:IsValid() then
        yieldIfWeCan()
        return nil -- not at end, stuck detection is done elsewhere

    end

    return false
end

-- GPT4 func
local function SnapToLadderAxis( ladderBottom, ladderTop, point )
    -- Calculate the ladder's direction vector
    local ladderDirection = ( ladderTop - ladderBottom ):GetNormalized()

    -- Calculate the vector from the bottom of the ladder to the point
    local bottomToPoint = point - ladderBottom

    -- Project the bottomToPoint vector onto the ladderDirection vector
    local projectedVector = ladderDirection * bottomToPoint:Dot( ladderDirection )

    -- Calculate the snapped position by adding the projected vector to the bottom of the ladder
    local snappedPosition = ladderBottom + projectedVector

    return snappedPosition
end

local function Dist2d( pos1, pos2 )
    local subtProduct = pos1 - pos2
    return subtProduct:Length2D()

end

function ENT:TermHandleLadder( aheadSegment, currSegment )

    if not aheadSegment then
        local _
        _, aheadSegment = self:GetNextPathArea( myArea ) -- top of the jump
    end
    if not currSegment then
        local path = self:GetPath()
        currSegment = path:GetCurrentGoal() -- maybe bottom of the jump, paths are stupid
    end

    if not aheadSegment then
        aheadSegment = currSegment
    end

    if not currSegment then return false end

    -- bot is not falling!
    local wasHandlingLadder = self.terminator_HandlingLadder

    local myPos = self:GetPos()
    local goingUp = aheadSegment.type == 4 or currSegment.type == 4
    local goingDown = aheadSegment.type == 5 or currSegment.type == 5

    local ladder = aheadSegment.ladder
    ladder = ladder or currSegment.ladder

    if not ladder then self:ExitLadder( myPos ) return end

    local top = ladder:GetTop()
    local bottom = ladder:GetBottom()
    local laddersNormalOffset = ladder:GetNormal() * 16
    local closestToLadderPos = SnapToLadderAxis( bottom + laddersNormalOffset, top + laddersNormalOffset, myPos )

    local laddersUp = ( top - bottom ):GetNormalized()
    local dist2DToLadder = Dist2d( myPos, closestToLadderPos )

    local ladderClimbTarget
    if goingUp then
        ladderClimbTarget = closestToLadderPos + laddersUp * 150
        if dist2DToLadder < 30 then
            self.terminator_HandlingLadder = true
            self.loco:Jump() -- if we are on ground, jump
            if wasHandlingLadder and myPos.z > top.z + -25 then
                local ladderExit = self:GetNextPathArea()
                if not ladderExit or not IsValid( ladderExit ) then
                    ladderExit = ladder:GetTopForwardArea()

                end
                if not ladderExit or not IsValid( ladderExit ) then
                    ladderExit = self:GetPos()

                end
                self:ExitLadder( ladderExit )
                return false

            elseif not wasHandlingLadder then
                self:EnterLadder( ladder )

            end

        end
    elseif goingDown then
        ladderClimbTarget = closestToLadderPos + -laddersUp * 150
        if dist2DToLadder < 30 then
            self.terminator_HandlingLadder = true
            self.loco:Jump() -- if we are on ground, jump

            local recalculate = nil
            local madFastDrop = self.IsSeeEnemy and self:IsReallyAngry() and myPos.z < bottom.z + 2000
            if madFastDrop then
                recalculate = myPos:Distance( bottom ) / 200

            end

            if wasHandlingLadder and ( myPos.z < bottom.z + 25 or madFastDrop ) then
                self:ExitLadder( ladder:GetBottomArea(), recalculate )
                return false

            elseif not wasHandlingLadder then
                self:EnterLadder( ladder )

            end

        end
    else
        ladderClimbTarget = closestToLadderPos

    end

    local dir = ( ladderClimbTarget - myPos ):GetNormalized()
     -- in the ladder
    if wasHandlingLadder then
        self.jumpingPeak = self:GetPos()
        self.overrideCrouch = CurTime() + 1
        local vel = dir * self.WalkSpeed * 1.5

        self.loco:SetVelocity( vel )

    -- snap onto the ladder
    elseif dist2DToLadder < 50 and not wasHandlingLadder then
        self.jumpingPeak = self:GetPos()
        self:SetPosNoTeleport( closestToLadderPos )
        self.loco:SetVelocity( vector_origin )

    -- walk to the ladder
    else
        self:GotoPosSimple( closestToLadderPos, 10 )

    end

    local nextLadderSound = self.nextLadderSound or 0
    ladderClimbTarget = ladderClimbTarget

    if wasHandlingLadder and nextLadderSound < CurTime() then
        self.nextLadderSound = CurTime() + 0.5
        if not self:IsSilentStepping() then
            local bite = 15
            if self.ReallyHeavy then
                bite = 0

            end
            local lvl = 93 + -bite
            local pitch = math.random( 70, 80 ) + bite
            self:EmitSound( "player/footsteps/ladder" .. math.random( 1, 4 ) .. ".wav", lvl, pitch )
            util.ScreenShake( myPos, 0.5 / bite, 20, 0.1, 1000 )

        end
    end

    return true

end

function ENT:HandlePathRemovedWhileOnladder()
    if not self.terminator_HandlingLadder then return end
    if self:PathIsValid() then return end
    self:ExitLadder( self:GetPos() )

end

-- easy alias for approach
function ENT:GotoPosSimple( pos, distance, noAdapt )
    if self:NearestPoint( pos ):DistToSqr( pos ) > distance^2 then
        local myPos = self:GetPos()
        local zToPos = ( pos.z - myPos.z )
        local dir = terminator_Extras.dirToPos( myPos, pos )
        dir.z = dir.z * 0.05
        dir:Normalize()

        local aboveUs
        local simpleClearPos
        local aboveUsJumpHeight
        local heightDiffNeededToJump = simpleJumpMinHeight + 20

        -- simple jump up to the pos
        if zToPos > heightDiffNeededToJump and self:IsAngry() then
            local dist2d = ( pos - myPos )
            dist2d.z = 0
            dist2d = dist2d:Length()
            local scaledDiffNeededToJump = heightDiffNeededToJump * 2
            local distExp = dist2d^1.3
            local adjustdedDiffNeeded = distExp - scaledDiffNeededToJump

            if zToPos > adjustdedDiffNeeded then
                aboveUs = true
                aboveUsJumpHeight = zToPos
                pos = pos + dir * simpleJumpMinHeight
                simpleClearPos = pos

            end
        end

        local onGround = self.loco:IsOnGround()
        if onGround then
            local jumpstate, _, jumpingHeight, jumpBlockClearPos = self:GetJumpBlockState( dir, pos, false )
            local goalBasedJump = jumpstate ~= 2 and aboveUs
            local readyToJump = not self.nextPathJump or self.nextPathJump < CurTime()
            --print( jumpstate, jumpingHeight )
            local adaptBlock = noAdapt
            if self.IsFodder then
                local hasCached = self.nextBringUsTowardsCache and self.nextBringUsTowardsCache > CurTime()
                adaptBlock = not hasCached or ( self.IsFodder and math.random( 1, 100 ) > 90 )

            end
            -- jump if the jumpblock says we should, or if the simple jump up says we should
            if readyToJump and ( jumpstate == 1 or goalBasedJump ) then
                jumpingHeight = jumpingHeight or aboveUsJumpHeight or simpleJumpMinHeight
                self:Jump( jumpingHeight + 20 )
                self.jumpBlockClearPos = simpleClearPos or jumpBlockClearPos
                self.moveAlongPathJumpingHeight = jumpingHeight
                return
            -- adapt if the jumpstate says we need to
            elseif jumpstate == 2 and not adaptBlock then
                local goodPosToGoto = self:PosThatWillBringUsTowards( myPos + vec_up15, pos, 50 )
                if not goodPosToGoto then return end
                self.loco:Approach( goodPosToGoto, 10000 )
                return

            end
        elseif not onGround and self.m_Jumping then
            local toChoose = {
                pos,
                self.jumpBlockClearPos,
                myPos + Vector( 0,0,self.moveAlongPathJumpingHeight ),

            }
            if self:MoveInAirTowardsVisible( toChoose ) ~= true then return end

            return

        end

        self.loco:Approach( pos, 10000 )
        --debugoverlay.Cross( pos, 10, 1, color_white, true )

    end
end

function ENT:EnterLadder()
    self.preLadderGravity = self.loco:GetGravity()

    self.loco:SetGravity( 0 )

    if not self:IsSilentStepping() then
        local bite = 15
        if self.ReallyHeavy then
            bite = 0

        end
        local lvl = 98 + -bite
        local pitch = math.random( 60, 70 ) + bite
        self:EmitSound( "player/footsteps/ladder" .. math.random( 1, 4 ) .. ".wav", lvl, pitch )
        util.ScreenShake( self:GetPos(), 10 / bite, 20, 0.2, 1000 )

    end
end

function ENT:ExitLadder( exit, recalculate )
    local pos
    if isvector( exit ) then
        pos = exit

    elseif IsValid( exit ) then
        pos = exit:GetClosestPointOnArea( self:GetPos() )

    end

    if not pos then return end

    self:InvalidatePath( "i exited a ladder" )
    self.terminator_HandlingLadder = nil

    --debugoverlay.Cross( pos, 100, 1, color_white, true )
    if recalculate then
        self.nextNewPath = CurTime() + recalculate

    end

    if not self.loco:IsOnGround() then
        -- wait to path until we're on the ground
        self.isHoppingOffLadder = true

    end
    self.needsPathRecalculate = true

    local myPos = self:GetPos()
    -- pos that is above the ladder or above the dest area
    local desiredPos = Vector( myPos.x, myPos.y, math.max( myPos.z + 15, pos.z + 35 ) )

    local b1, b2 = self:GetCollisionBounds()
    local mask = self:GetSolidMask()
    local cgroup = self:GetCollisionGroup()

    local findHighestClearPos = {
        start = myPos + vec_up15,
        endpos = desiredPos,
        mins = b1,
        maxs = b2,
        filter = TrFilterNoSelf( self ),
        mask = mask,
        collisiongroup = cgroup,

    }

    -- if bot is set to a pos that makes it conflict with world, it bugs out
    local clearResult = util.TraceHull( findHighestClearPos )

    self:SetPosNoTeleport( clearResult.HitPos )
    self.loco:SetVelocity( vector_up )

    -- finally, set our vel towards the ladder exit
    local ladderExitVel = ( pos - clearResult.HitPos ):GetNormalized()
    ladderExitVel = ladderExitVel * math.random( 300 + -40, 300 )
    ladderExitVel.z = 50

    timer.Simple( 0, function()
        if not IsValid( self ) then return end
        self.loco:SetGravity( self.preLadderGravity or 600 )
        self.loco:SetVelocity( ladderExitVel )

    end )

    if not self:IsSilentStepping() then
        local bite = 15
        if self.ReallyHeavy then
            bite = 0

        end
        local lvl = 98 + -bite
        local pitch = math.random( 60, 70 ) + bite
        self:EmitSound( "player/footsteps/ladder" .. math.random( 1, 4 ) .. ".wav", lvl, pitch )
        util.ScreenShake( self:GetPos(), 10 / bite, 20, 0.2, 1000 )

    end
end

--[[------------------------------------
    Name: NEXTBOT:Jump
    Desc: Use this to make bot jump.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:Jump( height )
    if not self.loco:IsOnGround() then return end

    local heightInternal = 0

    if height then
        -- jump a bit higher than we need ta
        heightInternal = height + 20

    else
        ErrorNoHaltWithStack( "TERMINATOR JUMPED WITH NO HEIGHT" )

    end

    heightInternal = math.Clamp( heightInternal, 0, self.JumpHeight )

    local vel = self.loco:GetVelocity()
    vel.z = ( 2.5 * self.loco:GetGravity() * heightInternal ) ^ 0.4986

    local pos = self:GetPos()

    self.loco:Jump()
    self.loco:SetVelocity( vel )

    self:SetupActivity()

    self:SetupCollisionBounds()
    self:MakeFootstepSound( 1, nil, 1.05 )

    if self.MetallicMoveSounds and not self:IsSilentStepping() then
        self:EmitSound( "physics/metal/metal_canister_impact_soft2.wav", 80, 40, 0.6, CHAN_STATIC )
        self:EmitSound( "physics/flesh/flesh_impact_hard1.wav", 80, 50, 0.6, CHAN_STATIC )
        util.ScreenShake( pos, 1, 20, 0.1, 600 )

    end

    self.m_Jumping = true

    self:RunTask( "OnJump", height )
end

local airSoundPath = "ambient/wind/wind_rooftop1.wav"

local function StartFallingSound( falling )
    local timerName = "terminator_falling_manage_sound_" .. falling:GetCreationID()
    falling:StopSound( airSoundPath )
    timer.Remove( timerName )

    local filterAll = RecipientFilter()
    filterAll:AddAllPlayers()

    local airSound = CreateSound( falling, airSoundPath, filterAll )
    airSound:SetSoundLevel( 85 )
    airSound:PlayEx( 1, 150 )

    falling.terminator_playingFallingSound = true

    falling:CallOnRemove( "terminator_stopwhooshsound", function() falling:StopSound( airSoundPath ) end )

    local StopAirSound = function()
        timer.Remove( timerName )
        if not IsValid( falling ) then return end
        falling:StopSound( airSoundPath )
        falling.terminator_playingFallingSound = nil

    end

    timer.Create( timerName, 0, 0, function()
        if not IsValid( falling ) then StopAirSound() return end
        if not airSound:IsPlaying() then StopAirSound() return end
        if falling:IsSilentStepping() then StopAirSound() return end
        local vel = falling:FallHeight()
        local pitch = 30 + ( vel / 20 )
        local volume = vel / 1000
        if falling.loco:IsOnGround() then StopAirSound() return end
        airSound:ChangePitch( pitch )
        airSound:ChangeVolume( volume )

    end )
end

function ENT:DoJumpPeak( myPos )
    local jumpingPeak = self.jumpingPeak
    if not jumpingPeak then
        jumpingPeak = myPos
        self.jumpingPeak = myPos

    end
    if self:GetPos().z > jumpingPeak.z then
        self.jumpingPeak = myPos

    end
end

function ENT:FallHeight()
    if not self.jumpingPeak then return 0 end
    return math.abs( self.jumpingPeak.z - self:GetPos().z )

end

function ENT:OnLeaveGround( _ )
    self:DoJumpPeak( self:GetPos() )

end

local lethalFallHeightReal = 2000
local noticeFall = lethalFallHeightReal * 0.25
local fearFall = lethalFallHeightReal + -( lethalFallHeightReal * 0.2 )

function ENT:HandleInAir()
    local myPos = self:GetPos()
    self:DoJumpPeak( myPos )

    local fallHeight = self:FallHeight()

    if fallHeight > 200 and self.ReallyHeavy and not self:IsSilentStepping() and not self.terminator_playingFallingSound then
        StartFallingSound( self )

    end

    if fallHeight > noticeFall then
        local isScardey = ( self:GetCreationID() % 8 == 1 )

        local lookAt
        if isScardey then
            lookAt = AngleRand()

        else
            -- look at places we wish we could land on
            local areaToLookAt = navmesh.GetNearestNavArea( myPos, true, 1500, true, false, -2 )
            if areaToLookAt then
                local myShootPos = self:GetShootPos()
                lookAt = terminator_Extras.dirToPos( myShootPos, areaToLookAt:GetClosestPointOnArea( myShootPos ) ):Angle()

            end
        end

        if fallHeight > fearFall then
            self:WeaponPrimaryAttack()

        end
        if lookAt then
            self:SetDesiredEyeAngles( lookAt )

        end
    end

    local waterLevel = self:WaterLevel()
    local oldLevel = self.oldJumpingWaterLevel or 0
    if oldLevel ~= waterLevel then
        self.oldJumpingWaterLevel = waterLevel
        if oldLevel == 0 and self:IsSolid() then
            local traceStruc = {
                start = self.jumpingPeak,
                endpos = myPos,
                mask = MASK_WATER

            }

            local waterResult = util.TraceLine( traceStruc )
            local watersSurface = Vector( myPos.x, myPos.y, waterResult.HitPos.z )

            local scale = self:FallHeight() / 18
            if not self.ReallyHeavy then
                scale = scale / 100

            end

            local sploosh = EffectData()
            sploosh:SetScale( math.Clamp( scale, 10, 20 ) )
            sploosh:SetOrigin( watersSurface )
            util.Effect( "watersplash", sploosh )

            local level = math.Clamp( 65 + ( scale / 1.5 ), 65, 100 )
            local pitch = math.Clamp( 120 + -( scale * 1.5 ), 60, 120 )

            sound.Play( "ambient/water/water_splash1.wav", watersSurface, level, pitch )

            if scale > 20 then
                util.ScreenShake( self:GetPos(), 4, 20, 0.1, 800 )
                sound.Play( "weapons/underwater_explode3.wav", watersSurface, level, pitch + -20, 0.5 )
                sound.Play( "physics/surfaces/underwater_impact_bullet1.wav", watersSurface, level, pitch + -20, 0.5 )

            end
        end
    end
end

local vecDown = Vector( 0, 0, -1 )

--[[------------------------------------
    NEXTBOT:OnLandOnGround
    Some functional with jumps
--]]------------------------------------
function ENT:OnLandOnGround( ent )
    if self.isHoppingOffLadder then
        self.isHoppingOffLadder = nil

    end

    if self.m_Jumping then
        self.m_Jumping = false
        self.nextPathJump = CurTime() + 0.15

        -- Restoring from jump

        if not self:IsPostureActive() then
            self:SetupActivity()
        end

        self:SetupCollisionBounds()

    end

    local myPos = self:GetPos()
    local fallHeight = self:FallHeight()

    local mins, maxs = self:BoundsAdjusted()
    local killScale = 5
    local killBoxScale = 0.5

    local fellOnSky = util.QuickTrace( myPos + vec_up25, down * 200, self ).HitSky

    -- wow we really fell far
    if fallHeight > lethalFallHeightReal then
        self:LethalFallDamage()
        killScale = 100
        killBoxScale = 8

    elseif fellOnSky and fallHeight > 500 then
        self:FallIntoTheVoid()

    elseif fallHeight >= 50 then
        local layer = self:AddGesture( self:TranslateActivity( ACT_LAND ) )

        if fallHeight >= 500 then
            if not self:IsSilentStepping() and self.MetallicMoveSounds then
                util.ScreenShake( self:GetPos(), 16, 20, 0.4, 3000 )
                self:EmitSound( "physics/metal/metal_canister_impact_soft2.wav", 100, 60, 1, CHAN_STATIC )
                self:EmitSound( "physics/metal/metal_computer_impact_bullet2.wav", 100, 30, 1, CHAN_STATIC )

                for _ = 1, 3 do
                    self:EmitSound( table.Random( self.Whaps ), 75, math.random( 115, 120 ), 1, CHAN_STATIC )

                end
            end
            killScale = 50
            killBoxScale = 4

        elseif fallHeight >= 250 then
            self:MakeFootstepSound( 1 )
            if not self:IsSilentStepping() and self.MetallicMoveSounds then
                util.ScreenShake( self:GetPos(), 4, 20, 0.1, 800 )
                self:EmitSound( "physics/metal/metal_canister_impact_soft2.wav", 84, 90, 1, CHAN_STATIC )
                self:EmitSound( "physics/metal/metal_computer_impact_bullet2.wav", 84, 40, 0.6, CHAN_STATIC )

            end
            self:SetLayerPlaybackRate( layer, 0.2 )
            self:SetLayerWeight( layer, 100 )
            killScale = 40
            killBoxScale = 1.5

        else
            self:MakeFootstepSound( 1 )
            if not self:IsSilentStepping() and self.MetallicMoveSounds then
                util.ScreenShake( self:GetPos(), 0.5, 20, 0.1, 600 )
                self:EmitSound( "physics/flesh/flesh_impact_hard1.wav", 80, 40, 0.3, CHAN_STATIC )
                self:EmitSound( "physics/metal/metal_canister_impact_soft2.wav", 80, 40, 0.3, CHAN_STATIC )

            end
            self:SetLayerPlaybackRate( layer, 1 )
            killScale = 20
            killBoxScale = 0.8

        end

        local heightToStartTakingDamage = self.HeightToStartTakingDamage
        if fallHeight > heightToStartTakingDamage then
            local damage = math.abs( fallHeight - heightToStartTakingDamage )
            damage = damage * self.FallDamagePerHeight
            self:TakeDamage( damage )

        end
    end

    if self.ReallyHeavy then

        maxs = maxs * killBoxScale
        mins = mins * killBoxScale

        local toKill = ents.FindAlongRay( myPos, myPos + vecDown * killScale, mins, maxs )
        for _, entToKill in ipairs( toKill ) do
            if entToKill == self then continue end
            local damage = killScale * 5

            if ent.huntersglee_breakablenails and damage < 250 then continue end

            local dmg = DamageInfo()
            dmg:SetAttacker( self )
            dmg:SetInflictor( self )
            dmg:SetDamageType( DMG_CLUB )
            dmg:SetDamage( damage )
            dmg:SetDamageForce( vecDown * killScale * 10 )
            dmg:SetDamagePosition( myPos )
            entToKill:TakeDamageInfo( dmg )

        end
        -- useful! keeping it!
        --debugoverlay.Box( myPos + vecDown * killScale, mins, maxs, 1, color_white )

    end

    self.jumpingPeak = nil
    self:RunTask( "OnLandOnGround", ent )

end

function ENT:FallIntoTheVoid()
    if self.ReallyHeavy and not self:IsSilentStepping() then
        local snd = CreateSound( self, "ambient/levels/canals/windmill_wind_loop1.wav" )
        snd:SetSoundLevel( 100 )
        snd:PlayEx( 1, 100 )
        snd:ChangePitch( 0, 2 )
        snd:ChangeVolume( 1 )
        snd:ChangeVolume( 0.1, 2 )
        timer.Simple( 2, function()
            if not snd then return end
            snd:Stop()
        end )
    end

    if self.TakesFallDamage then
        self:TakeDamage( math.huge )

    end
end


function ENT:LethalFallDamage()
    if self.ReallyStrong and not self:IsSilentStepping() then
        self:EmitSound( "physics/metal/metal_canister_impact_soft2.wav", 150, 60, 1, CHAN_STATIC )
        self:EmitSound( "physics/metal/metal_computer_impact_bullet2.wav", 150, 30, 1, CHAN_STATIC )
        util.ScreenShake( self:GetPos(), 16, 20, 0.4, 3000 )
        util.ScreenShake( self:GetPos(), 1, 20, 2, 8000 )

        for _ = 1, 3 do
            self:EmitSound( table.Random( self.Chunks ), 100, math.random( 115, 120 ), 1, CHAN_STATIC )
            self:EmitSound( table.Random( self.Whaps ), 75, math.random( 115, 120 ), 1, CHAN_STATIC )

        end
    end

    if self.TakesFallDamage then
        self:TakeDamage( math.huge )

    end
end


function ENT:Approach( pos )
    self.loco:Approach( pos, 1 )

end

--[[------------------------------------
    Name: NEXTBOT:SwitchCrouch
    Desc: (INTERNAL) Change crouch status.
    Arg1: bool | crouch | Should change from stand to crouch, otherwise change from crouch to stand
    Ret1: 
    Overriden to change step height between crouch/standing, prevents bot from sticking to ceiling.
--]]------------------------------------
function ENT:SwitchCrouch( crouch )

    self:SetCrouching( crouch )
    self:SetupCollisionBounds()

    if crouch then
        self.StepHeight = self.CrouchingStepHeight

    elseif not crouch then
        self.StepHeight = self.StandingStepHeight

    end

    self.loco:SetStepHeight( self.StepHeight )

end

hook.Add( "OnPhysgunPickup", "terminatorNextBotResetPhysgunned", function( _,  ent )
    if ent.TerminatorNextBot and ent.isTerminatorHunterBased then
        ent.m_Physguned = true
        ent.loco:SetGravity( 0 )
        ent.lastGroundLeavingPos = ent:GetPos()
    end
end )

hook.Add( "PhysgunDrop", "terminatorNextBotResetPhysgunned", function( _, ent )
    if ent.TerminatorNextBot and ent.isTerminatorHunterBased then
        ent.m_Physguned = false
        ent.loco:SetGravity( ent.DefaultGravity )
        ent.lastGroundLeavingPos = ent:GetPos()
    end
end )

function ENT:NotOnNavmesh()
    return not navmesh.GetNearestNavArea( self:GetPos(), false, 25, false, false, -2 ) and self:IsOnGround()

end