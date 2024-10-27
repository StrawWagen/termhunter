
-- the merging for this SUCKS!
-- would be worth finishing if i had a decent area merging algorithm

local math = math

local gridSize

local halfGrid = nil
local gridSmaller = nil
local vecGridsizeZ = nil
local vecHalfGridsize = nil

local trMins = nil
local trMaxs = nil

local areaCenteringOffset = nil
local oppCornerOffset = nil

local headroom = nil

local function updateGridSize( newSize )
    gridSize = newSize

    halfGrid = gridSize * 0.5
    gridSmaller = gridSize * 0.25
    vecGridsizeZ = Vector( 0, 0, gridSize )
    vecHalfGridsize = Vector( halfGrid, halfGrid, halfGrid )

    trMins = Vector( -gridSmaller, -gridSmaller, -1 )
    trMaxs = Vector( gridSmaller, gridSmaller, 1 )

    areaCenteringOffset = Vector( -halfGrid, -halfGrid, 0 )
    oppCornerOffset = Vector( halfGrid, halfGrid, 0 )

    headroom = math.floor( 40 / gridSize )

end
local roundDec = 2

local function navGetBounds( area )
    return area:GetCorner( 0 ), area:GetCorner( 2 )

end

local function vecAsKey( vec )
    return math.Round( vec.x, roundDec ) .. math.Round( vec.y, roundDec ) .. math.Round( vec.z, roundDec )

end

local function VectorMin( v1, v2 )
    return Vector(
        math.min( v1.x, v2.x ),
        math.min( v1.y, v2.y ),
        math.min( v1.z, v2.z )
    )
end

local function VectorMax( v1, v2 )
    return Vector(
        math.max( v1.x, v2.x ),
        math.max( v1.y, v2.y ),
        math.max( v1.z, v2.z )
    )
end

local up = Vector( 0, 0, 1 )

local red = Color( 255, 0, 0 )

local function SnapToGrid( vec )
    print( vec.x )
    vec.x = math.Round( vec.x / gridSize ) * gridSize
    vec.y = math.Round( vec.y / gridSize ) * gridSize
    vec.z = math.Round( vec.z / gridSize ) * gridSize
    print( vec.x )

end
local function GetSnappedToGrid( vec )
    local x = math.Round( vec.x / gridSize ) * gridSize
    local y = math.Round( vec.y / gridSize ) * gridSize
    local z = math.Round( vec.z / gridSize ) * gridSize
    return Vector( x, y, z )

end

-- Queue to store regions that need patching
local regionsQueue = {}

-- Flag to indicate if a patching process is currently running
local isPatching = false
hook.Remove( "Think", "PatchThinkHook" )

local function filterFunc( hit )
    if hit:IsWorld() then return true end

    local class = hit:GetClass()
    local isDoor = string.find( class, "door" ) and hit:IsSolid()
    if hit:IsNPC() or hit:IsPlayer() or isDoor then
        if isDoor and class == "prop_door_rotating" and not terminator_Extras.CanBashDoor( hit ) then
            return true

        else
            return nil

        end
    elseif hit.GetDriver then
        return nil

    end
    local obj = hit:GetPhysicsObject()
    if not obj:IsMotionEnabled() then return true end
    if not obj:IsMoveable() then return true end
end

