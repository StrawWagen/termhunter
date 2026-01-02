
resource.AddWorkshop( "2944078031" ) -- download pm please

local entMeta = FindMetaTable( "Entity" )
local plyMeta = FindMetaTable( "Player" )
local vecMeta = FindMetaTable( "Vector" )

local IsValid = IsValid
local negativeFiveHundredZ = Vector( 0,0,-500 )
local solidMask = bit.bor( MASK_SOLID, CONTENTS_MONSTERCLIP )
local vec_zero = Vector( 0, 0, 0 )

--[[--------------------------
    getNearestNav
    Get nearest navarea to pos
    @param pos Vector
    @return navarea Entity or NULL if something goes wrong
--]]--------------------------
terminator_Extras.getNearestNav = function( pos )
    if not pos then return NULL end
    local navArea = navmesh.GetNearestNavArea( pos, false, 2000, false, false, -2 )
    if not IsValid( navArea ) then return NULL end
    return navArea
end

--[[--------------------------
    getNearestNavFloor
    Snaps the pos to the floor, then gets the nearest navarea
    @param pos Vector
    @return navarea Entity or NULL
--]]--------------------------
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
    if not IsValid( navArea ) then return NULL end
    return navArea
end

--[[--------------------------
    getNearestPosOnNav
    Returns data about the nearest position on the navmesh to the given pos.
    @param pos Vector
    @return table { pos = Vector, area = NavArea }
--]]--------------------------
terminator_Extras.getNearestPosOnNav = function( pos )
    local result = { pos = nil, area = NULL }
    if not pos then return result end

    local navFound = terminator_Extras.getNearestNav( pos )

    if not IsValid( navFound ) then return result end

    result.pos = navFound:GetClosestPointOnArea( pos )
    result.area = navFound
    return result

end

--[[--------------------------
    dirToPos
    Returns a normalized direction vector from startPos to endPos
    @param startPos Vector
    @param endPos Vector
    @return Vector
--]]--------------------------
terminator_Extras.dirToPos = function( startPos, endPos )
    if not startPos then return vec_zero end
    if not endPos then return vec_zero end

    local subtProduct = endPos - startPos
    vecMeta.Normalize( subtProduct )
    return subtProduct

end

local rad2deg = 180 / math.pi
-- these methods are from e2 core functions, good stuff

terminator_Extras.BearingToPos = function( pos1, ang1, pos2, ang2 )
    local localPos = WorldToLocal( pos1, ang1, pos2, ang2 )
    local bearing = rad2deg * math.atan2( localPos.y, localPos.x )

    return bearing

end

terminator_Extras.PitchToPos = function( pos1, ang1, pos2, ang2 )
    local localPos = WorldToLocal( pos1, ang1, pos2, ang2 )

    local len = localPos:Length()
    if len < 0 then return 0 end
    return rad2deg * math.asin(localPos.z / len)

end

--[[--------------------------
    posIsInterrupting
    Checks if the position would "interrupt" any player.
    @param pos Vector
    @param yieldable boolean (optional) - set this to true if calling from within a coroutine
    @return boolean, Player - true if interrupting, Player who is interrupting
--]]--------------------------
local coroutine_yield = coroutine.yield
terminator_Extras.posIsInterrupting = function( pos, yieldable )
    for _, ply in player.Iterator() do
        if yieldable then
            coroutine_yield()

        end
        local viewEnt = plyMeta.GetViewEntity( ply )
        local shoot = plyMeta.GetShootPos( ply )
        local viewPos
        local interrupting = vecMeta.DistToSqr( shoot, pos ) < 1000^2
        if IsValid( viewEnt ) and viewEnt ~= ply then
            viewPos = viewEnt:WorldSpaceCenter()
            interrupting = interrupting or viewPos:DistToSqr( pos ) < 1000^2

        else
            viewPos = shoot

        end

        if interrupting or terminator_Extras.PosCanSee( pos, viewPos ) then
            return true, ply

        end
    end
end

