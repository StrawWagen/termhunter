
AddCSLuaFile()

terminator_Extras = terminator_Extras or {}

terminator_Extras.healthDefault = 900 -- shared, for GLEE
terminator_Extras.MDLSCALE_LARGE = 1.2
terminator_Extras.baseCoroutineThresh = 0.003 -- base coroutine thresh, so you can make your bot's thresh 0.1x the default thresh or something

local entMeta = FindMetaTable( "Entity" )

local IsValid = IsValid
local table_insert = table.insert
local bit_bor = bit.bor
local math_abs = math.abs

-- not localizing trace funcs

local posCanSeeTrData = {}

terminator_Extras.PosCanSee = function( startPos, endPos, mask )
    if not startPos then return end
    if not endPos then return end

    mask = mask or terminator_Extras.LineOfSightMask

    posCanSeeTrData.start = startPos
    posCanSeeTrData.endpos = endPos
    posCanSeeTrData.mask = mask

    local trace = util.TraceLine( posCanSeeTrData )
    return not trace.Hit, trace

end

local posCanSeeHullTrData = {}

terminator_Extras.PosCanSeeHull = function( startPos, endPos, mask, hull )
    if not startPos then return end
    if not endPos then return end

    mask = mask or terminator_Extras.LineOfSightMask

    posCanSeeHullTrData.start = startPos
    posCanSeeHullTrData.endpos = endPos
    posCanSeeHullTrData.mask = mask
    posCanSeeHullTrData.mins = -hull
    posCanSeeHullTrData.maxs = hull

    local trace = util.TraceHull( posCanSeeHullTrData )
    return not trace.Hit, trace

end

local cachedFilters

terminator_Extras.PosCanSeeComplex = function( startPos, endPos, filter, mask )
    if not startPos then return end
    if not endPos then return end

    local filterTbl = filter
    local collisiongroup = nil

    if IsValid( filter ) then
        if not cachedFilters then
            cachedFilters = {}
            timer.Simple( 1, function()
                cachedFilters = nil -- don't stick around

            end )
        end

        filterTbl = cachedFilters[filter]

        if not filterTbl then
            filterTbl = { filter }
            for _, child in ipairs( entMeta.GetChildren( filter ) ) do
                table_insert( filterTbl, child )

            end
            cachedFilters[filter] = filterTbl

        end

        collisiongroup = entMeta.GetCollisionGroup( filter )

    end

    if not mask then
        mask = bit_bor( CONTENTS_SOLID, CONTENTS_HITBOX )

    end

    local traceData = {
        filter = filterTbl,
        start = startPos,
        endpos = endPos,
        mask = mask,
        collisiongroup = collisiongroup,
    }
    local trace = util.TraceLine( traceData )
    local hitSomething = trace.Hit or trace.StartSolid
    return not hitSomething, trace

end

local nookDirections = {
    Vector( 1, 0, 0 ),
    Vector( -1, 0, 0 ),
    Vector( 0, 1, 0 ),
    Vector( 0, -1, 0 ),
    Vector( 0, 0, 1 ),
    Vector( 0, 0, -1 ),

}

-- returns SMALL numbers in open areas
-- returns BIG numbers in NOOKS, enclosed spaces
terminator_Extras.GetNookScore = function( pos, distance, overrideDirections )
    local directions = overrideDirections or nookDirections
    distance = distance or 800

    local traceData = {
        mask = MASK_SOLID_BRUSHONLY,
        start = pos,
    }
    local facesBlocked = 0
    local hits = {}
    for _, direction in ipairs( directions ) do
        traceData.endpos = pos + direction * distance
        local trace = util.TraceLine( traceData )

        local fraction
        if not trace.Hit then
            fraction = 1

        elseif trace.HitSky then -- its not a nook if its NEXT TO THE SKYBOX!!!
            fraction = 1

        else
            fraction = trace.Fraction

        end

        hits[fraction] = trace -- lol if this is 

        local isNookScore = fraction - 1 -- so facesblocked is higher when this is in small spaces
        facesBlocked = facesBlocked + math_abs( isNookScore )

    end

    return facesBlocked, hits

end


local vector6000ZUp = Vector( 0, 0, 6000 )
local vector1000ZDown = Vector( 0, 0, -1000 )

-- takes pos
-- returns definitelyUnderDisplacement, maybeUnderDisplacement, firstTraceResult
-- ret1 is definitive, never fails
-- ret2 had to be added because of some edge case i cant remember, i think displacements on top of displacements
-- ret3 is if you want to do stuff with the first trace result
-- good to do like, underDisplacement = ret1 or ret2

terminator_Extras.posIsUnderDisplacement = function( pos, dir )
    -- get the sky
    local firstTraceDat = {
        start = pos,
        endpos = pos + ( dir and dir * 6000 or vector6000ZUp ),
        mask = MASK_SOLID_BRUSHONLY,
    }
    local firstTraceResult = util.TraceLine( firstTraceDat )

    -- go back down
    local secondTraceDat = {
        start = firstTraceResult.HitPos,
        endpos = pos,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local secondTraceResult = util.TraceLine( secondTraceDat )
    if secondTraceResult.HitTexture ~= "**displacement**" then return nil, nil, firstTraceResult end

    -- final check to make sure
    local thirdTraceDat = {
        start = pos,
        endpos = pos + ( dir and dir * -1000 or vector1000ZDown ),
        mask = MASK_SOLID_BRUSHONLY,
    }
    local thirdTraceResult = util.TraceLine( thirdTraceDat )
    if thirdTraceResult.HitTexture ~= "TOOLS/TOOLSNODRAW" then return nil, true, firstTraceResult end -- we are probably under a displacement

    -- we are DEFINITely under one
    return true, nil, firstTraceResult

end

function terminator_Extras.copyMatsOver( from, to )
    for ind = 0, #from:GetMaterials() do
        local mat = from:GetSubMaterial( ind )
        if mat and mat ~= "" then
            to:SetSubMaterial( ind, mat )

        end
    end
    local myMat = from:GetMaterial()
    if myMat and myMat ~= "" then
        to:SetMaterial( myMat )

    end
end

function permaPrint( ... ) -- literally only exists so i can ctrl-f " print" to find stray debug prints
    print( ... )

end

function permaPrintTable( ... ) -- ditto
    PrintTable( ... )

end