local function processVoxel( voxel, mins, _maxs, vecsToPlace, closedVoxels, solidVoxels, areasToRemove )
    local voxelsKey = vecAsKey( voxel )
    if not util.IsInWorld( voxel ) then
        solidVoxels[voxelsKey] = true
        closedVoxels[voxelsKey] = true
        return

    end

    local bottomOfBounds = Vector( voxel.x, voxel.y, math.min( voxel.z, mins.z + -gridSize ) )
    local trStruc = {
        start = voxel,
        endpos = bottomOfBounds,
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = filterFunc,
        mins = trMins,
        maxs = trMaxs,

    }

    local result = util.TraceHull( trStruc )
    if result.StartSolid then
        solidVoxels[voxelsKey] = true
        closedVoxels[voxelsKey] = true
        return

    end
    for ind = 1, headroom do
        if solidVoxels[vecAsKey( voxel + ( vecGridsizeZ * ind ) )] then
            closedVoxels[voxelsKey] = true
            return

        end
    end

    local snapped = GetSnappedToGrid( result.HitPos )

    local line = { start = voxel, endpos = result.HitPos }
    local dist = line.start:Distance( line.endpos )
    local voxelsToToss = math.floor( dist / gridSize )
    if voxelsToToss >= 1 then
        debugoverlay.Line( voxel, line.endpos, 10, red, true )
        for ind = 1, voxelsToToss do
            local toToss = Vector( voxel.x, voxel.y, voxel.z + -( ind * gridSize ) )
            closedVoxels[vecAsKey( toToss )] = true

        end
    end

    if not result.Hit then return end
    closedVoxels[vecAsKey( voxel )] = true

    -- slope check
    if result.HitNormal:Dot( up ) < 0.5 then return end
    local existingArea = navmesh.GetNearestNavArea( result.HitPos, false, gridSize, false, true, -2 )

    if IsValid( existingArea ) and not areasToRemove[ existingArea ] then return end
    local key = vecAsKey( snapped )
    vecsToPlace[key] = { key = key, truePos = result.HitPos }

    debugoverlay.Cross( result.HitPos, 5, 10, color_white, true )

end

