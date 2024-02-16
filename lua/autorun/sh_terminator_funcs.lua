
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
    local hitSomething = trace.Hit or trace.StartSolid
    return not hitSomething, trace

end