
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

local upStanding = Vector( 0, 0, 25 )
local upCrouch = Vector( 0, 0, 10 )

local function AreasAreConnectable( area1, area2, checkOffs, trivialDist )
    if area1:IsConnected( area2 ) then return end -- already connected....
    if not AreasHaveAnyOverlap( area1, area2 ) then return end
    local doingCrouch = area1:HasAttributes( NAV_MESH_CROUCH ) or area2:HasAttributes( NAV_MESH_CROUCH )
    if not checkOffs then
        if doingCrouch then
            checkOffs = upCrouch

        else
            checkOffs = upStanding

        end
    end
    if not doingCrouch and not area1:IsPartiallyVisible( area2:GetClosestPointOnArea( area1:GetCenter() ) + checkOffs ) then return end
    if not goodDist( connectionDistance( area1, area2 ), trivialDist ) then return end
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

local function onNoArea( ply, beingChased, someoneWasChased )
    if not ply:IsOnGround() then return end

    local groundEnt = ply:GetGroundEntity()
    if not groundEnt then return end
    if not groundEnt:IsWorld() then return end

    local nextPlace = ply.term_NextRealPatchPlace or 0
    if nextPlace > CurTime() then return end

    local plyPos = ply:GetPos()
    ply.term_NextRealPatchPlace = CurTime() + 0.5
    ply.term_NextCrumbPatchPlace = CurTime() + 0.5

    local lastPatchPos = ply.term_LastPatchPos
    if lastPatchPos and lastPatchPos:Distance( plyPos ) < 50 then return end

    local isLowPriority = someoneWasChased and not beingChased

    if isLowPriority or terminator_Extras.IsLivePatching then
        if lastPatchPos and lastPatchPos:Distance( plyPos ) < 100 then return end
        ply.term_LastPatchPos = plyPos

        ply.term_PatchCrumbs = ply.term_PatchCrumbs or {}
        table.insert( ply.term_PatchCrumbs, plyPos )

    else
        ply.term_LastPatchPos = plyPos

        if ply:Crouching() and ply:GetVelocity():Length() < 225 then
            terminator_Extras.AddRegionToPatch( plyPos + -smallSize, plyPos + smallSize, 11.25 )
            return

        end
        terminator_Extras.dynamicallyPatchPos( plyPos )

    end
end

local hugeSize = Vector( 500, 500, 150 )

local function onSameArea( ply, beingChased, someoneWasChased )

    local queueIsWorking = terminator_Extras.IsLivePatching
    if queueIsWorking then ply.term_NextCrumbPatchPlace = CurTime() + 0.1 return end

    local lowPriority = someoneWasChased and not beingChased
    if lowPriority then ply.term_NextCrumbPatchPlace = CurTime() + 0.5 return end

    local nextPlace = ply.term_NextCrumbPatchPlace or 0
    if nextPlace > CurTime() then return end

    local crumbs = ply.term_PatchCrumbs
    if not crumbs then ply.term_NextCrumbPatchPlace = CurTime() + 0.1 return end

    ply.term_NextCrumbPatchPlace = CurTime() + 0.5
    local currCrumb = table.remove( crumbs, 1 )
    if not currCrumb then ply.term_PatchCrumbs = nil return end

    local crumbsArea = navmesh.GetNearestNavArea( currCrumb, false, 50, false, true, -2 )
    if IsValid( crumbsArea ) then return end

    terminator_Extras.AddRegionToPatch( currCrumb + -hugeSize, currCrumb + hugeSize, 50 )

end

-- patches gaps in navmesh, using players as a guide
-- patches will never be ideal, but they will be better than nothing

local navPatchingThink

