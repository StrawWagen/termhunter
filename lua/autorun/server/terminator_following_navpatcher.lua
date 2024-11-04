
terminator_Extras = terminator_Extras or {}

local doFollowingPatchingVar = CreateConVar( "terminator_followpatcher_enable", 1, FCVAR_ARCHIVE, "Patches the navmesh as players wander the map, Leads to terminators feeling smarter, following you through windows. Only runs with at least 1 bot spawned." )
local maxPlysToPatch = CreateConVar( "terminator_followpatcher_maxplys", 4, FCVAR_ARCHIVE, "Max amount of plys to process at a time, the system always prioritizes players being actively chased." )
local debuggingVar = CreateConVar( "terminator_followpatcher_debug", 0, FCVAR_ARCHIVE, "Debug the following patcher." )

local doFollowingPatching = doFollowingPatchingVar:GetBool()
cvars.AddChangeCallback( "terminator_followpatcher_enable", function( _, _, new )
    doFollowingPatching = tobool( new )

end, "updatepatching" )

local debugging = debuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_followpatcher_debug", function( _, _, new )
    debugging = tobool( new )

end, "updatedebugging" )

local function debugPrint( ... )
    if not debugging then return end
    print( ... )

end

local function lineBetween( area1, area2 )
    if not debugging then return end
    debugoverlay.Line( area1:GetCenter(), area2:GetCenter(), 10, Color( 255, 0, 0 ), true )

end

local upTen = Vector( 0, 0, 10 )
local upOffset = Vector( 0, 0, 25 )

local function connectionDistance( currArea, otherArea )
    local currCenter = currArea:GetCenter()

    local nearestInitial = otherArea:GetClosestPointOnArea( currCenter )
    local nearestFinal   = currArea:GetClosestPointOnArea( nearestInitial )
    nearestFinal.z = nearestInitial.z
    local distTo   = nearestInitial:Distance( nearestFinal )
    return distTo, nearestFinal, nearestInitial

end

terminator_Extras.connectionDistance = connectionDistance

local function distanceEdge( currArea, otherArea )
    local currCenter = currArea:GetCenter()

    local nearestInitial    = otherArea:GetClosestPointOnArea( currCenter )
    local nearestFinal      = currArea:GetClosestPointOnArea( nearestInitial )
    local distTo            = nearestInitial:Distance( nearestFinal )
    return distTo

end

local function goodDist( distTo )
    if distTo <= 5 then return true end

    local distQuota = 75
    local minCheck = -1
    local maxCheck = 1

    while distQuota < 400 do
        local min = distQuota + minCheck
        local max = distQuota + maxCheck

        if distTo > min and distTo < max then return true end
        distQuota = distQuota + 25

    end

    return nil

end

local math_min = math.min
local math_max = math.max

local function AreasHaveAnyOverlap( area1, area2 ) -- i love chatgpt functions
    -- Get corners of both areas
    local area1Corner1 = area1:GetCorner( 0 )
    local area1Corner2 = area1:GetCorner( 2 )
    local area2Corner1 = area2:GetCorner( 0 )
    local area2Corner2 = area2:GetCorner( 2 )

    -- Determine bounds of the areas
    local area1MinX = math_min( area1Corner1.x, area1Corner2.x )
    local area1MaxX = math_max( area1Corner1.x, area1Corner2.x )
    local area1MinY = math_min( area1Corner1.y, area1Corner2.y )
    local area1MaxY = math_max( area1Corner1.y, area1Corner2.y )

    local area2MinX = math_min( area2Corner1.x, area2Corner2.x )
    local area2MaxX = math_max( area2Corner1.x, area2Corner2.x )
    local area2MinY = math_min( area2Corner1.y, area2Corner2.y )
    local area2MaxY = math_max( area2Corner1.y, area2Corner2.y )

    -- Check for overlap on X or Y axis
    local xOverlap = ( area1MinX <= area2MaxX and area1MaxX >= area2MinX )
    local yOverlap = ( area1MinY <= area2MaxY and area1MaxY >= area2MinY )

    return xOverlap or yOverlap