-- Coroutine function to handle patching regions one-by-one
local function patchCoroutine()
    while #regionsQueue > 0 do
        coroutine.yield()

        -- Retrieve the next region from the queue
        local region = table.remove( regionsQueue, 1 )
        updateGridSize( region.gridSize )

        local pos1 = VectorMin( region.pos1, region.pos2 )
        local pos2 = VectorMax( region.pos1, region.pos2 )
        SnapToGrid( pos1 )
        SnapToGrid( pos2 )

        local middle = ( pos1 + pos2 ) / 2

        print( "Patching region from", pos1, "to", pos2 )

        -- Step 1: Find all navareas within the specified box
        local potentialBlockingAreas = navmesh.FindInBox( pos1, pos2 )
        coroutine.yield()

        local navAreasBlocking = {}

        -- Step 2: Expand the box to fit all found navareas
        if #potentialBlockingAreas > 0 then
            for _, area in ipairs( potentialBlockingAreas ) do
                if not IsValid( area ) then coroutine.yield( "done" ) return end -- outdated

                local mins, maxs = navGetBounds( area )
                pos1 = VectorMin( pos1, mins )
                pos2 = VectorMax( pos2, maxs )
                table.insert( navAreasBlocking, area )

            end
            print( "Expanded region to:", pos1, pos2 )
        end
        debugoverlay.Cross( pos1, 10, 10, color_white, true )
        debugoverlay.Cross( pos2, 10, 10, color_white, true )
        coroutine.yield()

        local areasToRemove = {}

        for _, area in ipairs( navAreasBlocking ) do
            if math.max( area:GetSizeX(), area:GetSizeY() ) > 500 and not ( area:Contains( pos1 ) and area:Contains( pos2 ) ) then continue end -- too big, better be worth it!

            areasToRemove[area] = true

        end

        local openVoxelsSeq = {}
        local closedVoxels = {}
        local solidVoxels = {}
        local vecsToPlace = {}

        local biggest = VectorMax( pos1, pos2 )
        local smallest = VectorMin( pos1, pos2 )

        local sizeInX = biggest.x - smallest.x
        local sizeInY = biggest.y - smallest.y
        local sizeInZ = biggest.z - smallest.z

        for z = 0, sizeInZ / gridSize do -- z first
            z = z * gridSize
            coroutine.yield()
            for x = 0, sizeInX / gridSize do
                x = x * gridSize
                coroutine.yield()
                for y = 0, sizeInY / gridSize do
                    y = y * gridSize
                    local voxel = Vector( smallest.x + x, smallest.y + y, smallest.z + z )
                    table.insert( openVoxelsSeq, voxel )
                end
            end
        end

        print( "Total voxels to process:", #openVoxelsSeq )

        -- Step 5: Process each voxel
        while #openVoxelsSeq >= 1 do
            local currVoxel = table.remove( openVoxelsSeq )
            if closedVoxels[vecAsKey( currVoxel )] then continue end

            coroutine.yield()
            -- Placeholder for voxel processing
            processVoxel( currVoxel, pos1, pos2, vecsToPlace, closedVoxels, solidVoxels, areasToRemove )

        end

        local count = table.Count( vecsToPlace )
        print( "Placing " .. count .. " navareas..." )

        if count >= 1 then
            local justNewAreas = {}
            for _, data in pairs( vecsToPlace ) do
                coroutine.yield()
                local pos = data.truePos
                local newArea = navmesh.CreateNavArea( pos + areaCenteringOffset, pos + oppCornerOffset )
                table.insert( justNewAreas, newArea )
                data.newArea = newArea

            end
            print( "Connecting placed areas..." )
            coroutine.yield( "wait" )
            for _, data in pairs( vecsToPlace ) do
                coroutine.yield()
                local pos = data.truePos
                local newArea = data.newArea
                local centerOfArea = pos + -areaCenteringOffset
                for _, otherArea in ipairs( navmesh.FindInBox( centerOfArea + -vecHalfGridsize, centerOfArea + vecHalfGridsize ) ) do
                    if areasToRemove[otherArea] then continue end
                    coroutine.yield()
                    if terminator_Extras.AreasAreConnectable( newArea, otherArea ) then
                        newArea:ConnectTo( otherArea )

                    end
                    if terminator_Extras.AreasAreConnectable( otherArea, newArea ) then
                        otherArea:ConnectTo( newArea )

                    end
                end
            end
            print( "Merging placed areas..." )
            coroutine.yield( "wait" )
            local merged = true
            while merged do
                coroutine.yield()
                merged = nil
                for _, area in ipairs( justNewAreas ) do
                    if not IsValid( area ) then continue end
                    for _, neighbor in ipairs( area:GetAdjacentAreas() ) do
                        merged, _, mergedArea = navmeshAttemptMerge( area, neighbor )
                        if merged then
                            table.insert( justNewAreas, mergedArea )
                            break

                        end
                    end
                    if merged then
                        break

                    end
                end
            end

            print( "Removing old areas..." )
            for _, area in ipairs( navAreasBlocking ) do
                if IsValid( area ) then
                    area:Remove()

                end
            end
        end
    end


    -- All regions have been processed; clean up the hook
    isPatching = false
    print( "All regions have been patched." )
    coroutine.yield( "done" )

end

local thread

-- The main function to add a region to the patch queue
function terminator_Extras.AddRegionToPatch( pos1, pos2, currGridSize )
    if true then return end -- TODO, FINISH THIS CODE!

    -- Add the new region to the queue
    table.insert( regionsQueue, { pos1 = pos1, pos2 = pos2, gridSize = currGridSize } )
    print( "Added region to queue:", pos1, pos2 )

    -- If not already patching, start the coroutine and add the Think hook
    if isPatching then return end
    isPatching = true
    hook.Add( "Think", "PatchThinkHook", function()
        if not isPatching then hook.Remove( "Think", "PatchThinkHook" ) return end

        if not thread or coroutine.status( thread ) == "dead" then
            thread = coroutine.create( patchCoroutine )

        end
        if thread then
            local oldTime = SysTime()
            while math.abs( oldTime - SysTime() ) < 0.0005 do
                inCoroutine = true
                local noErrors, result = coroutine.resume( thread )
                inCoroutine = nil
                if noErrors == false then -- errored
                    thread = nil
                    ErrorNoHaltWithStack( result )

                    break
                elseif result == "wait" then -- it wants us to wait a tick
                    break

                elseif result == "done" then -- all finished, clean up hook
                    thread = nil
                    hook.Remove( "Think", "PatchThinkHook" )
                    break

                end
            end
        end
    end )
end

-- Example usage:
--terminator_Extras.AddRegionToPatch( Entity(1):GetShootPos(), Entity(1):GetShootPos() + Entity(1):GetAimVector() * 500, 25 )

