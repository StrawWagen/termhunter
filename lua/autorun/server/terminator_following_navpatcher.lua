
terminator_Extras = terminator_Extras or {}
local terminator_Extras = terminator_Extras

local navMeta = FindMetaTable( "CNavArea" )
local vecMeta = FindMetaTable( "Vector" )
local entMeta = FindMetaTable( "Entity" )

local GetClosestPointOnArea = navMeta.GetClosestPointOnArea
local GetAdjacentAreas = navMeta.GetAdjacentAreas
local IsConnected = navMeta.IsConnected
local GetCenter = navMeta.GetCenter
local GetCorner = navMeta.GetCorner

local Distance = vecMeta.Distance

local table_insert = table.insert
local math_min = math.min
local math_max = math.max
local math_abs = math.abs
local CurTime = CurTime
local IsValid = IsValid


local defaultMaxPlysToPatch = 6

local doFollowingPatchingVar = CreateConVar( "terminator_followpatcher_enable", 1, FCVAR_ARCHIVE, "Patches the navmesh as players wander the map, Leads to terminators feeling smarter, following you through windows. Only runs with at least 1 bot spawned." )
local maxPlysToPatchVar = CreateConVar( "terminator_followpatcher_maxplayers", -1, FCVAR_ARCHIVE, "Max amount of plys to process at a time, the system always prioritizes players being actively chased. -1 for default," .. defaultMaxPlysToPatch )
local debuggingVar = CreateConVar( "terminator_followpatcher_debug", 0, FCVAR_ARCHIVE, "Debug the following patcher." )


local doFollowingPatching = doFollowingPatchingVar:GetBool()
cvars.AddChangeCallback( "terminator_followpatcher_enable", function( _, _, new )
    doFollowingPatching = tobool( new )

end, "updatepatching" )


local maxPlysToPatch
local function handleMaxPlysToPatch()
    maxPlysToPatch = tonumber( maxPlysToPatchVar:GetInt() )
    if maxPlysToPatch <= -1 then maxPlysToPatch = defaultMaxPlysToPatch end

end

cvars.AddChangeCallback( "terminator_followpatcher_maxplayers", function()
    handleMaxPlysToPatch()

end, "updatemaxplayers" )
handleMaxPlysToPatch()


local debugging = debuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_followpatcher_debug", function( _, _, new )
    debugging = tobool( new )

end, "updatedebugging" )

local function debugPrint( ... )
    if not debugging then return end
    permaPrint( ... )

end

local function lineBetween( area1, area2 )
    if not debugging then return end
    debugoverlay.Line( area1:GetCenter(), area2:GetCenter(), 10, Color( 255, 0, 0 ), true )

end


local upTen = Vector( 0, 0, 10 )

local function connectionDistance( currArea, otherArea )
    local currCenter = GetCenter( currArea )

    local nearestInitial = GetClosestPointOnArea( otherArea, currCenter )
    local nearestFinal   = GetClosestPointOnArea( currArea, nearestInitial )
    nearestFinal.z = nearestInitial.z
    local distTo   = Distance( nearestInitial, nearestFinal )
    return distTo, nearestFinal, nearestInitial

end

terminator_Extras.connectionDistance = connectionDistance

local function distanceEdge( currArea, otherArea )
    local currCenter = GetCenter( currArea )

    local nearestInitial    = GetClosestPointOnArea( otherArea, currCenter )
    local nearestFinal      = GetClosestPointOnArea( currArea, nearestInitial )
    local distTo            = Distance( nearestInitial, nearestFinal )
    return distTo

end

terminator_Extras.distanceEdge = distanceEdge

local function goodDist( distTo, trivialDist )
    trivialDist = trivialDist or 5
    if distTo <= trivialDist then return true end

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

local function AreasHaveAnyOverlap( area1, area2 ) -- i love chatgpt functions
    -- Get corners of both areas
    local area1Corner1 = GetCorner( area1, 0 )
    local area1Corner2 = GetCorner( area1, 2 )
    local area2Corner1 = GetCorner( area2, 0 )
    local area2Corner2 = GetCorner( area2, 2 )

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

terminator_Extras.AreasHaveAnyOverlap = AreasHaveAnyOverlap


