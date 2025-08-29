
local navMeta = FindMetaTable( "CNavArea" )
local GetCorner = navMeta.GetCorner

local table = table
local navmesh = navmesh
local bit = bit

local math = math
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_Round = math.Round

local util_IsInWorld = util.IsInWorld
local IsValid = IsValid
local Vector = Vector


local dedicatedRate = 0.002
local otherwiseRate = 0.005

local debuggingVar = CreateConVar( "terminator_areapatching_debugging", 0, FCVAR_NONE, "Enable areapatcher debug-prints/visualizers." )
local doAreaPatchingVar = CreateConVar( "terminator_areapatching_enable", 1, FCVAR_ARCHIVE, "Creates new areas if players, bots, end up off the navmesh. Only runs with at least 1 bot spawned." )
local areaPatchingRateVar = CreateConVar( "terminator_areapatching_rate", -1, FCVAR_ARCHIVE, "Max fraction of a second the area patcher can run at, -1 for default \"" .. otherwiseRate .. "\"", -1, 1 )

local debugging = debuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_areapatching_debugging", function( _, _, new )
    debugging = tobool( new )

end, "updatepatching" )

local doAreaPatching = doAreaPatchingVar:GetBool()
cvars.AddChangeCallback( "terminator_areapatching_enable", function( _, _, new )
    doAreaPatching = tobool( new )

end, "updatepatching" )

local areaPatchingRate = 0
local function doPatchingRate( rate )
    rate = rate or areaPatchingRateVar:GetFloat()
    if isstring( rate ) then
        rate = tonumber( rate )

    end
    if rate <= 0 then
        if game.IsDedicated() then
            areaPatchingRate = dedicatedRate

        else
            areaPatchingRate = otherwiseRate

        end
    else
        areaPatchingRate = rate

    end
end

doPatchingRate()

cvars.AddChangeCallback( "terminator_areapatching_rate", function( _, _, new )
    doPatchingRate( new )

end, "updatepatching" )

local function debugPrint( ... )
    if not debugging then return end
    permaPrint( ... )

end

local function filterFunc( hit )
    if hit:IsWorld() then return true end
    return false

end

local red = Color( 255, 0, 0 )

local posIsUnderDisplacement

local gridSize

local halfGrid
local gridSmaller
local vecGridsizeZ
local vecHalfGridsizeZ

local trMins
local trMaxs
local collideTrMins
local collideTrMaxs

local areaCenteringOffset
local oppCornerOffset

local headroomCrouch
local headroomStand
local headroomStandRaw
local headroomCrouchRaw

local upCrouch

local finalAreaCheckMins
local finalAreaCheckMaxs

local gridOffset
local oldGenCenter

local directionOffsets
local initialResult
local trStrucIntitial

local tempVectors

local function updateGridSize( newSize )
    gridSize = newSize

    halfGrid = gridSize * 0.5
    gridSmaller = gridSize * 0.25
    vecGridsizeZ = Vector( 0, 0, gridSize )
    vecHalfGridsizeZ = Vector( 0, 0, halfGrid / 2 )

    trMins = Vector( -gridSmaller, -gridSmaller, -1 )
    trMaxs = Vector( gridSmaller, gridSmaller, 1 )
    local collideXY = math_max( 15, gridSize * 0.65 )
    collideTrMins = Vector( -collideXY, -collideXY, -1 )
    collideTrMaxs = Vector( collideXY, collideXY, collideXY )

    areaCenteringOffset = Vector( -halfGrid, -halfGrid, 2 )
    oppCornerOffset = Vector( halfGrid, halfGrid, 2 )

    headroomStandRaw = 45
    headroomCrouchRaw = 20
    headroomStand = math.floor( headroomStandRaw / gridSize )
    headroomCrouch = math.floor( headroomCrouchRaw / gridSize )
    upCrouch = Vector( 0, 0, 20 )

    finalAreaCheckMins = Vector( -gridSize, -gridSize, -35 )
    finalAreaCheckMaxs = Vector( gridSize, gridSize, 35 )

    directionOffsets = {
        [0] = Vector( 0, gridSize, 0 ),    -- north
        [1] = Vector( gridSize, 0, 0 ),    -- east
        [2] = Vector( 0, -gridSize, 0 ),   -- south
        [3] = Vector( -gridSize, 0, 0 )    -- west

    }

    initialResult = {} -- just do this optimisation for the initial trace, it does most of the hard work
    trStrucIntitial = {
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = function( hit ) return filterFunc( hit ) end,
        mins = trMins,
        maxs = trMaxs,
        output = initialResult,

    }

    tempVectors = {}

    posIsUnderDisplacement = terminator_Extras.posIsUnderDisplacement

