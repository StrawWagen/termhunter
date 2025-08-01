local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local IsValid = IsValid
local SysTime = SysTime
local entMeta = FindMetaTable( "Entity" )

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
    local nextTrueAreaCache = self.nextTrueAreaCache or 0
    if nextTrueAreaCache < CurTime() then
        self.nextTrueAreaCache = CurTime() + 0.08
        local area = terminator_Extras.getNearestNavFloor( self:GetPos() )
        self.cachedTrueArea = area
        return area

    else
        return self.cachedTrueArea

    end
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

    --debug
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

function ENT:getMaxPathCurvature( myTbl, passArea, extentDistance )
    myTbl = myTbl or entMeta.GetTable( self )

    if not myTbl.PathIsValid( self ) then return 0 end

    extentDistance = extentDistance or 400

    local myNavArea = passArea or myTbl.GetCurrentNavArea( self, myTbl )

    local maxCurvature = 0
    local pathSegs = myTbl.getCachedPathSegments( self, myTbl )
    local distance = 0
    local wasCurrentSegment = nil

    -- go until we get past extent distance

    local oldTime = SysTime()
    for _, currSegment in ipairs( pathSegs ) do
        if wasCurrentSegment or currSegment.area == myNavArea then
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
    local invalidAndReady = not valid and ( destination and self:GetRangeTo( destination ) > 5 )
    local validAndNeedsUpdate = valid and self:CanDoNewPath( destination )
    return invalidAndReady or validAndNeedsUpdate

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
    if not IsValid( area1 ) then return end
    if not IsValid( area2 ) then return end
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

function ENT:AddAreasToAvoid( areas, mul )
    local myTbl = entMeta.GetTable( self )
    myTbl.pathAreasAdditionalCost = myTbl.pathAreasAdditionalCost or {}
    for _, avoid in ipairs( areas ) do
        -- lagspike if we try to flank around area that contains the destination
        if avoid and IsValid( avoid ) and ( avoid ~= myTbl.flankingDest ) then
            local oldMul = myTbl.pathAreasAdditionalCost[ avoid:GetID() ] or 0
            myTbl.pathAreasAdditionalCost[ avoid:GetID() ] = oldMul + mul
            --debugoverlay.Cross( avoid:GetCenter(), 10, 10, color_white, true )

        end
    end
end

--[[---------------------
    Name: NEXTBOT:SetupFlankingPath
    Desc: Sets up a flanking path around an area, to flank the enemy.
    Arg1: destination - Vector, where to flank to.
    Arg2: areaToFlankAround - CNavArea, the area to flank around.
    Arg3: flankAvoidRadius - supply this arg to steer bot around bubble of num's size around areaToFlankAround. Otherwise bot will try and avoid dynamic bubble between dest and areaToFlankAround.
    Returns: SetupPathShell result1, SetupPathShell result2
]]
function ENT:SetupFlankingPath( destination, areaToFlankAround, flankAvoidRadius )
    if not isvector( destination ) then return false, "flank_nodestvec" end

    if not IsValid( areaToFlankAround ) then return false, "flank_noareaaround" end

    self.flankingDest = terminator_Extras.getNearestPosOnNav( destination ).area
    if not self.flankingDest then return false, "flank_nodestarea" end

    self.hunterIsFlanking = true
    self.flankingIsReallyAngry = self:IsReallyAngry()

    if flankAvoidRadius then
        self:flankAroundArea( areaToFlankAround, flankAvoidRadius )

    else
        self:flankAroundCorridorBetween( self:GetPos(), areaToFlankAround:GetCenter() )

    end
    if IsValid( self:GetEnemy() ) then
        self:FlankAroundEasyEntraceToThing( areaToFlankAround:GetCenter(), self:GetEnemy() )

    end

    local result1, result2 = self:SetupPathShell( destination )

    self.hunterIsFlanking = nil
    self.flankingIsReallyAngry = nil

    return result1, result2

end

local FLANK_DEFAULT_COST = 10

function ENT:flankAroundArea( bubbleArea, bubbleRadius )
    bubbleRadius = math.Clamp( bubbleRadius, 0, 3000 )
    local bubbleCenter = bubbleArea:GetCenter()

    local areas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToAvoid( areas, FLANK_DEFAULT_COST )

end

function ENT:flankAroundCorridorBetween( bubbleStart, bubbleDestination )
    local offsetDirection = terminator_Extras.dirToPos( bubbleStart, bubbleDestination )
    local offsetDistance = bubbleStart:Distance( bubbleDestination )
    local bubbleRadius = math.Clamp( offsetDistance * 0.45, 0, 4000 )
    local offset = offsetDirection * ( offsetDistance * 0.6 )
    local bubbleCenter = bubbleStart + offset

    local firstBubbleAreas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToAvoid( firstBubbleAreas, FLANK_DEFAULT_COST )

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

    self:AddAreasToAvoid( secondBubbleAreasClipped, FLANK_DEFAULT_COST * 2 )
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


