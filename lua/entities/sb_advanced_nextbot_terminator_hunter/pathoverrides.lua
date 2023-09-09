
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
    local goalPathPoint = nil
    local isNextArea = nil

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
function ENT:GetPathHalfwayPoint()
    local myPos = self:GetPos()
    if not self:PathIsValid() then return myPos end

    local pathSegs = self:getCachedPathSegments()
    if not pathSegs then return myPos end

    local middlePathSegIndex = math.Round( #pathSegs / 2 )
    local middlePathSeg = pathSegs[ middlePathSegIndex ]
    return middlePathSeg.pos, middlePathSeg

end

-- used in tasks to not call a fail if bot is unstucking
function ENT:primaryPathIsValid()
    if self.isUnstucking then return true end -- dont start new paths
    -- behave normally
    return self:PathIsValid()

end

-- flanking!
local flankingDest
local hunterIsFlanking
local flankingZRewardBegin
local flankingAvoidAreas

function ENT:AddAreasToFlank( areas, mul )
    for _, avoid in ipairs( areas ) do
        if avoid ~= flankingDest then
            flankingAvoidAreas[ avoid:GetID() ] = mul
            --debugoverlay.Cross( avoid:GetCenter(), 10, 10, color_white, true )

        end
    end
end

function ENT:SetupFlankingPath( destination, areaToFlankAround, flankAvoidRadius )
    if not isvector( destination ) then return end
    -- lagspike if we try to flank around area that contains the destination
    flankingDest = terminator_Extras.getNearestPosOnNav( destination ).area
    if not flankingDest then return false end
    flankingZRewardBegin = destination.z + -96
    flankingAvoidAreas = flankingAvoidAreas or {}
    hunterIsFlanking = true

    if flankAvoidRadius then
        self:flankAroundArea( areaToFlankAround, flankAvoidRadius )

    else
        self:flankAroundCorridorBetween( self:GetPos(), areaToFlankAround:GetCenter() )

    end
    if IsValid( self:GetEnemy() ) then
        self:FlankAroundEasyEntraceToThing( areaToFlankAround:GetCenter(), self:GetEnemy() )

    end
    self:SetupPath2( destination )
    self:endFlankPath()

end

function ENT:flankAroundArea( bubbleArea, bubbleRadius )
    bubbleRadius = math.Clamp( bubbleRadius, 0, 3000 )
    local bubbleCenter = bubbleArea:GetCenter()

    local areas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToFlank( areas, 25 )

end

function ENT:flankAroundCorridorBetween( bubbleStart, bubbleDestination )
    local offsetDirection = terminator_Extras.dirToPos( bubbleStart, bubbleDestination )
    local offsetDistance = bubbleStart:Distance( bubbleDestination )
    local bubbleRadius = math.Clamp( offsetDistance * 0.45, 0, 4000 )
    local offset = offsetDirection * ( offsetDistance * 0.6 )
    local bubbleCenter = bubbleStart + offset

    local firstBubbleAreas = navmesh.Find( bubbleCenter, bubbleRadius, self.JumpHeight, self.JumpHeight )
    self:AddAreasToFlank( firstBubbleAreas, 25 )

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

    self:AddAreasToFlank( secondBubbleAreasClipped, 50 )
end

function ENT:endFlankPath()
    self.flankBubbleCenter = nil
    self.flankBubbleSizeSqr = nil
    flankingZRewardBegin = nil
    hunterIsFlanking = nil
    flankingAvoidAreas = nil

end

--TODO: dynamically check if a NAV_TRANSIENT areas are supported by terrain, then cache the results 
--local function isCachedTraversable( area )

local _IsValid = IsValid

function ENT:NavMeshPathCostGenerator( path, area, from, ladder, _, len )
    if not _IsValid( from ) then return 0 end

    local dist = 0
    local addedCost = 0
    local costSoFar = from:GetCostSoFar() or 0

    if _IsValid( ladder ) then
        local cost = ladder:GetLength() * 4
        cost = cost + 400
        return cost
    elseif len > 0 then
        dist = len
    else
        dist = from:GetCenter():Distance( area:GetCenter() )
    end


    if hunterIsFlanking and flankingAvoidAreas and flankingAvoidAreas[ area:GetID() ] then
        dist = dist * flankingAvoidAreas[ area:GetID() ]
        --debugoverlay.Cross( area:GetCenter(), 10, 10, color_white, true )

    end

    if area:HasAttributes( NAV_MESH_CROUCH ) then
        if hunterIsFlanking then
            -- vents?
            dist = dist * 0.5
        else
            -- its cool when they crouch so dont punish it much
            dist = dist * 1.1
        end
    end

    if area:HasAttributes( NAV_MESH_OBSTACLE_TOP ) then
        dist = dist * 2 -- these usually look goofy
    end

    local sizeX = area:GetSizeX()
    local sizeY = area:GetSizeY()

    if sizeX < 26 or sizeY < 26 then
        -- generator often makes small 1x1 areas with this attribute, on very complex terrain
        if area:HasAttributes( NAV_MESH_NO_MERGE ) then
            dist = dist * 8
        else
            dist = dist * 1.25
        end
    end
    if sizeX > 151 and sizeY > 151 and not hunterIsFlanking then --- mmm very simple terrain
        dist = dist * 0.6
    elseif sizeX > 76 and sizeY > 76 then -- this makes us prefer paths thru simple terrain
        dist = dist * 0.8
    end

    if area:HasAttributes( NAV_MESH_JUMP ) then
        dist = dist * 1.5
    end

    if area:HasAttributes( NAV_MESH_AVOID ) then
        dist = dist * 20
    end

    if from then
        local nav2Id = area:GetID()
        if not istable( navExtraDataHunter.nav1Id ) then goto skipShitConnectionDetection end
        if not navExtraDataHunter.nav1Id.shitConnnections then goto skipShitConnectionDetection end
        if navExtraDataHunter.nav1Id.shitConnnections[nav2Id] then
            addedCost = 1500
            dist = dist * 10
            if not navExtraDataHunter.nav1Id.superShitConnnections then goto skipSuperShitConnectionDetection end
            if navExtraDataHunter.nav1Id.superShitConnnections[nav2Id] then
                addedCost = 180000
            end
            ::skipSuperShitConnectionDetection::
        end
        ::skipShitConnectionDetection::
    end

    if area:HasAttributes( NAV_MESH_TRANSIENT ) then
        dist = dist * 2
    end

    if area:IsUnderwater() then
        dist = dist * 2
    end

    local cost = dist + addedCost + costSoFar

    local deltaZ = from:ComputeAdjacentConnectionHeightChange( area )
    local stepHeight = self.loco:GetStepHeight()
    local jumpHeight = self.loco:GetMaxJumpHeight()
    if deltaZ >= stepHeight then
        if deltaZ >= jumpHeight then return -1 end
        if deltaZ > stepHeight * 4 then
            if hunterIsFlanking then
                cost = cost * 6

            else
                cost = cost * 8

            end
        elseif deltaZ > stepHeight * 2 then
            if hunterIsFlanking then
                cost = cost * 4

            else
                cost = cost * 6

            end
        else
            if hunterIsFlanking then
                cost = cost * 1.5

            else
                cost = cost * 2

            end
        end
    elseif deltaZ <= -self.loco:GetDeathDropHeight() then
        cost = cost * 50000

    elseif deltaZ <= -jumpHeight then
        cost = cost * 4

    elseif deltaZ <= -stepHeight * 3 then
        if hunterIsFlanking then
            cost = cost * 2

        else
            cost = cost * 3

        end
    elseif deltaZ <= -stepHeight then
        if hunterIsFlanking then
            cost = cost * 1.2

        else
            cost = cost * 2

        end
    end

    return cost
end

--[[------------------------------------
    Name: NEXTBOT:SetupPath
    Desc: Creates new PathFollower object and computes path to goal. Invalidates old path.
    Arg1: Vector | pos | Goal position.
    Arg2: (optional) table | options | Table with options:
        `mindist` - SetMinLookAheadDistance
        `tolerance` - SetGoalTolerance
        `generator` - Custom cost generator
        `recompute` - recompute path every x seconds
    Ret1: any | PathFollower object if created succesfully, otherwise false
--]]------------------------------------
function ENT:SetupPath( pos, options )
    self:GetPath():Invalidate()

    options = options or {}
    options.mindist = options.mindist or self.PathMinLookAheadDistance
    options.tolerance = options.tolerance or self.PathGoalTolerance
    options.recompute = options.recompute or self.PathRecompute

    if not options.generator and not self:UsingNodeGraph() then
        options.generator = function( area, from, ladder, elevator, len )
            return self:NavMeshPathCostGenerator( self:GetPath(), area, from, ladder, elevator, len )
        end
    end

    local path = self:UsingNodeGraph() and self:NodeGraphPath() or Path( "Follow" )
    self.m_Path = path

    path:SetMinLookAheadDistance( options.mindist )
    path:SetGoalTolerance( options.tolerance )

    self.m_PathOptions = options
    self.m_PathPos = pos

    if not self:ComputePath( pos, options.generator ) then
        path:Invalidate()
        return false

    end

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