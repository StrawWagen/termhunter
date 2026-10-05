local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local IsValid = IsValid
local SysTime = SysTime
local entMeta = FindMetaTable( "Entity" )
local pathMeta = FindMetaTable( "PathFollower" )
local locoMeta  = FindMetaTable( "CLuaLocomotion" )

local terminator_Extras = terminator_Extras

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
    if not IsValid( path ) then return end
    path:Invalidate()

    self.term_PathShouldBeValid = nil
    self.term_ExpensivePath = nil

    self.term_cancelPathGen = true

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

function ENT:getCachedPathSegments( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )
    local path = myTbl.GetPath( self, myTbl )
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
    local myTbl = entMeta.GetTable( self )
    local path = myTbl.GetPath( self, myTbl )
    if not myTbl.PathIsValid( self, path ) then return end

    local targetReferenceArea = refArea or myTbl.GetCurrentNavArea( self, myTbl )
    if not IsValid( targetReferenceArea ) then return end

    local fodder = myTbl.IsFodder
    local key
    if fodder then
        key = tostring( pathMeta.GetEnd( path ) ) .. targetReferenceArea:GetID()
        local oldCacheKey = myTbl.GetNextPathAreaCacheKey
        if oldCacheKey and oldCacheKey == key then
            local cache = myTbl.GetNextPathAreaCache
            return cache[1], cache[2]

        end
    end

    local pathSegs = myTbl.getCachedPathSegments( self, myTbl )
    local myPathPoint = path:GetCurrentGoal()
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

    if fodder then
        myTbl.GetNextPathAreaCacheKey = key
        myTbl.GetNextPathAreaCache = { goalArea, goalPathPoint }

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

function ENT:GetPathDistanceToGoal( path )
    path = path or self:GetPath()
    if not self:PathIsValid( path ) then return 0 end

    local fullLength = path:GetLength()
    local distIntoPath = path:GetCursorPosition()

    return fullLength - distIntoPath

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

local table_insert = table.insert

local transientAreaPathable

do
    local transientAreaCached = {}
    local nextTransientAreaCaches = {}
    local belowOffset = Vector( 0, 0, -45 )
    local hull = Vector( 5, 5, 1 )

    transientAreaPathable = function( _, area, areasId )
        local nextCache = nextTransientAreaCaches[areasId] or 0
        if nextCache > CurTime() then return transientAreaCached[areasId] end
        nextTransientAreaCaches[areasId] = CurTime() + math.Rand( 0.5, 1 )

        local toCheckPositions = {}
        local center = area:GetCenter()
        table_insert( toCheckPositions, center )

        for cornerInd = 0, 3 do
            local corner = area:GetCorner( cornerInd )
            local dirToCenter = terminator_Extras.dirToPos( corner, center )
            local cornerOffsetted = corner + dirToCenter * 12.5

            table_insert( toCheckPositions, cornerOffsetted )

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
end

ENT.transientAreaPathable = transientAreaPathable

local badConnections = {}
local lastBadFlags = {}
local superBadConnections = {}
local lastSuperBadFlags = {}
local normalBadTimeout = 120
local superBadTimeout = 520

-- worst case product is 2^48, still exact
local CONN_ID_STRIDE = 2 ^ 24

local function getConnId( fromAreaId, toAreaId )
    -- this needs to have directionality
    return fromAreaId * CONN_ID_STRIDE + toAreaId

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
        -- dont obliterate new ones! the reflag scheduled its own timer, let that one clear it
        if lastFlag + ( normalBadTimeout + -10 ) > CurTime() then return end

        badConnections[connectionsId] = nil
        lastBadFlags[connectionsId] = nil

    end )

    if not superShitConnection then return end

    superBadConnections[connectionsId] = true
    lastSuperBadFlags[connectionsId] = CurTime()

    timer.Simple( superBadTimeout, function()
        local lastSuperFlag = lastSuperBadFlags[connectionsId]

        if not lastSuperFlag then return end
        if lastSuperFlag + ( superBadTimeout + -10 ) > CurTime() then return end

        superBadConnections[connectionsId] = nil
        lastSuperBadFlags[connectionsId] = nil

    end )
end

local function badConnectionCost( connectionsId, dist )
    if badConnections[connectionsId] then
        dist = dist * 10
        dist = dist + 3000

    end
    if superBadConnections[connectionsId] then
        dist = dist * 1000
        dist = dist + 20000000

    end
    return dist

end

local function clearConnectionFlags()
    -- emptied rather than reassigned, so the pending timer closures keep clearing the
    -- same tables the cost generator reads
    table.Empty( badConnections )
    table.Empty( lastBadFlags )
    table.Empty( superBadConnections )
    table.Empty( lastSuperBadFlags )

end

hook.Add( "PostCleanupMap", "terminator_clear_connectionflags", clearConnectionFlags )

hook.Add( "terminator_nextbot_noterms_exist", "clear_connectionflags_on_term_removal", clearConnectionFlags )

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

local FLANK_DEFAULT_COST = 5

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


local navmesh = navmesh
local band = bit.band

local navMeta = FindMetaTable( "CNavArea" )
local ladMeta = FindMetaTable( "CNavLadder" )

local GetID = navMeta.GetID
local LaddGetID = ladMeta.GetID

terminator_Extras.DOING_CORRIDORAREAS = terminator_Extras.DOING_CORRIDORAREAS or nil
local inCorridorAreas = nil -- save areas that were valid a* paths, and biast bots to use them, makes pathing faster by letting bots confidently traverse old valid paths
local corridorExpireTimes = nil

local function startCounting()
    inCorridorAreas = {}
    corridorExpireTimes = {}
    terminator_Extras.DOING_CORRIDORAREAS = true

    -- the corridors aren't worth keeping and using unless they're running really hot
    timer.Create( "terminator_cleanupcorridor", 5, 0, function()
        local cur = CurTime()
        for area, expireTime in pairs( corridorExpireTimes ) do
            if expireTime < cur then
                inCorridorAreas[area] = nil
                corridorExpireTimes[area] = nil

            end
        end
    end )
end

if terminator_Extras.DOING_CORRIDORAREAS then -- auto re fresh
    startCounting()

end