--[[--------------------------
    posIsInterruptingAlive
    same as above, but only checks players who are alive
--]]--------------------------
local recentlyDied = {}
local usingInterruptingAlive
terminator_Extras.posIsInterruptingAlive = function( pos, yieldable )
    if not usingInterruptingAlive then
        hook.Add( "PlayerDeath", "terminatorhelpers_posIsInterupptingAlive", function( ply )
            if not IsValid( ply ) then return end
            recentlyDied[ply] = true
            timer.Simple( 8, function() -- dont spoil it when they die
                recentlyDied[ply] = nil

            end )
        end )
        recentlyDied = {}
        usingInterruptingAlive = true

    end
    for _, ply in player.Iterator() do
        if ( entMeta.Health( ply ) <= 0 ) and not recentlyDied[ply] then continue end -- only check alive players
        if yieldable then
            coroutine_yield()

        end
        local viewEnt = plyMeta.GetViewEntity( ply )
        local shoot = plyMeta.GetShootPos( ply )
        local viewPos
        local interrupting = vecMeta.DistToSqr( shoot, pos ) < 1000^2
        if IsValid( viewEnt ) and viewEnt ~= ply then
            viewPos = viewEnt:WorldSpaceCenter()
            interrupting = interrupting or viewPos:DistToSqr( pos ) < 1000^2

        else
            viewPos = shoot

        end

        if interrupting or terminator_Extras.PosCanSee( pos, viewPos ) then
            return true, ply

        end
    end
end

--[[--------------------------
    areaIsInterruptingSomeone
    Same as above, but checks an area instead.
    @param area NavArea
    @param areasCenter Vector (optimisation) - center of the area, defaults to area:GetCenter()
    @param yieldable boolean (optional) - set this to true if calling from within a coroutine
    @return boolean, Player - true if interrupting, Player who is interrupting
--]]--------------------------
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
            return true, ply

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
    permaPrintTable( biggest )
    permaPrint( biggestKey )
    permaPrint( biggestSize )
    permaPrintTable( counts )

end--]]

local bigNegativeZ = Vector( 0, 0, -3000 )
local startOffset = Vector( 0, 0, 100 )
local function getFloorTr( pos )
    local traceDat = {
        mask = bit.bor( MASK_SOLID_BRUSHONLY, CONTENTS_MONSTERCLIP ),
        start = pos + startOffset,
        endpos = pos + bigNegativeZ
    }

    local trace = util.TraceLine( traceDat )
    return trace

end
terminator_Extras.getFloorTr = getFloorTr


local bigPositiveZ = Vector( 0, 0, 3000 )
local function getSkyTr( pos )
    local traceDat = {
        mask = bit.bor( MASK_SOLID_BRUSHONLY, CONTENTS_MONSTERCLIP ),
        start = pos,
        endpos = pos + bigPositiveZ
    }

    local trace = util.TraceLine( traceDat )
    return trace

end
terminator_Extras.getSkyTr = getSkyTr

--[[--------------------------
    posIsDisplacement
    Checks if the position is on a displacement.
    @param pos Vector
    @return boolean - true if on a displacement, nil if not
--]]--------------------------
local function posIsDisplacement( pos )
    local tr = getFloorTr( pos )
    if not tr then return end
    if tr.HitTexture ~= "**displacement**" then return end
    return true

end
terminator_Extras.posIsDisplacement = posIsDisplacement

--[[--------------------------
    areaIsEntirelyOverDisplacements
    Checks if the area is entirely over displacements.
    @param area NavArea
    @return boolean - true if all corners are over displacements, nil if not
--]]--------------------------
terminator_Extras.areaIsEntirelyOverDisplacements = function( area )
    local positions = {
        area:GetCorner( 0 ),
        area:GetCorner( 1 ),
        area:GetCorner( 2 ),
        area:GetCorner( 3 ),

    }
    for _, position in ipairs( positions ) do
        -- if just 1 of these is not on a displacement, then return nil
        if not posIsDisplacement( position ) then return end

    end
    -- every corner passed the check
    return true

end

--[[--------------------------
    TeleportTermTo
    Helper that 'safely' teleports a term npc to a position, kills the coroutine so any in-progress stuff won't setpos it back
    @param term Entity
    @param pos Vector
--]]--------------------------
terminator_Extras.TeleportTermTo = function( term, pos )
    term:SetPosNoTeleport( pos ) -- set their pos without triggering clientside velocity bug
    term:RestartMotionCoroutine() -- kill any logic that's about to set our pos
    term:StopMoving() -- stop movement, reject path updates, start the movement_wait task

end

--[[--------------------------
    recipFilterAllTargetablePlayers
    Returns a recipient filter with all players who are targetable (not flagged as notarget)
    @return RecipientFilter
--]]--------------------------
terminator_Extras.recipFilterAllTargetablePlayers = function()
    local targetablePlayers = {}
    for _, ply in player.Iterator() do
        if ply:IsFlagSet( FL_NOTARGET ) then continue end
        table.insert( targetablePlayers, ply )

    end

    local filter = RecipientFilter()
    filter:AddPlayers( targetablePlayers )
    return filter

end