local navmesh = navmesh
local IsValidCost = IsValid
local band = bit.band

local navMeta = FindMetaTable( "CNavArea" )
local ladMeta = FindMetaTable( "CNavLadder" )
local vecMeta = FindMetaTable( "Vector" )

local GetID = navMeta.GetID
local LaddGetID = ladMeta.GetID

terminator_Extras.DOING_CORRIDORAREAS = terminator_Extras.DOING_CORRIDORAREAS or nil 
local inCorridorAreas = nil -- save areas that were valid a* paths, and biast bots to use them, makes pathing faster by letting bots confidently traverse old valid paths
local corridorExpireTimes = nil

if terminator_Extras.DOING_CORRIDORAREAS then
    inCorridorAreas = {}
    corridorExpireTimes = {}

end

hook.Add( "terminator_nextbot_oneterm_exists", "corridorareas_optimisation", function()
    inCorridorAreas = {}
    corridorExpireTimes = {}
    terminator_Extras.DOING_CORRIDORAREAS = true

    timer.Create( "terminator_cleanupcorridor", 30, 0, function()
        local cur = CurTime()
        for area, expireTime in pairs( corridorExpireTimes ) do
            if expireTime < cur then
                inCorridorAreas[area] = nil
                corridorExpireTimes[area] = nil

            end
        end
    end )
end )

hook.Add( "terminator_nextbot_noterms_exist", "corridorareas_optimisation", function()
    inCorridorAreas = nil
    corridorExpireTimes = nil
    timer.Remove( "terminator_cleanupcorridor" )
    terminator_Extras.DOING_CORRIDORAREAS = nil

end )

local function addToCorridor( corridor )
    local cur = CurTime()
    for _, area in ipairs( corridor ) do
        inCorridorAreas[area] = true
        corridorExpireTimes[area] = cur + 60

    end
end

-- scoreKeeper

function ENT:NavMeshPathCostGenerator( myTbl, toArea, fromArea, ladder, connDist )
    local toAreasId = GetID( toArea )
    local cost = connDist
    local laddering

    if ladder and IsValidCost( ladder ) then
        if not myTbl.CanUseLadders then return -1 end

        laddering = true
        -- ladders are kinda dumb
        -- avoid if we can
        cost = ladMeta.GetLength( ladder ) * 2
        cost = cost + 400
    end

    cost = badConnectionCheck( getConnId( GetID( fromArea ), toAreasId ), cost )

    if laddering then return cost end

    local additionalCost = myTbl.pathAreasAdditionalCost[ toAreasId ]
    if additionalCost then
        cost = cost * additionalCost
        --debugoverlay.Cross( toArea:GetCenter(), 10, 10, color_white, true )

    end

    local attributes = navMeta.GetAttributes( toArea )
    local crouching

    if band( attributes, NAV_MESH_TRANSIENT ) ~= 0 and not self:transientAreaPathable( toArea, toAreasId ) then return -1 end

    local hunterIsFlanking = myTbl.hunterIsFlanking
    local flankingIsReallyAngry = myTbl.flankingIsReallyAngry

    if band( attributes, NAV_MESH_CROUCH ) ~= 0 then
        crouching = true
        if hunterIsFlanking then
            -- vents?
            cost = cost * 0.5
        else
            -- its cool when they crouch so dont punish it much
            cost = cost * 1.1
        end
    end

    if band( attributes, NAV_MESH_OBSTACLE_TOP ) ~= 0 then
        if navMeta.HasAttributes( fromArea, NAV_MESH_OBSTACLE_TOP ) then
            cost = cost * 4
        else
            cost = cost * 1.5 -- these usually look goofy
        end
    end

    local sizeX = navMeta.GetSizeX( toArea )
    local sizeY = navMeta.GetSizeY( toArea )

    if sizeX < 26 or sizeY < 26 then
        -- generator often makes small 1x1 areas with this attribute, on very complex terrain
        if band( attributes, NAV_MESH_NO_MERGE ) ~= 0 then
            cost = cost * 4
        else
            cost = cost * 1.25
        end
    end
    if sizeX > 151 and sizeY > 151 and not hunterIsFlanking then --- mmm very simple terrain
        cost = cost * 0.75

    elseif sizeX > 76 and sizeY > 76 then -- this makes us prefer paths thru simple terrain, it's cheaper!
        cost = cost * 0.9

    end

    if band( attributes, NAV_MESH_AVOID ) ~= 0 then
        cost = cost * 20
    end

    if navMeta.IsUnderwater( toArea ) then
        cost = cost * 2
    end

    if inCorridorAreas[toArea] then
        cost = cost * 0.5 -- this area was part of some other bot's valid path, so it probably goes somewhere useful
        --debugoverlay.Cross( toArea:GetCenter(), 10, 10, Color( 0, 255, 0 ), true )

    end

    local deltaZ = navMeta.ComputeAdjacentConnectionHeightChange( fromArea, toArea )
    local stepHeight = myTbl.loco:GetStepHeight()
    local jumpHeight = myTbl.loco:GetJumpHeight()
    if deltaZ >= stepHeight then
        if deltaZ >= jumpHeight then return -1 end
        if deltaZ > stepHeight * 4 then
            if hunterIsFlanking then
                cost = cost * 2

            else
                cost = cost * 5

            end
        elseif deltaZ > stepHeight * 2 then
            if hunterIsFlanking then
                cost = cost * 1.5

            else
                cost = cost * 3

            end
        else
            if hunterIsFlanking then
                cost = cost * 1.25

            else
                cost = cost * 2

            end
        end
        if crouching then
            cost = cost * 10

        end
    elseif not flankingIsReallyAngry and deltaZ <= -myTbl.loco:GetDeathDropHeight() then
        cost = cost * 50000

    elseif not flankingIsReallyAngry and deltaZ <= -jumpHeight then
        cost = cost * 2.5

    elseif not flankingIsReallyAngry and deltaZ <= -stepHeight * 3 then
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
    elseif deltaZ > 5 or deltaZ < -5 then
        if hunterIsFlanking then
            cost = cost * 1.1

        else
            cost = cost * 1.2

        end
    end

    return cost
