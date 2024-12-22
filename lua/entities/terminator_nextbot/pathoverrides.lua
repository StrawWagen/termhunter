local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local IsValid = IsValid

local function yieldIfWeCan( reason )
    if not coroutine_running() then return end
    coroutine_yield( reason )

end

local cheatsVar = GetConVar( "sv_cheats" )
local function isCheats()
    return cheatsVar:GetBool()

end


function ENT:GetTrueCurrentNavArea()
    -- don't redo this when we just updated it
    local area = NULL
    local nextTrueAreaCache = self.nextTrueAreaCache or 0
    if nextTrueAreaCache < CurTime() then
        area = terminator_Extras.getNearestNavFloor( self:GetPos() )
        self.nextTrueAreaCache = CurTime() + 0.08

    end
    if area == NULL then area = nil end
    self.cachedTrueArea = area

    return area

end

function ENT:InvalidatePath( reason )
    local path = self:GetPath()
    if not path:IsValid() then return end
    path:Invalidate()

    self.m_PathObstacleGoal = nil
    self.m_PathObstacleRebuild = nil
    self.m_PathObstacleAvoidPos = nil
    self.m_PathObstacleAvoidTarget = nil
    self.m_PathObstacleAvoidTimeout = 0

    -- debug
    if not isCheats() then return end

    -- this is displayed when bot is used by a player
    self.lastPathInvalidateReason = reason

end

function ENT:getCachedPathSegments()
    local path = self:GetPath()
    local pathEnd = path:GetEnd()
    local lastEnd = self.lastCachedPathEnd or vector_origin
    if pathEnd == lastEnd then return self.cachedPathSegments end

    local segments = path:GetAllSegments()
    self.cachedPathSegments = segments
    self.lastCachedPathEnd = pathEnd
    return segments

end

function ENT:getMaxPathCurvature( passArea, extentDistance )

    if not self:PathIsValid() then return 0 end

    extentDistance = extentDistance or 400

    local myNavArea = passArea or self:GetCurrentNavArea()

    local maxCurvature = 0
    local pathSegs = self:getCachedPathSegments()
    local distance = 0
    local wasCurrentSegment = nil

    -- go until we get past extent distance

    for _, currSegment in ipairs( pathSegs ) do
        if currSegment.area == myNavArea or wasCurrentSegment then
            wasCurrentSegment = true

            distance = distance + currSegment.length
            if distance >= extentDistance then
                break

            end
            local absCurvature = math.abs( currSegment.curvature )
            if absCurvature > maxCurvature then
                maxCurvature = absCurvature
            end
        end
    end
    return maxCurvature

end

function ENT:GetNextPathArea( refArea, offset, visCheck )
    if not self:PathIsValid() then return end

    local targetReferenceArea = refArea or self:GetCurrentNavArea()
    if not targetReferenceArea then return end

    local pathSegs = self:getCachedPathSegments()
    local myPathPoint = self:GetPath():GetCurrentGoal()
    local myShootPos = self:GetShootPos()
    local goalArea = NULL
    local goalPathPoint
    local isNextArea

    for _, pathPoint in ipairs( pathSegs ) do -- find the real next area
        if isNextArea == true and pathPoint.area ~= myPathPoint.area then
            -- stop when next is not visible
            if visCheck and goalArea and not terminator_Extras.PosCanSeeComplex( myShootPos, pathPoint.pos + vector_up * 25, self ) then
                break

            end
            goalArea = pathPoint.area
            goalPathPoint = pathPoint
            if offset and offset >= 1 then
                offset = offset + -1

            else
                --debugoverlay.Cross( pathPoint.area:GetCenter(), 40, 0.1, Color( 0,0,255 ), true )
                break

            end
        elseif pathPoint.area == targetReferenceArea or pathPoint.area == myPathPoint.area then
            myPathPoint = pathPoint
            isNextArea = true
            --debugoverlay.Cross( pathPoint.area:GetCenter(), 0.1, 10, Color( 255,0,0 ), true )

        end
    end
    return goalArea, goalPathPoint

end

