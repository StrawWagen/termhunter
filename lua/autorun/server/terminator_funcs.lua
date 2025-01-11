
resource.AddWorkshop( "2944078031" ) -- download pm please

local negativeFiveHundredZ = Vector( 0,0,-500 )
local solidMask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP )
local vec_zero = Vector( 0, 0, 0 )

terminator_Extras.getNearestNavFloor = function( pos )
    if not pos then return NULL end
    local Dat = {
        start = pos,
        endpos = pos + negativeFiveHundredZ,
        mask = solidMask
    }
    local Trace = util.TraceLine( Dat )
    if not Trace.HitWorld then return NULL end
    local navArea = navmesh.GetNearestNavArea( Trace.HitPos, false, 2000, false, false, -2 )
    if not navArea then return NULL end
    if not navArea:IsValid() then return NULL end
    return navArea
end

terminator_Extras.getNearestNav = function( pos )
    if not pos then return NULL end
    local Dat = {
        start = pos,
        endpos = pos + negativeFiveHundredZ,
        mask = solidMask
    }
    local Trace = util.TraceLine( Dat )
    if not Trace.Hit then return NULL end
    local navArea = navmesh.GetNearestNavArea( pos, false, 2000, false, false, -2 )
    if not navArea then return NULL end
    if not navArea:IsValid() then return NULL end
    return navArea
end

terminator_Extras.getNearestPosOnNav = function( pos )
    local result = { pos = nil, area = NULL }
    if not pos then return result end

    local navFound = terminator_Extras.getNearestNav( pos )

    if not navFound then return result end
    if not navFound:IsValid() then return result end

    result = { pos = navFound:GetClosestPointOnArea( pos ), area = navFound }
    return result

end

terminator_Extras.dirToPos = function( startPos, endPos )
    if not startPos then return vec_zero end
    if not endPos then return vec_zero end

    return ( endPos - startPos ):GetNormalized()

end

terminator_Extras.BearingToPos = function( pos1, ang1, pos2, ang2 )
    local localPos = WorldToLocal( pos1, ang1, pos2, ang2 )
    local bearing = 180 / math.pi * math.atan2( localPos.y, localPos.x )

    return bearing

end

local coroutine_yield = coroutine.yield

terminator_Extras.posIsInterrupting = function( pos, yieldable )
    for _, ply in player.Iterator() do
        if yieldable then
            coroutine_yield()

        end
        local viewEnt = ply:GetViewEntity()
        local shoot = ply:GetShootPos()
        local viewPos
        local interrupting = shoot:DistToSqr( pos ) < 1000^2
        if IsValid( viewEnt ) and viewEnt ~= ply then
            viewPos = viewEnt:WorldSpaceCenter()
            interrupting = interrupting or viewPos:DistToSqr( pos ) < 1000^2

        else
            viewPos = shoot

        end

        if interrupting or terminator_Extras.PosCanSee( pos, viewPos ) then
            return true

        end
    end
end

terminator_Extras.areaIsInterruptingSomeone = function( area, areasCenter, yieldable )
    areasCenter = areasCenter or area:GetCenter()

    for _, ply in player.Iterator() do
        if yieldable then
            coroutine_yield()

        end
        local viewEnt = ply:GetViewEntity()
        local shoot = ply:GetShootPos()
        local viewPos
        local interrupting = shoot:DistToSqr( areasCenter ) < 1000^2
        if IsValid( viewEnt ) and viewEnt ~= ply then
            viewPos = viewEnt:WorldSpaceCenter()
            interrupting = interrupting or viewPos:DistToSqr( areasCenter ) < 1000^2

        else
            viewPos = shoot

        end
        if interrupting or area:IsVisible( viewPos ) then
            return true

        end
    end
end

--[[ find memory leaks!
for _, ent in ipairs( ents.FindByClass( "terminator_nextbot*" ) ) do
    local biggestSize = 0
    local biggestKey
    local biggest
    local counts = {}
    for key, value in pairs( ent:GetTable() ) do
        if not istable( value ) then continue end
        local count = table.Count( value )

        counts[key] = count

        if istable( value ) and count > biggestSize then
            biggestSize = count
            biggestKey = key
            biggest = value

        end
    end
    PrintTable( biggest )
    print( biggestKey )
    print( biggestSize )
    PrintTable( counts )

end--]]