do
    local entsMeta = FindMetaTable( "Entity" )
    local plyMeta = FindMetaTable( "Player" )
    local areaMeta = FindMetaTable( "CNavArea" )
    local vecMeta = FindMetaTable( "Vector" )
    local math = math
    local Vector = Vector

    local upMagicNum = 20
    local speedToPatchAhead = 100^2
    local doorCheckHull = Vector( 18, 18, 1 )
    local flattener = Vector( 1, 1, 0.5 )
    local tooFarDistSqr = 40^2

    navPatchingThink = function( ply, beingChased, someoneWasChased )

        local plyTbl = ply:GetTable()

        local badMovement = entsMeta.GetMoveType( ply ) == MOVETYPE_NOCLIP or entsMeta.Health( ply ) <= 0 or plyMeta.GetObserverMode( ply ) ~= OBS_MODE_NONE

        if badMovement then
            plyTbl.term_PatchingData = nil
            plyTbl.oldPatchingArea = nil
            return

        end

        local specialMovement = plyMeta.InVehicle( ply ) or entsMeta.WaterLevel( ply ) > 1

        local plyPos = entsMeta.GetPos( ply )
        local currArea, distToArea
        if plyTbl.GetNavAreaData then -- glee
            currArea, distToArea = plyTbl.GetNavAreaData( ply )
            if not IsValid( currArea ) then onNoArea( ply, beingChased, someoneWasChased ) return end

        else
            currArea = navmesh.GetNearestNavArea( plyPos, false, 25, false, true, -2 )
            if not IsValid( currArea ) then onNoArea( ply, beingChased, someoneWasChased ) return end

            local plysNearestToCenter = entsMeta.NearestPoint( ply, areaMeta.GetCenter( currArea ) )
            distToArea = vecMeta.Distance( plysNearestToCenter, areaMeta.GetClosestPointOnArea( currArea, plysNearestToCenter ) )

        end

        -- we are crouching and theres no area? navpatch NOW!
        if distToArea > 15 and plyMeta.Crouching( ply ) then onNoArea( ply, beingChased, someoneWasChased ) return end

        local patchABitAhead = beingChased and not terminator_Extras.IsLivePatching and math.random( 0, 100 ) < 5 and vecMeta.LengthSqr( entsMeta.GetVelocity( ply ) ) > speedToPatchAhead
        if patchABitAhead then -- rare, not doing _index optim
            local aheadPos = plyPos + ( ply:GetVelocity() * flattener ):GetNormalized() * 250
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

        local plysCenter = entsMeta.WorldSpaceCenter( ply )
        local patchData = plyTbl.term_PatchingData
        if not patchData then
            patchData = { highestGotOffGround = plysCenter.z }
            plyTbl.term_PatchingData = patchData

        end
        if specialMovement then
            patchData.wasSpecialMovement = true
            patchData.highestGotOffGround = math.max( patchData.highestGotOffGround, plysCenter.z )

        else
            if not entsMeta.IsOnGround( ply ) then
                patchData.highestGotOffGround = math.max( patchData.highestGotOffGround, plysCenter.z )
                patchData.wasOffGround = true
                return

            end
        end

        -- most operations stop here
        if currArea == oldArea then onSameArea( ply, beingChased, someoneWasChased ) return end

        -- dont waste connections to areas that are gonna get merged
        if terminator_Extras.IsLivePatching then return end

        patchData = table.Copy( patchData )

        plyTbl.term_PatchingData = nil
        plyTbl.oldPatchingArea = currArea

        if areaMeta.IsConnected( oldArea, currArea ) and areaMeta.IsConnected( currArea, oldArea ) then return end
        if not AreasHaveAnyOverlap( oldArea, currArea ) then debugPrint( "0" ) return end

        local currClosestPos = areaMeta.GetClosestPointOnArea( currArea, plysCenter )
        local oldClosestPos = areaMeta.GetClosestPointOnArea( oldArea, plysCenter )
        local highestHeight = math.max( patchData.highestGotOffGround, oldClosestPos.z + upMagicNum, currClosestPos.z + upMagicNum )

        local plysCenter2 = Vector( plysCenter.x, plysCenter.y, highestHeight ) -- yuck
        local currClosestPosInAir = Vector( currClosestPos.x, currClosestPos.y, highestHeight )
        local oldClosestPosInAir = Vector( oldClosestPos.x, oldClosestPos.y, highestHeight )

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

        -- detect really shabby doorways that non-terminator nextbots cannot navigate if we patch normally
        local shabbyDoorwayCheck = math.max( areaMeta.GetSizeX( oldArea ), areaMeta.GetSizeY( oldArea ) ) >= 75 -- shabby doorways are only a problem if both areas are relatively big
        shabbyDoorwayCheck = shabbyDoorwayCheck and math.max( areaMeta.GetSizeX( currArea ), areaMeta.GetSizeY( currArea ) ) >= 75
        shabbyDoorwayCheck = shabbyDoorwayCheck and math.abs( currClosestPos.z - oldClosestPos.z ) < upMagicNum -- this check is for doorways!
        if shabbyDoorwayCheck then
            local betweenPos = ( currClosestPosInAir + oldClosestPosInAir ) / 2
            local oldCenterOffsetted = areaMeta.GetCenter( oldArea )
            oldCenterOffsetted.z = highestHeight
            if debugging then debugoverlay.Line( oldCenterOffsetted, currClosestPosInAir, 5, color_white, true ) end
            if not terminator_Extras.PosCanSeeHull( oldCenterOffsetted, currClosestPosInAir, MASK_SOLID_BRUSHONLY, doorCheckHull ) then terminator_Extras.dynamicallyPatchPos( betweenPos ) debugPrint( "4a" ) return end

            local currCenterOffsetted = areaMeta.GetCenter( currArea )
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
    local max = maxPlysToPatch:GetInt()

    -- we should always patch people being chased if we can!
    for _, ply in player.Iterator() do
        local lowCount = #playersToPatch < max
        local chasedUntil = plysCurrentlyBeingChased[ ply ]
        if not lowCount then
            break

        elseif chasedUntil and chasedUntil > cur then
            table.insert( playersToPatch, ply )
            chasedPlayers[ ply ] = true
            someoneWasChased = true

        end
    end

    -- if there is still room in the table, add people not being chased
    if #playersToPatch < 4 then
        for _, ply in player.Iterator() do
            local lowCount = #playersToPatch < max
            if not lowCount then
                break
            elseif not chasedPlayers[ ply ] and not ply:IsFlagSet( FL_NOTARGET ) then
                table.insert( playersToPatch, ply )

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
        ply.term_PatchCrumbs = nil
        ply.term_LastPatchPos = nil
        ply.term_NextRealPatchPlace = nil
        ply.term_NextCrumbPatchPlace = nil

    end
end )