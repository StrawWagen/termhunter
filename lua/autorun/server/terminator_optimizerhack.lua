
-- navmesh optimizer merging code

local navMeta = FindMetaTable( "CNavArea" )
local GetCenter = navMeta.GetCenter
local GetCorner = navMeta.GetCorner
local GetSizeX = navMeta.GetSizeX
local GetSizeY = navMeta.GetSizeY
local IsConnected = navMeta.IsConnected
local GetAttributes = navMeta.GetAttributes
local GetAdjacentAreas = navMeta.GetAdjacentAreas
local GetIncomingConnections = navMeta.GetIncomingConnections
local GetClosestPointOnArea = navMeta.GetClosestPointOnArea

local vecMeta = FindMetaTable( "Vector" )
local DistToSqr = vecMeta.DistToSqr

local IsValid = IsValid
local table = table
local bit_band = bit.band

terminator_Extras = terminator_Extras or {}
local terminator_Extras = terminator_Extras

local cornerIndexes = { 0,1,2,3 }
local fiveSqared = 5^2

local function navSurfaceArea( navArea )
    local area = GetSizeX( navArea ) * GetSizeY( navArea )
    return area

end

local function connectionData( currArea, otherArea )
    local currCenter = GetCenter( currArea )

    local nearestInitial = GetClosestPointOnArea( otherArea, currCenter )
    local nearestFinal   = GetClosestPointOnArea( currArea, nearestInitial )
    local height = -( nearestFinal.z - nearestInitial.z )

    nearestFinal.z = nearestInitial.z
    local distTo   = DistToSqr( nearestInitial, nearestFinal )

    return distTo, height

end

local function navAreaGetCloseCorners( pos, areaToCheck )

    if not IsValid( areaToCheck ) then return end
    local toReturn = nil
    local closeCorners = {}

    for _, biggestCornerIndex in ipairs( cornerIndexes ) do
        local biggestAreaCorner = GetCorner( areaToCheck, biggestCornerIndex )

        if DistToSqr( pos, biggestAreaCorner ) < fiveSqared then
            toReturn = true
            table.insert( closeCorners, biggestAreaCorner )

        end
    end

    return toReturn, closeCorners

end

local function hasAttributeFast( attributes, attribute )
    if not attributes then return false end
    if not attribute then return false end

    local has = bit_band( attributes, attribute ) > 0
    return has

end

function terminator_Extras.navAreasCanMerge( start, next )

    if not ( start and next ) then return false, 0, NULL end -- outdated

    local startA = GetAttributes( start )
    local nextA = GetAttributes( next )

    --SUPER fast
    local isStairs = hasAttributeFast( startA, NAV_MESH_STAIRS ) or hasAttributeFast( nextA, NAV_MESH_STAIRS )
    local probablyBreakingStairs
    if isStairs then
        -- DONT MESS WITH STAIRS!
        probablyBreakingStairs = true
        -- ok these are coplanar, and they're both stairs... i'll let this slide....
        if start:IsCoplanar( next ) and hasAttributeFast( startA, NAV_MESH_STAIRS ) and hasAttributeFast( nextA, NAV_MESH_STAIRS ) then
            probablyBreakingStairs = nil

        end
    end

    local noMerge = hasAttributeFast( startA, NAV_MESH_NO_MERGE ) or hasAttributeFast( nextA, NAV_MESH_NO_MERGE ) -- probably has this for a reason huh... 
    local doingAnObstacle = hasAttributeFast( startA, NAV_MESH_OBSTACLE_TOP ) and hasAttributeFast( nextA, NAV_MESH_OBSTACLE_TOP )
    local noMergeAndNotObstacle = noMerge and not doingAnObstacle

    local transient = hasAttributeFast( startA, NAV_MESH_TRANSIENT ) or hasAttributeFast( nextA, NAV_MESH_TRANSIENT )

    local startCrouch = hasAttributeFast( startA, NAV_MESH_CROUCH )
    local nextCrouch = hasAttributeFast( nextA, NAV_MESH_CROUCH )
    local leavingCrouch = startCrouch and not nextCrouch
    local enteringCrouch = nextCrouch and not startCrouch

    local probablyBreakingCrouch = leavingCrouch or enteringCrouch -- don't make a little bit of crouch area way too big

    local startBlock = hasAttributeFast( startA, NAV_MESH_NAV_BLOCKER )
    local nextBlock = hasAttributeFast( nextA, NAV_MESH_NAV_BLOCKER )
    local leavingBlock = startBlock and not nextBlock
    local enteringBlock = nextBlock and not startBlock

    local probablyBreakingSelectiveBlock = leavingBlock or enteringBlock

    if probablyBreakingStairs or noMergeAndNotObstacle or transient or probablyBreakingCrouch or probablyBreakingSelectiveBlock then return false, 0, NULL end

    -- GetLadders creates a new table, can add stuff to it
    local ladders = start:GetLadders()
    terminator_Extras.tableAdd( ladders, next:GetLadders() )

    if #ladders > 0 then return false, 0, NULL end -- dont break the ladders!

    -- fast
    local distance, height = connectionData( start, next )
    local nextToEachtoher = distance < 15^2
    local heightGood = math.abs( height ) < 20
    if not nextToEachtoher then return false, 0, NULL end
    if not heightGood then return false, 0, NULL end


    --fast
    local center1 = GetCenter( start )
    local center2 = GetCenter( next )
    local sameX = center1.x == center2.x
    local sameY = center1.y == center2.y

    local sameSomething = sameX or sameY
    if not sameSomething then return false, 0, NULL end --if we can, throw these away as early as possible

    -- fast
    local startSizeX = GetSizeX( start )
    local nextSizeX = GetSizeX( next )
    local startSizeY = GetSizeY( start )
    local nextSizeY = GetSizeY( next )

    local sameXSize = startSizeX == nextSizeX
    local sameYSize = startSizeY == nextSizeY

    local mergable = ( sameX and sameXSize ) or ( sameY and sameYSize )
    if not mergable then return false, 0, NULL end


    -- this is fast
    local maxLong = 800 -- default 700
    local tooLong = ( startSizeX + nextSizeX ) > maxLong or ( startSizeY + nextSizeY ) > maxLong

    local mySurfaceArea = navSurfaceArea( start )
    local nextAreaSurfaceArea = navSurfaceArea( next )

    local newSurfaceArea = mySurfaceArea + nextAreaSurfaceArea
    local wouldBeTooBig = newSurfaceArea > 300000 or tooLong
    if wouldBeTooBig then return false, 0, NULL end

    local coplanar = start:IsCoplanar( next )

    -- ok this merge is gonna cause artifacts!
    if not coplanar then
        local zDifference = math.abs( center1.z - center2.z )
        -- areas are far apart in height, the artifact will be big
        if zDifference > 20 then
            -- if they're both on displacements then we can let it slide
            local startIsOnDisplacement = terminator_Extras.areaIsEntirelyOverDisplacements( start )
            if not startIsOnDisplacement then return false, 0, NULL end

            local nextIsOnDisplacement = terminator_Extras.areaIsEntirelyOverDisplacements( next )
            if not nextIsOnDisplacement then return false, 0, NULL end

        end
    end

    return true, newSurfaceArea