hook.Add( "terminator_nextbot_oneterm_exists", "corridorareas_optimisation", function()
    startCounting()

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
        --debugoverlay.Cross( area:GetCenter(), 10, 10, Color( 255, 0, 0), true )
        inCorridorAreas[area] = true
        corridorExpireTimes[area] = cur + math.random( 15, 25 ) -- dont hold onto these for long, it's gonna get outdated fast

    end
end

function ENT:NavMeshPathCostGenerator( locoData, toArea, fromArea, ladder, connDist )
    local toAreasId = GetID( toArea )
    local cost = connDist
    local laddering

    if ladder and IsValid( ladder ) then
        if not locoData.canUseLadders then return -1 end

        laddering = true
        -- ladders are kinda dumb
        -- avoid if we can
        cost = ladMeta.GetLength( ladder ) * 1.5
        cost = cost + 200

    end

    cost = badConnectionCost( getConnId( GetID( fromArea ), toAreasId ), cost )

    if laddering then return cost end

    local additionalCost = locoData.pathAreasAdditionalCost[ toAreasId ]
    if additionalCost then
        cost = cost * additionalCost

    end

    local attributes = navMeta.GetAttributes( toArea )
    local crouching

    if band( attributes, NAV_MESH_TRANSIENT ) ~= 0 then
        if not transientAreaPathable( nil, toArea, toAreasId ) then
            return -1

        end
        coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )
        if not IsValid( fromArea ) then return -1 end
        if not IsValid( toArea ) then return -1 end

    end

    local hunterIsFlanking = locoData.hunterIsFlanking
    local flankingIsReallyAngry = locoData.flankingIsReallyAngry

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

    if band( attributes, NAV_MESH_AVOID ) ~= 0 then
        cost = cost * 20

    end

    local sizeX = navMeta.GetSizeX( toArea )
    local sizeY = navMeta.GetSizeY( toArea )
    local smallestSize = sizeX < sizeY and sizeX or sizeY

    local minWidth = locoData.minPathingAreaWidth
    if smallestSize < minWidth then
        return -1

    elseif smallestSize < 26 then
        -- generator often makes small 1x1 areas with this attribute, on very complex terrain
        if band( attributes, NAV_MESH_NO_MERGE ) ~= 0 then
            cost = cost * 4

        else
            cost = cost * 1.25

        end
    elseif smallestSize > 151 and not hunterIsFlanking then -- this makes us prefer paths thru simple terrain, it's cheaper!
        cost = cost * 0.7

    end

    if navMeta.IsUnderwater( toArea ) then
        if not locoData.canSwim then
            cost = cost * 4

        end
        cost = cost * 2

    end

    if inCorridorAreas[toArea] then -- this area was part of some other bot's valid path, so it probably goes somewhere useful
        if hunterIsFlanking then -- let the flanking weights still steer us 
            cost = cost * 0.5

        elseif not locoData.isFodder then
            cost = cost * 0.25

        else -- lean on this system HARD for fodder bots
            cost = cost * 0.1

        end
    end

    local deltaZ = navMeta.ComputeAdjacentConnectionHeightChange( fromArea, toArea )

    local stepHeight = locoData.stepHeight
    local jumpHeight = locoData.jumpHeight

    if deltaZ >= stepHeight then
        if deltaZ >= jumpHeight then return -1 end
        if deltaZ > stepHeight * 4 then
            if hunterIsFlanking then
                cost = cost * 5

            else
                cost = cost * 8

            end
        elseif deltaZ > stepHeight * 2 then
            if hunterIsFlanking then
                cost = cost * 2

            else
                cost = cost * 5

            end
        else
            if hunterIsFlanking then
                cost = cost * 1.5

            else
                cost = cost * 3

            end
        end
        if crouching then
            cost = cost * 10

        end
    elseif not flankingIsReallyAngry and deltaZ <= -locoData.deathDropHeight then
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

    coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )
    if not IsValid( fromArea ) then return -1 end
    if not IsValid( toArea ) then return -1 end

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

    coroutine_yield()

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
    coroutine_yield()

    if not isvector( endpos ) then return nil, "blocked2" end
    if self.isUnstucking and not isUnstuck then return nil, "blocked3" end

    local endArea = terminator_Extras.getNearestPosOnNav( endpos )

    local reachable = self:areaIsReachable( endArea.area )
    if not reachable then
        -- make sure we dont get super duper stuck
        if self.isUnstucking and isUnstuck then
            self.overrideVeryStuck = true

        end
        return nil, "blocked4"

    end

    coroutine_yield()

    -- if we are not going to an orphan ( can still be an orphan, this is just a sanity check! )
    -- prevents paths to really small collections of navareas that don't connect back to the bot. ( and the lagspikes that come from those! )
    local pathDestinationIsAnOrphan, encounteredABlockedArea = self:AreaIsOrphan( endArea.area )

    coroutine_yield()

    -- not an orphan, proceed as normal!
    if pathDestinationIsAnOrphan ~= true then
        local before = SysTime()
        local computed, wasGood = self:SetupPath( endpos, endArea.area )
        local after = SysTime()

        local cost = ( after - before )
        if cost > 0.75 then -- yeesh!
            self.term_ExpensivePath = true

        end

        -- good path, escape here
        if computed or self:PathIsValid() then
            self.setupPath2NoNavs = nil
            self.nextNewPath = CurTime() + math.Clamp( cost * 4, 0.1, 1 )

            if not wasGood then
                self:FloodMarkAsUnreachable( endArea.area )

            end

            coroutine_yield()

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

    coroutine_yield()

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

    local failString = "extremefailure "
    if pathDestinationIsAnOrphan then
        failString = failString .. " WAS ORPHAN!"

    end

    self:RunTask( "OnPathFail", endpos, failString )

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

local tableAdd = terminator_Extras.tableAdd
local table_IsEmpty = table.IsEmpty
local inf = math.huge
local ipairs = ipairs
local isnumber = isnumber
local table_Random = table.Random
local floor = math.floor

local function addTo( idToAdd, seqTbl, maskTbl, posTbl )
    if not maskTbl[idToAdd] then
        local n = #seqTbl + 1
        seqTbl[n] = idToAdd
        maskTbl[idToAdd] = true
        posTbl[idToAdd] = n
        return true

    end
    return false

end

local function removeFrom( idToRemove, seqTbl, maskTbl, posTbl )
    local existed = maskTbl[idToRemove]
    if not existed then return false end

    maskTbl[idToRemove] = nil
    local i = posTbl[idToRemove]
    posTbl[idToRemove] = nil
    local n = #seqTbl
    if i ~= n then
        local last = seqTbl[n]
        seqTbl[i] = last    -- move last element into the gap
        posTbl[last] = i    -- update last element's recorded position

    end
    seqTbl[n] = nil         -- pop tail
    return true

end

-- addToSorted and takeLowestFrom are the same three tables again, but seqTbl is kept as a
-- binary min heap on costs1[id] + costs2[id], so the cheapest id is always seqTbl[1].
-- posTbl is what makes that affordable, it says where an id sits without searching for it.
-- the cost tables are read live on every compare, so a queued id's cost must never rise

local function siftUp( seqTbl, posTbl, i, costs1, costs2 )
    local id = seqTbl[i]
    local cost = costs1[id] + costs2[id]

    while i > 1 do
        local parent = floor( i * 0.5 )
        local parentId = seqTbl[parent]
        if costs1[parentId] + costs2[parentId] <= cost then break end

        seqTbl[i] = parentId    -- parent is dearer, so it sinks into our slot
        posTbl[parentId] = i
        i = parent

    end
    seqTbl[i] = id
    posTbl[id] = i

