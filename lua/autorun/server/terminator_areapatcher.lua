
local navMeta = FindMetaTable( "CNavArea" )
local GetCorner = navMeta.GetCorner

local table = table
local navmesh = navmesh
local bit = bit
local coroutine_yield = coroutine.yield

local math = math
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local math_Round = math.Round

local util_IsInWorld = util.IsInWorld
local IsValid = IsValid
local Vector = Vector


local dedicatedRate = 0.003
local otherwiseRate = 0.006

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

local smallGridSize = 12.5

local patchTbl

local function patchCleanup()
    patchTbl = nil

end

local function updateGridSize( newSize )
    patchTbl = {}

    patchTbl.gridSize = newSize
    patchTbl.gridOffset = smallGridSize / 2

    patchTbl.halfGrid = patchTbl.gridSize * 0.5
    patchTbl.gridSmaller = patchTbl.gridSize * 0.25
    patchTbl.vecQuarterGridsizeZ = Vector( 0, 0, patchTbl.halfGrid / 2 )

    patchTbl.trMins = Vector( -patchTbl.gridSmaller, -patchTbl.gridSmaller, -1 )
    patchTbl.trMaxs = Vector( patchTbl.gridSmaller, patchTbl.gridSmaller, 1 )
    local collideXY = math_max( 15, patchTbl.gridSize * 0.65 )
    patchTbl.collideTrMins = Vector( -collideXY, -collideXY, -1 )
    patchTbl.collideTrMaxs = Vector( collideXY, collideXY, collideXY )

    patchTbl.areaCenteringOffset = Vector( -patchTbl.halfGrid, -patchTbl.halfGrid, 2 )
    patchTbl.oppCornerOffset = Vector( patchTbl.halfGrid, patchTbl.halfGrid, 2 )

    patchTbl.headroomStandRaw = 70
    patchTbl.headroomCrouchRaw = 20
    patchTbl.headroomStand = math.floor( patchTbl.headroomStandRaw / patchTbl.gridSize )
    patchTbl.headroomCrouch = math.floor( patchTbl.headroomCrouchRaw / patchTbl.gridSize )
    patchTbl.upCrouch = Vector( 0, 0, patchTbl.headroomCrouchRaw )

    patchTbl.finalAreaCheckMins = Vector( -patchTbl.gridSize, -patchTbl.gridSize, -35 )
    patchTbl.finalAreaCheckMaxs = Vector( patchTbl.gridSize, patchTbl.gridSize, 35 )

    patchTbl.initialResult = {} -- just do this optimisation for the initial trace, it does most of the hard work
    patchTbl.trStrucInitial = {
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = function( hit ) return filterFunc( hit ) end,
        mins = patchTbl.trMins,
        maxs = patchTbl.trMaxs,
        output = patchTbl.initialResult,

    }

    patchTbl.tempVectors = {}

    patchTbl.posIsUnderDisplacement = terminator_Extras.posIsUnderDisplacement

end

-- this kind of optimisation is sort of ok since there's just 1 area patcher coroutine
local function tempVector( id, x, y, z )
    local temp = patchTbl.tempVectors[id]
    if not temp then
        temp = Vector( x or 0, y or 0, z or 0 )
        patchTbl.tempVectors[id] = temp
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

-- how far a row of cells, or one of the rectangle's two side edges, may sit off the
-- straight line its own two ends describe
local maxMergeDiff = 10

-- steepest step allowed between two cells side by side, on either axis. A staircase's
-- treads are each perfectly flat, so without this they'd merge into one smooth ramp
local maxMergeSlope = 0.6

-- floors this far out of parallel belong to different surfaces, whatever their heights
-- say. About 18 degrees
local minNormalDot = 0.95

-- mirrors the caps in navAreasCanMerge, terminator_optimizerhack.lua
local maxMergedSide = 800
local maxMergedSurface = 300000