end

function ENT:FloodMarkAsUnreachable( startArea )

    if terminator_Extras.IsLivePatching then return end
    local myTbl = entMeta.GetTable( self )

    local scoreData = {}
    local invalidUnreachable
    local wasABlockedArea = false
    scoreData.myArea = myTbl.GetCurrentNavArea( self, myTbl )
    scoreData.decreasingScores = {}
    scoreData.droppedDownAreas = {}
    scoreData.areasToUnreachable = {}

    -- find areas around the path's end that we can't reach
    -- this prevents super obnoxous stutters on maps with tens of thousands of navareas
    local scoreFunction = function( scoreData, area1, area2 )
        local score = scoreData.decreasingScores[GetID( area1 )] or 10000
        local droppedDown = scoreData.droppedDownAreas[GetID( area1 )]
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

        elseif dropToArea > myTbl.loco:GetMaxJumpHeight() or droppedDown then
            score = 1
            scoreData.droppedDownAreas[GetID( area2 )] = true

        else
            score = score + -1
            table.insert( scoreData.areasToUnreachable, area2 )

        end

        --debugoverlay.Text( area2:GetCenter(), tostring( score ), 8 )
        scoreData.decreasingScores[GetID( area2 )] = score

        return score

    end
    self:findValidNavResult( scoreData, startArea, 2000, scoreFunction )

    yieldIfWeCan()

    -- ok remember the areas as unreachable so we dont go through this again
    -- unless there was a locked door!
    if not wasABlockedArea then
        self:rememberAsUnreachable( startArea )

        -- stop after marking the path dest, IF the unreachable finder was invalid!
        if not invalidUnreachable then
            for _, area in ipairs( scoreData.areasToUnreachable ) do
                self:rememberAsUnreachable( area )

            end
        end
    end