local upStanding = Vector( 0, 0, 25 )
local upCrouch = Vector( 0, 0, 10 )

local function AreasAreConnectable( area1, area2, checkOffs, trivialDist )
    if IsConnected( area1, area2 ) then return end -- already connected....
    if not AreasHaveAnyOverlap( area1, area2 ) then return end -- can't connect diagonally
    local doingCrouch = navMeta.HasAttributes( area1, NAV_MESH_CROUCH ) or navMeta.HasAttributes( area2, NAV_MESH_CROUCH )
    if not checkOffs then
        if doingCrouch then
            checkOffs = upCrouch

        else
            checkOffs = upStanding

        end
    end
    if not doingCrouch and not navMeta.IsPartiallyVisible( area1, GetClosestPointOnArea( area2, GetCenter( area1 ) ) + checkOffs ) then return end
    if not goodDist( connectionDistance( area1, area2 ), trivialDist ) then return end
    return true

end

terminator_Extras.AreasAreConnectable = AreasAreConnectable


-- do checks to see if connection from old area to curr area is a good idea
function terminator_Extras.smartConnectionThink( oldArea, currArea, simple )
    if IsConnected( oldArea, currArea ) then debugPrint( "5" ) return end

    -- get dist flat, no z component
    local distTo = connectionDistance( oldArea, currArea )

    if distTo > 55 and not goodDist( distTo ) then debugPrint( "6" ) return end

    -- check if there's a simple-ish way from oldArea to currArea
    -- dont create a new connection if there is
    if not simple then

        local oldsNearestToCurr = GetClosestPointOnArea( oldArea, GetCenter( currArea ) )
        local currsNearestToOld = GetClosestPointOnArea( currArea, oldsNearestToCurr )
        local distFunc
        if math_abs( oldsNearestToCurr.z - currsNearestToOld.z ) > 50 then
            distFunc = connectionDistance

        else
            distFunc = distanceEdge

        end

        local returnBlacklist = {}
        for _, area in ipairs( GetAdjacentAreas( currArea ) ) do
            returnBlacklist[area] = true

        end

        local smallestDist = distFunc( oldArea, currArea )
        local potentiallyBetterConnections = {}
        local doneAlready = {}

        for _, firstLayer in ipairs( GetAdjacentAreas( oldArea ) ) do
            if returnBlacklist[firstLayer] and distFunc( firstLayer, currArea ) <= smallestDist then
                lineBetween( firstLayer, currArea )
                debugPrint( "7" )
                return

            end

            table_insert( potentiallyBetterConnections, firstLayer )
            doneAlready[firstLayer] = true

            for _, secondLayer in ipairs( GetAdjacentAreas( firstLayer ) ) do
                if doneAlready[secondLayer] then continue end
                table_insert( potentiallyBetterConnections, secondLayer )
                doneAlready[secondLayer] = true

                for _, thirdLayer in ipairs( GetAdjacentAreas( secondLayer ) ) do
                    if doneAlready[thirdLayer] then continue end
                    table_insert( potentiallyBetterConnections, thirdLayer )
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

    navMeta.ConnectTo( oldArea, currArea )
    hook.Run( "terminator_navpatcher_patched", oldArea, currArea )

    return true

end

local smallSize = Vector( 100, 100, 75 )