end

local navAreasCanMerge = terminator_Extras.navAreasCanMerge

function terminator_Extras.navmeshAttemptMerge( start, next )

    local canMerge, newSurfaceArea = navAreasCanMerge( start, next )

    if canMerge ~= true then return false, 0, NULL end

    --sloooow
    local connectionsFromStart = GetAdjacentAreas( start )
    local connectionsFromNext = GetAdjacentAreas( next )

    local connectionsToStart = GetIncomingConnections( start )
    local connectionsToNext = GetIncomingConnections( next )

    local connectionsFrom       = terminator_Extras.tableCopySimple( connectionsFromStart )
    terminator_Extras.tableAdd( connectionsFrom, connectionsFromNext )

    local oneWayConnectionsTo = terminator_Extras.tableCopySimple( connectionsToStart )
    terminator_Extras.tableAdd( oneWayConnectionsTo, connectionsToNext )

    local twoWayConnections     = {}

    for key, twoWayArea in ipairs( connectionsFrom ) do
        if not IsValid( start ) then continue end
        if not IsValid( next ) then continue end
        if not IsValid( twoWayArea ) then continue end

        if ( IsConnected( start, twoWayArea ) or IsConnected( next, twoWayArea ) ) or ( IsConnected( twoWayArea, start ) or IsConnected( twoWayArea, next ) ) then
            table.insert( twoWayConnections, #twoWayConnections + 1, twoWayArea )
            connectionsFrom[ key ] = nil
        end
    end

    -- get biggest neighbor, we dont want fuck up a later merge with them if possible
    local largestSurfaceArea = 0
    local biggestArea = NULL

    for _, potentiallyBiggestArea in ipairs( twoWayConnections ) do
        local surfaceArea = navSurfaceArea( potentiallyBiggestArea )
        if surfaceArea > largestSurfaceArea then
            largestSurfaceArea = surfaceArea
            biggestArea = potentiallyBiggestArea
        end
    end

    -- make sure this doesnt break anythin
    if biggestArea ~= next then

        local sameCornerAsBiggestArea = nil
        local offendingCorners = {}
        local newOffendingCorners = {}

        for _, startCornerIndex in ipairs( cornerIndexes ) do
            local currStartCorner = GetCorner( start, startCornerIndex )

            sameCornerAsBiggestArea, newOffendingCorners = navAreaGetCloseCorners( currStartCorner, biggestArea )

            terminator_Extras.tableAdd( offendingCorners, newOffendingCorners )

        end

        -- start the cancelling checks when we could potentially merge with a way bigger neighbor
        if sameCornerAsBiggestArea then

            -- are we out of options?
            local mergingOptions = 0
            for _, mergableOption in ipairs( connectionsFromStart ) do
                if navAreasCanMerge( start, mergableOption ) and mergableOption ~= next then
                    mergingOptions = mergingOptions + 1

                end
            end

            -- allow blocking when there's more than 1 option, and we're not the smaller area
            if mergingOptions > 1 and navSurfaceArea( start ) > navSurfaceArea( next ) then
                -- cancel the merge if it will delete the corner we have in common with the biggest area
                for _, theOffendingCorner in ipairs( offendingCorners ) do
                    local startAreaEncapsulatesCorner = getShortestDistanceToNavSqr( start, theOffendingCorner )
                    local nextAreaEncapsulatesCorner = getShortestDistanceToNavSqr( next, theOffendingCorner )

                    if nextAreaEncapsulatesCorner and startAreaEncapsulatesCorner then
                        --debugoverlay.Cross( theOffendingCorner, 5, 5 )
                        --debugoverlay.Line( start:GetCenter() + Vector( 0,0,20 ), next:GetCenter(), 5, 20 )
                        return false, 0, NULL end
                end
            end
        end
    end

    -- north westy
    local NWCorner1 = GetCorner( start, 0 )
    local NWCorner2 = GetCorner( next, 0 )

    local NWCorner = NWCorner1
    if NWCorner2.y < NWCorner.y then
        NWCorner.y = NWCorner2.y
        NWCorner.z = NWCorner2.z
    end
    if NWCorner2.x < NWCorner.x then
        NWCorner.x = NWCorner2.x
        NWCorner.z = NWCorner2.z
    end

    -- find most north easty corner
    local NECorner1 = GetCorner( start, 1 )
    local NECorner2 = GetCorner( next, 1 )

    local NECorner = NECorner1
    if NECorner2.y < NECorner.y then
        NECorner.y = NECorner2.y
        NECorner.z = NECorner2.z
    end
    if NECorner2.x > NECorner.x then
        NECorner.x = NECorner2.x
        NECorner.z = NECorner2.z
    end

    -- find most south westy corner
    local SWCorner1 = GetCorner( start, 3 )
    local SWCorner2 = GetCorner( next, 3 )

    local SWCorner = SWCorner1
    if SWCorner2.y > SWCorner.y then
        SWCorner.y = SWCorner2.y
        SWCorner.z = SWCorner2.z
    end
    if SWCorner2.x < SWCorner.x then
        SWCorner.x = SWCorner2.x
        SWCorner.z = SWCorner2.z
    end

    -- find most south easty corner
    local SECorner1 = GetCorner( start, 2 )
    local SECorner2 = GetCorner( next, 2 )

    local SECorner = SECorner1
    if SECorner2.y > SECorner.y then
        SECorner.y = SECorner2.y
        SECorner.z = SECorner2.z
    end
    if SECorner2.x > SECorner.x then
        SECorner.x = SECorner2.x
        SECorner.z = SECorner2.z
    end

    local startA = GetAttributes( start )
    local nextA = GetAttributes( next )

    local obstacle = hasAttributeFast( startA, NAV_MESH_OBSTACLE_TOP ) or hasAttributeFast( nextA, NAV_MESH_OBSTACLE_TOP )
    local crouch = hasAttributeFast( startA, NAV_MESH_CROUCH ) or hasAttributeFast( nextA, NAV_MESH_CROUCH )
    local stairs = hasAttributeFast( startA, NAV_MESH_STAIRS ) or hasAttributeFast( nextA, NAV_MESH_STAIRS )

    local newArea = navmesh.CreateNavArea( NECorner, SWCorner )
    if not IsValid( newArea ) then return false, 0, NULL end -- this failed, dont delete the old areas

    start:Remove()
    next:Remove()

    if obstacle then
        newArea:SetAttributes( NAV_MESH_OBSTACLE_TOP )
    end

    if crouch then
        newArea:SetAttributes( NAV_MESH_CROUCH )
    end

    if stairs then
        newArea:SetAttributes( NAV_MESH_STAIRS )
    end

    for _, fromArea in pairs( connectionsFrom ) do
        if not IsValid( fromArea ) then continue end
        newArea:ConnectTo( fromArea )
    end
    for _, toArea in pairs( oneWayConnectionsTo ) do
        if not IsValid( toArea ) then continue end
        toArea:ConnectTo( newArea )
    end
    for _, twoWayArea in pairs( twoWayConnections ) do
        if not IsValid( twoWayArea ) then continue end
        newArea:ConnectTo( twoWayArea )
        twoWayArea:ConnectTo( newArea )
    end

    newArea:SetCorner( 0, NWCorner )
    newArea:SetCorner( 2, SECorner )

    --debugoverlay.Line( center1, center2, 3, Color( 255, 255, 255 ), true )

    return true, newSurfaceArea, newArea
end