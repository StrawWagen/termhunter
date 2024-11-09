
AddCSLuaFile()

terminator_Extras = terminator_Extras or {}

terminator_Extras.PosCanSee = function( startPos, endPos, mask )
    if not startPos then return end
    if not endPos then return end

    mask = mask or terminator_Extras.LineOfSightMask

    local trData = {
        start = startPos,
        endpos = endPos,
        mask = mask,
    }
    local trace = util.TraceLine( trData )
    return not trace.Hit, trace

end

terminator_Extras.PosCanSeeComplex = function( startPos, endPos, filter, mask )
    if not startPos then return end
    if not endPos then return end

    local filterTbl = {}
    local collisiongroup = nil

    if IsValid( filter ) then
        filterTbl = filter:GetChildren()
        table.insert( filterTbl, filter )

        collisiongroup = filter:GetCollisionGroup()

    end

    if not mask then
        mask = bit.bor( CONTENTS_SOLID, CONTENTS_HITBOX )

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

    local facesBlocked = 0
    local hits = {}
    for _, direction in ipairs( directions ) do
        local traceData = {
            start = pos,
            endpos = pos + direction * distance,
            mask = MASK_SOLID_BRUSHONLY,

        }

        local trace = util.TraceLine( traceData )
        if not trace.Hit then continue end

        hits[trace.Fraction] = trace

        facesBlocked = facesBlocked + math.abs( trace.Fraction - 1 )

    end

    return facesBlocked, hits

end