end

-- this kind of optimisation is sort of ok since there's just 1 area patcher coroutine
local function tempVector( id, x, y, z )
    local temp = tempVectors[id]
    if not temp then
        temp = Vector( x or 0, y or 0, z or 0 )
        tempVectors[id] = temp
        return temp

    end
    if x then
        temp.x = x

    end
    if y then
        temp.y = y

    end
    if z then
        temp.z = z

    end
    return temp

end

local function findOrthogonalUnmergedNeighborsInDir( data, dir, vecsToPlace )
    local neighbors = {}

    local offset = directionOffsets[dir]
    if not offset then return neighbors end

    for key, vec in pairs( vecsToPlace ) do
        if key ~= data.key then
            local isNeighbor = false
            -- Check for orthogonal match, allowing different sized areas
            if dir == 0 or dir == 2 then -- north/south (y-axis)
                local withinXBounds = ( data.corner1.x < vec.corner2.x ) and ( data.corner2.x > vec.corner1.x )
                local goodY = vec.corner1.y == data.corner1.y + offset.y
                isNeighbor = withinXBounds and goodY

            elseif dir == 1 or dir == 3 then -- east/west (x-axis)
                local withinYBounds = ( data.corner1.y < vec.corner2.y ) and ( data.corner2.y > vec.corner1.y )
                local goodX = vec.corner1.x == data.corner1.x + offset.x
                isNeighbor = withinYBounds and goodX

            end
            if isNeighbor then
                table.insert( neighbors, vec )

            end
        end
    end
    return neighbors

end

local maxMergeDiff = 10

local function getCornersIfMerged( toMergeSet )
    local invalid
    local doneOne
    local oldCrouch

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge
    local minZ, maxZ = math.huge, -math.huge

    for _, tbl in ipairs( toMergeSet ) do
        minX = math_min( minX, tbl.corner1.x, tbl.corner2.x )
        maxX = math_max( maxX, tbl.corner1.x, tbl.corner2.x )
        minY = math_min( minY, tbl.corner1.y, tbl.corner2.y )
        maxY = math_max( maxY, tbl.corner1.y, tbl.corner2.y )

        local newMinZ = math_min( tbl.corner1.z, tbl.corner2.z )
        local newMaxZ = math_max( tbl.corner1.z, tbl.corner2.z )

        if doneOne and math_abs( newMinZ - minZ ) > maxMergeDiff then
            invalid = true

        end
        if doneOne and math_abs( newMaxZ - maxZ ) > maxMergeDiff then
            invalid = true

        end

        if ( oldCrouch ~= nil ) and ( oldCrouch ~= tbl.crouch ) then
            invalid = true

        end

        if invalid then break end

        oldCrouch = tbl.crouch

        doneOne = true

        minZ = math_min( minZ, newMinZ )
        maxZ = math_max( maxZ, newMaxZ )

    end

    if invalid then return end
    return true, minX, maxX, minY, maxY, minZ, maxZ

end

local function mergeWithNeighbors( data, vecsToPlace )
    local neighbors
    for dir = 0, 3 do

        neighbors = findOrthogonalUnmergedNeighborsInDir( data, dir, vecsToPlace )
        if #neighbors <= 0 then continue end

        local allGood, minX, maxX, minY, maxY, minZ, maxZ = getCornersIfMerged( neighbors )
        if not allGood then continue end


        local center1 = ( data.corner1 + data.corner2 ) / 2
        local center2 = ( tempVector( "mergeneighbors1", minX, minY, minZ ) + tempVector( "mergeneighbors2", maxX, maxY, maxZ ) ) / 2
        local sameX = center1.x == center2.x
        local sameY = center1.y == center2.y

        local startSizeX = math_abs( data.corner1.x - data.corner2.x )
        local nextSizeX = math_abs( minX - maxX )
        local startSizeY = math_abs( data.corner1.y - data.corner2.y )
        local nextSizeY = math_abs( minY - maxY )

        local sameXSize = startSizeX == nextSizeX
        local sameYSize = startSizeY == nextSizeY

        local mergable = ( sameX and sameXSize ) or ( sameY and sameYSize )
        if not mergable then continue end


        local toMergeSet = { data }
        table.Add( toMergeSet, neighbors )

        allGood, minX, maxX, minY, maxY, minZ, maxZ = getCornersIfMerged( toMergeSet )
        if not allGood then continue end

        for _, toMerge in ipairs( neighbors ) do
            vecsToPlace[ toMerge.key ] = nil

        end

        data.corner1 = Vector( minX, minY, minZ )
        data.corner2 = Vector( maxX, maxY, maxZ )

        return true
    end