-- The cell at this spot that belongs with seed's rectangle, or nothing if this spot has
-- none to offer it.
local function pickCell( stack, seed, consumed, nearZ, tolerance )
    if not stack then return end

    -- buildCellGrid sorted these, so this takes the lowest floor that fits
    for _, cand in ipairs( stack ) do
        if consumed[cand] then continue end
        if cand.crouch ~= seed.crouch then continue end
        if math_abs( cand.z - nearZ ) > tolerance then continue end
        if cand.normal:Dot( seed.normal ) < minNormalDot then continue end

        return cand

    end
end

-- Fills out[1..width] with the row of cells at iy spanning ix..ix + width - 1 and returns
-- whether it found every one. Claims nothing, so a caller that gives up owes nothing.
local function probeWholeRow( cellGrid, ix, iy, width, seed, consumed, prevZ, maxStep, out )
    -- each cell only has to be one step off the cell west of it, and the first one step
    -- off the row above. Nothing here stops a row stepping its way into a bulge, fitsLine
    -- at the caller is what does that
    local anchor = prevZ
    for ind = 0, width - 1 do
        local column = cellGrid[ix + ind]
        -- no cell was ever placed anywhere at this x
        if not column then return end

        local cand = pickCell( column[iy], seed, consumed, anchor, maxStep )
        -- missing, taken by another rectangle, or too far off to join. A row is all or
        -- nothing, so the whole probe fails on any one of them
        if not cand then return end

        out[ind + 1] = cand
        anchor = cand.z

    end
    return true

end

-- Fills out[1..height] with the column of cells at ix spanning iy..iy + height - 1 and
-- returns whether it found every one. Claims nothing.
local function probeWholeColumn( cellGrid, ix, iy, height, seed, consumed, rowCellZs, width, maxStep, out )
    local column = cellGrid[ix]
    if not column then return end

    for ind = 0, height - 1 do
        -- each of these extends the row beside it, so it steps off that row's east end
        -- rather than off the cell above it
        local cand = pickCell( column[iy + ind], seed, consumed, rowCellZs[ind + 1][width], maxStep )
        if not cand then return end

        out[ind + 1] = cand

    end
    return true

end

-- CNavArea interpolates its four corners, so the built surface runs straight between the
-- ends of every row and straight between the ends of every edge. This is what holds the
-- cells in between to that, on both axes.
local function fitsLine( zs, count )
    -- two of anything are a straight line by definition
    if count <= 2 then return true end

    local first = zs[1]
    local step = ( zs[count] - first ) / ( count - 1 )
    for ind = 2, count - 1 do
        if math_abs( zs[ind] - ( first + step * ( ind - 1 ) ) ) > maxMergeDiff then return false end

    end
    return true

end

-- fitsLine down one side of the rectangle, whose heights sit a row apart rather than side
-- by side. col is 1 for the west edge, the row width for the east.
local function edgeFitsLine( rowCellZs, count, col )
    if count <= 2 then return true end

    local first = rowCellZs[1][col]
    local step = ( rowCellZs[count][col] - first ) / ( count - 1 )
    for ind = 2, count - 1 do
        if math_abs( rowCellZs[ind][col] - ( first + step * ( ind - 1 ) ) ) > maxMergeDiff then return false end

    end
    return true

end

-- Whether a size x size square of cells with its min corner at ix, iy all belongs with
-- seed. Claims nothing.
local function fitsSquare( cellGrid, ix, iy, size, seed, consumed, maxStep, rowCellZs, pending )
    local prevZ = seed.z
    for ind = 0, size - 1 do
        if not probeWholeRow( cellGrid, ix, iy + ind, size, seed, consumed, prevZ, maxStep, pending ) then return false end

        local row = rowCellZs[ind + 1]
        if not row then
            row = {}
            rowCellZs[ind + 1] = row

        end
        for col = 1, size do
            row[col] = pending[col].z

        end
        if not fitsLine( row, size ) then return false end

        prevZ = row[1]

    end
    -- rowCellZs and pending are growRect's scratch, borrowed to answer the question. It
    -- refills both from its own seed before it reads them
    return edgeFitsLine( rowCellZs, size, 1 ) and edgeFitsLine( rowCellZs, size, size )

end

