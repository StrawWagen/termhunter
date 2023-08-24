

terminator_Extras.dirToPos = function( startPos, endPos )
    if not startPos then return end
    if not endPos then return end

    return ( endPos - startPos ):GetNormalized()

end

terminator_Extras.GetNookScore = function( pos, distance, overrideDirections )
    local directions = overrideDirections or nookDirections
    distance = distance or 800
    local facesBlocked = 0
    for _, direction in ipairs( directions ) do
        local traceData = {
            start = pos,
            endpos = pos + direction * distance,
            mask = MASK_SOLID_BRUSHONLY,

        }

        local trace = util.TraceLine( traceData )
        if not trace.Hit then continue end

        facesBlocked = facesBlocked + math.abs( trace.Fraction - 1 )

    end

    return facesBlocked

end

terminator_Extras.BearingToPos = function( pos1, ang1, pos2, ang2 )
    local localPos = WorldToLocal( pos1, ang1, pos2, ang2 )
    local bearing = 180 / math.pi * math.atan2( localPos.y, localPos.x )

    return bearing

end

terminator_Extras.PosCanSee = function( startPos, endPos )
    if not startPos then return end
    if not endPos then return end

    local mask = {
        start = startPos,
        endpos = endPos,
        mask = LineOfSightMask
    }
    local trace = util.TraceLine( mask )
    return not trace.Hit, trace

end

terminator_Extras.PosCanSeeComplex = function( startPos, endPos, filter, mask )
    if not startPos then return end
    if not endPos then return end

    local filterTbl = {}
    local collisiongroup = nil

    if IsValid( filter ) then
        filterTbl = table.Copy( filter:GetChildren() )
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
    return not trace.Hit, trace

end