end

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
        local computed, wasGood = self:SetupPath( endpos, endArea.area )
        local after = SysTime()

        local cost = ( after - before )
        if cost > 2 then
            self.term_ExpensivePath = true

        end

        -- good path, escape here
        if computed or self:PathIsValid() then
            self.setupPath2NoNavs = nil
            self.nextNewPath = CurTime() + math.Clamp( cost * 4, 0.1, 1 )

            if not wasGood then
                self:FloodMarkAsUnreachable( endArea.area )

            end

            return nil, "blocked5 ( the good ending )"

        -- no path! something failed
        else
            local setupPath2NoNavs = self.setupPath2NoNavs or 0
            -- aha, im not on the navmesh! that's why!
            local myArea = navmesh.GetNearestNavArea( self:GetPos(), false, 45, false, false, -2 )
            if ( not IsValid( myArea ) or #myArea:GetAdjacentAreas() <= 0 ) and self:IsOnGround() then
                self.setupPath2NoNavs = setupPath2NoNavs + 1

            end
            if setupPath2NoNavs > 4 then
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

    if not IsValid( endArea.area ) then return nil, "softfail1" end -- outdated....

    if not self:IsOnGround() then return nil, "softfail2" end -- don't member as unreachable when we're in the air
    if endArea.area:GetClosestPointOnArea( endpos ):Distance( endpos ) > 25 then return nil, "softfail3" end -- if endpos is off the navmesh then dont create false unreachable flags

    --debugoverlay.Text( endArea.area:GetCenter(), "unREACHABLE" .. tostring( pathDestinationIsAnOrphan ), 8 )

    self:FloodMarkAsUnreachable( endArea.area )

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

local ladderOffset = 800000

-- helper func for findValidNavResult
local function AreaOrLadderGetID( areaOrLadder )
    if not areaOrLadder then return end
    if areaOrLadder.GetTop then
        -- never seen a navmesh with 800k areas
        return LaddGetID( areaOrLadder ) + ladderOffset

    else
        return GetID( areaOrLadder )

    end
end

-- helper func for findValidNavResult
local function getNavAreaOrLadderById( areaOrLadderID )
    local area = navmesh.GetNavAreaByID( areaOrLadderID )
    if area then
        return area

    end
    local ladder = navmesh.GetNavLadderByID( areaOrLadderID + -ladderOffset )
    if ladder then
        return ladder

    end
end

-- helper func for findValidNavResult
local function AreaOrLadderGetCenter( areaOrLadder )
    if not areaOrLadder then return end
    if areaOrLadder.GetTop then
        return ( ladMeta.GetTop( areaOrLadder ) + ladMeta.GetBottom( areaOrLadder ) ) / 2

    else
        return navMeta.GetCenter( areaOrLadder )

    end
end

local table_Add = table.Add
local table_IsEmpty = table.IsEmpty
local inf = math.huge
local ipairs = ipairs
local isnumber = isnumber
local table_remove = table.remove
local table_insert = table.insert
local table_Random = table.Random

-- helper func for findValidNavResult
local function removeFrom( idToRemove, seqTbl, maskTbl )
    local existed = maskTbl[idToRemove]
    if not existed then return false end

    maskTbl[idToRemove] = nil
    for i = 1, #seqTbl do
        if seqTbl[i] == idToRemove then
            table_remove( seqTbl, i )
            return true -- removed

        end
    end
    return false -- not removed

end

-- helper func for findValidNavResult
local function addTo( idToAdd, seqTbl, maskTbl )
    if not maskTbl[idToAdd] then
        seqTbl[#seqTbl + 1] = idToAdd
        maskTbl[idToAdd] = true
        return true

    end
    return false -- not added, already there

end

-- helper func for findValidNavResult
local function AreaOrLadderGetAdjacentAreas( areaOrLadder, blockLadders )
    local adjacents = {}
    if not areaOrLadder then return adjacents end
    if areaOrLadder.GetTop then -- is ladder
        if blockLadders then return end
        table_insert( adjacents, ladMeta.GetBottomArea( areaOrLadder ) )
        table_insert( adjacents, ladMeta.GetTopForwardArea( areaOrLadder ) )
        table_insert( adjacents, ladMeta.GetTopBehindArea( areaOrLadder ) )
        table_insert( adjacents, ladMeta.GetTopRightArea( areaOrLadder ) )
        table_insert( adjacents, ladMeta.GetTopLeftArea( areaOrLadder ) )

    else
        if blockLadders then
            adjacents = navMeta.GetAdjacentAreas( areaOrLadder )

        else
            adjacents = table_Add( navMeta.GetAdjacentAreas( areaOrLadder ), navMeta.GetLadders( areaOrLadder ) )

        end

    end
    return adjacents

end

--[[------------------------------------
    Name: findValidNavResult
    Desc: Iterative function that finds the connected area with the best score.
        This is essentially A* but for finding a goal somewhere, instead of finding a path to a goal.
        Areas with the highest return from the score function are selected.
        Areas that return a score of 0 or less from the score function are ignored.
        Areas that return a score of inf immediately end the search.
    Arg1: table | data | Data table for the search.
    Arg2: any | start | Starting position or area.
    Arg3: number | radius | Maximum search radius.
    Arg4: function | scoreFunc | Function to evaluate the score of an area.
    Arg5: (optional) number | noMoreOptionsMin | Minimum number of closed areas before stopping.
    Ret1: Vector | Best area's center.
    Ret2: CNavArea | Best area.
    Ret3: bool | If this escaped the radius.
    Ret4: table | Table of all areas explored.
--]]------------------------------------
function ENT:findValidNavResult( data, start, radius, scoreFunc, noMoreOptionsMin )
    local pos = nil
    local res = nil
    local cur = nil
    local blockRadiusEnd = data.blockRadiusEnd -- by default, this func tries to find a way to escape the radius, set this to true if you're finding a cover pos or something
    if isvector( start ) then -- parse it!
        pos = start
        res = terminator_Extras.getNearestPosOnNav( pos )
        cur = res.area

    elseif IsValid( start ) then
        pos = AreaOrLadderGetCenter( start )
        cur = start

    end
    -- start is invalid or off the navmesh
    if not IsValid( cur ) then return nil, NULL, nil, nil end

    local curId = AreaOrLadderGetID( cur )
    local blockLadders = not self.CanUseLadders

    noMoreOptionsMin = noMoreOptionsMin or 8

    local opened = { [curId] = true }
    local openedSequential = { curId }
    local closed = {}
    local closedSequential = {}
    local distances = { [curId] = AreaOrLadderGetCenter( cur ):Distance( pos ) }
    local scores = { [curId] = 1 }
    local opCount = 0
    local isLadder = {}

    if cur.GetTop then
        isLadder[curId] = true

    end

    while not table_IsEmpty( opened ) do
        local bestScore = 0
        local bestArea = nil

        for _, currOpenedId in ipairs( openedSequential ) do
            local myScore = scores[currOpenedId]

            if isnumber( myScore ) and myScore > bestScore then
                bestScore = myScore
                bestArea = currOpenedId

            end
        end
        if not bestArea then -- fallback
            local _
            _, bestArea = table_Random( opened )

        end

        local areaId = bestArea
        removeFrom( areaId, openedSequential, opened )
        addTo( areaId, closedSequential, closed )

        local area = getNavAreaOrLadderById( areaId )

        opCount = opCount + 1
        if ( opCount % 15 ) == 0 then
            yieldIfWeCan()
            if not IsValid( area ) then
                -- area was removed while we were yielding, damn areapatcher
                return nil, NULL, nil, nil

            end
        end

        local myDist = distances[areaId]
        local noMoreOptions = #openedSequential == 1 and #closedSequential >= noMoreOptionsMin

        if noMoreOptions or opCount >= 600 or bestScore == inf then
            local _, bestClosedAreaId = table_Random( closed )
            local bestClosedScore = 0

            for _, currClosedId in ipairs( closedSequential ) do
                local currClosedScore = scores[currClosedId]

                if isnumber( currClosedScore ) and currClosedScore > bestClosedScore and isLadder[ currClosedId ] ~= true then
                    bestClosedScore = currClosedScore
                    bestClosedAreaId = currClosedId

                end
                if bestClosedScore == inf then
                    break

                end
            end
            local bestClosedArea = navmesh.GetNavAreaByID( bestClosedAreaId )
            -- edge case, huh??? if this happens
            if not bestClosedArea then return nil, NULL, nil, nil end

            -- ran out of perf/options/found best area
            return navMeta.GetCenter( bestClosedArea ), bestClosedArea, nil, closedSequential

        elseif not blockRadiusEnd and myDist > radius and area and not isLadder[areaId] then
            -- found an area that escaped the radius, blockable by blockRadiusEnd
            return navMeta.GetCenter( area ), area, true, closedSequential

        end

        local adjacents = AreaOrLadderGetAdjacentAreas( area, blockLadders )

        for _, adjArea in ipairs( adjacents ) do
            local adjID = AreaOrLadderGetID( adjArea )

            if not closed[adjID] then

                local theScore = 0
                if area.GetTop or adjArea.GetTop then
                    -- just let the algorithm pass through this
                    theScore = scores[areaId]

                else
                    theScore = scoreFunc( data, area, adjArea )

                end
                if theScore <= 0 then continue end

                local adjDist = AreaOrLadderGetCenter( area ):Distance( AreaOrLadderGetCenter( adjArea ) )
                local distance = myDist + adjDist

                distances[adjID] = distance
                scores[adjID] = theScore
                addTo( adjID, openedSequential, opened )

                if adjArea.GetTop then
                    isLadder[adjID] = true

                end
            end
        end
    end
end


-- try to replicate default path:Compute behaviour
local function adjacentAreasSkippingLadders( area )
    local areaDatas = navMeta.GetAdjacentAreaDistances( area )

    local ladders = navMeta.GetLadders( area )
    if #ladders > 0 then
        local areasCenter = navMeta.GetCenter( area )
        local already = { [GetID( area )] = true }
        for _, areaData in ipairs( areaDatas ) do
            already[GetID( areaData.area )] = true

        end
        for _, ladder in ipairs( ladders ) do
            local ladderAdjacents = AreaOrLadderGetAdjacentAreas( ladder )
            for _, ladderAdj in ipairs( ladderAdjacents ) do
                local ladderAdjID = GetID( ladderAdj )
                if not already[ladderAdjID] then
                    local adjacentsData = {
                        area = ladderAdj,
                        dist = vecMeta.Distance( navMeta.GetCenter( ladderAdj ), areasCenter ), -- simple distance, can change later if its a problem
                        ladder = ladder,
                        --dir shouldnt need this
                    }
                    table_insert( areaDatas, adjacentsData )
                    already[ladderAdjID] = true

                end
            end
        end
    end

    return areaDatas
end

-- return "path" of navareas that get us where we're going
local function reconstruct_path( cameFrom, goalArea )
    local total_path_reverse = { goalArea }
    local noCircles = {}

    local count = 0
    local currId = GetID( goalArea )
    local last = goalArea:GetCenter()
    while cameFrom[currId] do
        count = count + 1
        if count % 15 == 14 then
            coroutine_yield( "pathing" )

        end
        local current = cameFrom[currId]
        currId = current.id

        if noCircles[currId] then -- rare, happened when navmesh was being actively edited, also when the astar was giving invalid camefroms
            --debugoverlay.Line( last, current.area:GetCenter(), 15, Color( 255, 0, 0 ), true )
            --debugoverlay.Cross( last, 15, 15, Color( 255, 0, 0 ), true )
            return false

        --else
            --debugoverlay.Line( last, current.area:GetCenter(), 5, color_white, true )

        end
        last = current.area:GetCenter()
        noCircles[currId] = true

        total_path_reverse[#total_path_reverse + 1] = current.area

    end

    local total_path
    if #total_path_reverse > 0 then
        total_path = {}
        for i = #total_path_reverse, 1, -1 do
            total_path[#total_path + 1] = total_path_reverse[i]

        end
    else
        total_path = { goalArea }

    end

    return total_path

end

local function areaDistToPos( start, goalPos )
    return vecMeta.Distance( navMeta.GetCenter( start ), goalPos )

end

local newUnreachableClass
local newUnreachables = 0

-- actually finds the paths, on coroutine
-- theoretically possible to use this without a term, but you will need to supply a scoreKeeper, see ENT:NavMeshPathCostGenerator

-- returns... | area, final goal | table, area corridor | bool, if we got there | string, debug status

function terminator_Extras.Astar( me, myTbl, startArea, goal, goalArea, scoreKeeper )
    if not IsValid( startArea ) or not IsValid( goalArea ) then return nil, nil, false, "fail1" end -- FAIL
    if startArea == goalArea then return goalArea, { startArea, goalArea }, true, "succeed3" end -- already there

    myTbl = myTbl or {} -- handle non-object astar calls in the future?

    local lastNewUnreachables = newUnreachables
    local maxPathingIterations = myTbl.MaxPathingIterations
    local fodder = myTbl.IsFodder
    local currExtent = 0

    local startAreasId = GetID( startArea )
    local opened = { [startAreasId] = true }
    local openedSequential = { startAreasId }
    local closed = {}
    local closedSequential = {}
    local cameFrom = {}
    local costsSoFar = { [startAreasId] = 0 }
    local costsToEnd = { [startAreasId] = areaDistToPos( startArea, goal ) }

    while #openedSequential > 0 do
        if fodder and lastNewUnreachables ~= newUnreachables then -- fodder enems share unreachable areas, so check if a buddy marked this as unreachable
            lastNewUnreachables = newUnreachables
            if newUnreachableClass == entMeta.GetClass( me ) and not myTbl.areaIsReachable( me, goalArea ) then
                return goalArea, nil, false, "fail3"

            end
        end
        coroutine_yield( "pathing" ) -- so corotine manager knows we're pathing

        local smallestCost = inf
        local bestId
        for _, id in ipairs( openedSequential ) do
            local cost = costsSoFar[id] + costsToEnd[id]
            if cost < smallestCost then
                smallestCost = cost
                bestId = id

            end
        end
        local costSoFar = costsSoFar[bestId]
        local ourCameFrom = cameFrom[bestId]
        removeFrom( bestId, openedSequential, opened )
        addTo( bestId, closedSequential, closed )

        local bestArea = navmesh.GetNavAreaByID( bestId )
        if not IsValid( bestArea ) then -- we are in a coroutine, this can happen
            continue

        end

        --debugoverlay.Text( bestArea:GetCenter(), "A* " .. tostring( math.Round( smallestCost ) ), 5, color_white, true )

        if maxPathingIterations and currExtent > maxPathingIterations then -- all out :(
            local smallestCompromiseCost = inf
            local bestCompromiseId
            for _, id in ipairs( opened ) do
                if not costsSoFar[id] then continue end
                local cost = costsSoFar[id] + costsToEnd[id]
                if cost < smallestCompromiseCost then
                    smallestCompromiseCost = cost
                    bestCompromiseId = id

                end
            end
            if bestCompromiseId then
                local bestCompromiseArea = navmesh.GetNavAreaByID( bestCompromiseId )
                local areaCorridor = reconstruct_path( cameFrom, bestCompromiseArea )
                if not areaCorridor then
                    return bestCompromiseArea, nil, false, "fail4"

                end
                return bestCompromiseArea, areaCorridor, false, "succeed2"

            else
                return nil, false, "fail5"

            end
        elseif bestArea == goalArea then
            return goalArea, reconstruct_path( cameFrom, goalArea ), true, "succeed1"

        end


        local adjacentDatas = adjacentAreasSkippingLadders( bestArea )

        for _, neighborDat in ipairs( adjacentDatas ) do
            currExtent = currExtent + 1
            if currExtent % 4 == 3 then
                coroutine_yield( "pathing" )

            end
            local neighbor = neighborDat.area
            if not IsValid( neighbor ) then continue end -- can happen when navmesh is being edited

            local neighborsId = GetID( neighbor )
            -- NavMeshPathCostGenerator
            local neighborsCost = scoreKeeper( neighbor, bestArea, neighborDat.ladder, neighborDat.dist )

            local neighborsCostSoFar = costSoFar + neighborsCost

            local wasTackled = opened[neighborsId] or closed[neighborsId]

            local cannotTraverse = neighborsCost <= -1

            if cannotTraverse and wasTackled then -- cant go this way, but there's already a way there
                continue

            elseif cannotTraverse then -- cant go this way
                addTo( neighborsId, closedSequential, closed ) -- mark as closed
                costsSoFar[neighborsId] = costSoFar * 1000 -- blow up the cost, so any valid retraces are very confident going back over this
                continue

            end

            local goodRetrace = wasTackled and ourCameFrom and ourCameFrom.id ~= neighborsId and neighborsCostSoFar <= costsSoFar[neighborsId]

            if wasTackled and not goodRetrace then
                continue

            else
                costsSoFar[neighborsId] = neighborsCostSoFar
                costsToEnd[neighborsId] = areaDistToPos( neighbor, goal )

                removeFrom( neighborsId, closedSequential, closed )
                addTo( neighborsId, openedSequential, opened )
                cameFrom[ neighborsId ] = { id = bestId, ladder = neighborDat.ladder, area = bestArea }

            end
        end
    end
    return goalArea, nil, false, "fail6"

end

local Astar = terminator_Extras.Astar

hook.Add( "term_updateunreachableareas", "term_nouseless_fodderpaths", function( classUpdated )
    newUnreachables = newUnreachables + 1
    newUnreachableClass = classUpdated

end )

local allowedDeviations
local areaCorridorNexts -- used to force the path:Compute to use a specific path

-- generatorHack is a hack to allow us to use default path structure with a custom generator
-- used to force the path:Compute to use a specific path, since we can't build a Path() manually
local function generatorHack( area, fromArea, _ladder, _elevator, _length ) -- unthinkable HACK!!!
    local areaId
    local fromNext

    if fromArea then
        fromNext = areaCorridorNexts[ GetID( fromArea ) ]
        if not fromNext then -- not on the path
            allowedDeviations = allowedDeviations + -1 -- allow some deviations
            if allowedDeviations <= 0 then
                return -1 -- not in corridor, dont use this area

            else
                return 10000000000000 -- low priority

            end
        end
    else
        return 1 -- start of path

    end

    if area then
        areaId = GetID( area )
        local areaMask = areaCorridorNexts[ areaId ]
        if not areaMask then
            return 10000000000000 -- not in corridor, try this last

        end
    end

    if fromNext == true then -- special area
        return 1

    elseif fromNext == areaId then -- keep going
        return 1

    end

    return -1 -- not the correct path

end

local function AstarCompute( path, me, myTbl, goal, goalArea, scoreKeeper )
    local startArea = me:GetCurrentNavArea()
    --debugoverlay.Line( startArea:GetCenter(), goal, 5, Color( 0, 255, 0 ), true )
    local start = SysTime()
    local newGoalArea, areaCorridor, wasGood, _debugMsg = Astar( me, myTbl, startArea, goal, goalArea, scoreKeeper )
    local timeTaken = SysTime() - start

    if not areaCorridor then
        path:Invalidate() -- a* failed to find a good path, or even a compromise path
        return nil, false, "noCorridor"

    end

    if not IsValid( startArea ) or not IsValid( newGoalArea ) then -- outdated!
        path:Invalidate() -- outdated, happens when the navmesh is being edited
        return nil, false, "invalidEnds"

    end

    goal = navMeta.GetClosestPointOnArea( newGoalArea, goal ) -- make sure the goal lines up

    local corridorIds = {}
    for _, area in ipairs( areaCorridor ) do
        --debugoverlay.Cross( area:GetCenter(), 10, 5, color_white, true )
        if not IsValid( area ) then continue end
        corridorIds[#corridorIds + 1] = GetID( area )

    end

    --local last = areaCorridor[1]:GetCenter() --debugging

    -- terrible hack, we make a corridor with astar, then run a path:Compute inside that corridor
    -- all this since building a Path() manually seemed to not be possible
    -- the things that must be done for coroutined pathfinding...

    areaCorridorNexts = { [GetID( newGoalArea )] = true, [GetID( startArea )] = corridorIds[1] }
    for i, currId in ipairs( corridorIds ) do
        local nextOne = corridorIds[i + 1]
        if nextOne then
            areaCorridorNexts[ currId ] = nextOne -- force the compute to take the correct path

        else
            areaCorridorNexts[ currId ] = true

        end

        --[[
        yieldIfWeCan("wait")
        local thisCenter = navMeta.GetCenter( getNavAreaOrLadderById( currId ) )
        debugoverlay.Line( last, thisCenter, 5, color_white, true )
        last = thisCenter
        --]]

    end

    allowedDeviations = 250

    local computed = path:Compute( me, goal, generatorHack )
    areaCorridorNexts = nil
    allowedDeviations = nil

    if not path:IsValid() then -- :(
        return nil, false, "noCompute"

    end

    if timeTaken > 2 or startArea:GetCenter():Distance( goal ) > 1000 then
        addToCorridor( areaCorridor ) -- let future bots confidently traverse this valid path corridor

    end

    return computed, wasGood, "allGood"
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
function ENT:SetupPath( pos, endArea )
    local myTbl = entMeta.GetTable( self )
    myTbl.InvalidatePath( self, "i started a new path" )

    myTbl.pathAreasAdditionalCost = myTbl.pathAreasAdditionalCost or {}

    if not myTbl.IsFodder then -- fodder npcs usually dont live long enough for this to matter.
        -- areas that we took damage in
        myTbl.AddAreasToAvoid( self, myTbl.hazardousAreas, FLANK_DEFAULT_COST / 2 )

    end

    local adjusted = myTbl.AdditionalAvoidAreas( self, myTbl.pathAreasAdditionalCost )
    if istable( adjusted ) then
        myTbl.pathAreasAdditionalCost = adjusted

    end

    if myTbl.awarenessDamaging then
        local damagingAreas = self:DamagingAreas()
        local avoidStrength = 50
        -- blinded by rage
        if self:IsReallyAngry() then
            avoidStrength = 2

        elseif self:IsAngry() then
            avoidStrength = 25

        end
        self:AddAreasToAvoid( damagingAreas, avoidStrength )

    end

    local function scoreKeeper( area, from, ladder, connDist )
        return myTbl.NavMeshPathCostGenerator( self, myTbl, area, from, ladder, connDist )

    end

    local path = Path( "Follow" )
    myTbl.m_Path = path

    path:SetMinLookAheadDistance( myTbl.PathMinLookAheadDistance )
    path:SetGoalTolerance( myTbl.PathGoalTolerance )

    myTbl.m_PathPos = pos

    local computed, wasGood, _status = AstarCompute( path, self, myTbl, pos, endArea, scoreKeeper )
    --print( self:GetCreationID(), "AstarCompute", computed, wasGood, _status )

    myTbl.pathAreasAdditionalCost = nil

    if not path:IsValid() then
        self:InvalidatePath( "i failed to build a path" )

        -- this stuck edge case usually happens when the bot ends up in some orphan part of the navmesh with no way out, eg bottom of an elevator shaft
        local old = myTbl.term_ConsecutivePathFailures or 0
        if old > 25 then
            myTbl.overrideVeryStuck = true -- alert the reallystuck_handler

        elseif old >= 5 then
            local currNav = myTbl.GetCurrentNavArea( self, myTbl )
            if not IsValid( currNav ) or self:AreaIsOrphan( currNav, true ) then
                myTbl.overrideVeryStuck = true -- alert the reallystuck_handler early!

            end
        end

        if self:IsOnGround() then
            myTbl.term_ConsecutivePathFailures = old + 1

        end
        return false

    end

    myTbl.term_ConsecutivePathFailures = 0

    return computed, wasGood

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