end

local function AreasAreConnectable( area1, area2, checkOffs )
    if area1:IsConnected( area2 ) then return end -- already connected....
    if not AreasHaveAnyOverlap( area1, area2 ) then return end
    checkOffs = checkOffs or upOffset
    if not area1:IsPartiallyVisible( area2:GetClosestPointOnArea( area1:GetCenter() ) + checkOffs ) then return end
    if not goodDist( connectionDistance( area1, area2 ) ) then return end
    return true

end

terminator_Extras.AreasAreConnectable = AreasAreConnectable


-- do checks to see if connection from old area to curr area is a good idea
function terminator_Extras.smartConnectionThink( oldArea, currArea, simple )
    if oldArea:IsConnected( currArea ) then debugPrint( "5" ) return end

    -- get dist flat, no z component
    local distTo = connectionDistance( oldArea, currArea )

    if distTo > 55 and not goodDist( distTo ) then debugPrint( "6" ) return end

    -- check if there's a simple-ish way from oldArea to currArea
    -- dont create a new connection if there is
    if not simple then

        local oldsNearestToCurr = oldArea:GetClosestPointOnArea( currArea:GetCenter() )
        local currsNearestToOld = currArea:GetClosestPointOnArea( oldsNearestToCurr )
        local distFunc
        if math.abs( oldsNearestToCurr.z - currsNearestToOld.z ) > 50 then
            distFunc = connectionDistance

        else
            distFunc = distanceEdge

        end

        local returnBlacklist = {}
        for _, area in ipairs( currArea:GetAdjacentAreas() ) do
            returnBlacklist[area] = true

        end

        local smallestDist = distFunc( oldArea, currArea )
        local potentiallyBetterConnections = {}
        local doneAlready = {}

        for _, firstLayer in ipairs( oldArea:GetAdjacentAreas() ) do
            if returnBlacklist[firstLayer] and distFunc( firstLayer, currArea ) <= smallestDist then
                lineBetween( firstLayer, currArea )
                debugPrint( "7" )
                return

            end

            table.insert( potentiallyBetterConnections, firstLayer )
            doneAlready[firstLayer] = true

            for _, secondLayer in ipairs( firstLayer:GetAdjacentAreas() ) do
                if doneAlready[secondLayer] then continue end
                table.insert( potentiallyBetterConnections, secondLayer )
                doneAlready[secondLayer] = true

                for _, thirdLayer in ipairs( secondLayer:GetAdjacentAreas() ) do
                    if doneAlready[thirdLayer] then continue end
                    table.insert( potentiallyBetterConnections, thirdLayer )
                    doneAlready[thirdLayer] = true

                end
            end
        end

        local smallestDistArea = nil
        for _, area in ipairs( potentiallyBetterConnections ) do
            if AreasAreConnectable( area, currArea ) then
                local currDist = distFunc( area, currArea )
                if currDist < smallestDist then
                    smallestDistArea = area
                    smallestDist = currDist

                end
            end
        end
        if smallestDistArea and smallestDistArea ~= oldArea then
            debugPrint( "8" )
            lineBetween( smallestDistArea, currArea )
            return

        end
    end

    if hook.Run( "terminator_navpatcher_blockpatch", oldArea, currArea ) == true then return end

    oldArea:ConnectTo( currArea )
    hook.Run( "terminator_navpatcher_patched", oldArea, currArea )

    return true

end

local smallSize = Vector( 100, 100, 75 )