-- Sorts the placed cells into cellGrid[ix][iy], plus the extent of the whole thing so
-- callers can walk it. Returns nothing at all if there were no cells.
local function buildCellGrid( vecsToPlace )
    local cellGrid = {}
    local minIx, maxIx = math.huge, -math.huge
    local minIy, maxIy = math.huge, -math.huge
    local any

    for _, data in pairs( vecsToPlace ) do
        local ix, iy = data.ix, data.iy

        local column = cellGrid[ix]
        if not column then
            column = {}
            cellGrid[ix] = column

        end
        local stack = column[iy]
        if not stack then
            stack = {}
            column[iy] = stack

        end
        stack[#stack + 1] = data

        minIx = math_min( minIx, ix )
        maxIx = math_max( maxIx, ix )
        minIy = math_min( minIy, iy )
        maxIy = math_max( maxIy, iy )
        any = true

    end

    if not any then return end

    -- one spot can hold several floors stacked over each other, a walkway above a
    -- street. Lowest first, which is the order pickCell relies on
    for _, column in pairs( cellGrid ) do
        for _, stack in pairs( column ) do
            if #stack > 1 then
                table.sort( stack, function( a, b ) return a.z < b.z end )

            end
        end
    end

    return cellGrid, minIx, maxIx, minIy, maxIy

end

local function claimCells( consumed, cells, count )
    for ind = 1, count do
        consumed[cells[ind]] = true

    end
end

-- Grows seed's rectangle out from its min corner, returning its size in cells.
local function growRect( cellGrid, ix, iy, seed, consumed, limits, rowCellZs, pending )
    local width, height = 1, 1
    -- rowCellZs[row][col] is the floor traced under every cell the rectangle covers. Its
    -- four outer values are the corner heights the nav area gets built from
    local firstRow = rowCellZs[1]
    if not firstRow then
        firstRow = {}
        rowCellZs[1] = firstRow

    end
    firstRow[1] = seed.z

    local canEast, canSouth = true, true
    while canEast or canSouth do
        -- extend whichever side is shorter, so this comes out blocky instead of running
        -- east as far as it can and stopping
        if canEast and ( not canSouth or width <= height ) then
            if width >= limits.perSide or ( ( width + 1 ) * height ) > limits.total then
                canEast = false

            elseif probeWholeColumn( cellGrid, ix + width, iy, height, seed, consumed, rowCellZs, width, limits.cellRise, pending ) then
                -- the new column becomes every row's east end, so it moves each row's own
                -- line and the east edge's line with it. Writing past width before that is
                -- checked is safe, nothing reads there unless the rectangle really grows
                local fits = true
                for ind = 1, height do
                    local row = rowCellZs[ind]
                    row[width + 1] = pending[ind].z
                    if not fitsLine( row, width + 1 ) then
                        fits = false
                        break

                    end
                end
                if fits and edgeFitsLine( rowCellZs, height, width + 1 ) then
                    claimCells( consumed, pending, height )
                    width = width + 1

                else
                    canEast = false

                end
            else
                -- growing south only adds cells to what this probe already couldn't
                -- find, so east never opens back up
                canEast = false

            end
        elseif height >= limits.perSide or ( width * ( height + 1 ) ) > limits.total then
            canSouth = false

        else
            local blocked = true
            if probeWholeRow( cellGrid, ix, iy + height, width, seed, consumed, rowCellZs[height][1], limits.cellRise, pending ) then
                local row = rowCellZs[height + 1]
                if not row then
                    row = {}
                    rowCellZs[height + 1] = row

                end
                for ind = 1, width do
                    row[ind] = pending[ind].z

                end
                -- the row has to sit on its own line, and both edges still on theirs
                if fitsLine( row, width ) and edgeFitsLine( rowCellZs, height + 1, 1 ) and edgeFitsLine( rowCellZs, height + 1, width ) then
                    blocked = nil

                end
            end
            if blocked then
                canSouth = false

            else
                claimCells( consumed, pending, width )
                height = height + 1

            end
        end
    end
    -- every pass above either claimed cells or retired a side, so this always ends
    return width, height

end

-- Covers the placed cells with as few rectangles as will hold them, for the caller to
-- build nav areas out of. Every cell ends up under exactly one of them.
local function greedyMergeCells( vecsToPlace )
    local cellGrid, minIx, maxIx, minIy, maxIy = buildCellGrid( vecsToPlace )
    if not cellGrid then return {} end

    local gridSize = patchTbl.gridSize
    -- in cells, so growing can measure itself against width and height directly
    local limits = {
        cellRise = gridSize * maxMergeSlope,
        perSide = math_max( 1, math.floor( maxMergedSide / gridSize ) ),
        total = math_max( 1, math.floor( maxMergedSurface / ( gridSize * gridSize ) ) ),

    }

    local consumed = {}
    local merged = {}
    local rowCellZs = {}
    local pending = {}

    -- Scan order alone hands the first rectangle whatever ground the scan reached first,
    -- and along an irregular edge that is a one cell fringe, so it grows into a strip and
    -- leaves more fringe behind it. Seeding where a square actually fits, largest square
    -- down, leaves the awkward shapes for last instead of building out of them.
    --
    -- Each threshold costs another walk of the grid, so halve it rather than step it.
    local threshold = 1
    local biggestSquare = math_min( limits.perSide, maxIx - minIx + 1, maxIy - minIy + 1 )
    while threshold * 2 <= biggestSquare do
        threshold = threshold * 2

    end

    while threshold >= 1 do
        for iy = minIy, maxIy do
            coroutine_yield()

            for ix = minIx, maxIx do
                local column = cellGrid[ix]
                local stack = column and column[iy]
                if not stack then continue end

                for _, seed in ipairs( stack ) do
                    -- an earlier pass, or an earlier rectangle in this one, already has it
                    if consumed[seed] then continue end
                    -- leave it for a smaller square. The threshold 1 pass has no test to
                    -- fail, so nothing is left behind at the end
                    if threshold > 1 and not fitsSquare( cellGrid, ix, iy, threshold, seed, consumed, limits.cellRise, rowCellZs, pending ) then continue end

                    -- growRect claims the rest as it probes, this one is on us
                    consumed[seed] = true

                    local width, height = growRect( cellGrid, ix, iy, seed, consumed, limits, rowCellZs, pending )

                    local corner1 = seed.corner1
                    local minX, minY = corner1.x, corner1.y
                    local maxX, maxY = minX + width * gridSize, minY + height * gridSize

                    -- all four, at the floor traced under each. CreateNavArea reads only
                    -- corner1 and corner2, so the caller has to put the others back
                    merged[#merged + 1] = {
                        corner1 = Vector( minX, minY, rowCellZs[1][1] ),
                        corner2 = Vector( maxX, maxY, rowCellZs[height][width] ),
                        northEast = Vector( maxX, minY, rowCellZs[1][width] ),
                        southWest = Vector( minX, maxY, rowCellZs[height][1] ),
                        crouch = seed.crouch,

                    }
                end
            end
        end
        threshold = math.floor( threshold / 2 )

    end

    return merged

end

local roundDec = 2

local function navGetBounds( area )
    return GetCorner( area, 0 ), GetCorner( area, 2 )

end

local function vecAsKey( vec )
    return math_Round( vec.x, roundDec ) .. math_Round( vec.y, roundDec ) .. math_Round( vec.z, roundDec )

end

local function vecAsKeyUnpacked( x, y, z )
    return math_Round( x, roundDec ) .. math_Round( y, roundDec ) .. math_Round( z, roundDec )

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
    gridSizeInternal = gridSizeInternal or patchTbl.gridSize
    gridOffsetInternal = gridOffsetInternal or patchTbl.gridOffset
    vec.x = ( math_Round( vec.x / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal
    vec.y = ( math_Round( vec.y / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal
    vec.z = ( math_Round( vec.z / gridSizeInternal ) * gridSizeInternal ) + gridOffsetInternal

end

terminator_Extras.SnapVecToGrid = SnapToGrid

local function GetSnappedToGrid( vec )
    local x = ( math_Round( vec.x / patchTbl.gridSize ) * patchTbl.gridSize ) + patchTbl.gridOffset
    local y = ( math_Round( vec.y / patchTbl.gridSize ) * patchTbl.gridSize ) + patchTbl.gridOffset
    local z = ( math_Round( vec.z / patchTbl.gridSize ) * patchTbl.gridSize ) + patchTbl.gridOffset
    return Vector( x, y, z )

end

local HEADROOM_NONE = 0
local HEADROOM_CROUCH = 1
local HEADROOM_STAND = 2

local function getHeadroom( voxel, solidVoxels )
    local clearCount = 0
    -- x/y never change per-call; pre-build their key halves so only z varies each iteration
    local keyX, keyY = voxel.x, voxel.y
    local gridSize = patchTbl.gridSize
    for ind = 1, patchTbl.headroomStand + 1 do
        local key = vecAsKeyUnpacked( keyX, keyY, math_Round( voxel.z + gridSize * ind, roundDec ) )
        if solidVoxels[key] then
            break
        else
            clearCount = clearCount + 1
        end
    end
    if clearCount >= patchTbl.headroomStand then return HEADROOM_STAND end
    if clearCount > patchTbl.headroomCrouch then return HEADROOM_CROUCH end

    return HEADROOM_NONE

end

-- Queue to store regions that need patching
terminator_Extras.regionsQueue = {}
local regionsQueue = terminator_Extras.regionsQueue

-- Flag to indicate if a patching process is currently running
local isPatching = false
hook.Remove( "Think", "PatchThinkHook" )

local noNavTextures = {
    ["tools/toolsnodraw"] = true,
    ["halflife/black"] = true,
    ["tools/toolsblack"] = true,

}

local function processVoxel( voxel, mins, _maxs, vecsToPlace, closedVoxels, headroomTbl, solidVoxels )
    local voxelsKey = vecAsKey( voxel )
    if not util_IsInWorld( voxel ) then
        solidVoxels[voxelsKey] = true
        closedVoxels[voxelsKey] = true
        return

    end

    local bottomOfBounds = tempVector( "processvoxelboundbottom", voxel.x, voxel.y, math_min( voxel.z, mins.z + -patchTbl.gridSize ) )
    patchTbl.trStrucInitial.start = voxel
    patchTbl.trStrucInitial.endpos = bottomOfBounds

    util.TraceHull( patchTbl.trStrucInitial )
    if patchTbl.initialResult.StartSolid then
        if debugging then
            debugoverlay.Cross( voxel, 5, 10, Color( 255, 0, 0 ), true )

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

    local hitPos = patchTbl.initialResult.HitPos
    local snapped = GetSnappedToGrid( hitPos )

    local dist = voxel:Distance( hitPos )
    local voxelsToToss = math.floor( dist / patchTbl.gridSize )
    if voxelsToToss >= 1 then -- skip voxels early if floor trace passed through them no issue
        if debugging then
            debugoverlay.Line( voxel, hitPos, 10, Color( 255, 0, 0 ), true )

        end
        for ind = 1, voxelsToToss do
            closedVoxels[vecAsKeyUnpacked( voxel.x, voxel.y, voxel.z - ind * patchTbl.gridSize )] = true

        end
    end
    if not patchTbl.initialResult.Hit then return end
    closedVoxels[vecAsKey( voxel )] = true

    local hitTexLower = string.lower( patchTbl.initialResult.HitTexture )
    if noNavTextures[hitTexLower] then return end -- dont place outside of maps
    if patchTbl.initialResult.HitSky then return end -- dont place on skybox, probably an "endless" pit

    -- slope check
    local hitNormal = patchTbl.initialResult.HitNormal
    if hitNormal:Dot( up ) < 0.5 then return end


    -- if this is a massive overhang, skip it
    -- will probably get patched up with a lower grid size pass later if needed
    local trStrucFindFloor = {
        start = hitPos + patchTbl.vecQuarterGridsizeZ,
        endpos = hitPos + -patchTbl.vecQuarterGridsizeZ,
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = filterFunc,

    }

    local floorResult = util.TraceLine( trStrucFindFloor )
    if not floorResult.Hit then return end


    -- is this inside a wall?
    local trStrucCollide = {
        start = hitPos + patchTbl.upCrouch,
        endpos = hitPos + patchTbl.upCrouch + up,
        mask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP ),
        filter = filterFunc,
        mins = patchTbl.collideTrMins,
        maxs = patchTbl.collideTrMaxs,

    }

    local collideResult = util.TraceHull( trStrucCollide )
    if collideResult.StartSolid then return end

    local defUnder, probUnder, upTrResult = patchTbl.posIsUnderDisplacement( hitPos )
    if defUnder or probUnder then return end

    local finalHeadroomDist = upTrResult.HitPos:Distance( hitPos )
    if finalHeadroomDist < patchTbl.headroomCrouchRaw then return end -- really tiny space

    local existingArea = navmesh.GetNearestNavArea( hitPos, false, patchTbl.halfGrid, false, true, -2 )
    if IsValid( existingArea ) then return end

    local existingAreas = navmesh.FindInBox( hitPos + patchTbl.finalAreaCheckMins, hitPos + patchTbl.finalAreaCheckMaxs )
    if existingAreas and #existingAreas >= 1 then
        for _, area in ipairs( existingAreas ) do
            local areasNearestToHit = area:GetClosestPointOnArea( hitPos )
            if areasNearestToHit:Distance2D( hitPos ) < patchTbl.gridSize * 0.5 then
                if debugging then
                    debugoverlay.Line( hitPos, areasNearestToHit, 10, Color( 255, 0, 0 ), true )

                end
                return -- area is too close to an existing area

            end
        end
    end

    local key = vecAsKey( snapped )
    local corner1 = hitPos + patchTbl.areaCenteringOffset
    vecsToPlace[key] = {
        key = key,
        truePos = hitPos,
        corner1 = corner1,
        corner2 = hitPos + patchTbl.oppCornerOffset,
        headroom = voxelsHeadroom,
        -- voxelsHeadroom was measured at voxel, which can sit many grid steps above the
        -- floor we're actually placing on. finalHeadroomDist is the clearance at hitPos
        crouch = finalHeadroomDist < patchTbl.headroomStandRaw,
        -- the voxel column's spot on the grid, so merging is integer work
        ix = math_Round( ( voxel.x - mins.x ) / patchTbl.gridSize ),
        iy = math_Round( ( voxel.y - mins.y ) / patchTbl.gridSize ),
        z = corner1.z,
        -- initialResult is reused by every trace, this has to be our own copy
        normal = Vector( hitNormal.x, hitNormal.y, hitNormal.z ),

    }

    if debugging then
        debugoverlay.Cross( hitPos, 5, 10, color_white, true )

    end
end

local oldGenCenter

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

        if oldGenCenter and patchTbl.gridSize < smallGridSize and oldGenCenter:Distance( newGenCenter ) < ( patchTbl.gridSize * 4 ) then -- we are stuck regenerating one point, try shuffling this
            local offset = math.random( -4, 4 )
            offset = offset * smallGridSize / 2

            patchTbl.gridOffset = smallGridSize / 2
            debugPrint( "Area generation is stuck, offsetting grid by " .. patchTbl.gridOffset )

        end

        local pos1 = VectorMin( region.pos1, region.pos2 )
        local pos2 = VectorMax( region.pos1, region.pos2 )
        SnapToGrid( pos1 )
        SnapToGrid( pos2 )

        oldGenCenter = newGenCenter

        debugPrint( "Patching region from", pos1, "to", pos2 )

        local closedVoxels = {} -- spots that we dont need to check
        local solidVoxels = {} -- solid spots
        local vecsToPlace = {} -- good spots we found
        local headroomTbl = {} -- headroom per voxel; unused for now, could be useful later
        local validatedAreas = {} -- all the areas we made this pass

        local sizeInX = pos2.x - pos1.x
        local sizeInY = pos2.y - pos1.y
        local sizeInZ = pos2.z - pos1.z

        -- iterate over the entire volume
        -- start from the top
        -- process each 'voxel'
        -- if solid, add to closedVoxels and solidVoxels
        -- check floor of voxel
        -- if below is clear, close all voxels until the floor
        -- and add floor to vecsToPlace with headroom info
        local zSteps = math.floor( sizeInZ / patchTbl.gridSize )
        for zInd = zSteps, 0, -1 do
            local z = zInd * patchTbl.gridSize
            coroutine_yield()

            for x = 0, sizeInX / patchTbl.gridSize do
                x = x * patchTbl.gridSize
                coroutine_yield()

                for y = 0, sizeInY / patchTbl.gridSize do
                    y = y * patchTbl.gridSize
                    local vx, vy, vz = pos1.x + x, pos1.y + y, pos1.z + z
                    local key = vecAsKeyUnpacked( vx, vy, vz )
                    if closedVoxels[key] then continue end

                    local voxel = Vector( vx, vy, vz )
                    coroutine_yield()
                    processVoxel( voxel, pos1, pos2, vecsToPlace, closedVoxels, headroomTbl, solidVoxels )
                    if debugging and IsValid( Entity( 1 ) ) and voxel:Distance( Entity( 1 ):GetPos() ) < 250 then
                        coroutine_yield( "wait" )

                    end
                end
            end
        end

        debugPrint( "Placing!" )

        if next( vecsToPlace ) then
            debugPrint( "Pre-merging areas..." )

            vecsToPlace = greedyMergeCells( vecsToPlace )

            local count = #vecsToPlace
            debugPrint( "Placing " .. count .. " navareas..." )

            local justNewAreas = {}
            local justNewAreasSeq = {}
            for _, data in pairs( vecsToPlace ) do
                coroutine_yield()
                if debugging then
                    debugoverlay.Cross( data.corner1, 5, 15, Color( 0, 255, 0 ), true )
                    debugoverlay.Cross( data.corner2, 5, 15, Color( 0, 255, 0 ), true )
                    debugoverlay.Cross( data.northEast, 3, 15, Color( 0, 200, 0 ), true )
                    debugoverlay.Cross( data.southWest, 3, 15, Color( 0, 200, 0 ), true )

                end
                local newArea = navmesh.CreateNavArea( data.corner1, data.corner2 )
                -- CreateNavArea leveled these two off against the corners it was handed,
                -- put the traced floor back under them. Only their heights differ from
                -- what it built, so the area keeps the footprint FindInBox indexed it by

                newArea:SetCorner( 0, data.corner1 )
                newArea:SetCorner( 1, data.northEast )
                newArea:SetCorner( 2, data.corner2 )
                newArea:SetCorner( 3, data.southWest )

                table.insert( justNewAreasSeq, newArea )
                justNewAreas[newArea] = true
                data.newArea = newArea
                if data.crouch then
                    newArea:AddAttributes( NAV_MESH_CROUCH )

                end
            end

            debugPrint( "Connecting placed areas..." )
            coroutine_yield( "wait" )

            local additionalSize = math_max( patchTbl.gridSize, smallGridSize )
            additionalSize = additionalSize * 0.95 -- bit smaller than grid size, so we dont connect over areas too far
            local additional = Vector( additionalSize, additionalSize, additionalSize )
            local upOff = patchTbl.upCrouch / 2

            for _, data in pairs( vecsToPlace ) do
                coroutine_yield()
                local newArea = data.newArea
                local mins, maxs = navGetBounds( newArea )
                for _, otherArea in ipairs( navmesh.FindInBox( mins + -additional, maxs + additional ) ) do
                    local trivialDist -- defaults to 5 in following navpatcher 
                    if not justNewAreas[otherArea] then
                        trivialDist = math_max( smallGridSize, patchTbl.gridSize ) -- not a new area, allow long connections!

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

            local mergedArea
            local merged = true
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
            local endOffset = Vector( 0, 0, patchTbl.headroomStandRaw )
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
                local noErrors, result = coroutine_resume( thread )
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
                    timer.Simple( 30, function() -- clean this up if patching stops
                        if terminator_Extras.IsLivePatching then return end
                        patchCleanup()

                    end )
                    break

                end
            end
        end
    end )
end

local function snapToNavmeshCornerIfFurther( toSnap, ref, tooFar )
    local area = navmesh.GetNearestNavArea( toSnap )
    if not area then return toSnap end

    local closestOnArea = area:GetClosestPointOnArea( toSnap )

    local originalDist = toSnap:Distance( ref )
    local distToArea = closestOnArea:Distance( ref )
    if distToArea < originalDist then return toSnap end -- its closer
    if closestOnArea:Distance( toSnap ) > tooFar then return toSnap end -- snap is too big

    return closestOnArea

end

local smallSize = Vector( 100, 100, 50 )
local bigSize = Vector( 175, 175, 100 )
local hugeSize = Vector( 500, 500, 150 )

-- add 1 region to patch queue around pos, choosing size and resolution based on existing nav areas nearby
function terminator_Extras.dynamicallyPatchPos( pos )
    if not doAreaPatching then return end
    if #regionsQueue >= 100 then return end -- don't let this blow up!

    local areasInSmallSize = navmesh.FindInBox( pos + -smallSize * 1.5, pos + smallSize * 1.5 )
    if areasInSmallSize and #areasInSmallSize >= 1 then
        local pos1 = pos + -smallSize
        local pos2 = pos + smallSize
        pos1 = snapToNavmeshCornerIfFurther( pos1, pos, smallGridSize * 8 )
        pos2 = snapToNavmeshCornerIfFurther( pos2, pos, smallGridSize * 8 )
        terminator_Extras.AddRegionToPatch( pos1, pos2, smallGridSize )

    else
        local areasInBigSize = navmesh.FindInBox( pos + -bigSize * 1.5, pos + bigSize * 1.5 )
        if areasInBigSize and #areasInBigSize >= 1 then
            local pos1 = pos + -bigSize
            local pos2 = pos + bigSize
            pos1 = snapToNavmeshCornerIfFurther( pos1, pos, 25 * 4 )
            pos2 = snapToNavmeshCornerIfFurther( pos2, pos, 25 * 4 )
            terminator_Extras.AddRegionToPatch( pos1, pos2, 25 )

        else
            local pos1 = pos + -hugeSize
            local pos2 = pos + hugeSize
            pos1 = snapToNavmeshCornerIfFurther( pos1, pos, 25 * 6 )
            pos2 = snapToNavmeshCornerIfFurther( pos2, pos, 25 * 6 )
            terminator_Extras.AddRegionToPatch( pos1, pos2, 25 )

        end
    end
end

-- Superadmin-only concommand to patch around the caller's eye trace position using smallSize and grid size 12.5, smallGridSize
concommand.Add( "terminator_areapatch_here", function( ply, _, args )
    if not IsValid( ply ) then return end -- must be a player
    if not ply:IsSuperAdmin() then
        if ply.ChatPrint then ply:ChatPrint( "Superadmin only." ) end
        return

    end

    local gridSize = tonumber( args[1] )
    local allowedExpansion = tonumber( args[2] )
    if not gridSize then
        gridSize = smallGridSize
        allowedExpansion = gridSize * 8

    elseif not allowedExpansion then
        allowedExpansion = gridSize * 4

    end

    local tr = ply:GetEyeTrace()
    if not tr or not tr.HitPos then return end

    local pos = tr.HitPos
    SnapToGrid( pos, gridSize, 0 )

    local pos1 = pos + -smallSize
    local pos2 = pos + smallSize
    pos1 = snapToNavmeshCornerIfFurther( pos1, pos, gridSize * 8 )
    pos2 = snapToNavmeshCornerIfFurther( pos2, pos, gridSize * 8 )
    terminator_Extras.AddRegionToPatch( pos1, pos2, gridSize )

    -- always show region being queued with a debug box
    local boxMins = -smallSize
    local boxMaxs = smallSize
    debugoverlay.Box( pos, boxMins, boxMaxs, 10, Color( 0, 255, 0, 10 ) )

    if debugging and ply.ChatPrint then
        ply:ChatPrint( "Queued nav patch at eye position (grid " .. gridSize .. ")." )

    end

end, nil, "Patch a nav region centered at your crosshair using smallSize and specified grid size (default " .. smallGridSize .. ", superadmin only)" )