-- good for approaching enemy from multiple angles
-- eg, check other hunter's halfway points, flank around them
function ENT:GetPathHalfwayPoint()
    local myPos = self:GetPos()
    if not self:PathIsValid() then return myPos end

    local pathSegs = self:getCachedPathSegments()
    if not pathSegs then return myPos end

    local middlePathSegIndex = math.Round( #pathSegs / 2 )
    local middlePathSeg = pathSegs[ middlePathSegIndex ]
    return middlePathSeg.pos, middlePathSeg

end

-- helper, used in tasks to not call a fail if bot is unstucking
function ENT:primaryPathIsValid( path )
    path = path or self:GetPath()
    if self.isUnstucking then return true end -- dont start new paths
    -- behave normally
    return self:PathIsValid( path )

end

function ENT:MyPathLength( path )
    path = path or self:GetPath()
    if not self:PathIsValid( path ) then return 0 end

    return path:GetLength()

end

-- helper
function ENT:primaryPathInvalidOrOutdated( destination )
    if not self:nextNewPathIsGood() then return end
    local path = self:GetPath()
    local valid = self:primaryPathIsValid( path )
    return not valid or ( valid and self:CanDoNewPath( destination ) )

end

--[[function ENT:pathInvalidOrOutdated( destination )
    local path = self:GetPath()
    local valid = self:primaryPathIsValid( path )
    return not valid or ( valid and self:CanDoNewPath( destination ) )

end--]]

local transientAreaCached = {}
local nextTransientAreaCaches = {}
local belowOffset = Vector( 0, 0, -45 )
local hull = Vector( 5, 5, 1 )

function ENT:transientAreaPathable( area, areasId )
    local nextCache = nextTransientAreaCaches[areasId] or 0
    if nextCache > CurTime() then return transientAreaCached[areasId] end
    nextTransientAreaCaches[areasId] = CurTime() + math.Rand( 0.5, 1 )

    local toCheckPositions = {}
    local center = area:GetCenter()
    table.insert( toCheckPositions, center )

    for cornerInd = 0, 3 do
        local corner = area:GetCorner( cornerInd )
        local dirToCenter = terminator_Extras.dirToPos( corner, center )
        local cornerOffsetted = corner + dirToCenter * 12.5

        table.insert( toCheckPositions, cornerOffsetted )

    end

    local traceData = {
        mask = MASK_SOLID,
        mins = -hull,
        maxs = hull,

    }
    local hits = 0
    local misses = 0
    local lastChecked
    for _, currPos in ipairs( toCheckPositions ) do
        -- simple check for already traced positions.
        if lastChecked and currPos:DistToSqr( lastChecked ) < 25 then continue end -- 25 is 5^2 
        lastChecked = currPos

        traceData.start = currPos
        traceData.endpos = currPos + belowOffset

        local traceRes = util.TraceHull( traceData )
        if ( traceRes.Hit and traceRes.HitNormal:Dot( vector_up ) > 0.65 ) or traceRes.StartSolid then
            hits = hits + 1

        else
            misses = misses + 1

        end
    end

    local isTraversable = hits >= 2 and misses < hits / 6
    --debugoverlay.Text( center, tostring( hits ) .. " " .. tostring( misses ), 5 )
    transientAreaCached[areasId] = isTraversable

    return isTraversable

end


local badConnections = {}
local lastBadFlags = {}
local superBadConnections = {}
local lastSuperBadFlags = {}
local normalBadTimeout = 120
local superBadTimeout = 520

local function getConnId( fromAreaId, toAreaId )
    -- this needs to have directionality
    return fromAreaId + ( toAreaId / 2 )

end

-- make nextbot recognize two nav areas that dont connect in practice
function ENT:flagConnectionAsShit( area1, area2 )
    if not area1:IsValid() then return end
    if not area2:IsValid() then return end
    if not area1:IsConnected( area2 ) then return end -- no connection to flag! bot probably fell off it's path

    local connectionsId = getConnId( area1:GetID(), area2:GetID() )

    local superShitConnection = nil
    if badConnections[ connectionsId ] then superShitConnection = true end

    badConnections[connectionsId] = true
    lastBadFlags[connectionsId] = CurTime()

    timer.Simple( normalBadTimeout, function()
        local lastFlag = lastBadFlags[connectionsId]

        if not lastFlag then return end -- ???
        -- dont obliterate new ones!
        if lastFlag + ( normalBadTimeout + -10 ) < CurTime() then return end

        badConnections[connectionsId] = nil
        lastBadFlags[connectionsId] = nil

    end )

    if not superShitConnection then return end

    superBadConnections[connectionsId] = true
    lastSuperBadFlags[connectionsId] = CurTime()

    timer.Simple( superBadTimeout, function()
        local lastSuperFlag = lastSuperBadFlags[connectionsId]

        if not lastSuperFlag then return end
        if lastSuperFlag + ( normalBadTimeout + -10 ) < CurTime() then return end

        superBadConnections[connectionsId] = nil
        lastSuperBadFlags[connectionsId] = nil

    end )
end

hook.Add( "PostCleanupMap", "terminator_clear_connectionflags", function()
    badConnections = {}
    lastBadFlags = {}
    superBadConnections = {}
    lastSuperBadFlags = {}
end )


-- flanking!
local hunterIsFlanking
local flankingDest
local pathAreasAdditionalCost
local isReallyAngry = nil
local tooFarToFlank = 4000^2

function ENT:AddAreasToAvoid( areas, mul )
    pathAreasAdditionalCost = pathAreasAdditionalCost or {}
    for _, avoid in ipairs( areas ) do
        -- lagspike if we try to flank around area that contains the destination
        if avoid and IsValid( avoid ) and ( avoid ~= flankingDest ) then
            local oldMul = pathAreasAdditionalCost[ avoid:GetID() ] or 0
            pathAreasAdditionalCost[ avoid:GetID() ] = oldMul + mul
            --debugoverlay.Cross( avoid:GetCenter(), 10, 10, color_white, true )

        end
    end
end

function ENT:SetupFlankingPath( destination, areaToFlankAround, flankAvoidRadius )
    if not isvector( destination ) then return false end

    local myPos = self:GetPos()

    if destination:DistToSqr( myPos ) < tooFarToFlank and IsValid( areaToFlankAround ) then

        flankingDest = terminator_Extras.getNearestPosOnNav( destination ).area
        if not flankingDest then return false end

        hunterIsFlanking = true
        isReallyAngry = self:IsReallyAngry()

        if flankAvoidRadius then
            self:flankAroundArea( areaToFlankAround, flankAvoidRadius )

        else
            self:flankAroundCorridorBetween( myPos, areaToFlankAround:GetCenter() )

        end
        if IsValid( self:GetEnemy() ) then
            self:FlankAroundEasyEntraceToThing( areaToFlankAround:GetCenter(), self:GetEnemy() )

        end

        local result1, result2 = self:SetupPathShell( destination )

        self:endFlankPath()

        return result1, result2

    else
        return self:SetupPathShell( destination )

    end
end

function ENT:flankAroundArea( bubbleArea, bubbleRadius )
    bubbleRadius = math.Clamp( bubbleRadius, 0, 3000 )
    local bubbleCenter = bubbleArea:GetCenter()

    local areas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToAvoid( areas, 25 )

end

function ENT:flankAroundCorridorBetween( bubbleStart, bubbleDestination )
    local offsetDirection = terminator_Extras.dirToPos( bubbleStart, bubbleDestination )
    local offsetDistance = bubbleStart:Distance( bubbleDestination )
    local bubbleRadius = math.Clamp( offsetDistance * 0.45, 0, 4000 )
    local offset = offsetDirection * ( offsetDistance * 0.6 )
    local bubbleCenter = bubbleStart + offset

    local firstBubbleAreas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToAvoid( firstBubbleAreas, 25 )

end

function ENT:FlankAroundEasyEntraceToThing( bubbleStart, thing )
    local bubbleDestination = thing:GetPos()
    local offsetDirection = terminator_Extras.dirToPos( bubbleStart, bubbleDestination )
    local offsetDistance = bubbleStart:Distance( bubbleDestination )

    local secondBubbleAreas = navmesh.Find( bubbleDestination, math.Clamp( offsetDistance * 0.5, 100, 400 ), self.JumpHeight, self.JumpHeight )
    local secondBubbleAreasClipped = {}

    local bitInFrontOffset = offsetDirection * 100
    local positveSideOfPlane = bubbleDestination + bitInFrontOffset
    local negativeSideOfPlane = bubbleStart + bitInFrontOffset + -offsetDirection * offsetDistance

    -- make sure we at least try to avoid going right in front of them
    for _, area in ipairs( secondBubbleAreas ) do
        local areasCenter = area:GetCenter()
        local distToPositive = areasCenter:DistToSqr( positveSideOfPlane )
        local distToNegative = areasCenter:DistToSqr( negativeSideOfPlane )

        if distToPositive < distToNegative then
            table.insert( secondBubbleAreasClipped, area )
            --debugoverlay.Cross( area:GetCenter(), 10, 10, color_white, true )

        end
    end

    self:AddAreasToAvoid( secondBubbleAreasClipped, 50 )
end

function ENT:endFlankPath()
    self.flankBubbleCenter = nil
    self.flankBubbleSizeSqr = nil
    flankingZRewardBegin = nil
    hunterIsFlanking = nil
    isReallyAngry = nil

end

local function badConnectionCheck( connectionsId, dist )
    if badConnections[connectionsId] then
        dist = dist * 10
        dist = dist + 3000

    end
    if superBadConnections[connectionsId] then
        dist = dist + 20000000

    end
    return dist

end

--TODO: dynamically check if a NAV_TRANSIENT areas are supported by terrain, then cache the results 
--local function isCachedTraversable( area )

local jumpHeightCached
local stepHeightCached
local deathHeightCached
local canLadderCached
local maxExtentCached
local currExtent

local IsValid = IsValid
local band = bit.band

function ENT:NavMeshPathCostGenerator( _, toArea, fromArea, ladder, _, len )
    if not IsValid( fromArea ) then return 0 end

    if maxExtentCached then
        currExtent = currExtent + 1
        if currExtent > maxExtentCached then return -1 end

    end

    local toAreasId = toArea:GetID()
    local dist
    local laddering

    if IsValid( ladder ) then
        if not canLadderCached then return -1 end

        laddering = true
        -- ladders are kinda dumb
        -- avoid if we can
        dist = ladder:GetLength() * 2
        dist = dist + 400
    elseif len > 0 then
        dist = len
    else
        dist = fromArea:GetCenter():Distance( toArea:GetCenter() )
    end

    dist = badConnectionCheck( getConnId( fromArea:GetID(), toAreasId ), dist )

    local costSoFar = fromArea:GetCostSoFar() or 0

    if laddering then return costSoFar + dist end

    if pathAreasAdditionalCost[ toAreasId ] then
        dist = dist * pathAreasAdditionalCost[ toAreasId ]
        --debugoverlay.Cross( toArea:GetCenter(), 10, 10, color_white, true )

    end

    local attributes = toArea:GetAttributes()
    local crouching

    if band( attributes, NAV_MESH_TRANSIENT ) ~= 0 and not self:transientAreaPathable( toArea, toAreasId ) then return false end

    if band( attributes, NAV_MESH_CROUCH ) ~= 0 then
        crouching = true
        if hunterIsFlanking then
            -- vents?
            dist = dist * 0.5
        else
            -- its cool when they crouch so dont punish it much
            dist = dist * 1.1
        end
    end

    if band( attributes, NAV_MESH_OBSTACLE_TOP ) ~= 0 then
        if fromArea:HasAttributes( NAV_MESH_OBSTACLE_TOP ) then
            dist = dist * 4
        else
            dist = dist * 1.5 -- these usually look goofy
        end
    end

    local sizeX = toArea:GetSizeX()
    local sizeY = toArea:GetSizeY()

    if sizeX < 26 or sizeY < 26 then
        -- generator often makes small 1x1 areas with this attribute, on very complex terrain
        if band( attributes, NAV_MESH_NO_MERGE ) ~= 0 then
            dist = dist * 4
        else
            dist = dist * 1.25
        end
    end
    if sizeX > 151 and sizeY > 151 and not hunterIsFlanking then --- mmm very simple terrain
        dist = dist * 0.75
    elseif sizeX > 76 and sizeY > 76 then -- this makes us prefer paths thru simple terrain, it's cheaper!
        dist = dist * 0.9
    end

    if band( attributes, NAV_MESH_AVOID ) ~= 0 then
        dist = dist * 20
    end

    if toArea:IsUnderwater() then
        dist = dist * 2
    end

    local cost = dist + costSoFar

    local deltaZ = fromArea:ComputeAdjacentConnectionHeightChange( toArea )
    local stepHeight = stepHeightCached
    local jumpHeight = jumpHeightCached
    if deltaZ >= stepHeight then
        if deltaZ >= jumpHeight then return -1 end
        if deltaZ > stepHeight * 4 then
            if hunterIsFlanking then
                cost = cost * 2

            else
                cost = cost * 4

            end
        elseif deltaZ > stepHeight * 2 then
            if hunterIsFlanking then
                cost = cost * 1.5

            else
                cost = cost * 2.5

            end
        else
            if hunterIsFlanking then
                cost = cost * 1.25

            else
                cost = cost * 1.5

            end
        end
        if crouching then
            cost = cost * 10

        end
    elseif not isReallyAngry and deltaZ <= -deathHeightCached then
        cost = cost * 50000

    elseif not isReallyAngry and deltaZ <= -jumpHeight then
        cost = cost * 2.5

    elseif not isReallyAngry and deltaZ <= -stepHeight * 3 then
        if hunterIsFlanking then
            cost = cost * 1.5

        else
            cost = cost * 2

        end
    elseif deltaZ <= -stepHeight then
        if hunterIsFlanking then
            cost = cost * 1.25

        else
            cost = cost * 1.5

        end
    end

    return cost
end

-- do this so we can store extra stuff about new paths
function ENT:SetupPathShell( endpos, isUnstuck )
    if not endpos then ErrorNoHaltWithStack( "no endpos" ) return nil, "error1" end
    -- block path spamming
    -- exceptions for unstucker paths, they're VIP
    if not isUnstuck and not self:nextNewPathIsGood() then return nil, "blocked1" end
    self.nextNewPath = CurTime() + math.Rand( 0.05, 0.1 )

    if not isvector( endpos ) then return nil, "blocked2" end
    if self.isUnstucking and not isUnstuck then return nil, "blocked3" end

    self.term_ExpensivePath = nil
    local endArea = terminator_Extras.getNearestPosOnNav( endpos )

    local reachable = self:areaIsReachable( endArea.area )
    if not reachable then
        -- make sure we dont get super duper stuck
        if self.isUnstucking and isUnstuck then
            self.overrideVeryStuck = true

        end
        return nil, "blocked4"

    end

    yieldIfWeCan()

    -- if we are not going to an orphan ( can still be an orphan, this is just a sanity check! )
    -- prevents paths to really small collections of navareas that don't connect back to the bot. ( and the lagspikes that come from those! )
    local pathDestinationIsAnOrphan, encounteredABlockedArea = self:AreaIsOrphan( endArea.area )

    yieldIfWeCan()

    -- not an orphan, proceed as normal!
    if pathDestinationIsAnOrphan ~= true then
        -- save path start info for the HunterIsStuck
        self.LastMovementStart = CurTime()
        self.LastMovementStartPos = self:GetPos()
        self.PathEndPos = endpos

        local before = SysTime()
        self:SetupPath( endpos )
        local after = SysTime()

        local cost = ( after - before )
        if cost > 0.03 then
            self.term_ExpensivePath = true

        end

        -- good path, escape here
        if self:primaryPathIsValid() then
            self.setupPath2NoNavs = nil
            self.nextNewPath = CurTime() + cost * 8

            return nil, "blocked5 ( the good ending )"

        -- no path! something failed
        else
            local setupPath2NoNavs = self.setupPath2NoNavs or 0
            -- aha, im not on the navmesh! that's why!
            if not navmesh.GetNearestNavArea( self:GetPos(), false, 45, false, false, -2 ) and self:IsOnGround() then
                self.setupPath2NoNavs = setupPath2NoNavs + 1

            end
            if setupPath2NoNavs > 5 then
                self.setupPath2NoNavs = nil
                self.overrideVeryStuck = true

            end
        end
    end

    yieldIfWeCan()

    -- only get to here if the path failed

    -- first blocked area check, got it from the orphan checker? probably a locked door, store that for the door bashing stuff
    if encounteredABlockedArea then
        self.encounteredABlockedAreaWhenPathing = true

    end

    if not IsValid( endArea.area ) then return end -- outdated....

    if not self:IsOnGround() then return end -- don't member as unreachable when we're in the air
    if endArea.area:GetClosestPointOnArea( endpos ):Distance( endpos ) > 25 then return end -- if endpos is off the navmesh then dont create false unreachable flags

    --debugoverlay.Text( endArea.area:GetCenter(), "unREACHABLE" .. tostring( pathDestinationIsAnOrphan ), 8 )

    local scoreData = {}
    local invalidUnreachable
    local wasABlockedArea = false
    scoreData.myArea = self:GetCurrentNavArea()
    scoreData.decreasingScores = {}
    scoreData.droppedDownAreas = {}
    scoreData.areasToUnreachable = {}

    -- find areas around the path's end that we can't reach
    -- this prevents super obnoxous stutters on maps with tens of thousands of navareas
    local scoreFunction = function( scoreData, area1, area2 )
        local score = scoreData.decreasingScores[area1:GetID()] or 10000
        local droppedDown = scoreData.droppedDownAreas[area1:GetID()]
        local dropToArea = area2:ComputeAdjacentConnectionHeightChange( area1 )

        -- uhhh we got back to our own area....
        if area2 == scoreData.myArea then
            if score > 1 then -- really screwed
                invalidUnreachable = true

            end
            return math.huge

        -- we are dealing with a locked door, not an orphan/elevated area!
        elseif area2:IsBlocked() then
            wasABlockedArea = true
            score = 0

        elseif dropToArea > self.loco:GetMaxJumpHeight() or droppedDown then
            score = 1
            scoreData.droppedDownAreas[area2:GetID()] = true

        else
            score = score + -1
            table.insert( scoreData.areasToUnreachable, area2 )

        end

        --debugoverlay.Text( area2:GetCenter(), tostring( score ), 8 )
        scoreData.decreasingScores[area2:GetID()] = score

        return score

    end
    self:findValidNavResult( scoreData, endArea.area:GetCenter(), 2000, scoreFunction )

    yieldIfWeCan()

    -- ok remember the areas as unreachable so we dont go through this again
    -- unless there was a locked door!
    if not wasABlockedArea then
        self:rememberAsUnreachable( endArea.area )

        -- stop after marking the path dest, IF the unreachable finder was invalid!
        if not invalidUnreachable then
            for _, area in ipairs( scoreData.areasToUnreachable ) do
                self:rememberAsUnreachable( area )

            end
        end
    end

    -- we got stuck while in the middle of an unstuck!
    if self.isUnstucking and isUnstuck then
        self.overrideVeryStuck = true

    end

    self:RunTask( "OnPathFail" )

    local failString = "extremefailure "
    if pathDestinationIsAnOrphan then
        failString = failString .. " WAS ORPHAN!"

    end

    return true, failString

end

-- stub
function ENT:AdditionalAvoidAreas()
end

--[[------------------------------------
    Name: NEXTBOT:SetupPath
    Desc: Creates new PathFollower object and computes path to goal. Invalidates old path.
    Arg1: Vector | pos | Goal position.
    Arg2: (optional) table | options | Table with options:
        `mindist` - SetMinLookAheadDistance
        `tolerance` - SetGoalTolerance
        `generator` - Custom cost generator
    Ret1: any | PathFollower object if created succesfully, otherwise false
--]]------------------------------------
function ENT:SetupPath( pos, options )
    self:InvalidatePath( "i started a new path" )

    jumpHeightCached = self.loco:GetMaxJumpHeight()
    stepHeightCached = self.loco:GetStepHeight()
    deathHeightCached = self.loco:GetDeathDropHeight()
    canLadderCached = self.CanUseLadders
    maxExtentCached = self.MaxPathingIterations -- set this to like 5000 if you dont care about a specific bot having perfect paths
    currExtent = 0

    if not self.IsFodder then -- fodder npcs usually dont live long enough for this to matter.
        -- areas that we took damage in
        self:AddAreasToAvoid( self.hazardousAreas, 10 )

    end

    local adjusted = self:AdditionalAvoidAreas( pathAreasAdditionalCost )
    if istable( adjusted ) then
        pathAreasAdditionalCost = adjusted

    end

    pathAreasAdditionalCost = pathAreasAdditionalCost or {}

    if self.awarenessDamaging then
        local damagingAreas = self:DamagingAreas()
        local avoidStrength = 100
        -- blinded by rage
        if self:IsReallyAngry() then
            avoidStrength = 5

        elseif self:IsAngry() then
            avoidStrength = 50

        end
        self:AddAreasToAvoid( damagingAreas, avoidStrength )

    end

    options = options or {}
    options.mindist = options.mindist or self.PathMinLookAheadDistance
    options.tolerance = options.tolerance or self.PathGoalTolerance

    if not options.generator then
        options.generator = function( area, from, ladder, elevator, len )
            return self:NavMeshPathCostGenerator( self:GetPath(), area, from, ladder, elevator, len )
        end
    end

    local path = Path( "Follow" )
    self.m_Path = path

    path:SetMinLookAheadDistance( options.mindist )
    path:SetGoalTolerance( options.tolerance )

    self.m_PathOptions = options
    self.m_PathPos = pos

    local computed = self:ComputePath( pos, options.generator )

    pathAreasAdditionalCost = nil
    jumpHeightCached = nil
    stepHeightCached = nil
    deathHeightCached = nil
    canLadderCached = nil
    maxExtentCached = nil
    currExtent = nil

    if not computed then
        self:InvalidatePath( "i failed to build a path" )

        -- this stuck edge case usually happens when the bot ends up in some orphan part of the navmesh with no way out, eg bottom of an elevator shaft
        local old = self.term_ConsecutivePathFailures or 0
        if old > 25 then
            self.overrideVeryStuck = true

        elseif old >= 5 then
            local currNav = self:GetCurrentNavArea()
            if not IsValid( currNav ) or self:AreaIsOrphan( currNav, true ) then
                self.overrideVeryStuck = true

            end
        end

        if self:IsOnGround() then
            self.term_ConsecutivePathFailures = old + 1

        end
        return false

    end

    self.term_ConsecutivePathFailures = 0

    return path

end

--[[
local function heuristic_cost_estimate( start, goal )
    return start:GetCenter():Distance( goal:GetCenter() )

end

-- using CNavAreas as table keys doesn't work, we use IDs
function reconstruct_path( cameFrom, current )
    local total_path = { current }

    current = current:GetID()
    while cameFrom[ current ] do
        current = cameFrom[ current ]
        table.insert( total_path, navmesh.GetNavAreaByID( current ) )

    end
    return total_path

end

local function Astar( start, goal )
    if not IsValid( start ) or not IsValid( goal ) then return false end
    if start == goal then return true end

    start:ClearSearchLists()

    start:AddToOpenList()

    local cameFrom = {}

    start:SetCostSoFar( 0 )

    start:SetTotalCost( heuristic_cost_estimate( start, goal ) )
    start:UpdateOnOpenList()

    while not start:IsOpenListEmpty() do
        local current = start:PopOpenList() -- Remove the area with lowest cost in the open list and return it
        if ( current == goal ) then
            return reconstruct_path( cameFrom, current )
        end

        current:AddToClosedList()

        for _, neighbor in pairs( current:GetAdjacentAreas() ) do
            local newCostSoFar = current:GetCostSoFar() + heuristic_cost_estimate( current, neighbor )

            if neighbor:IsUnderwater() then -- Add your own area filters or whatever here
                continue
            end

            if ( ( neighbor:IsOpen() || neighbor:IsClosed() ) && neighbor:GetCostSoFar() <= newCostSoFar ) then
                continue
            else
                neighbor:SetCostSoFar( newCostSoFar );
                neighbor:SetTotalCost( newCostSoFar + heuristic_cost_estimate( neighbor, goal ) )

                if ( neighbor:IsClosed() ) then

                    neighbor:RemoveFromClosedList()
                end

                if ( neighbor:IsOpen() ) then
                    -- This area is already on the open list, update its position in the list to keep costs sorted
                    neighbor:UpdateOnOpenList()
                else
                    neighbor:AddToOpenList()
                end

                cameFrom[ neighbor:GetID() ] = current:GetID()
            end
        end
    end

    return false
end

--]]

--[[------------------------------------
    Name: NEXTBOT:ComputePath
    Desc: (INTERNAL) Computes path to goal.
    Arg1: Vector | pos | Goal position.
    Arg2: (optional) function | generator | Custom cost generator for A* algorithm
    Ret1: bool | Path generated succesfully
--]]------------------------------------
function ENT:ComputePath( pos, generator )
    local path = self:GetPath()

    if path:Compute( self, pos, generator ) then
        local ang = self:GetAngles()
        -- path update makes bot look forward on the path
        path:Update( self )
        self:SetAngles( ang )

        return path:IsValid()
    end

    return false

end

function ENT:DamagingAreas()
    local damagingAreas = {}
    local added = 0
    local jumpHeight = self.JumpHeight
    for _, volatile in ipairs( self.awarenessDamaging ) do
        if added > 10 then break end
        if not IsValid( volatile ) then continue end
        added = added + 1
        table.Add( damagingAreas, navmesh.Find( volatile:GetPos(), 50, jumpHeight, jumpHeight ) )

    end
    return damagingAreas

end