local function onNoArea( ply )
    if terminator_Extras.IsLivePatching then return end
    if not ply:IsOnGround() then return end

    local groundEnt = ply:GetGroundEntity()
    if not groundEnt then return end
    if not groundEnt:IsWorld() then return end

    local nextPlace = ply.term_NextRealPatchPlace or 0
    if nextPlace > CurTime() then return end

    ply.term_NextRealPatchPlace = CurTime() + 1

    local plyPos = ply:GetPos()
    local minGrid = 50
    if ply:Crouching() and ply:GetVelocity():Length() < 225 then
        terminator_Extras.AddRegionToPatch( plyPos + -smallSize, plyPos + smallSize, 11.25 )
        return

    end
    terminator_Extras.dynamicallyPatchPos( plyPos, minGrid )

end

-- patches gaps in navmesh, using players as a guide
-- patches will never be ideal, but they will be better than nothing

local flattener = Vector( 1, 1, 0.5 )
local tooFarDistSqr = 40^2

local function navPatchingThink( ply )

    local badMovement = ply:GetMoveType() == MOVETYPE_NOCLIP or ply:Health() <= 0 or ply:GetObserverMode() ~= OBS_MODE_NONE or ply:InVehicle()

    if badMovement then
        ply.term_PatchingData = nil
        ply.oldPatchingArea = nil
        return

    end

    local currArea, distToArea
    if ply.GetNavAreaData then
        currArea, distToArea = ply:GetNavAreaData()
        if not IsValid( currArea ) then onNoArea( ply ) return end

    else
        local plyPos = ply:GetPos()
        currArea = navmesh.GetNearestNavArea( plyPos, false, 15, false, true, -2 )
        if not IsValid( currArea ) then onNoArea( ply ) return end
        if not terminator_Extras.IsLivePatching and math.random( 0, 100 ) < 5 and ply:GetVelocity():Length() > 100 then
            local aheadPos = plyPos + ( ply:GetVelocity() * flattener ):GetNormalized() * 250
            if util.IsInWorld( aheadPos ) and terminator_Extras.PosCanSee( plyPos, aheadPos ) then
                local aheadArea = navmesh.GetNearestNavArea( aheadPos, false, 150, false, true, -2 )

                if not IsValid( aheadArea ) then
                    terminator_Extras.dynamicallyPatchPos( aheadPos, 50 )

                end
            end
        end
        local plysNearestToCenter = ply:NearestPoint( currArea:GetCenter() )
        distToArea = plysNearestToCenter:Distance( currArea:GetClosestPointOnArea( plysNearestToCenter ) )

    end

    -- cant be sure of areas further away from the player than this!
    if distToArea > tooFarDistSqr then return end

    local oldArea = ply.oldPatchingArea
    if not IsValid( oldArea ) then
        oldArea = currArea
        ply.oldPatchingArea = oldArea

    end

    local plysCenter = ply:WorldSpaceCenter()
    local patchData = ply.term_PatchingData
    if not patchData then
        patchData = {}
        patchData.highestGotOffGround = plysCenter.z
        ply.term_PatchingData = patchData

    end
    if not ply:IsOnGround() then
        patchData.highestGotOffGround = math.max( patchData.highestGotOffGround, plysCenter.z )
        patchData.wasOffGround = true
        return

    end

    if currArea == oldArea then return end
    if terminator_Extras.IsLivePatching then return end

    patchData = table.Copy( patchData )

    ply.term_PatchingData = nil
    ply.oldPatchingArea = currArea

    if oldArea:IsConnected( currArea ) and currArea:IsConnected( oldArea ) then return end
    if not AreasHaveAnyOverlap( oldArea, currArea ) then debugPrint( "0" ) return end

    plysCenter = ply:WorldSpaceCenter()

    local currClosestPos = currArea:GetClosestPointOnArea( plysCenter )
    local oldClosestPos = oldArea:GetClosestPointOnArea( plysCenter )
    local highestHeight = math.max( patchData.highestGotOffGround, oldClosestPos.z + 25, currClosestPos.z + 25 )

    local plysCenter2 = Vector( plysCenter.x, plysCenter.y, highestHeight ) -- yuck
    local currClosestPosInAir = Vector( currClosestPos.x, currClosestPos.y, highestHeight )
    local oldClosestPosInAir = Vector( oldClosestPos.x, oldClosestPos.y, highestHeight )

    if debugging then
        debugoverlay.Line( currClosestPos + upTen, currClosestPosInAir, 5, color_white, true )
        debugoverlay.Line( currClosestPosInAir, plysCenter2, 5, color_white, true )
        debugoverlay.Line( plysCenter2, oldClosestPosInAir, 5, color_white, true )
        debugoverlay.Line( oldClosestPos + upTen, oldClosestPosInAir, 5, color_white, true )

    end

    -- goes from last area, to the highest height, then back down to the current area
    if not terminator_Extras.PosCanSee( currClosestPos + upTen, currClosestPosInAir, MASK_SOLID_BRUSHONLY ) then debugPrint( "1" ) return end
    if not terminator_Extras.PosCanSee( currClosestPosInAir, plysCenter2, MASK_SOLID_BRUSHONLY ) then debugPrint( "2" ) return end
    if not terminator_Extras.PosCanSee( plysCenter2, oldClosestPosInAir, MASK_SOLID_BRUSHONLY ) then debugPrint( "3" ) return end
    if not terminator_Extras.PosCanSee( oldClosestPos + upTen, oldClosestPosInAir, MASK_SOLID_BRUSHONLY ) then debugPrint( "4" ) return end

    -- if ply was on the ground the entire time, we can skip all the anti-krangle stuff
    local skipBigChecks = not patchData.wasOffGround

    terminator_Extras.smartConnectionThink( oldArea, currArea, skipBigChecks )
    terminator_Extras.smartConnectionThink( currArea, oldArea, skipBigChecks )