end

local function siftDown( seqTbl, posTbl, i, n, costs1, costs2 )
    local id = seqTbl[i]
    local cost = costs1[id] + costs2[id]

    while true do
        local child = i * 2
        if child > n then break end

        local childId = seqTbl[child]
        local childCost = costs1[childId] + costs2[childId]

        if child < n then -- there's a right child too, take whichever is cheaper
            local rightId = seqTbl[child + 1]
            local rightCost = costs1[rightId] + costs2[rightId]
            if rightCost < childCost then
                child = child + 1
                childId = rightId
                childCost = rightCost

            end
        end
        if cost <= childCost then break end

        seqTbl[i] = childId     -- child is cheaper, so it rises into our slot
        posTbl[childId] = i
        i = child

    end
    seqTbl[i] = id
    posTbl[id] = i

end

local function addToSorted( idToAdd, seqTbl, maskTbl, posTbl, costs1, costs2 )
    local at = posTbl[idToAdd]
    if at then
        -- already queued. callers only requeue an id after lowering its cost, so it can
        -- only need to move up. requeue one that got dearer and the heap goes wrong
        siftUp( seqTbl, posTbl, at, costs1, costs2 )
        return false

    end
    local n = #seqTbl + 1
    seqTbl[n] = idToAdd
    maskTbl[idToAdd] = true
    posTbl[idToAdd] = n
    siftUp( seqTbl, posTbl, n, costs1, costs2 )
    return true

end

local function takeLowestFrom( seqTbl, maskTbl, posTbl, costs1, costs2 )
    local n = #seqTbl
    if n == 0 then return nil end

    local bestId = seqTbl[1]
    maskTbl[bestId] = nil
    posTbl[bestId] = nil

    local last = seqTbl[n]
    seqTbl[n] = nil             -- pop tail
    if n > 1 then
        seqTbl[1] = last        -- move tail to the root and let it settle
        posTbl[last] = 1
        siftDown( seqTbl, posTbl, 1, n + -1, costs1, costs2 )

    end
    return bestId

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
            adjacents = navMeta.GetAdjacentAreas( areaOrLadder )
            tableAdd( adjacents, navMeta.GetLadders( areaOrLadder ) )

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

    local myTbl = entMeta.GetTable( self )

    local curId = AreaOrLadderGetID( cur )
    local blockLadders = not myTbl.CanUseLadders

    noMoreOptionsMin = noMoreOptionsMin or 8

    local opened = { [curId] = true }
    local openedSequential = { curId }
    local openedPositions = { [curId] = 1 }
    local closed = {}
    local closedSequential = {}
    local closedPositions = {}
    local distances = { [curId] = AreaOrLadderGetCenter( cur ):Distance( pos ) }
    local scores = { [curId] = 1 }
    local opCount = 0
    local isLadder = {}
    local fodder = myTbl.IsFodder

    if cur.GetTop then
        isLadder[curId] = true

    end

    local yieldable = coroutine_running()

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
        removeFrom( areaId, openedSequential, opened, openedPositions )
        addTo( areaId, closedSequential, closed, closedPositions )

        local area = getNavAreaOrLadderById( areaId )

        opCount = opCount + 1
        if yieldable then
            coroutine_yield()

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

                if isnumber( currClosedScore ) and currClosedScore > bestClosedScore and isLadder[currClosedId] ~= true then
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
                if yieldable and fodder then
                    coroutine_yield()
                    if not ( IsValid( area ) and IsValid( adjArea ) ) then
                        continue

                    end
                end
                local theScore = 0
                if area.GetTop or adjArea.GetTop then
                    -- just let the algorithm pass through this
                    theScore = scores[areaId]

                else
                    theScore = scoreFunc( data, area, adjArea )

                end
                if theScore <= 0 then
                    addTo( adjID, closedSequential, closed, closedPositions )
                    continue

                end

                local adjDist = AreaOrLadderGetCenter( area ):Distance( AreaOrLadderGetCenter( adjArea ) )
                local distance = myDist + adjDist

                distances[adjID] = distance
                scores[adjID] = theScore
                addTo( adjID, openedSequential, opened, openedPositions )

                if adjArea.GetTop then
                    isLadder[adjID] = true

                end

                if theScore == inf then break end

            end
        end
    end
end


-- try to replicate default path:Compute behaviour
local function adjacentAreasSkippingLadders( area, canUseLadders )
    local areaDatas = navMeta.GetAdjacentAreaDistances( area )

    if not canUseLadders then return areaDatas end

    local ladders = navMeta.GetLadders( area )
    if #ladders > 0 then
        local already = { [GetID( area )] = true }
        for _, areaData in ipairs( areaDatas ) do
            already[GetID( areaData.area )] = true

        end
        for _, ladder in ipairs( ladders ) do
            local ladderAlreadyDone = { [GetID( area )] = true }
            local ladderAdjacents = AreaOrLadderGetAdjacentAreas( ladder )
            for _, ladderAdj in ipairs( ladderAdjacents ) do
                local ladderAdjID = GetID( ladderAdj )
                if ladderAlreadyDone[ladderAdjID] then continue end

                local adjacentsData
                if already[ladderAdjID] then
                    for _, areaData in ipairs( areaDatas ) do
                        if areaData.area ~= ladderAdj then continue end
                        adjacentsData = areaData
                        break
                    end
                end
                if adjacentsData then
                    adjacentsData.dist = ladder:GetLength()
                    adjacentsData.ladder = ladder

                else
                    adjacentsData = {
                        area = ladderAdj,
                        dist = ladder:GetLength(),
                        ladder = ladder,
                        --dir shouldnt need this
                    }
                end

                areaDatas[#areaDatas + 1] = adjacentsData
                ladderAlreadyDone[ladderAdjID] = true

            end
        end
    end

    return areaDatas
end

-- return "path" of navareas that get us where we're going
local function reconstruct_path( cameFromId, cameFromArea, goalArea )
    local total_path_reverse = { goalArea }
    local noCircles = {}

    --local last = goalArea:GetCenter()

    local count = 0
    local currId = GetID( goalArea )
    while cameFromId[currId] do
        count = count + 1
        if count >= 25 and count % 15 == 14 then -- only yield for long paths
            coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )

        end
        local fromArea = cameFromArea[currId]
        currId = cameFromId[currId]

        if noCircles[currId] then -- rare, happened when navmesh was being actively edited, also when the astar was giving invalid camefroms
            --debugoverlay.Line( last, fromArea:GetCenter(), 15, Color( 255, 0, 0 ), true )
            --debugoverlay.Cross( last, 15, 15, Color( 255, 0, 0 ), true )
            return false

        --else
            --debugoverlay.Line( last, fromArea:GetCenter(), 5, color_white, true )

        end
        if not IsValid( fromArea ) then -- outdated
            return false

        end
        --last = fromArea:GetCenter()
        noCircles[currId] = true

        total_path_reverse[#total_path_reverse + 1] = fromArea

    end

    local total_path
    if #total_path_reverse > 0 then
        total_path = {}
        for i = #total_path_reverse, 1, -1 do
            if i >= 25 and i % 15 == 14 then -- only yield for long paths
                coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )

            end
            total_path[#total_path + 1] = total_path_reverse[i]

        end
    else
        total_path = { goalArea }

    end

    return total_path

end

local areaDistToPos

do
    local function simple_abs( num )
        if num < 0 then return -num end
        return num

    end

    areaDistToPos = function( start, goalPos )
        local startPos = navMeta.GetCenter( start )
        local manhattanDist = simple_abs( startPos.x - goalPos.x ) + simple_abs( startPos.y - goalPos.y ) + simple_abs( startPos.z - goalPos.z )
        return manhattanDist

    end
end

-- fallback goal for when the search runs out of iterations. closed areas are the ones we
-- actually expanded, so we know a route to each, and the nearest to the goal is as far as
-- we got. areas the cost generator refused get closed with no costsToEnd entry, and those
-- are skipped, we never confirmed a way into them
local function getClosestToGoal( seqSearchTbl, costsToEnd )
    local smallestCost = inf
    local bestId
    for i, id in ipairs( seqSearchTbl ) do
        if i % 25 == 24 then
            coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )

        end
        local cost = costsToEnd[id]
        if cost and cost < smallestCost then
            smallestCost = cost
            bestId = id

        end
    end
    return bestId