local function onNoArea( ply, plyTbl, beingChased, someoneWasChased ) -- ply is off navmesh
    if not ply:IsOnGround() then return end

    local groundEnt = entMeta.GetGroundEntity( ply )
    if not groundEnt then return end
    if not groundEnt:IsWorld() then return end -- can only place areas on the world

    local nextPlace = plyTbl.term_NextRealPatchPlace or 0
    if nextPlace > CurTime() then return end

    local plyPos = entMeta.GetPos( ply )
    plyTbl.term_NextRealPatchPlace = CurTime() + 0.5
    plyTbl.term_NextCrumbPatchPlace = CurTime() + 0.5

    local lastPatchPos = plyTbl.term_LastPatchPos
    if lastPatchPos and Distance( lastPatchPos, plyPos ) < 50 then return end

    local isLowPriority = someoneWasChased and not beingChased

    if isLowPriority or terminator_Extras.IsLivePatching then -- place crumbs so we dont miss big gaps
        if lastPatchPos and Distance( lastPatchPos, plyPos ) < 100 then return end
        plyTbl.term_LastPatchPos = plyPos

        plyTbl.term_PatchCrumbs = plyTbl.term_PatchCrumbs or {}
        -- clamp this table, don't clamp if we're working from scratch
        if #plyTbl.term_PatchCrumbs >= 25 and not terminator_Extras.navPatcher_WorkingFromScratch then return end

        table_insert( plyTbl.term_PatchCrumbs, plyPos )

    else
        plyTbl.term_LastPatchPos = plyPos

        if ply:Crouching() and ply:GetVelocity():LengthSqr() < 225^2 then -- always patch in vents etc
            terminator_Extras.AddRegionToPatch( plyPos + -smallSize, plyPos + smallSize, 11.25 )
            return

        end
        terminator_Extras.dynamicallyPatchPos( plyPos )

    end
end

local hugeSize = Vector( 500, 500, 150 )

local function onSameArea( _ply, plyTbl, beingChased, someoneWasChased ) -- ply doesn't need patching, see if we can place crumbs

    local queueIsWorking = terminator_Extras.IsLivePatching
    if queueIsWorking then plyTbl.term_NextCrumbPatchPlace = CurTime() + 0.1 return end

    local lowPriority = someoneWasChased and not beingChased
    if lowPriority then plyTbl.term_NextCrumbPatchPlace = CurTime() + 0.5 return end

    local nextPlace = plyTbl.term_NextCrumbPatchPlace or 0
    if nextPlace > CurTime() then return end

    local crumbs = plyTbl.term_PatchCrumbs
    if not crumbs then plyTbl.term_NextCrumbPatchPlace = CurTime() + 0.1 return end

    plyTbl.term_NextCrumbPatchPlace = CurTime() + 0.5
    local currCrumb = table.remove( crumbs, 1 )
    if not currCrumb then plyTbl.term_PatchCrumbs = nil return end

    local crumbsArea = navmesh.GetNearestNavArea( currCrumb, false, 50, false, true, -2 )
    if IsValid( crumbsArea ) then return end

    terminator_Extras.AddRegionToPatch( currCrumb + -hugeSize, currCrumb + hugeSize, 50 )

end

-- patches gaps in navmesh, using players as a guide
-- patches will never be ideal, but they will be better than nothing

local navPatchingThink