end

local plysCurrentlyBeingChased

local function navPatchSelectivelyThink()
    if not doFollowingPatching then return end
    local cur = CurTime()
    local playersToPatch = {}
    local addedPlayerCreationIds = {}
    local max = maxPlysToPatch:GetInt()
    -- we should always patch people being chased if we can!
    for _, ply in player.Iterator() do
        local lowCount = #playersToPatch < max
        local chasedUntil = plysCurrentlyBeingChased[ ply ]
        if lowCount and chasedUntil and chasedUntil > cur then
            table.insert( playersToPatch, ply )
            addedPlayerCreationIds[ ply:GetCreationID() ] = true

        elseif not lowCount then
            break

        end
    end

    -- if there is still room in the table, add people not being chased
    if #playersToPatch < 4 then
        for _, ply in player.Iterator() do
            local lowCount = #playersToPatch < max
            if lowCount and not addedPlayerCreationIds[ ply:GetCreationID() ] and not ply:IsFlagSet( FL_NOTARGET ) then
                table.insert( playersToPatch, ply )

            elseif not lowCount then
                break

            end
        end
    end

    for _, ply in ipairs( playersToPatch ) do
        navPatchingThink( ply )

    end
end

hook.Add( "terminator_nextbot_oneterm_exists", "setup_following_navpatcher", function()
    if not doFollowingPatching then return end
    if GAMEMODE.IsReallyHuntersGlee == true then return end -- TODO: REMOVE THIS!
    plysCurrentlyBeingChased = {}
    hook.Add( "Think", "terminator_following_navpatcher", function()
        navPatchSelectivelyThink()

    end )
    hook.Add( "terminator_enemythink", "terminator_cacheplysbeingchased", function( _, enemy )
        if not IsValid( enemy ) then return end
        if not enemy:IsPlayer() then return end
        plysCurrentlyBeingChased[ enemy ] = CurTime() + 5

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "teardown_following_navpatcher", function()
    plysCurrentlyBeingChased = nil
    hook.Remove( "Think", "terminator_following_navpatcher" )
    hook.Remove( "terminator_enemythink", "terminator_cacheplysbeingchased" )
    for _, ply in player.Iterator() do
        ply.oldPatchingArea = nil
        ply.term_PatchingData = nil

    end
end )