end

local newUnreachableClass
local newUnreachables = 0

-- actually finds the paths, on coroutine
-- theoretically possible to use this without a term, but you will need to supply a NavMeshPathCostGenerator, see ENT:NavMeshPathCostGenerator

-- returns... | area, final goal | table, area corridor | bool, if we got there | string, debug status

function terminator_Extras.Astar( me, myTbl, startArea, goal, goalArea, NavMeshPathCostGenerator )
    if not IsValid( startArea ) or not IsValid( goalArea ) then return nil, nil, false, "fail1" end -- FAIL
    if startArea == goalArea then return goalArea, { startArea, goalArea }, true, "succeed3" end -- already there

    myTbl = myTbl or {} -- handle non-object astar calls in the future?

    local lastNewUnreachables = newUnreachables
    local maxPathingIterations = myTbl.MaxPathingIterations
    local fodder = myTbl.IsFodder
    local currExtent = 0

    local startAreasId = GetID( startArea )
    local opened = {}
    local openedSequential = {}
    local openedPositions = {}
    local closed = {}
    local closedSequential = {}
    local closedPositions = {}
    local cameFromId = {}
    local cameFromArea = {}
    local costsSoFar = { [startAreasId] = 0 }
    local costsToEnd = { [startAreasId] = areaDistToPos( startArea, goal ) }
    local areasById = { [startAreasId] = startArea } -- every area we touch arrives as an object, no need to look it up again

    addToSorted( startAreasId, openedSequential, opened, openedPositions, costsSoFar, costsToEnd )

    NavMeshPathCostGenerator = NavMeshPathCostGenerator or myTbl.NavMeshPathCostGenerator

    local locoData = {
        canUseLadders = myTbl.CanUseLadders,
        pathAreasAdditionalCost = myTbl.pathAreasAdditionalCost,
        hunterIsFlanking = myTbl.hunterIsFlanking,
        flankingIsReallyAngry = myTbl.flankingIsReallyAngry,
        minPathingAreaWidth = myTbl.MinPathingAreaWidth,
        stepHeight = locoMeta.GetStepHeight( myTbl.loco ),
        jumpHeight = locoMeta.GetJumpHeight( myTbl.loco ),
        deathDropHeight = locoMeta.GetDeathDropHeight( myTbl.loco ),
        canSwim = myTbl.CanSwim,
        isFodder = fodder,

    }

    while #openedSequential > 0 do
        if myTbl.term_cancelPathGen then return goalArea, nil, false, "fail2.5" end -- another part of us says CANCEL THIS!

        -- fodder enems share unreachable areas, so check if a buddy marked this as unreachable
        if fodder and lastNewUnreachables ~= newUnreachables then
            lastNewUnreachables = newUnreachables
            if newUnreachableClass == entMeta.GetClass( me ) and not myTbl.areaIsReachable( me, goalArea ) then
                return goalArea, nil, false, "fail3"

            end
        end

        local bestId = takeLowestFrom( openedSequential, opened, openedPositions, costsSoFar, costsToEnd )

        local costSoFar = costsSoFar[bestId]
        local ourCameFromId = cameFromId[bestId]
        addTo( bestId, closedSequential, closed, closedPositions )

        coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING )

        local bestArea = areasById[bestId]
        if not IsValid( bestArea ) then -- we are in a coroutine, this can happen
            continue

        end

        --debugoverlay.Text( bestArea:GetCenter(), "A* " .. tostring( math.Round( costSoFar ) ), 1, color_white, true )

        if maxPathingIterations and currExtent > maxPathingIterations then -- all out :( guess the goal is whatever got closest
            coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )

            local bestCompromiseId = getClosestToGoal( closedSequential, costsToEnd )
            if bestCompromiseId then
                local bestCompromiseArea = areasById[bestCompromiseId]
                local areaCorridor = reconstruct_path( cameFromId, cameFromArea, bestCompromiseArea )
                if not areaCorridor then
                    return bestCompromiseArea, nil, false, "fail4"

                end
                return bestCompromiseArea, areaCorridor, false, "succeed2"

            else
                return nil, false, "fail5"

            end
        elseif bestArea == goalArea then -- got there!
            coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING_DONTWAIT )

            return goalArea, reconstruct_path( cameFromId, cameFromArea, goalArea ), true, "succeed1"

        end


        local adjacentDatas = adjacentAreasSkippingLadders( bestArea, locoData.canUseLadders )

        for _, neighborDat in ipairs( adjacentDatas ) do
            currExtent = currExtent + 1
            coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING )

            local neighbor = neighborDat.area
            if not IsValid( neighbor ) then continue end -- areapatcher!!!
            if not IsValid( bestArea ) then break end

            local neighborsId = GetID( neighbor )
            -- NavMeshPathCostGenerator
            local neighborsCost = NavMeshPathCostGenerator( me, locoData, neighbor, bestArea, neighborDat.ladder, neighborDat.dist )

            local neighborsCostSoFar = costSoFar + neighborsCost

            local wasTackled = opened[neighborsId] or closed[neighborsId]

            local cannotTraverse = neighborsCost <= -1

            if cannotTraverse and wasTackled then -- cant go this way, but there's already a way there
                continue

            elseif cannotTraverse then -- cant go this way
                addTo( neighborsId, closedSequential, closed, closedPositions ) -- mark as closed
                costsSoFar[neighborsId] = costSoFar * 1000 -- blow up the cost, so any valid retraces are very confident going back over this
                coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING )
                continue

            end

            local goodRetrace = wasTackled and ourCameFromId and ourCameFromId ~= neighborsId and neighborsCostSoFar <= costsSoFar[neighborsId]

            if wasTackled and not goodRetrace then
                coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING )
                continue

            else
                costsSoFar[neighborsId] = neighborsCostSoFar
                if not costsToEnd[neighborsId] then
                    -- the heuristic only reads the area and the goal, neither of which move,
                    -- so a requeued area already has the answer from last time
                    costsToEnd[neighborsId] = areaDistToPos( neighbor, goal )

                end
                areasById[neighborsId] = neighbor

                removeFrom( neighborsId, closedSequential, closed, closedPositions )
                addToSorted( neighborsId, openedSequential, opened, openedPositions, costsSoFar, costsToEnd )
                cameFromId[neighborsId] = bestId
                cameFromArea[neighborsId] = bestArea
                coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.PATHING )

            end
        end
    end
    return goalArea, nil, false, "fail6"