do
    local plyMeta = FindMetaTable( "Player" )
    local math = math
    local Vector = Vector

    local upMagicNum = 20
    local speedToPatchAhead = 100^2
    local doorCheckHull = Vector( 18, 18, 1 )
    local flattener = Vector( 1, 1, 0.5 )
    local tooFarDistSqr = 40^2

    local plysCenter2 = Vector( 0, 0, 0 )
    local currClosestPosInAir = Vector( 0, 0, 0 )
    local oldClosestPosInAir = Vector( 0, 0, 0 )

    navPatchingThink = function( ply, beingChased, someoneWasChased )

        local plyTbl = entMeta.GetTable( ply )

        local badMovement = entMeta.GetMoveType( ply ) == MOVETYPE_NOCLIP or entMeta.Health( ply ) <= 0 or plyMeta.GetObserverMode( ply ) ~= OBS_MODE_NONE

        if badMovement then
            plyTbl.term_PatchingData = nil
            plyTbl.oldPatchingArea = nil
            return

        end

        local specialMovement = plyMeta.InVehicle( ply ) or entMeta.WaterLevel( ply ) > 1

        local plyPos = entMeta.GetPos( ply )
        local currArea, distToArea
        if plyTbl.GetNavAreaData then -- glee
            currArea, distToArea = plyTbl.GetNavAreaData( ply )
            if not IsValid( currArea ) then onNoArea( ply, plyTbl, beingChased, someoneWasChased ) return end

        else
            currArea = navmesh.GetNearestNavArea( plyPos, false, 25, false, true, -2 )
            if not IsValid( currArea ) then onNoArea( ply, plyTbl, beingChased, someoneWasChased ) return end

            local plysNearestToCenter = entMeta.NearestPoint( ply, GetCenter( currArea ) )
            distToArea = Distance( plysNearestToCenter, GetClosestPointOnArea( currArea, plysNearestToCenter ) )

        end

        -- we are crouching and theres no area? navpatch NOW!
        if distToArea > 15 and plyMeta.Crouching( ply ) then onNoArea( ply, plyTbl, beingChased, someoneWasChased ) return end

        local patchABitAhead = beingChased and not terminator_Extras.IsLivePatching and math.random( 0, 100 ) < 5 and vecMeta.LengthSqr( entMeta.GetVelocity( ply ) ) > speedToPatchAhead
        if patchABitAhead then -- rare
            local aheadOffset = vecMeta.GetNormalized( ply:GetVelocity() * flattener ) * 250
            local aheadPos = plyPos + aheadOffset
            if util.IsInWorld( aheadPos ) and terminator_Extras.PosCanSee( plyPos, aheadPos ) then
                local aheadArea = navmesh.GetNearestNavArea( aheadPos, false, 150, false, true, -2 )

                if not IsValid( aheadArea ) then
                    terminator_Extras.dynamicallyPatchPos( aheadPos, 50 )

                end
            end
        end

        -- cant be sure of areas further away from the player than this!
        if distToArea > tooFarDistSqr then return end

        local oldArea = plyTbl.oldPatchingArea
        if not IsValid( oldArea ) then
            oldArea = currArea
            plyTbl.oldPatchingArea = oldArea

        end

        local plysCenter = entMeta.WorldSpaceCenter( ply )
        local patchData = plyTbl.term_PatchingData
        if not patchData then
            patchData = {
                highestGotOffGround = plysCenter.z,
                wasOffGround = false,
                wasSpecialMovement = false,
            }
            plyTbl.term_PatchingData = patchData

        end
        if specialMovement then
            patchData.wasSpecialMovement = true
            patchData.highestGotOffGround = math_max( patchData.highestGotOffGround, plysCenter.z )

        else
            if not entMeta.IsOnGround( ply ) then
                patchData.highestGotOffGround = math_max( patchData.highestGotOffGround, plysCenter.z )
                patchData.wasOffGround = true
                return

            end
        end

        -- most operations stop here
        if currArea == oldArea then onSameArea( ply, plyTbl, beingChased, someoneWasChased ) return end

        -- dont waste connections to areas that are gonna get merged
        if terminator_Extras.IsLivePatching then return end

        plyTbl.term_PatchingData = nil
        plyTbl.oldPatchingArea = currArea

        if IsConnected( oldArea, currArea ) and IsConnected( currArea, oldArea ) then return end
        if not AreasHaveAnyOverlap( oldArea, currArea ) then debugPrint( "0" ) return end

        local currClosestPos = GetClosestPointOnArea( currArea, plysCenter )
        local oldClosestPos = GetClosestPointOnArea( oldArea, plysCenter )
        local highestHeight = math_max( patchData.highestGotOffGround, oldClosestPos.z + upMagicNum, currClosestPos.z + upMagicNum )

        -- center of players but with the highest height
        plysCenter2.x, plysCenter2.y, plysCenter2.z = plysCenter.x, plysCenter.y, highestHeight
        -- current area closest pos to player but with the highest height
        currClosestPosInAir.x, currClosestPosInAir.y, currClosestPosInAir.z = currClosestPos.x, currClosestPos.y, highestHeight
        -- old area closest pos to player but with the highest height
        oldClosestPosInAir.x, oldClosestPosInAir.y, oldClosestPosInAir.z = oldClosestPos.x, oldClosestPos.y, highestHeight

        if debugging then
            -- currClosestPos + upTen so that this doesnt fail when the area is ~10 units underground
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

        -- create areas if there's a very thin constriction, doorway, etc
        local shabbyDoorwayCheck = math_max( navMeta.GetSizeX( oldArea ), navMeta.GetSizeY( oldArea ) ) >= 75 -- shabby doorways are only a problem if both areas are relatively big
        shabbyDoorwayCheck = shabbyDoorwayCheck and math_max( navMeta.GetSizeX( currArea ), navMeta.GetSizeY( currArea ) ) >= 75
        shabbyDoorwayCheck = shabbyDoorwayCheck and math_abs( currClosestPos.z - oldClosestPos.z ) < upMagicNum -- this check is for doorways!
        if shabbyDoorwayCheck then
            local betweenPos = ( currClosestPosInAir + oldClosestPosInAir ) / 2
            local oldCenterOffsetted = GetCenter( oldArea )
            oldCenterOffsetted.z = highestHeight
            if debugging then debugoverlay.Line( oldCenterOffsetted, currClosestPosInAir, 5, color_white, true ) end
            if not terminator_Extras.PosCanSeeHull( oldCenterOffsetted, currClosestPosInAir, MASK_SOLID_BRUSHONLY, doorCheckHull ) then terminator_Extras.dynamicallyPatchPos( betweenPos ) debugPrint( "4a" ) return end

            local currCenterOffsetted = GetCenter( currArea )
            currCenterOffsetted.z = highestHeight
            if debugging then debugoverlay.Line( currCenterOffsetted, oldClosestPosInAir, 5, color_white, true ) end
            if not terminator_Extras.PosCanSeeHull( currCenterOffsetted, oldClosestPosInAir, MASK_SOLID_BRUSHONLY, doorCheckHull ) then terminator_Extras.dynamicallyPatchPos( betweenPos ) debugPrint( "4b" ) return end

        end

        -- if ply was on the ground the entire time, we can skip all the anti-krangle stuff
        local skipBigChecks = not ( patchData.wasOffGround or patchData.wasSpecialMovement )

        terminator_Extras.smartConnectionThink( oldArea, currArea, skipBigChecks )
        terminator_Extras.smartConnectionThink( currArea, oldArea, skipBigChecks )

    end