end

local roundDec = 2

local function navGetBounds( area )
    return GetCorner( area, 0 ), GetCorner( area, 2 )

end

local function vecAsKey( vec )
    return math_Round( vec.x, roundDec ) .. math_Round( vec.y, roundDec ) .. math_Round( vec.z, roundDec )

end

local function VectorMin( v1, v2 )
    return Vector(
        math_min( v1.x, v2.x ),
        math_min( v1.y, v2.y ),
        math_min( v1.z, v2.z )
    )
end

local function VectorMax( v1, v2 )
    return Vector(
        math_max( v1.x, v2.x ),
        math_max( v1.y, v2.y ),
        math_max( v1.z, v2.z )
    )
end

local up = Vector( 0, 0, 1 )

local function SnapToGrid( vec, gridSizeInternal, gridOffsetInternal )
    gridSizeInternal = gridSizeInternal or gridSize
    gridOffsetInternal = gridOffsetInternal or gridOffset
    vec.x = ( math_Round( vec.x / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal
    vec.y = ( math_Round( vec.y / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal
    vec.z = ( math_Round( vec.z / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal

end

terminator_Extras.SnapVecToGrid = SnapToGrid

local function GetSnappedToGrid( vec )
    local x = ( math_Round( vec.x / gridSize ) * gridSize ) + gridOffset
    local y = ( math_Round( vec.y / gridSize ) * gridSize ) + gridOffset
    local z = ( math_Round( vec.z / gridSize ) * gridSize ) + gridOffset
    return Vector( x, y, z )

end

local HEADROOM_NONE = 0
local HEADROOM_CROUCH = 1
local HEADROOM_STAND = 2

local function getHeadroom( voxel, solidVoxels )
    local clearCount = 0
    for ind = 1, headroomStand + 1 do
        if solidVoxels[vecAsKey( voxel + ( vecGridsizeZ * ind ) )] then
            break
        else
            clearCount = clearCount + 1
        end
    end
    if clearCount >= headroomStand then return HEADROOM_STAND end
    if clearCount > headroomCrouch then return HEADROOM_CROUCH end
    return HEADROOM_NONE

end

-- Queue to store regions that need patching
local regionsQueue = {}

-- Flag to indicate if a patching process is currently running
local isPatching = false
hook.Remove( "Think", "PatchThinkHook" )

local function processVoxel( voxel, mins, _maxs, vecsToPlace, closedVoxels, headroomTbl, solidVoxels )
    local voxelsKey = vecAsKey( voxel )
    if not util_IsInWorld( voxel ) then
        solidVoxels[voxelsKey] = true
        closedVoxels[voxelsKey] = true
        return

    end

    local bottomOfBounds = tempVector( "processvoxelboundbottom", voxel.x, voxel.y, math_min( voxel.z, mins.z + -gridSize ) )
    trStrucIntitial.start = voxel
    trStrucIntitial.endpos = bottomOfBounds

    util.TraceHull( trStrucIntitial )
    if initialResult.StartSolid then
        if debugging then
            debugoverlay.Cross( voxel, 5, 10, red, true )

        end
        solidVoxels[voxelsKey] = true
        closedVoxels[voxelsKey] = true
        return

    end

    local voxelsHeadroom = getHeadroom( voxel, solidVoxels )
    headroomTbl[voxelsKey] = voxelsHeadroom
    if debugging then
        debugoverlay.Text( voxel, tostring( voxelsHeadroom ), 10, false )

    end

    if voxelsHeadroom <= HEADROOM_NONE then
        closedVoxels[voxelsKey] = true
        return

    end

    local hitPos = initialResult.HitPos
    local snapped = GetSnappedToGrid( hitPos )

    local line = { start = voxel, endpos = hitPos }
    local dist = line.start:Distance( line.endpos )
    local voxelsToToss = math.floor( dist / gridSize )
    if voxelsToToss >= 1 then -- skip voxels early if floor trace passed through them no issue
        if debugging then
            debugoverlay.Line( voxel, line.endpos, 10, red, true )

        end
        for ind = 1, voxelsToToss do
            local toToss = tempVector( "processvoxeltossing", voxel.x, voxel.y, voxel.z + -( ind * gridSize ) )
            closedVoxels[vecAsKey( toToss )] = true

        end
    end
    if not initialResult.Hit then return end
    closedVoxels[vecAsKey( voxel )] = true

    if initialResult.HitTexture == "TOOLS/TOOLSNODRAW" then return end -- dont place outside of maps
    if initialResult.HitSky then return end -- dont place on skybox, probably an "endless" pit

    -- slope check
    if initialResult.HitNormal:Dot( up ) < 0.5 then return end


    local trStrucFindFloor = {
        start = hitPos + vecHalfGridsizeZ,
        endpos = hitPos + -vecHalfGridsizeZ,
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = filterFunc,

    }

    local floorResult = util.TraceLine( trStrucFindFloor )
    if not floorResult.Hit then return end


    local trStrucCollide = {
        start = hitPos + upCrouch,
        endpos = hitPos + upCrouch + up,
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = filterFunc,
        mins = collideTrMins,
        maxs = collideTrMaxs,

    }

    local collideResult = util.TraceHull( trStrucCollide )
    if collideResult.StartSolid then return end

    local defUnder, probUnder, upTrResult = posIsUnderDisplacement( hitPos )
    if defUnder or probUnder then return end
    if upTrResult.HitPos:Distance( hitPos ) < headroomCrouchRaw then return end -- really tiny space

    local existingArea = navmesh.GetNearestNavArea( hitPos, false, halfGrid, false, true, -2 )
    if IsValid( existingArea ) then return end

    local existingAreas = navmesh.FindInBox( hitPos + finalAreaCheckMins, hitPos + finalAreaCheckMaxs )
    if existingAreas and #existingAreas >= 1 then
        for _, area in ipairs( existingAreas ) do
            local areasNearestToHit = area:GetClosestPointOnArea( hitPos )
            if areasNearestToHit:Distance2D( hitPos ) < gridSize * 0.5 then
                if debugging then
                    debugoverlay.Line( hitPos, areasNearestToHit, 10, red, true )

                end
                return -- area is too close to an existing area

            end
        end
    end

    local pos = hitPos
    local key = vecAsKey( snapped )
    vecsToPlace[key] = {
        key = key,
        truePos = pos,
        corner1 = pos + areaCenteringOffset,
        corner2 = pos + oppCornerOffset,
        headroom = voxelsHeadroom,
        crouch = voxelsHeadroom <= HEADROOM_CROUCH

    }

    if debugging then
        debugoverlay.Cross( pos, 5, 10, color_white, true )

    end

end

local coroutine_yield = coroutine.yield

-- Coroutine function to handle patching regions one-by-one
local function patchCoroutine()
    while #regionsQueue > 0 do
        terminator_Extras.IsLivePatching = true
        coroutine_yield()

        -- Retrieve the next region from the queue
        local region = table.remove( regionsQueue, 1 )
        updateGridSize( region.gridSize )

        local newGenCenter = region.pos1 + region.pos2
        newGenCenter = newGenCenter / 2

        if oldGenCenter and gridSize < 12.5 and oldGenCenter:Distance( newGenCenter ) < ( gridSize * 6 ) then -- we are stuck regenerating one point, try shuffling this
            gridOffset = math.random( -4, 4 )
            debugPrint( "Area generation is stuck, offsetting grid by " .. gridOffset )

        else
            gridOffset = 0

        end

        local pos1 = VectorMin( region.pos1, region.pos2 )
        local pos2 = VectorMax( region.pos1, region.pos2 )
        SnapToGrid( pos1 )
        SnapToGrid( pos2 )

        oldGenCenter = newGenCenter

        debugPrint( "Patching region from", pos1, "to", pos2 )

        local openVoxelsSeq = {} -- spots we are yet to check
        local closedVoxels = {} -- spots that we dont need to check
        local solidVoxels = {} -- solid spots
        local vecsToPlace = {} -- good spots we found
        local headroomTbl = {} -- headroom, for simple crouching checks
        local validatedAreas = {} -- all the areas we made this pass

        local biggest = VectorMax( pos1, pos2 )
        local smallest = VectorMin( pos1, pos2 )

        local sizeInX = biggest.x - smallest.x
        local sizeInY = biggest.y - smallest.y
        local sizeInZ = biggest.z - smallest.z

        for z = 0, sizeInZ / gridSize do -- z first
            z = z * gridSize
            coroutine_yield()
            for x = 0, sizeInX / gridSize do
                x = x * gridSize
                coroutine_yield()
                for y = 0, sizeInY / gridSize do
                    y = y * gridSize
                    local voxel = Vector( smallest.x + x, smallest.y + y, smallest.z + z )
                    table.insert( openVoxelsSeq, voxel )
                end
            end
        end

        debugPrint( "Total voxels to process:", #openVoxelsSeq )

        -- Step 5: Process each voxel
        while #openVoxelsSeq >= 1 do
            local currVoxel = table.remove( openVoxelsSeq )
            if closedVoxels[vecAsKey( currVoxel )] then continue end

            coroutine_yield()
            processVoxel( currVoxel, pos1, pos2, vecsToPlace, closedVoxels, headroomTbl, solidVoxels )
            --[[
            if debugging and IsValid( Entity(1) ) and currVoxel:Distance( Entity(1):GetPos() ) < 250 then
                coroutine_yield( "wait" )

            end --]]
        end

        local count = table.Count( vecsToPlace )
        debugPrint( "Placing!" )

        if count >= 1 then
            debugPrint( "Pre-merging areas..." )

            local merged = true
            while merged do
                coroutine_yield()
                merged = nil
                for _, data in pairs( vecsToPlace ) do
                    coroutine_yield()
                    if mergeWithNeighbors( data, vecsToPlace ) then
                        merged = true
                        break

                    end
                end
            end

            debugPrint( "Placing " .. count .. " navareas..." )

            local justNewAreas = {}
            local justNewAreasSeq = {}
            for _, data in pairs( vecsToPlace ) do
                coroutine_yield()
                local newArea = navmesh.CreateNavArea( data.corner1, data.corner2 )
                table.insert( justNewAreasSeq, newArea )
                justNewAreas[newArea] = true
                data.newArea = newArea
                if data.crouch then
                    newArea:AddAttributes( NAV_MESH_CROUCH )

                end
            end

            debugPrint( "Connecting placed areas..." )
            coroutine_yield( "wait" )

            local additionalSize = math_max( gridSize, 25 )
            local additional = Vector( additionalSize, additionalSize, additionalSize )

            for _, data in pairs( vecsToPlace ) do
                coroutine_yield()
                local upOff = upCrouch / 2
                local newArea = data.newArea
                local mins, maxs = navGetBounds( newArea )
                for _, otherArea in ipairs( navmesh.FindInBox( mins + -additional, maxs + additional ) ) do
                    local trivialDist -- defaults to 5 in following navpatcher 
                    if not justNewAreas[otherArea] then
                        trivialDist = math_max( 25, gridSize ) -- not a new area, allow long connections!

                    end
                    coroutine_yield()
                    local connectable1 = terminator_Extras.AreasAreConnectable( newArea, otherArea, upOff, trivialDist )
                    local connectable2 = terminator_Extras.AreasAreConnectable( otherArea, newArea, upOff, trivialDist )
                    if connectable1 then
                        newArea:ConnectTo( otherArea )

                    end
                    if connectable2 then
                        otherArea:ConnectTo( newArea )

                    end
                end
            end

            debugPrint( "Merging placed areas..." )
            coroutine_yield( "wait" )

            merged = true
            while merged do
                coroutine_yield()
                merged = nil
                for _, area in ipairs( justNewAreasSeq ) do
                    if not IsValid( area ) then continue end
                    for _, neighbor in ipairs( area:GetAdjacentAreas() ) do
                        merged, _, mergedArea = terminator_Extras.navmeshAttemptMerge( area, neighbor )
                        if merged then
                            table.insert( justNewAreasSeq, mergedArea )
                            coroutine_yield( "wait" )
                            break

                        end
                    end
                    if merged then
                        break

                    end
                end
            end
            validatedAreas = {}
            for _, area in ipairs( justNewAreasSeq ) do
                if IsValid( area ) then
                    table.insert( validatedAreas, area )

                end
            end

            debugPrint( "checking for attributes..." )

            local trStruc = {
                filter = filterFunc,
            }
            local upCrouchCheck = Vector( 0, 0, 10 )
            local endOffset = Vector( 0, 0, headroomStandRaw )
            for _, area in ipairs( validatedAreas ) do
                local areasCenter = area:GetCenter()
                trStruc.start = areasCenter + upCrouchCheck
                trStruc.endpos = areasCenter + endOffset

                local result = util.TraceLine( trStruc )
                if result.Hit then
                    area:AddAttributes( NAV_MESH_CROUCH )

                end
            end
        end
        terminator_Extras.IsLivePatching = nil
        coroutine_yield( "waitlong" )

        local areaCreatedCount = #validatedAreas
        hook.Run( "terminator_areapatcher_doneapatch", validatedAreas, areaCreatedCount )

    end

    -- All regions have been processed; clean up the hook
    isPatching = false
    debugPrint( "All regions have been patched." )
    coroutine_yield( "done" )

end


local coroutine_resume = coroutine.resume
local coroutine_status = coroutine.status

local thread
local nextThink = 0
terminator_Extras.IsLivePatching = nil

-- The main function to add a region to the patch queue
function terminator_Extras.AddRegionToPatch( pos1, pos2, currGridSize )
    if not doAreaPatching then return end
    -- Add the new region to the queue
    table.insert( regionsQueue, { pos1 = pos1, pos2 = pos2, gridSize = currGridSize } )
    debugPrint( "Added region to queue:", pos1, pos2 )

    -- If not already patching, start the coroutine and add the Think hook
    if isPatching then return end
    isPatching = true
    hook.Add( "Think", "PatchThinkHook", function()
        if not isPatching then hook.Remove( "Think", "PatchThinkHook" ) return end
        if nextThink > CurTime() then return end

        if not thread or coroutine_status( thread ) == "dead" then
            thread = coroutine.create( patchCoroutine )

        end
        if thread then
            local oldTime = SysTime()
            while math_abs( oldTime - SysTime() ) < areaPatchingRate do
                inCoroutine = true
                local noErrors, result = coroutine_resume( thread )
                inCoroutine = nil
                if noErrors == false then -- errored
                    thread = nil
                    terminator_Extras.IsLivePatching = nil
                    ErrorNoHaltWithStack( result )

                    break
                elseif result == "wait" then -- it wants us to wait a tick
                    break

                elseif result == "waitlong" then -- it wants us to wait a bit
                    nextThink = CurTime() + 0.5
                    break

                elseif result == "done" then -- all finished, clean up hook
                    thread = nil
                    terminator_Extras.IsLivePatching = nil
                    hook.Remove( "Think", "PatchThinkHook" )
                    break

                end
            end
        end
    end )
end

local smallSize = Vector( 100, 100, 50 )
local bigSize = Vector( 175, 175, 100 )
local hugeSize = Vector( 500, 500, 150 )

function terminator_Extras.dynamicallyPatchPos( pos )
    if not doAreaPatching then return end
    local areasInSmallSize = navmesh.FindInBox( pos + -smallSize * 1.25, pos + smallSize * 1.25 )
    if areasInSmallSize and #areasInSmallSize >= 1 then
        terminator_Extras.AddRegionToPatch( pos + -smallSize, pos + smallSize, 11.25 )

    else
        local areasInBigSize = navmesh.FindInBox( pos + -bigSize, pos + bigSize )
        if areasInBigSize and #areasInBigSize >= 1 then
            terminator_Extras.AddRegionToPatch( pos + -bigSize, pos + bigSize, 25 )

        else
            terminator_Extras.AddRegionToPatch( pos + -hugeSize, pos + hugeSize, 50 )

        end
    end
end

-- Superadmin-only concommand to patch around the caller's eye trace position using smallSize and grid size 11.25
concommand.Add( "terminator_areapatch_here", function( ply )
    if not IsValid( ply ) then return end -- must be a player
    if not ply:IsSuperAdmin() then
        if ply.ChatPrint then ply:ChatPrint( "Superadmin only." ) end
        return
    end

    local tr = ply:GetEyeTrace()
    if not tr or not tr.HitPos then return end

    local pos = tr.HitPos
    SnapToGrid( pos, 11.25, 0 )

    terminator_Extras.AddRegionToPatch( pos + -smallSize, pos + smallSize, 11.25 )

    -- Visualize the region being queued with a debug box
    local boxMins = -smallSize
    local boxMaxs = smallSize
    debugoverlay.Box( pos, boxMins, boxMaxs, 10, Color( 0, 255, 0 ) )

    if debugging and ply.ChatPrint then
        ply:ChatPrint( "Queued nav patch at eye position (grid 11.25)." )
    end
end, nil, "Patch a nav region centered at your crosshair using smallSize and grid 11.25 (superadmin only)")