end

local Astar = terminator_Extras.Astar

-- unreachable area sharing!
hook.Add( "term_updateunreachableareas", "term_nouseless_fodderpaths", function( classUpdated )
    newUnreachables = newUnreachables + 1
    newUnreachableClass = classUpdated

end )

local allowedDeviations
local areaCorridorNexts -- used to force the path:Compute to use a specific path

-- generatorHack is a hack to allow us to use default path structure with a custom generator
-- used to force the path:Compute to use a specific path, since we can't build a Path() manually
local function generatorHack( area, fromArea, _ladder, _elevator, _length ) -- unthinkable HACK!!!
    local fromNext

    if fromArea then
        fromNext = areaCorridorNexts[fromArea]
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
        local areaMask = areaCorridorNexts[area]
        if not areaMask then
            return 10000000000000 -- not in corridor, try this last

        end
    end

    if fromNext == true then -- special area
        return 1

    elseif fromNext == area then -- the good ending, keep going
        return 1

    end

    return -1 -- not the correct path

end

local function AstarCompute( path, me, myTbl, goal, goalArea )
    local startArea = myTbl.GetCurrentNavArea( me )
    --debugoverlay.Line( startArea:GetCenter(), goal, 5, Color( 0, 255, 0 ), true )

    local start = SysTime()
    local newGoalArea, areaCorridor, wasGood, _debugMsg = Astar( me, myTbl, startArea, goal, goalArea )
    local timeTaken = SysTime() - start

    --print( _debugMsg )

    if not areaCorridor then
        path:Invalidate() -- a* failed to find a good path, or even a compromise path, HARD failure
        return nil, false, "noCorridor"

    end

    coroutine_yield()

    if not IsValid( startArea ) or not IsValid( newGoalArea ) then -- outdated!
        path:Invalidate() -- outdated, happens when the navmesh is being edited
        return nil, false, "invalidEnds"

    end

    goal = navMeta.GetClosestPointOnArea( newGoalArea, goal ) -- make sure the goal lines up

    coroutine_yield()

    local corridorIds = {}
    for _, area in ipairs( areaCorridor ) do
        --debugoverlay.Cross( area:GetCenter(), 10, 5, color_white, true )
        if not IsValid( area ) then continue end
        corridorIds[#corridorIds + 1] = area

    end

    --local last = areaCorridor[1]:GetCenter() --debugging

    -- terrible hack, we make a corridor with astar, then run a path:Compute inside that corridor
    -- all this since building a Path() manually seemed to not be possible
    -- the things that must be done for coroutined pathfinding...

    areaCorridorNexts = { [newGoalArea] = true, [startArea] = corridorIds[1] }
    for i, curr in ipairs( corridorIds ) do
        local nextOne = corridorIds[i + 1]
        if nextOne then
            areaCorridorNexts[curr] = nextOne -- force the compute to take the correct path

        else
            areaCorridorNexts[curr] = true

        end

        --[[
        coroutine_yield( terminator_Extras.BOT_COROUTINE_RESULTS.WAIT )
        local thisCenter = navMeta.GetCenter( curr )
        --debugoverlay.Line( last, thisCenter, 5, color_white, true )
        last = thisCenter
        --]]

    end

    allowedDeviations = #corridorIds + 50

    local computed = path:Compute( me, goal, generatorHack ) -- "fake" path compute with overriden score func, forces it to stay on the rails defined by coroutined a*
    areaCorridorNexts = nil
    allowedDeviations = nil

    coroutine_yield()

    if not path:IsValid() then -- :(
        return nil, false, "noCompute"

    end

    if timeTaken > 2 or #areaCorridor > 500 then
        coroutine_yield()
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

    coroutine_yield()

    local myTbl = entMeta.GetTable( self )

    -- save path start info for the HunterIsStuck
    myTbl.m_LastPathStartTime = CurTime()
    myTbl.m_LastPathStartPos = self:GetPos()
    myTbl.m_PathPos = pos

    myTbl.InvalidatePath( self, "i started a new path" )

    myTbl.term_cancelPathGen = nil

    myTbl.pathAreasAdditionalCost = myTbl.pathAreasAdditionalCost or {}

    if not myTbl.IsFodder then -- fodder npcs usually dont live long enough for this to matter.
        -- areas that we took damage in
        myTbl.AddAreasToAvoid( self, myTbl.hazardousAreas, FLANK_DEFAULT_COST / 2 )

    end

    local adjusted = myTbl.AdditionalAvoidAreas( self, myTbl.pathAreasAdditionalCost )
    if istable( adjusted ) then
        myTbl.pathAreasAdditionalCost = adjusted

    end

    coroutine_yield()

    -- avoid areas that we took damage in before
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

    coroutine_yield()

    myTbl.term_PathShouldBeValid = true

    local path = Path( "Follow" )
    myTbl.m_Path = path

    coroutine_yield()

    path:SetMinLookAheadDistance( myTbl.PathMinLookAheadDistance )

    coroutine_yield()

    path:SetGoalTolerance( myTbl.PathGoalTolerance )

    coroutine_yield()

    local computed, wasGood, _status = AstarCompute( path, self, myTbl, pos, endArea )
    --print( self:GetCreationID(), "AstarCompute", computed, wasGood, _status )

    coroutine_yield()

    myTbl.pathAreasAdditionalCost = nil

    if not path:IsValid() then
        self:InvalidatePath( "i failed to build a path" )

        -- this stuck edge case usually happens when the bot ends up in some orphan part of the navmesh with no way out, eg bottom of an elevator shaft
        local old = myTbl.term_ConsecutivePathFailures or 0
        if old > 15 then
            myTbl.overrideVeryStuck = true -- alert the reallystuck_handler

        elseif old >= 5 then -- start checkin if we're at the bottom of an elevator shaft
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

    ProtectedCall( function()
        myTbl.RunTask( self, "OnFinishBuildingPath", path, pos, wasGood )

    end )

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
        terminator_Extras.tableAdd( damagingAreas, navmesh.Find( volatile:GetPos(), 50, jumpHeight, jumpHeight ) )

    end
    return damagingAreas

end


function ENT:IsBusyBuildingPath( myTbl )
    if myTbl.term_PathShouldBeValid and not IsValid( myTbl.m_Path ) then
        local startedBuilding = myTbl.m_LastPathStartTime or 0
        local sinceStartedBuilding = math.abs( CurTime() - startedBuilding )
        return true, sinceStartedBuilding

    end
    return false

end



-- did we already try, and fail, to path there?
function ENT:areaIsReachable( area )
    if not area then return end
    if not IsValid( area ) then return end
    if self.unreachableAreas[area:GetID()] then return end
    return true

end

-- don't build paths to these areas!
function ENT:rememberAsUnreachable( area, areasId )
    if not IsValid( area ) then return end
    areasId = areasId or area:GetID()
    self.unreachableAreas[areasId] = true
    if self.IsFodder then
        hook.Run( "term_updateunreachableareas", self:GetClass(), area )

    end

    --debugoverlay.Cross( area:GetCenter(), 20, 20, Color( 255, 0, 0 ), true )

    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        self:rememberAsReachable( area, areasId )

    end )
    return true
end

-- undo the above
function ENT:rememberAsReachable( area, areasId )
    if not IsValid( area ) then return end
    areasId = areasId or area:GetID()

    self.unreachableAreas[areasId] = nil
    return true

end



function ENT:ResetUnstuckInfo()
    self.StuckPos5 = vec_zero
    self.StuckPos4 = vec_zero
    self.StuckPos3 = vec_zero
    self.StuckPos2 = vec_zero

    self.StuckEnt3 = nil
    self.StuckEnt2 = nil
    self.StuckEnt1 = nil

    --print( "reset" )

end

function ENT:TryGeneratingAreas()
    local oldArea = self.term_OldAreaWeTriedGeneratingAt
    if oldArea then
        local currArea = self:GetTrueCurrentNavArea()
        if oldArea == currArea then return end

        self.term_OldAreaWeTriedGeneratingAt = currArea

    end

    if self:IsUnderDisplacement() then return end -- dont generate areas down here!

    terminator_Extras.dynamicallyPatchPos( self:GetPos() )

end

-- MoveAlongPath found this segment to be impossible to cross 
function ENT:OnHardBlocked()
    --print( "hardblocked" )
    self:Anger( 1 )
    -- check FAST
    self.nextUnstuckCheck = CurTime()
    self.nextPosUpdate = CurTime()
    self.blockUnstuckRetrace = CurTime() + 1

    self:TryGeneratingAreas()

end

local function DistToSqr2D( pos1, pos2 )
    if not pos1 or not pos2 then return math.huge end
    local product = pos1 - pos2
    return product:Length2DSqr()
end

-- unstuck that flags a connection as bad, then the bot will bash anything nearby, then it will back up.
-- there are 2 more unstucks.
-- one that first makes the bot walk somewhere random, then if that fails and the bot is REALLY stuck, teleports/removes it ( reallystuck_handler task )
-- the base one ( in motionoverrides ) that teleports it to a clear spot next to it, if it's intersecting anything
local function HunterIsStuck( self, myTbl )
    local nextUnstuck = myTbl.nextUnstuckCheck or 0
    if nextUnstuck > CurTime() then return end

    if IsValid( myTbl.terminatorStucker ) then return true end

    if myTbl.overrideMiniStuck then myTbl.overrideMiniStuck = nil return true end

    if not myTbl.nextUnstuckCheck then
        myTbl.nextUnstuckCheck = CurTime() + 0.1
        myTbl.ResetUnstuckInfo( self )

    end
    local add = 0.2
    if myTbl.term_ExpensivePath then -- i really like this path :(
        add = add * 10

    end
    myTbl.nextUnstuckCheck = CurTime() + add

    local HasAcceleration = myTbl.loco:GetAcceleration()
    if HasAcceleration <= 0 then return end -- we aren't trying to move rn

    local myPos = self:GetPos()
    local startPos = myTbl.m_LastPathStartPos
    local goalPos = myTbl.m_PathPos
    local notMoving = myTbl.StuckPos3 and myTbl.StuckPos5
    -- laddering? check 3d dist, not 2d dist!
    if notMoving and myTbl.terminator_HandlingLadder then
        notMoving = myPos:DistToSqr( myTbl.StuckPos3 ) < 20^2 and myPos:DistToSqr( myTbl.StuckPos5 ) < 20^2 

    elseif notMoving then
        notMoving = DistToSqr2D( myPos, myTbl.StuckPos5 ) < 20^2 and DistToSqr2D( myPos, myTbl.StuckPos3 ) < 20^2

    end

    --[[if self.StuckPos3 and self.StuckPos5 then
        --debugoverlay.Sphere( self.StuckPos3, 20, 2, color_white, true )
        --debugoverlay.Sphere( self.StuckPos5, 20, 2, color_white, true )

    end--]]

    local blocker = myTbl.LastShootBlocker
    if not IsValid( blocker ) then
        blocker = myTbl.GetCachedDisrespector( self, myTbl )

    end
    if IsValid( blocker ) and ( blocker:IsNPC() or blocker:IsPlayer() ) then
        blocker = nil

    end

    local farFromStart = DistToSqr2D( myPos, startPos ) > 15^2
    local farFromStartAndNew = farFromStart or ( myTbl.m_LastPathStartTime and ( myTbl.m_LastPathStartTime + 1 < CurTime() ) )
    local farFromEnd = DistToSqr2D( myPos, goalPos ) > 15^2
    local isPath = myTbl.PathIsValid( self )

    local notMovingAndSameBlocker = myTbl.StuckEnt1 and ( myTbl.StuckEnt1 == myTbl.StuckEnt2 ) and ( myTbl.StuckEnt1 == myTbl.StuckEnt3 ) and notMoving

    local nextPosUpdate = myTbl.nextPosUpdate or 0

    if nextPosUpdate < CurTime() and isPath then
        if myTbl.canDoRun( self ) and not myTbl.IsJumping( self, myTbl ) then
            myTbl.nextPosUpdate = CurTime() + 0.25

        else
            myTbl.nextPosUpdate = CurTime() + 0.55

        end
        myTbl.StuckPos5 = myTbl.StuckPos4
        myTbl.StuckPos4 = myTbl.StuckPos3
        myTbl.StuckPos3 = myTbl.StuckPos2
        myTbl.StuckPos2 = myTbl.StuckPos1
        myTbl.StuckPos1 = myPos

        myTbl.StuckEnt3 = myTbl.StuckEnt2
        myTbl.StuckEnt2 = myTbl.StuckEnt1
        myTbl.StuckEnt1 = blocker

    end

    --print( ( notMoving or notMovingAndSameBlocker ), farFromStartAndNew, farFromEnd, isPath )
    local stuck = ( notMoving or notMovingAndSameBlocker ) and farFromStartAndNew and farFromEnd and isPath
    if stuck then -- reset so chains of stuck events happen less
        myTbl.ResetUnstuckInfo( self )

    end

    return stuck

end

local vec_up = Vector( 0, 0, 1 )

function ENT:IsUnderDisplacement()
    local myPos = self:GetShootPos()
    local nearestArea = terminator_Extras.getNearestNav( myPos )
    local checkDir
    if IsValid( nearestArea ) then -- handle being outside caves, where there won't be a displacement upwards, but will be a bit sideways
        checkDir = terminator_Extras.dirToPos( myPos, nearestArea:GetCenter() )
    else
        checkDir = vec_up
    end
    return terminator_Extras.posIsUnderDisplacement( myPos, checkDir )

end

--do this so we can override the nextbot's current path
function ENT:ControlPath2( AimMode )
    local myTbl = self:GetTable()
    local result = nil

    if myTbl.blockControlPath and myTbl.blockControlPath > CurTime() then return end

    local validPath = myTbl.PathIsValid( self )
    local badPathAndStuck = myTbl.isUnstucking and not validPath
    local bashableWithinReasonableRange = myTbl.GetCachedBashableWithinReasonableRange( self )

    local blockUnstuckRetrace = myTbl.blockUnstuckRetrace or 0 -- allow this to be blocked
    local doUnstuckPath = blockUnstuckRetrace < CurTime()
    myTbl.blockUnstuckRetrace = nil

    local posBasedStuck = HunterIsStuck( self, myTbl )

    if badPathAndStuck or posBasedStuck then -- new unstuck
        local myPos = self:GetPos()
        myTbl.startUnstuckDestination = myTbl.m_PathPos -- save where we were going
        myTbl.startUnstuckPos = myPos
        myTbl.lastUnstuckStart = CurTime()

        if validPath and not terminator_Extras.IsLivePatching then
            self:TryGeneratingAreas()

        end

        coroutine_yield()

        local myNav = myTbl.GetTrueCurrentNavArea( self ) or self:GetCurrentNavArea()
        if not IsValid( myNav ) then return end --- AAAAH

        local scoreData = {}

        scoreData.canDoUnderWater = self:isUnderWater()
        scoreData.self = self
        scoreData.dirToEnd = self:GetForward()
        scoreData.bearingPos = myTbl.startUnstuckPos

        coroutine_yield()

        if validPath then -- we were pathing, time to flag this connection
            local path = self:GetPath()
            local _, aheadSegment = myTbl.GetNextPathArea( self, myNav ) -- top of the jump
            local currSegment = path:GetCurrentGoal() -- maybe bottom of the jump, paths are stupid
            local dirPathGoes
            local areasInDir

            if not aheadSegment then goto skipTheShitConnectionFlag end

            scoreData.dirToEnd = terminator_Extras.dirToPos( myPos, path:GetEnd() )
            if not aheadSegment or not currSegment then goto skipTheShitConnectionFlag end
            if not IsValid( aheadSegment.area ) then goto skipTheShitConnectionFlag end

            dirPathGoes = myNav:ComputeDirection( aheadSegment.pos )
            areasInDir = myNav:GetAdjacentAreasAtSide( dirPathGoes )

            for _, area in ipairs( areasInDir ) do
                --debugoverlay.Line( myNav:GetCenter(), area:GetCenter(), 5, Color( 255, 255, 0 ), true )
                myTbl.flagConnectionAsShit( self, myNav, area )

            end
            myTbl.flagConnectionAsShit( self, currSegment.area, aheadSegment.area )

            --debugoverlay.Line( currSegment.area:GetCenter(), aheadSegment.area:GetCenter(), 5, Color( 255, 255, 0 ), true )

            ::skipTheShitConnectionFlag::

            coroutine_yield()

            myTbl.InvalidatePath( self, "connection was flagged, killing my path for a new one!" )

        end

        if doUnstuckPath then -- get OUTTA here
            for _ = 1, 4 do
                coroutine_yield()
                local randOffset = math.random( -40, 40 )

                -- find an area that is at least in the opposite direction of our current path
                local scoreFunction = function( scoreData, area1, area2 )
                    local dirToEnd = scoreData.dirToEnd:Angle()
                    local bearing = terminator_Extras.BearingToPos( scoreData.bearingPos, dirToEnd, area2:GetCenter(), dirToEnd )
                    bearing = math.abs( bearing )
                    bearing = bearing + randOffset
                    local dropToArea = math.abs( area1:ComputeAdjacentConnectionHeightChange( area2 ) )
                    local score = 5
                    if area2:HasAttributes( NAV_MESH_TRANSIENT ) then
                        score = 0.1
                    elseif bearing < 45 then
                        score = score * 15
                    elseif bearing < 135 then
                        score = score * 5
                    elseif bearing > 135 then
                        score = 0.1
                    else
                        local dist = scoreData.bearingPos:Distance( area2:GetCenter() )
                        local removed = dist * 0.01
                        score = math.Clamp( 1 - removed, 0, 1 )
                    end
                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = score * 0.001
                    end
                    if dropToArea > self.loco:GetStepHeight() then
                        score = score * 0.01
                    end

                    --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( bearing ) ), 4 )

                    return score

                end

                coroutine_yield()

                local _, escapeArea = self:findValidNavResult( scoreData, myPos, 1000, scoreFunction )
                if not IsValid( escapeArea ) then continue end
                --debugoverlay.Cross( escapeArea:GetCenter(), 50, 100, Color( 255, 255, 0 ), true )
                self:SetupPathShell( escapeArea:GetRandomPoint(), true )

                coroutine_yield()

                if self:PathIsValid() and IsValid( myNav ) then
                    self.initArea = myNav
                    self.initAreaId = self.initArea:GetID()
                    break

                end
            end
            if not self:PathIsValid() then return false end
            self.isUnstucking = true

        end

        coroutine_yield()

        myTbl.tryToHitUnstuck = isstring( myTbl.TERM_FISTS )
        myTbl.unstuckingTimeout = CurTime() + 10
        myTbl.ReallyAnger( self, 10 )

    end

    validPath = myTbl.PathIsValid( self )

    if myTbl.tryToHitUnstuck then
        local done = nil
        local toBeat = myTbl.entToBeatUp
        local lastShootBlocker = myTbl.LastShootBlocker

        local disrespector = lastShootBlocker or bashableWithinReasonableRange[1]
        if not disrespector then
            disrespector = myTbl.GetCachedDisrespector( self, myTbl )

        end

        if myTbl.hitTimeout then -- randomly attack stuff around the spot where we got stuck
            if not toBeat or not IsValid( toBeat ) then -- find something to attack
                -- something new to break
                local somethingNewToBeatup = bashableWithinReasonableRange[1]
                local newWithinBashRange = IsValid( somethingNewToBeatup ) and myTbl.lastBeatUpEnt ~= somethingNewToBeatup
                local newDisrespector = IsValid( disrespector ) and myTbl.lastBeatUpEnt ~= disrespector
                if newWithinBashRange or newDisrespector then
                    toBeat = bashableWithinReasonableRange[1] or disrespector
                    myTbl.entToBeatUp = toBeat
                    myTbl.hitTimeout = CurTime() + 3

                else
                    done = true

                end
            elseif toBeat and IsValid( toBeat ) then -- attack the thing!
                local valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose, visible = myTbl.beatUpEnt( self, myTbl, toBeat, true )
                local isNailed = istable( toBeat.huntersglee_breakablenails )
                local isInDanger = myTbl.getLostHealth( self ) >= 20
                local dangerAndNotNailed = isInDanger and not isNailed
                -- door was bashed or we are bored, or scared
                if myTbl.hitTimeout < CurTime() or not toBeat:IsSolid() or dangerAndNotNailed then
                    done = true
                    myTbl.lastBeatUpEnt = toBeat

                end
                if not closeAndCanHit or not visible then
                    myTbl.entToBeatUp = nil
                    myTbl.lastBeatUpEnt = toBeat

                end
                -- BEAT UP THE NAILED THING!
                if isNailed and visible and nearAndCanHit and closeAndCanHit and valid and attacked then
                    myTbl.GetTheBestWeapon( self )
                    myTbl.hitTimeout = CurTime() + 3

                -- shoot the nailed thing
                elseif isNailed and not isClose and visible and myTbl.IsRangedWeapon( self ) then
                    myTbl.shootAt( self, myTbl.getBestPos( self, toBeat ) )
                    myTbl.lastShootingType = "controlPath2_toBeat"

                end
            end
        -- keep attacking, we're doing something!
        elseif ( IsValid( lastShootBlocker ) and lastShootBlocker ~= myTbl.lastBeatUpEnt ) or ( IsValid( disrespector ) and disrespector ~= myTbl.lastBeatUpEnt ) then
            myTbl.hitTimeout = CurTime() + 3

        else
            done = true

        end
        if done or myTbl.hitTimeout < CurTime() then
            myTbl.entToBeatUp = nil
            myTbl.hitTimeout = nil
            myTbl.tryToHitUnstuck = nil

        end
    elseif myTbl.isUnstucking then
        if not validPath then
            myTbl.isUnstucking = false
            return false

        end
        result = myTbl.ControlPath( self, AimMode )
        local DistToStart = self:GetPos():Distance( myTbl.startUnstuckPos )
        local FarEnough = DistToStart > 200
        local myNavArea = myTbl.GetTrueCurrentNavArea( self ) or self:GetCurrentNavArea()

        if not IsValid( myNavArea ) then return end
        local NotStart = myTbl.initAreaId ~= myNavArea:GetID()

        local Escaped = nil

        if FarEnough and NotStart then
            Escaped = true

        elseif result then
            Escaped = true

        end
        if Escaped or myTbl.unstuckingTimeout < CurTime() then
            myTbl.isUnstucking = nil
            if myTbl.startUnstuckDestination then
                myTbl.SetupPathShell( self, myTbl.startUnstuckDestination )

            end
        end
    else
        if not validPath then return false end
        local wep = myTbl.GetWeapon( self, myTbl )
        if wep and wep.worksWithoutSightline and IsValid( myTbl.GetEnemy( self ) ) and AimMode == true then
            AimMode = nil

        end
        result = myTbl.ControlPath( self, AimMode )

    end
    return result