end

local plysCurrentlyBeingChased

local function navPatchSelectivelyThink()
    if not doFollowingPatching then return end
    local cur = CurTime()
    local playersToPatch = {}
    local chasedPlayers = {}
    local someoneWasChased = nil
    local max = maxPlysToPatch

    -- we should always patch people being chased if we can!
    for _, ply in player.Iterator() do
        local lowCount = #playersToPatch < max
        local chasedUntil = plysCurrentlyBeingChased[ply]
        if not lowCount then
            break

        elseif chasedUntil and chasedUntil > cur then
            table_insert( playersToPatch, ply )
            chasedPlayers[ply] = true
            someoneWasChased = true

        end
    end

    -- if there is still room in the table, add people not being chased
    if #playersToPatch < maxPlysToPatch then
        for _, ply in player.Iterator() do
            local lowCount = #playersToPatch < max
            if not lowCount then
                break
            elseif not chasedPlayers[ply] and not ply:IsFlagSet( FL_NOTARGET ) then
                table_insert( playersToPatch, ply )

            end
        end
    end

    for _, ply in ipairs( playersToPatch ) do
        navPatchingThink( ply, chasedPlayers[ply], someoneWasChased )

    end
end

hook.Add( "terminator_nextbot_oneterm_exists", "setup_following_navpatcher", function()
    if not doFollowingPatching then return end
    plysCurrentlyBeingChased = {}
    hook.Add( "Think", "terminator_following_navpatcher", function()
        navPatchSelectivelyThink()

    end )
    hook.Add( "terminator_enemythink", "terminator_cacheplysbeingchased", function( _, enemy )
        if not IsValid( enemy ) then return end
        if not enemy:IsPlayer() then return end
        plysCurrentlyBeingChased[enemy] = CurTime() + 5

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "teardown_following_navpatcher", function()
    plysCurrentlyBeingChased = nil
    hook.Remove( "Think", "terminator_following_navpatcher" )
    hook.Remove( "terminator_enemythink", "terminator_cacheplysbeingchased" )
    for _, ply in player.Iterator() do
        local plyTbl = entMeta.GetTable( ply )
        plyTbl.oldPatchingArea = nil
        plyTbl.term_PatchingData = nil
        plyTbl.term_PatchCrumbs = nil
        plyTbl.term_LastPatchPos = nil
        plyTbl.term_NextRealPatchPlace = nil
        plyTbl.term_NextCrumbPatchPlace = nil

    end
end )