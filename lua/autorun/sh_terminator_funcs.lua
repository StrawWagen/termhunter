
AddCSLuaFile()

terminator_Extras = terminator_Extras or {}

terminator_Extras.healthDefault = 900 -- shared, for GLEE
terminator_Extras.MDLSCALE_LARGE = 1.2
terminator_Extras.baseCoroutineThresh = 0.05 -- base coroutine thresh, so you can make your bot's thresh 0.1x the default thresh or something

local entMeta = FindMetaTable( "Entity" )
local areaMeta = FindMetaTable( "CNavArea" )

local IsValid = IsValid
local table_insert = table.insert
local bit_bor = bit.bor
local math_abs = math.abs

local vecUpOff = Vector( 0, 0, 25 )

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
-- arg1: pos to test
-- arg2: distance to trace, default 800
-- arg3: optional override directions table
-- ret1: nook score, 6 is fully enclosed(never happens in playable space), 0 is fully open(never happens, the floor counts too)
-- ret2: table of all the traces, key is fraction for easy sorting, so bigger ones went further, smaller ones hit closer
local GetNookScore = function( pos, distance, overrideDirections )
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

        hits[fraction] = trace -- lol if two of them are the same fraction

        local isNookScore = fraction - 1 -- so facesblocked is higher when this is in small spaces
        facesBlocked = facesBlocked + math_abs( isNookScore )

    end

    return facesBlocked, hits

end
terminator_Extras.GetNookScore = GetNookScore


-- takes area
-- returns & caches nook score of it's center

local nookScoreCache = {}
terminator_Extras.GetAreasNookScore_nookScoreCache = nookScoreCache
local managingCache

terminator_Extras.GetAreasNookScore = function( area )
    if not managingCache then
        managingCache = true
        timer.Simple( 60 * 5, function()
            nookScoreCache = {}
            terminator_Extras.GetAreasNookScore_nookScoreCache = nookScoreCache
            managingCache = nil

        end )
    end
    local cached = nookScoreCache[area]
    if cached then return cached end
    local score = GetNookScore( areaMeta.GetCenter( area ) + vecUpOff )

    nookScoreCache[area] = score
    return score

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

local LocalToWorld = LocalToWorld

function terminator_Extras.DrawInHand( wep, posOffset, angOffset )
    local owner = wep:GetOwner()
    if IsValid( owner ) and owner:GetActiveWeapon() == wep then
        local attachId = owner:LookupAttachment( "anim_attachment_RH" )
        if attachId <= 0 then return end
        local attachTbl = owner:GetAttachment( attachId )
        local posOffsetW, angOffsetW = LocalToWorld( posOffset, angOffset, attachTbl.Pos, attachTbl.Ang )
        wep:SetPos( posOffsetW )
        wep:SetAngles( angOffsetW )

        wep:SetupBones()

    end
end

-- table.Add without saftey checks, without using table.insert
function terminator_Extras.tableAdd( dest, source )
    for _, thing in pairs( source ) do
        dest[#dest + 1] = thing

    end
end

-- simple sequential table copier
function terminator_Extras.tableCopySimple( source )
    local new = {}
    for _, v in ipairs( source ) do
        new[#new + 1] = v

    end
    return new

end