end

-- override this to remove path recalculating, we already do that
function ENT:ControlPath( lookatgoal, myTbl )
    myTbl = myTbl or self:GetTable()
    if not myTbl.PathIsValid( self ) then return false end

    local pos = myTbl.GetPathPos( self )

    local range = self:GetRangeTo( pos )

    if range < myTbl.PathGoalToleranceFinal then
        myTbl.InvalidatePath( self, "i reached the end of my path!" )
        return true

    end

    -- beartrap
    if IsValid( myTbl.terminatorStucker ) then
        return false

    end

    if myTbl.MoveAlongPath( self, lookatgoal, myTbl ) then
        return true

    end
end

function ENT:nextNewPathIsGood()
    local nextNewPath = self.nextNewPath or 0
    if nextNewPath > CurTime() then return end
    if self.terminator_HandlingLadder then self:TermHandleLadder() return end
    if self.isHoppingOffLadder then
        self.isHoppingOffLadderCount = ( self.isHoppingOffLadderCount or 0 ) + 1
        if self.isHoppingOffLadderCount > 20 then
            self.isHoppingOffLadder = false
            self.isHoppingOffLadderCount = nil

        end
        return

    end

    return true
end

function ENT:CanDoNewPath( pathTarget )
    if not isvector( pathTarget ) then return false end
    local myTbl = entMeta.GetTable( self )
    if not myTbl.nextNewPathIsGood( self ) then return false end
    if myTbl.isUnstucking and myTbl.PathIsValid( self ) then return false end -- dont rebuild the path if we're handling an unstuck
    if myTbl.primaryPathIsValid( self ) and myTbl.terminator_HandlingLadder then myTbl.TermHandleLadder( self ) return false end
    local newPathDist = 1
    local mul = 1
    if myTbl.term_ExpensivePath then
        mul = 3

    end
    local pathLeng = myTbl.GetPathDistanceToGoal( self ) or 0
    local pathPos = myTbl.m_PathPos

    if pathLeng > 10000 then
        newPathDist = 4000 -- dont do pathing as often if the target is far away from me!
    elseif pathLeng > 5000 then
        newPathDist = 3000
    elseif pathLeng > 500 then
        newPathDist = 400
    elseif pathLeng > 100 then
        newPathDist = 90
    end

    newPathDist = newPathDist * mul

    local targsDistToPos = pathTarget:DistToSqr( pathPos )

    local needsNew = targsDistToPos > newPathDist^2 or myTbl.needsPathRecalculate
    myTbl.needsPathRecalculate = nil
    return needsNew

end
