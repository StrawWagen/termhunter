AddCSLuaFile()

ENT.Base = "sb_advanced_nextbot_soldier_base"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"

list.Set( "NPC", "sb_advanced_nextbot_terminator_hunter", {
    Name = "Terminator Overcharged",
    Class = "sb_advanced_nextbot_terminator_hunter",
    Category = "SB Advanced Nextbots",
    Weapons = { "weapon_terminatorfists_sb_anb" },
} )

-- these need to be shared
include( "compatibilityhacks.lua" )

if CLIENT then
    language.Add( "sb_advanced_nextbot_terminator_hunter", ENT.PrintName )
    return

elseif SERVER then
    -- gun stuff
    include( "weapons.lua" )
    include( "weapholstering.lua" )
    -- task stuff
    include( "taskoverride.lua" )
    -- motion, interacting with stuff that blocks motion
    include( "motionoverrides.lua" )
    -- pathing, flanking support
    include( "pathoverrides.lua" )
    -- enemyoverrides, crouching to look at enemies, hating killers, etc 
    include( "enemyoverrides.lua" )
    -- damage shows on bot's model, also modifies damage amount taken for like cballs.
    include( "prettydamage.lua" )

end

LineOfSightMask = MASK_BLOCKLOS
terminator_Extras.LineOfSightMask = LineOfSightMask

ENT.TERM_FISTS = "weapon_terminatorfists_sb_anb"
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"
ENT.ARNOLD_MODEL = ARNOLD_MODEL

CreateConVar( "termhunter_modeloverride", ARNOLD_MODEL, FCVAR_NONE, "Override the terminator nextbot's spawned-in model. Model needs to be rigged for player movement" )

local extremeUnstucking = CreateConVar( "termhunter_doextremeunstucking", 1, FCVAR_ARCHIVE, "Teleport terminators medium distances if they get really stuck?", 0, 1 )

local function termModel()
    local convar = GetConVar( "termhunter_modeloverride" )
    local model = ARNOLD_MODEL
    if convar then
        local varModel = convar:GetString()
        if varModel and util.IsValidModel( varModel ) then
            model = varModel
        end
    end
    return model

end

if not termModel() then
    RunConsoleCommand( "termhunter_modeloverride", ARNOLD_MODEL )

end

if not navExtraDataHunter then
    navExtraDataHunter = {}
end

local vec_zero = Vector( 0 )
local vector6000ZUp = Vector( 0, 0, 6000 )
local vector1000ZDown = Vector( 0, 0, -1000 )
local negativeFiveHundredZ = Vector( 0,0,-500 )
local plus25Z = Vector( 0,0,25 )

local _CurTime = CurTime

--utility functions begin

local function PickRealVec( toPick )
    -- ipairs breaks if nothing is stored in any index, thanks ipairs!!!!!
    for index = 1, table.maxn( toPick ) do
        local picked = toPick[ index ]
        if isvector( picked ) then
            return picked

        end
    end
end

local function hasReasonableHealth( ent )
    local entsHp = ent:Health()
    return entsHp > 0 and entsHp < 300

end

function ENT:campingTolerance()
    local myPos = self:GetPos()
    -- lower is better
    local nookScore = terminator_Extras.GetNookScore( myPos + plus25Z, 6000 )
    local tolerance
    if nookScore < 3 then-- 3 score is a really good spot
        tolerance = 4000 / nookScore

    elseif nookScore < 4 then
        tolerance = 2000 / nookScore

    else
        tolerance = 100 / nookScore

    end
    return tolerance

end


function ENT:enemyBearingToMeAbs()
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then return 0 end
    local myPos = self:GetPos()
    local enemyPos = enemy:GetPos()
    local enemyAngle = enemy:EyeAngles()
    return math.abs( terminator_Extras.BearingToPos( myPos, enemyAngle, enemyPos, enemyAngle ) )

end

local function SqrDistGreaterThan( Dist1, Dist2 )
    return Dist1 > Dist2 ^ 2
end

local function SqrDistLessThan( Dist1, Dist2 )
    return Dist1 < Dist2 ^ 2
end

local function Distance2D( pos1, pos2 )
    local product = pos1 - pos2
    return product:Length2D()
end

local function DistToSqr2D( pos1, pos2 )
    if not pos1 or not pos2 then return math.huge end
    local product = pos1 - pos2
    return product:Length2DSqr()
end

-- accurate method that does not require laggy :distance, still slower than :distance
local function distBetweenTwoAreas( area1, area2 )
    local dir = area1:GetCenter() - area2:GetCenter()
    local dist = 0
    if dir[1] > dir[2] then
        dist = ( area1:GetSizeX() + area2:GetSizeX() ) * 0.5
    else
        dist = ( area1:GetSizeY() + area2:GetSizeY() ) * 0.5
    end
    return dist
end

function ENT:getBestPos( ent )
    if not IsValid( ent ) then return vec_zero end
    local shootPos = self:GetShootPos()
    local pos = ent:NearestPoint( shootPos )
    -- put the nearest point a bit inside the entity
    pos = ent:WorldToLocal( pos )
    pos = pos * 0.6
    pos = ent:LocalToWorld( pos )

    --debugoverlay.Cross( pos, 5, 5 )

    if pos and ent:GetClass() ~= "func_breakable_surf" and terminator_Extras.PosCanSee( shootPos, pos ) then
        return pos

    end

    pos = ent:WorldSpaceCenter()

    local obj = ent:GetPhysicsObject()
    if IsValid( obj ) then
        local center = obj:GetMassCenter()
        if center ~= vec_zero then
            pos = ent:LocalToWorld( center )

        end
    end
    return pos

end

local function getUsefulPositions( area )
    local out = {}
    local center = area:GetCenter()
    table.Add( out, area:GetHidingSpots( 8 ) )

    if area:GetSizeX() > 25 and area:GetSizeY() > 25 then
        for cornerId = 0, 3 do
            local corner = area:GetCorner( cornerId )
            local cornerBroughtInAbit = corner + ( terminator_Extras.dirToPos( corner, center ) * 20 )
            table.insert( out, cornerBroughtInAbit )

        end
    else
        table.insert( out, center )

    end

    return out

end

local ladderOffset = 800000

local function AreaOrLadderGetID( areaOrLadder )
    if not areaOrLadder then return end
    if areaOrLadder.GetTop then
        -- never seen a navmesh with 800k areas
        return areaOrLadder:GetID() + ladderOffset

    else
        return areaOrLadder:GetID()

    end
end

local function getNavAreaOrLadderById( areaOrLadderID )
    local area = navmesh.GetNavAreaByID( areaOrLadderID )
    if area then
        return area

    end
    local ladder = navmesh.GetNavLadderByID( areaOrLadderID + -ladderOffset )
    if ladder then
        return ladder

    end
end

local function AreaOrLadderGetCenter( areaOrLadder )
    if not areaOrLadder then return end
    if areaOrLadder.GetTop then
        return ( areaOrLadder:GetTop() + areaOrLadder:GetBottom() ) / 2

    else
        return areaOrLadder:GetCenter()

    end
end

local function AreaOrLadderGetAdjacentAreas( areaOrLadder )
    local adjacents = {}
    if not areaOrLadder then return adjacents end
    if areaOrLadder.GetTop then -- is ladder
        table.Add( adjacents, areaOrLadder:GetBottomArea() )
        table.Add( adjacents, areaOrLadder:GetTopForwardArea() )
        table.Add( adjacents, areaOrLadder:GetTopBehindArea() )
        table.Add( adjacents, areaOrLadder:GetTopRightArea() )
        table.Add( adjacents, areaOrLadder:GetTopLeftArea() )

    else
        adjacents = table.Add( areaOrLadder:GetAdjacentAreas(), areaOrLadder:GetLadders() )

    end
    return adjacents

end

-- iterative function that finds connected area with the best score
-- areas with highest return from scorefunc are selected
-- areas that return 0 score from scorefunc are ignored
-- returns the best scoring area if it's further than dist or no other options exist
function ENT:findValidNavResult( data, start, radius, scoreFunc, noMoreOptionsMin )
    local pos = nil
    local res = nil
    local cur = nil
    local inf = math.huge
    local blockRadiusEnd = data.blockRadiusEnd

    if isvector( start ) then
        pos = start
        res = terminator_Extras.getNearestPosOnNav( pos )
        cur = res.area

    elseif start and start.IsValid and start:IsValid() then
        pos = AreaOrLadderGetCenter( start )
        cur = start

    end
    if not cur or not cur:IsValid() then return nil, NULL, nil end
    local curId = AreaOrLadderGetID( cur )

    noMoreOptionsMin = noMoreOptionsMin or 8

    local opened = { [curId] = true }
    local closed = {}
    local openedSequential = {}
    local closedSequential = {}
    local distances = { [curId] = AreaOrLadderGetCenter( cur ):Distance( pos ) }
    local scores = { [curId] = 1 }
    local opCount = 0
    local isLadder = {}

    if cur.GetTop then
        isLadder[curId] = true

    end

    while not table.IsEmpty( opened ) do
        local bestScore = 0
        local bestArea = nil

        for _, currOpenedId in ipairs( openedSequential ) do
            local myScore = scores[currOpenedId]

            if isnumber( myScore ) and myScore > bestScore then
                bestScore = myScore
                bestArea = currOpenedId

            end
        end
        if not bestArea then
            _, bestArea = table.Random( opened )

        end

        opCount = opCount + 1

        local areaId = bestArea
        opened[areaId] = nil
        closed[areaId] = true
        -- table.removebyvalue fucking crashes the session
        for key, value in ipairs( openedSequential ) do
            if value == areaId then
                table.remove( openedSequential, key )
            end
        end
        table.insert( closedSequential, areaId )

        local area = getNavAreaOrLadderById( areaId )
        local myDist = distances[areaId]
        local noMoreOptions = #openedSequential == 1 and #closedSequential >= noMoreOptionsMin

        if noMoreOptions or opCount >= 300 or bestScore == inf then
            local _, bestClosedAreaId = table.Random( closed )
            local bestClosedScore = 0

            for _, currClosedId in ipairs( closedSequential ) do
                local currClosedScore = scores[currClosedId]

                if isnumber( currClosedScore ) and currClosedScore > bestClosedScore and isLadder[ currClosedId ] ~= true then
                    bestClosedScore = currClosedScore
                    bestClosedAreaId = currClosedId

                end
                if bestClosedScore == inf then
                    break

                end
            end
            local bestClosedArea = navmesh.GetNavAreaByID( bestClosedAreaId )
            if not bestClosedArea then return nil, NULL, nil end -- huh??

            return bestClosedArea:GetCenter(), bestClosedArea, nil

        elseif not blockRadiusEnd and myDist > radius and area and not area.GetTop then
            return area:GetCenter(), area, true

        end

        local adjacents = AreaOrLadderGetAdjacentAreas( area )

        for _, adjArea in ipairs( adjacents ) do
            local adjID = AreaOrLadderGetID( adjArea )

            if not closed[adjID] then

                local theScore = 0
                if area.GetTop or adjArea.GetTop then
                    -- just let the algorithm pass through this
                    theScore = scores[areaId]

                else
                    theScore = scoreFunc( data, area, adjArea )

                end
                if theScore <= 0 then continue end

                local adjDist = AreaOrLadderGetCenter( area ):Distance( AreaOrLadderGetCenter( adjArea ) )
                local distance = myDist + adjDist

                distances[adjID] = distance
                scores[adjID] = theScore
                opened[adjID] = true

                if adjArea.GetTop then
                    isLadder[adjID] = true

                end

                table.insert( openedSequential, adjID )

            end
        end
    end
end
-- util funcs end

-- detect small areas that don't have incoming connections! stops huuuuge lagspikes on big maps
function ENT:AreaIsOrphan( potentialOrphan )

    local myNav = self:GetTrueCurrentNavArea() or self:GetCurrentNavArea()

    if potentialOrphan == myNav then return nil, nil end

    local checkedSurfaceArea = 0
    local unConnectedAreasSequential = {}
    local unConnectedAreas = {}
    local connectedAreasSequential = {}
    local scoreData = {}
    scoreData.decreasingScores = {}
    scoreData.encounteredABlockedArea = nil
    scoreData.encounteredALadder = nil
    scoreData.botsNav = myNav

    local scoreFunction = function( scoreData, area1, area2 )
        if area2:IsBlocked() then scoreData.encounteredABlockedArea = true return 0 end
        if #area2:GetLadders() >= 1 then scoreData.encounteredALadder = true end

        local nextAreaId = area2:GetID()
        local currAreaId = area1:GetID()
        local score = scoreData.decreasingScores[currAreaId] or 10000

        checkedSurfaceArea = area2:GetSizeX() * area2:GetSizeY()

        -- area has shit connection or we left from an area with shit connection
        if not area2:IsConnected( area1 ) or unConnectedAreas[currAreaId] then
            unConnectedAreas[nextAreaId] = true
            score = -1
            table.insert( unConnectedAreasSequential, nextAreaId )
            --debugoverlay.Text( area2:GetCenter(), "unConnected", 8 )

        -- good connection
        else
            -- just return early if we're in the same group
            if area2 == scoreData.botsNav then
                scoreData.sameGroupAsUs = true
                return math.huge

            end
            for placementInSeqTable, potentiallyReValidAreaId in ipairs( unConnectedAreasSequential ) do
                if potentiallyReValidAreaId == nextAreaId then
                    --debugoverlay.Text( area2:GetCenter() + Vector(0,0,50), "reConnected", 8 )
                    unConnectedAreas[nextAreaId] = nil
                    table.remove( unConnectedAreasSequential, placementInSeqTable )

                end
            end
            table.insert( connectedAreasSequential, nextAreaId )
        end

        scoreData.decreasingScores[nextAreaId] = score + -1

        --debugoverlay.Text( area2:GetCenter() + Vector( 0,0,10 ), tostring( score ), 8 )

        return score

    end

    local checkRadius = 700

    local _, _, escaped = self:findValidNavResult( scoreData, potentialOrphan, checkRadius, scoreFunction, 80 )

    local destConfined = not escaped and not scoreData.sameGroupAsUs

    local lessNoWaysBackThanWaysBack = ( #unConnectedAreasSequential <= #connectedAreasSequential )
    local isSubstantiallySized = checkedSurfaceArea > ( checkRadius^2 ) * 0.15
    local isPotentiallyPartOfWhole = lessNoWaysBackThanWaysBack and isSubstantiallySized

    --print( escaped, scoreData.sameGroupAsUs, isPotentiallyPartOfWhole )

    -- could not confirm that it's an orphan
    if not destConfined or isPotentiallyPartOfWhole or scoreData.encounteredALadder then return nil, scoreData.encounteredABlockedArea end

    -- is an orphan
    return true, scoreData.encounteredABlockedArea

end

function ENT:EnemyIsBoxedIn()
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then return end

    local enemysNavArea = terminator_Extras.getNearestPosOnNav( enemy:GetPos() ).area
    if not enemysNavArea or not enemysNavArea.IsValid or not enemysNavArea:IsValid() then return end
    local stepH = self.loco:GetStepHeight()
    local enteranceImIn = navmesh.Find( self:GetPos(), 350, stepH, stepH )

    local areasThatAreEntrance = {}

    for _, entranceArea in ipairs( enteranceImIn ) do
        areasThatAreEntrance[ entranceArea:GetID() ] = true

    end
    -- not boxed in, we're just close
    if areasThatAreEntrance[ enemysNavArea:GetID() ] then return end

    local scoreData = {}
    scoreData.hasEscape = nil
    scoreData.decreasingScores = {}
    scoreData.hasEscape = nil

    local scoreFunction = function( scoreData, area1, area2 )
        if area2:IsBlocked() then return 0 end
        if #area2:GetLadders() >= 1 then scoreData.hasEscape = true return math.huge end

        local area1Id = area1:GetID()
        local area2Id = area2:GetID()
        local score = scoreData.decreasingScores[area1Id] or 10000

        if areasThatAreEntrance[ area2Id ] then
            return 0

        end
        scoreData.decreasingScores[area2Id] = score + -1

        --debugoverlay.Text( area2:GetCenter() + Vector( 0,0,10 ), tostring( score ), 8 )

        return score

    end

    local checkRadius = 1350
    local _, _, escaped = self:findValidNavResult( scoreData, enemy:GetPos(), checkRadius, scoreFunction, 10 )

    local boxedIn = not escaped and not scoreData.hasEscape

    return boxedIn

end

local MEMORY_MEMORIZING = 1
local MEMORY_INERT = 2
local MEMORY_BREAKABLE = 4
local MEMORY_VOLATILE = 8
local MEMORY_THREAT = 16
local MEMORY_WEAPONIZEDNPC = 32

function ENT:ignoreEnt( ent )
    ent.terminatorIgnoreEnt = true

end
function ENT:unIgnoreEnt( ent )
    if not IsValid( ent ) then return end
    ent.terminatorIgnoreEnt = nil

end
function ENT:caresAbout( ent )
    if not IsValid( ent ) then return end
    if ent == self then return end
    if not IsValid( ent:GetPhysicsObject() ) then return end
    if not ent:IsSolid() then return end
    if ent:IsFlagSet( FL_WORLDBRUSH ) then return end
    if ent:IsFlagSet( FL_STATICPROP ) then return end
    if ent:IsPlayer() then return end
    return true

end

function ENT:getAwarenessKey( ent )
    if not IsValid( ent ) then return end
    local model = ent:GetModel()
    local class = ent:GetClass()
    if not isstring( class ) or not isstring( model ) then return "" end
    return class .. " " .. model

end

function ENT:memorizeEntAs( dat1, memory )
    local key = nil
    if isentity( dat1 ) then
        key = self:getAwarenessKey( dat1 )
    elseif isstring( dat1 ) then
        key = dat1
    end
    if not key then return end
    self.awarenessMemory[key] = memory
end

function ENT:getMemoryOfObject( ent )
    local key = self:getAwarenessKey( ent )
    local memory = nil
    local overrideResponse = ent.terminatorHunterInnateReaction
    if isfunction( overrideResponse ) then
        memory = overrideResponse( ent, self )
    else
        memory = self.awarenessMemory[key]
    end
    return memory, key

end

function ENT:memorizedAsBreakable( ent )
    local memory, _ = self:getMemoryOfObject( ent )

    if isnumber( memory ) and memory == MEMORY_BREAKABLE then
        return true

    end
end

function ENT:ClearOrBreakable( start, endpos )
    local tr = util.TraceLine( {
        start = start,
        endpos = endpos,
        mask = MASK_SHOT,
        filter = self,
    } )

    local hitNothingOrHitBreakable = true
    local hitNothing = true
    if tr.Hit then
        hitNothing = nil
        hitNothingOrHitBreakable = nil

    end
    if IsValid( tr.Entity ) then
        local enemy = self:GetEnemy()
        local isVehicle = tr.Entity:IsVehicle() and tr.Entity:GetDriver() and tr.Entity:GetDriver() == enemy
        if self:memorizedAsBreakable( tr.Entity ) then
            hitNothingOrHitBreakable = true

        elseif enemy == tr.Entity or isVehicle then
            hitNothingOrHitBreakable = true
            hitNothing = true

        end
    end

    return hitNothingOrHitBreakable, tr, hitNothing

end

function ENT:understandObject( ent )
    local class = ent:GetClass()
    local memory, _ = self:getMemoryOfObject( ent )

    local isLockedDoor = class == "prop_door_rotating" and ent:GetInternalVariable( "m_bLocked" ) ~= false and ent:IsSolid() and terminator_Extras.CanBashDoor( ent )

    if isLockedDoor then
        -- locked doors create navmesh blocker flags under them even though we can bash them down
        -- KILL ALL LOCKED DOORS!
        table.insert( self.awarnessLockedDoors, ent )
        table.insert( self.awarenessBash, ent )

    end

    if ent.terminatorIgnoreEnt then return end

    if isnumber( memory ) then
        if memory == MEMORY_MEMORIZING then
            table.insert( self.awarenessUnknown, ent )

        elseif memory == MEMORY_INERT then
            -- do nothing, it's inert

        elseif memory == MEMORY_BREAKABLE then -- entities that we can shoot if they're blocking us
            table.insert( self.awarenessBash, ent )
        elseif memory == MEMORY_VOLATILE then -- entities that we can shoot to damage enemies
            table.insert( self.awarenessVolatiles, ent )
        elseif memory == MEMORY_WEAPONIZEDNPC and ( ent:IsNPC() or ent:IsNextBot() ) then
            self:MakeFeud( ent )
        elseif memory == MEMORY_THREAT then-- idea for this was like slams and stuff, not ever gonna happen until i have a miracle of an idea for implimentation
            ---print( "aaa", key )
        end
    else
        local mdl = ent:GetModel()
        local isFunc = class:StartWith( "func_" )
        local isDynamic = class:StartWith( "prop_dynamic" )
        local isWoodBoard = string.find( mdl, "wood_board" )
        local isVentGuard = string.find( mdl, "/vent" )
        local isExplosiveBarrel = string.find( mdl, "oildrum001_explosive" )
        if isFunc then
            local isFuncBreakable = class:StartWith( "func_breakable" )
            if isFuncBreakable and hasReasonableHealth( ent ) then
                self:memorizeEntAs( ent, MEMORY_BREAKABLE )

            else
                self:memorizeEntAs( ent, MEMORY_INERT )

            end
        elseif ent.huntersglee_breakablenails then
            table.insert( self.awarenessBash, ent )

        elseif isDynamic or class == "base_entity" then
            self:memorizeEntAs( ent, MEMORY_INERT )

        elseif isWoodBoard or isVentGuard then
            self:memorizeEntAs( ent, MEMORY_BREAKABLE )

        elseif isExplosiveBarrel then
            self:memorizeEntAs( ent, MEMORY_VOLATILE )

        else
            if class == self:GetClass() and mdl == self:GetModel() then
                self:memorizeEntAs( ent, MEMORY_INERT )

            else
                self:memorizeEntAs( ent, MEMORY_MEMORIZING )
                table.insert( self.awarenessUnknown, ent )

            end
        end
    end
end

local vecMeta = FindMetaTable( "Vector" )
local distToSqr = vecMeta.DistToSqr

function ENT:understandSurroundings()
    self.awarenessSubstantialStuff = {}
    self.awarenessUnknown = {}
    self.awarenessBash = {}
    self.awarenessVolatiles = {}
    self.awarnessLockedDoors = {}
    local pos = self:GetPos()
    local surroundings = ents.FindInSphere( pos, 1500 )

    local centers = {}

    for _, ent in ipairs( surroundings ) do
        centers[ent] = ent:WorldSpaceCenter()

    end

    table.sort( surroundings, function( a, b ) -- sort ents by distance to me 
        local ADist = distToSqr( centers[a], pos )
        local BDist = distToSqr( centers[b], pos )
        return ADist < BDist

    end )

    local substantialStuff = {}
    local caresAbout = self.caresAbout
    for _, currEnt in ipairs( surroundings ) do
        if #substantialStuff > 300 then -- cap this!
            break

        end
        if caresAbout( self, currEnt ) then
            table.insert( substantialStuff, currEnt )

        end
    end

    local understandObject = self.understandObject
    for _, currEnt in ipairs( substantialStuff ) do
        understandObject( self, currEnt )
        table.insert( self.awarenessSubstantialStuff, currEnt )

    end
end

function ENT:getShootableVolatiles( enemy )
    if not self.awarenessVolatiles then return end
    if not enemy then return end

    for _, currVolatile in ipairs( self.awarenessVolatiles ) do
        if not IsValid( currVolatile ) then continue end

        local pos = self:getBestPos( currVolatile )
        if SqrDistGreaterThan( pos:DistToSqr( enemy:GetPos() ), 300 ) then continue end
        if not terminator_Extras.PosCanSee( self:GetShootPos(), pos ) then continue end

        return currVolatile

    end
end

function ENT:GetCachedBashableWithinReasonableRange()
    local nextCache = self.nextBashablesNearbyCache or 0
    local doCache = nextCache < _CurTime()

    if doCache or not self.bashableWithinReasonableRange then
        self.nextBashablesNearbyCache = _CurTime() + 0.8

        local range = self:GetWeaponRange()
        range = range + -40
        range = math.Clamp( range, 0, 150 )
        local bashableWithinReasonableRange = {}

        for _, currentBashable in ipairs( self.awarenessBash ) do
            if not IsValid( currentBashable ) then continue end

            local distSqr = self:GetShootPos():DistToSqr( self:getBestPos( currentBashable ) )
            if SqrDistGreaterThan( distSqr, range ) then continue end

            table.insert( bashableWithinReasonableRange, currentBashable )

        end
        self.bashableWithinReasonableRange = bashableWithinReasonableRange

    end
    return self.bashableWithinReasonableRange

end

function ENT:GetDesiredEnemyRelationship( ent )
    local disp = D_HT
    local theirdisp = D_HT
    local priority = 1000

    if ent.isTerminatorHunterChummy == self.isTerminatorHunterChummy then
        disp = D_LI
        theirdisp = D_LI

    end

    if ent:IsPlayer() then
        priority = 1
    elseif ent:IsNPC() or ent:IsNextBot() then
        local memories = {}
        if self.awarenessMemory then
            memories = self.awarenessMemory
        end
        local key = self:getAwarenessKey( ent )
        local memory = memories[key]
        if memory == MEMORY_WEAPONIZEDNPC then
            priority = priority + -300
        else
            disp = D_NU
            --print("boringent" )
            priority = priority + -100
        end
    end

    return disp,priority,theirdisp
end

-- override this to remove path recalculating, we already do that
function ENT:ControlPath( lookatgoal )
    if not self:PathIsValid() then return false end

    local path = self:GetPath()
    local pos = self:GetPathPos()
    local options = self.m_PathOptions

    local range = self:GetRangeTo( pos )

    if range < options.tolerance or range < self.PathGoalToleranceFinal then
        path:Invalidate()
        return true
    end

    if IsValid( self.terminatorStucker ) then
        return false
    end

    if self:MoveAlongPath( lookatgoal ) then
        return true
    end
end

function ENT:GetDisrespectingEnt()
    local myShootPos = self:GetShootPos()
    local myPos = self:GetPos()
    local disrespector = nil
    local disrespectorRange = 75
    local notClose = 0

    for _, potentialDisrespect in ipairs( self.awarenessSubstantialStuff ) do
        if IsValid( potentialDisrespect ) and not potentialDisrespect:IsWeapon() then
            local disrespectBestPos = potentialDisrespect:NearestPoint( myShootPos )
            local close = SqrDistLessThan( disrespectBestPos:DistToSqr( myShootPos ), disrespectorRange ) or SqrDistLessThan( disrespectBestPos:DistToSqr( myPos ), disrespectorRange )
            if close then
                local clear, trace = terminator_Extras.PosCanSeeComplex( myShootPos, disrespectBestPos, self )
                if clear or ( IsValid( trace.Entity ) and trace.Entity == disrespector ) then
                    disrespector = potentialDisrespect
                    break

                end
            else
                -- table is sorted by dist, stop checking if we get far enough into it
                notClose = notClose + 1
                if notClose >= 20 then
                    break

                end
            end
        end
    end
    return disrespector
end

function ENT:GetCachedDisrespector()
    local nextDisrespectorCache = self.terminator_NextDisrespectorCache or 0
    if nextDisrespectorCache < CurTime() then
        self.terminator_NextDisrespectorCache = CurTime() + 0.1
        self.terminator_CachedDisrespectingEnt = self:GetDisrespectingEnt()

    end

    return self.terminator_CachedDisrespectingEnt

end

-- interacting with shootblocker START

local hullminFists = Vector( -20, -20, -30 )
local hullmaxFists = Vector( 20, 20, 30 )

local hullminOtherwise = Vector( -5, -5, -5 )
local hullmaxOtherwise = Vector( 5, 5, 5 )

local function hullmin( ref )
    if ref.IsFists and ref:IsFists() then
        return hullminFists

    end
    return hullminOtherwise

end


local function hullmax( ref )
    if ref.IsFists and ref:IsFists() then
        return hullmaxFists

    end
    return hullmaxOtherwise

end

function ENT:ShootBlockerWorld( start, pos, filter )

    local nextWorldBlockerCheck = self.nextWorldBlockerCheck or 0
    local readyForCheck = not self.oldWorldBlocker or nextWorldBlockerCheck < _CurTime()

    if not readyForCheck then return self.oldWorldBlocker end

    local traceStruc = {
        start = start,
        endpos = pos,
        filter = filter,
        mask = bit.bor( MASK_SOLID_BRUSHONLY ),
        mins = hullmin( self ),
        maxs = hullmax( self ),
    }
    local tr = util.TraceHull( traceStruc )

    if tr.Hit then
        self.nextWorldBlockerCheck = _CurTime() + 0.1
    else
        self.nextWorldBlockerCheck = _CurTime() + 0.5
    end

    self.oldWorldBlocker = tr

    return tr
end

function ENT:ShootBlocker( start, pos, filter )
    local traceStruc = {
        start = start,
        endpos = pos,
        filter = filter,
        mask = self:GetSolidMask(),
    }
    local tr = util.TraceLine( traceStruc )
    if tr.Hit and not tr.HitWorld then return tr.Entity, tr end

    traceStruc = {
        start = start,
        endpos = pos,
        filter = filter,
        mask = self:GetSolidMask(),
        mins = hullmin( self ),
        maxs = hullmax( self ),
    }
    tr = util.TraceHull( traceStruc )

    return tr.Entity, tr

end

function ENT:Use2( toUse )
    if toUse:IsVehicle() then return end
    hook.Run( "TerminatorUse", self, toUse )
    ProtectedCall( function() toUse:Use( self, self, USE_ON ) end )
    toUse.usedByTerm = true
    local time = _CurTime()
    toUse.usedByTermTime = time
    timer.Simple( 15, function()
        if not toUse then return end
        if toUse.usedByTermTime ~= time then return end
        toUse.usedByTerm = nil
    end )

    local nextUseSound = self.nextUseSound or 0

    if nextUseSound < _CurTime() then
        self.nextUseSound = _CurTime() + math.Rand( 0.05, 0.1 )
        self:EmitSound( "common/wpn_select.wav", 65, math.random( 95, 105 ) )

        if not toUse.GetPhysicsObject then return end
        local obj = toUse:GetPhysicsObject()
        if not obj or not obj.IsValid or not obj:IsValid() then return end

        obj:ApplyForceCenter( VectorRand() * 1000 )

    end
end

function ENT:tryToOpen( blocker, blockerTrace )
    local class = blocker:GetClass()

    local OpenTime = self.OpenDoorTime or 0
    if blocker and blocker ~= self.oldBlockerITriedToOpen then
        self.oldBlockerITriedToOpen = blocker
        self.startedTryingToOpen = _CurTime()

    end
    local startedTryingToOpen = self.startedTryingToOpen or 0

    local doorTimeIsGood = _CurTime() - OpenTime > 2
    local doorIsStale = _CurTime() - startedTryingToOpen > 2
    local doorIsVeryStale = _CurTime() - startedTryingToOpen > 8
    local memory, _ = self:getMemoryOfObject( blocker )
    local breakableMemory = memory == MEMORY_BREAKABLE
    local blockerHp = blocker:Health()
    local isFists = self:IsFists()

    -- i hate the floppy things on the parking garage map
    local theFloppyThingsAndBash = class == "prop_ragdoll" and isFists
    local shouldAttack = string.find( class, "breakable" ) or theFloppyThingsAndBash or ( string.find( class, "prop_" ) and blockerHp > 0 and blockerHp < 100 )

    local range = self:GetWeaponRange()
    local traceDistanceSqr = blockerTrace.StartPos:DistToSqr( blockerTrace.HitPos )
    local blockerAtGoodRange = range and traceDistanceSqr < range^2

    local directlyInMyWay, blockersBearingToPath = self:EntIsInMyWay( blocker, 140 )

    if blocker.huntersglee_breakablenails then
        self:ReallyAnger( 5 )
        self:beatUpEnt( blocker, true )
        self.overrideStuckBeatupEnt = blocker

    elseif class == "prop_door_rotating" and doorTimeIsGood then
        local doorState = blocker:GetInternalVariable( "m_eDoorState" )
        if blocker:GetInternalVariable( "m_bLocked" ) == true and isFists and blockerAtGoodRange then
            self:WeaponPrimaryAttack()

        elseif ( self:IsAngry() and doorIsStale and isFists and terminator_Extras.CanBashDoor( blocker ) and blockerAtGoodRange ) or ( self:IsReallyAngry() and doorIsVeryStale and isFists ) then
            self:WeaponPrimaryAttack()

        elseif doorState ~= 2 then -- door is not open
            self.OpenDoorTime = _CurTime()
            self:Use2( blocker )

        -- door is open but it opened in a way that blocked me 
        elseif doorState == 2 and blockerAtGoodRange and directlyInMyWay then
            if doorIsStale then
                if isFists then
                    self:WeaponPrimaryAttack()

                elseif self.HasFists then
                    self:DoFists()

                end
            elseif _CurTime() - OpenTime > 1 then
                self:Use2( blocker )

            end
        end
    elseif shouldAttack or breakableMemory then
        if breakableMemory and blockerAtGoodRange and self:GetCachedDisrespector() and hasReasonableHealth( blocker ) and not self.IsSeeEnemy then
            self:WeaponPrimaryAttack()

        elseif self:IsReallyAngry() or ( blockersBearingToPath and blockersBearingToPath > 120 ) then
            if range and blockerAtGoodRange then
                self:WeaponPrimaryAttack()

            elseif not self:IsFists() then
                self:WeaponPrimaryAttack()

            end
        end
    elseif ( class == "func_door_rotating" or class == "func_door" ) and blocker:GetInternalVariable( "m_toggle_state" ) == 1 and doorTimeIsGood then
        self.OpenDoorTime = _CurTime()
        self:Use2( blocker )

    elseif doorTimeIsGood and not self:ShouldBeEnemy( blocker ) then
        self.OpenDoorTime = _CurTime()
        self:Use2( blocker )

    -- generic, kill the blocker
    elseif self:IsReallyAngry() and self:caresAbout( blocker ) and not blocker:IsNextBot() and not blocker:IsPlayer() then
        local isFunc = class:StartWith( "func_" )
        local isDynamic = class:StartWith( "prop_dynamic" )
        local interactable = not ( isFunc or isDynamic )
        if interactable and directlyInMyWay and blockerAtGoodRange then
            self:WeaponPrimaryAttack()

        elseif interactable and self.loco:GetVelocity():LengthSqr() < 25^2 then
            self:WeaponPrimaryAttack()

        end
    end
    if string.find( class, "door" ) and self:IsReallyAngry() then
        if isFists then
            self:WeaponPrimaryAttack()
            self:ReallyAnger( 10 )

        elseif self.HasFists then
            self:DoFists()

        end
    end
end

function ENT:BehaviourThink()
    if self:primaryPathIsValid() and not self:IsControlledByPlayer() and not self:DisableBehaviour() then
        local filter = self:GetChildren()
        filter[#filter + 1] = self

        local pos = self:GetShootPos()
        local endpos1 = pos + self:GetAimVector() * 150
        local endpos2 = pos + self:GetAimVector() * 100
        local blocker, blockerTrace = self:ShootBlocker( pos, endpos1, filter )
        local worldBlocker = self:ShootBlockerWorld( pos, endpos2, filter ) or {}

        if IsValid( blocker ) and not blocker:IsWorld() then
            self:tryToOpen( blocker, blockerTrace )

        end

        self.LastShootBlocker = blocker

        local blocks = { blockerTrace, worldBlocker }
        -- slow down bot when it has stuff in front of it
        for _, blocked in ipairs( blocks ) do
            if blocked.Hit and blocked.Fraction < 0.25 then
                local fractionAsTime = math.abs( blocked.Fraction - 1 )
                local time = math.Clamp( fractionAsTime, 0.2, 1 ) * 0.6
                local finalTime = _CurTime() + time
                local oldTime = self.nearObstacleBlockRunning or 0
                if oldTime < finalTime then
                    self.nearObstacleBlockRunning = finalTime
                end
                break
            end
        end
    else
        self.LastShootBlocker = false
    end
end

-- make nextbot recognize two nav areas that dont connect in practice
function ENT:flagConnectionAsShit( area1, area2 )
    if not area1:IsValid() then return end
    if not area2:IsValid() then return end

    if not area1:IsConnected( area2 ) then return end -- we fell off our path area or something

    local superShitConnection = nil
    local nav1Id = area1:GetID()
    local nav2Id = area2:GetID()

    if not istable( navExtraDataHunter.nav1Id ) then navExtraDataHunter.nav1Id = {} end
    if not istable( navExtraDataHunter.nav1Id.shitConnnections ) then navExtraDataHunter.nav1Id.shitConnnections = {} end
    if navExtraDataHunter.nav1Id.shitConnnections[nav2Id] then superShitConnection = true end

    navExtraDataHunter.nav1Id.shitConnnections[nav2Id] = true
    navExtraDataHunter.nav1Id["lastConnectionFlag"] = _CurTime()

    timer.Simple( 120, function()
        local nav = navmesh.GetNavAreaByID( nav1Id )
        if not nav then return end
        if not nav:IsValid() then return end

        local lastFlag = navExtraDataHunter.nav1Id["lastConnectionFlag"] or 0

        if lastFlag + 110 < _CurTime() then return end
        if not navExtraDataHunter.nav1Id then return end
        if not navExtraDataHunter.nav1Id.shitConnnections then return end

        navExtraDataHunter.nav1Id["lastConnectionFlag"] = nil
        navExtraDataHunter.nav1Id.shitConnnections[nav2Id] = nil

    end )

    if not superShitConnection then return end
    if not istable( navExtraDataHunter.nav1Id.superShitConnection ) then navExtraDataHunter.nav1Id.superShitConnection = {} end

    navExtraDataHunter.nav1Id.superShitConnection[nav2Id] = true
    navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] = _CurTime()

    timer.Simple( 520, function()
        local nav = navmesh.GetNavAreaByID( nav1Id )
        if not nav then return end
        if not nav:IsValid() then return end

        local lastFlag = navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] or 0

        if lastFlag + 110 < _CurTime() then return end
        if not navExtraDataHunter.nav1Id then return end
        if not navExtraDataHunter.nav1Id.superShitConnection then return end

        navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] = nil
        navExtraDataHunter.nav1Id.superShitConnection[nav2Id] = nil

    end )
end

-- add constraints 

local vecFiftyZ = Vector( 0,0,50 )

-- some of the oldest code in this file right here
local function FindSpot2( self, Options )
    local pos = Options.Pos
    local Checked = self.SearchCheckedNavs
    local SelfPos = self:GetPos()

    local Areas = navmesh.Find( pos, Options.Radius, Options.Stepdown, Options.Stepup )
    if not Areas then return end
    local Count = table.Count( Areas )
    local I = 0
    local HidingSpots = {}
    local walkedAreas = self.walkedAreas
    local FinalSpot = nil

    while I < Count do
        I = I + 1
        local Curr = Areas[I]
        local Valid = Curr:IsValid()
        if not Valid then return end

        local CurrId = Curr:GetID()
        local unReachable = not self:areaIsReachable( Curr )
        local AreaChecked = Checked[ CurrId ] 
        local UnderWater = Curr:IsUnderwater() and not Options.AllowWet
        local Walked = walkedAreas[ CurrId ]
        local block = unReachable or UnderWater or AreaChecked or Walked
        if Valid and not block then
            local ValidSpots = Curr:GetHidingSpots( Options.Type )
            table.Add( HidingSpots, ValidSpots )

        end
    end

    local _ = 0
    local Done = false
    local Offset = vecFiftyZ
    Count = table.Count( HidingSpots )

    while _ < Count and not Done do
        _ = _ + 1
        local CurrSpot = HidingSpots[_]
        local DistSqrToCurr = CurrSpot:DistToSqr( pos )
        if SqrDistGreaterThan( DistSqrToCurr, Options.MinRadius ) then
            if not Options.Visible then
                if not terminator_Extras.PosCanSee( pos + Offset, CurrSpot + Offset ) then
                    Done = true
                    FinalSpot = CurrSpot
                --else 
                    --debugoverlay.Cross( CurrSpot, 2, 10, Color( 255, 0, 0 ), true )
                end
            elseif Options.Visible then
                if terminator_Extras.PosCanSee( SelfPos + Offset, CurrSpot + Offset ) then
                    Done = true
                    FinalSpot = CurrSpot
                end
            end
        end
        if not Done then
            local currSpotNav = terminator_Extras.getNearestNav( CurrSpot )
            if currSpotNav and currSpotNav:IsValid() then
                table.insert( self.SearchCheckedNavs, currSpotNav:GetID(), true )
            end
        --else 
            --debugoverlay.Cross( FinalSpot, 20, 10, Color( 255, 255, 255 ), true )
        end
    end

    if Done and FinalSpot then
        return FinalSpot

    else
        return nil

    end
end
-- set these vars for the unstucker
local function StartNewMove( self )
    self.LastMovementStart = _CurTime()
    self.LastMovementStartPos = self:GetPos()

end

function ENT:nextNewPathIsGood()
    local nextNewPath = self.nextNewPath or 0
    if nextNewPath > _CurTime() then return end
    if self.isHoppingOffLadder then
        self.isHoppingOffLadderCount = ( self.isHoppingOffLadderCount or 0 ) + 1
        if self.isHoppingOffLadderCount > 100 then
            self.isHoppingOffLadder = false
            self.isHoppingOffLadderCount = nil

        end
        return

    end

    return true
end

function ENT:CanDoNewPath( pathTarget )
    if not isvector( pathTarget ) then return false end
    if not self:nextNewPathIsGood() then return false end
    if self.BlockNewPaths then return false end
    local NewPathDist = 1
    local Dist = self:GetPath():GetLength() or 0
    local PathPos = self.PathEndPos or vec_zero

    if Dist > 10000 then
        NewPathDist = 3000 -- dont do pathing as often if the target is far away from me!
    elseif Dist > 5000 then
        NewPathDist = 1500
    elseif Dist > 500 then
        NewPathDist = 300
    elseif Dist > 100 then
        NewPathDist = 50
    end

    local needsNew = SqrDistGreaterThan( pathTarget:DistToSqr( PathPos ), NewPathDist ) or self.needsPathRecalculate
    self.needsPathRecalculate = nil
    return needsNew

end


-- do this so we can store extra stuff about new paths
function ENT:SetupPath2( endpos, isUnstuck )
    -- unstucking paths are VIP
    if not isUnstuck and not self:nextNewPathIsGood() then return end
    self.nextNewPath = _CurTime() + math.Rand( 0.05, 0.1 )

    if not isvector( endpos ) then return end
    if self.isUnstucking and not isUnstuck then return end

    local endArea = terminator_Extras.getNearestPosOnNav( endpos )

    local reachable = self:areaIsReachable( endArea.area )
    if not reachable then
        -- make sure we dont get super duper stuck
        if self.isUnstucking and isUnstuck then
            self.overrideVeryStuck = true

        end
        return

    end

    local pathDestinationIsAnOrphan, encounteredABlockedArea = self:AreaIsOrphan( endArea.area )

    if pathDestinationIsAnOrphan ~= true then -- if we are not going to an orphan ( can still be an orphan, this is just a sanity check! )
        StartNewMove( self )
        self:SetupPath( endpos )
        self.PathEndPos = endpos

        -- good path
        if self:primaryPathIsValid() then
            self.setupPath2NoNavs = nil
            return

        -- no path! something failed
        else
            local setupPath2NoNavs = self.setupPath2NoNavs or 0
            -- aha, im not on the navmesh! that's why!
            if not navmesh.GetNearestNavArea( self:GetPos(), false, 45, false, false, -2 ) and self:IsOnGround() then
                self.setupPath2NoNavs = setupPath2NoNavs + 1

            end
            if setupPath2NoNavs > 5 then
                self.setupPath2NoNavs = nil
                self.overrideVeryStuck = true

            end
        end
    end

    if encounteredABlockedArea then
        self.encounteredABlockedAreaWhenPathing = true

    end

    if not self:IsOnGround() then return end -- don't member as unreachable when we're in the air
    if endArea.area:GetClosestPointOnArea( endpos ):Distance( endpos ) > 10 then return end

    --debugoverlay.Text( endArea.area:GetCenter(), "unREACHABLE" .. tostring( pathDestinationIsAnOrphan ), 8 )

    local scoreData = {}
    scoreData.decreasingScores = {}
    scoreData.droppedDownAreas = {}
    scoreData.areasToUnreachable = {}
    wasABlockedArea = nil

    -- find areas around the path's end that we can't reach
    local scoreFunction = function( scoreData, area1, area2 )
        local score = scoreData.decreasingScores[area1:GetID()] or 10000
        local droppedDown = scoreData.droppedDownAreas[area1:GetID()]
        local dropToArea = area2:ComputeAdjacentConnectionHeightChange( area1 )

        -- we are dealing with a locked door, not an orphan/elevated area!
        if area2:IsBlocked() then
            wasABlockedArea = true
            score = 0

        elseif dropToArea > self.loco:GetMaxJumpHeight() or droppedDown then
            score = 1
            scoreData.droppedDownAreas[area2:GetID()] = true

        else
            score = score + -1
            table.insert( scoreData.areasToUnreachable, area2 )

        end

        --debugoverlay.Text( area2:GetCenter(), tostring( score ), 8 )
        scoreData.decreasingScores[area2:GetID()] = score

        return score

    end
    self:findValidNavResult( scoreData, endArea.area:GetCenter(), 3000, scoreFunction )

    -- if there was a locked door, don't remember as unreachable!
    if not wasABlockedArea then
        self:rememberAsUnreachable( endArea.area )

        for _, area in ipairs( scoreData.areasToUnreachable ) do
            self:rememberAsUnreachable( area )

        end
    end

    -- make sure we dont get super duper stuck
    if self.isUnstucking and isUnstuck then
        self.overrideVeryStuck = true

    end

    return true
end

-- this is a stupid hack
-- fixes bot firing guns slow in multiplyer, without making bot think faster.
-- eg m9k minigun firing at one tenth its actual fire rate
function ENT:CreateShootingTimer()
    local timerName = "terminator_fastshootingthink_" .. self:GetCreationID()
    timer.Create( timerName, 0, 0, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        if self.terminator_FiringIsAllowed ~= true then return end

        self:WeaponPrimaryAttack()

        if math.abs( self.terminator_LastFiringIsAllowed - CurTime() ) > 0.25 then
            self.terminator_FiringIsAllowed = nil

        end
    end )
end

function ENT:shootAt( endpos, blockShoot )
    self.terminator_FiringIsAllowed = nil
    self.terminator_LastFiringIsAllowed = CurTime()
    if not endpos then return end
    local endposOffsetted = endpos
    local enemy = self:GetEnemy()
    local wep = self:GetWeapon()
    if IsValid( enemy ) and not wep.terminator_NoLeading then
        endposOffsetted = endposOffsetted + ( enemy:GetVelocity() * 0.08 )
        endposOffsetted = endposOffsetted - ( self:GetVelocity() * 0.08 )

    end
    local attacked = nil
    local out = nil
    local pos = self:GetShootPos()
    local dir = endposOffsetted-pos
    dir:Normalize()

    self:SetDesiredEyeAngles( dir:Angle() )

    local angNeeded = 11.25
    if self:IsMeleeWeapon() then
        angNeeded = 60

    elseif wep.terminator_IsBurst then
        angNeeded = 4

    end

    local dot = math.Clamp( self:GetAimVector():Dot( dir ), 0, 1 )
    local ang = math.deg( math.acos( dot ) )

    if ang <= angNeeded and not blockShoot then
        local filter = self:GetChildren()
        filter[#filter + 1] = self
        filter[#filter + 1] = enemy
        local blockAttack = nil
        -- witness me hack for glee
        if enemy.AttackConfirmed then
            if IsValid( enemy ) and not blockShoot and enemy:Health() > 0 and self.DistToEnemy < self:GetWeaponRange() * 1.5 then
                enemy.AttackConfirmed( enemy, self )

            end
            if not enemy.attackConfirmedBlock then
                self.terminator_FiringIsAllowed = true
                attacked = true

            else
                blockAttack = true

            end
        end
        if not attacked and not blockAttack then
            self.terminator_FiringIsAllowed = true

            local nextWeaponJudge = self.nextWeaponJudge or 0
            -- fix over-judging in singleplayer
            if nextWeaponJudge < _CurTime() then
                self.nextWeaponJudge = _CurTime() + 0.08
                self:JudgeWeapon()

            end
            attacked = true
        end
    end

    if ang < 1 then
        out = true
    end
    return out, attacked

end

function ENT:canHitEnt( ent )
    local myShootPos = self:GetShootPos()
    local objPos = self:getBestPos( ent )
    local behindObj = objPos + terminator_Extras.dirToPos( myShootPos, objPos ) * 40

    -- use fist's mask!
    local mask = nil
    if self:IsFists() and self:GetWeapon().HitMask then
        mask = self:GetWeapon().HitMask

    end

    local _, hitTrace = terminator_Extras.PosCanSeeComplex( myShootPos, behindObj, self, mask )
    --debugoverlay.Cross( hitTrace.HitPos, 10, 10 )

    local closenessSqr = myShootPos:DistToSqr( objPos )
    local weapDist = self:GetWeaponRange() + -20
    local hitReallyClose = SqrDistLessThan( hitTrace.HitPos:DistToSqr( behindObj ), 30 ) or SqrDistLessThan( hitTrace.HitPos:DistToSqr( objPos ), 30 )
    local visible = ( hitTrace.Entity == ent ) or hitReallyClose

    local canHit = visible and ( weapDist == math.huge or SqrDistLessThan( closenessSqr, weapDist ) )

    return canHit, closenessSqr, objPos, hitTrace.HitPos, visible

end

local crouchingOffset = Vector( 0,0,30 )
local standingOffset = Vector( 0,0,50 )

-- throw away swep, go towards ent, and beat it up
function ENT:beatUpEnt( ent, unstucking )
    local valid = true
    local forcePath = nil
    local alwaysValid = nil
    local canHit, closenessSqr, entsRealPos, _, visible = self:canHitEnt( ent )

    local isNear = SqrDistLessThan( closenessSqr, 500 )
    local quiteNear = SqrDistLessThan( closenessSqr, 150 )
    local isClose = SqrDistLessThan( closenessSqr, 50 )

    local nearAndCanHit = canHit and isNear
    local closeAndCanHit = canHit and isClose
    if quiteNear then
        local distIfCrouch = ( self:GetPos() + crouchingOffset ):DistToSqr( entsRealPos )
        local distIfStand = ( self:GetPos() + standingOffset ):DistToSqr( entsRealPos )

        if distIfCrouch < distIfStand then
            self.overrideCrouch = _CurTime() + 0.3
            self.forcedShouldWalk = _CurTime() + 0.2

        end
    end
    --debugoverlay.Cross( entsRealPos, 50, 1, Color( 255, 255, 0 ), true )

    local blockShoot = true

    if canHit then
        if closeAndCanHit and not self:IsFists() and self.HasFists then
            self:DoFists()

        end
        blockShoot = nil

    end

    local _, attacked = self:shootAt( entsRealPos, blockShoot )
    self.blockAimingAtEnemy = _CurTime() + 0.2

    local pathValid = self:primaryPathIsValid()
    if unstucking then
        pathValid = self:PathIsValid()

    end

    local newPathWouldBeCheap = self:CanDoNewPath( entsRealPos )
    local newPath = not pathValid or ( pathValid and newPathWouldBeCheap )
    newPath = newPath and not closeAndCanHit

    if newPath and not unstucking then
        local pathPos = entsRealPos
        local area = nil
        for index = 1, 150 do
            local offset = VectorRand()
            offset.z = 0
            offset:Normalize()
            offset = offset * index
            area = navmesh.GetNavArea( entsRealPos + offset, 5000 )
            if area then break end

        end

        if area and not nearAndCanHit and area:IsValid() then
            local adjacents = area:GetAdjacentAreas()
            local foundBlocker = area:IsBlocked()
            if #adjacents > 0 then
                for _, adjArea in ipairs( adjacents ) do
                    if adjArea:IsBlocked() and not foundBlocker then
                        adjacents = adjArea:GetAdjacentAreas()
                        foundBlocker = true
                        break
                    end
                end
            end

            -- the beating up is a blocker, build a path to one of the areas next to it, and make sure that path gets us close to the blocker!
            if foundBlocker then
                forcePath = true
                alwaysValid = true
                local thaArea = table.Random( adjacents )
                -- the adjacent area is also blocked....
                if thaArea:IsBlocked() then
                    forcePath = nil
                    alwaysValid = nil

                end

                local maxSize = math.max( thaArea:GetSizeX(), thaArea:GetSizeY() )
                local ratio = 0.9

                if maxSize < 125 then
                    ratio = 0.6

                end

                local ratio2 = 1 - ratio
                local closestComp = thaArea:GetClosestPointOnArea( entsRealPos ) * ratio
                local centerComp = thaArea:GetCenter() * ratio2

                pathPos = closestComp + centerComp

            end
        end

        --debugoverlay.Cross( pathPos, 100, 1, color_white, true )

        self:GetPath():Invalidate()
        self:SetupPath2( pathPos, forcePath )

        if not self:primaryPathIsValid() and not alwaysValid then
            self:ignoreEnt( ent )
            valid = false

        end
    elseif pathValid and not unstucking then
        self:ControlPath2( true )

    else
        self:GotoPosSimple( entsRealPos, 5 )

        self.forcedShouldWalk = _CurTime() + 0.4
        self.blockControlPath = _CurTime() + 0.1

    end

    return valid, attacked, nearAndCanHit, closeAndCanHit, isNear, isClose, visible

end

function ENT:ResetUnstuckInfo()
    self.StuckPos5 = vec_zero
    self.StuckPos4 = vec_zero
    self.StuckPos3 = vec_zero
    self.StuckPos2 = vec_zero

    self.StuckEnt4 = nil
    self.StuckEnt3 = nil
    self.StuckEnt2 = nil
    self.StuckEnt1 = nil

    --print( "reset" )

end

-- unstuck that flags a connection as bad, then the bot will bash anything nearby, then it will back up.
-- there are 2 more unstucks, one that teleports the bot when it is REALLY stuck ( reallystuck_handler task ), and the base one ( in motionoverrides ) that teleports it to a clear spot next to it, if it's intersecting anything
local function HunterIsStuck( self )
    local nextUnstuck = self.nextUnstuckCheck or 0
    if nextUnstuck > _CurTime() then return end

    if IsValid( self.terminatorStucker ) then return true end

    if self.overrideMiniStuck then self.overrideMiniStuck = nil return true end

    if not self.nextUnstuckCheck then
        self.nextUnstuckCheck = _CurTime() + 0.1
        self:ResetUnstuckInfo()

    end
    self.nextUnstuckCheck = _CurTime() + 0.2

    local HasAcceleration = self.loco:GetAcceleration()
    if HasAcceleration <= 0 then return end

    local myPos = self:GetPos()
    local StartPos = self.LastMovementStartPos or vec_zero
    local GoalPos = self.PathEndPos or vec_zero
    local NotMoving
    if self.terminator_HandlingLadder and self.StuckPos5 and self.StuckPos3 then
        NotMoving = myPos:DistToSqr( self.StuckPos5 ) < 20^2 and myPos:DistToSqr( self.StuckPos3 ) < 20^2

    else
        NotMoving = DistToSqr2D( myPos, self.StuckPos5 ) < 20^2 and DistToSqr2D( myPos, self.StuckPos3 ) < 20^2

    end

    --[[if self.StuckPos3 and self.StuckPos5 then
        --debugoverlay.Sphere( self.StuckPos3, 20, 2, color_white, true )
        --debugoverlay.Sphere( self.StuckPos5, 20, 2, color_white, true )

    end--]]

    local blocker = self.LastShootBlocker
    if not IsValid( blocker ) then
        blocker = self:GetCachedDisrespector()

    end

    local FarFromStart = DistToSqr2D( myPos, StartPos ) > 15^2
    local FarFromStartAndNew = FarFromStart or ( self.LastMovementStart + 1 < _CurTime() )
    local FarFromEnd = DistToSqr2D( myPos, GoalPos ) > 15^2
    local IsPath = self:PathIsValid()

    local NotMovingAndSameBlocker = self.StuckEnt1 and ( self.StuckEnt1 == self.StuckEnt2 ) and ( self.StuckEnt1 == self.StuckEnt4 ) and DistToSqr2D( myPos, self.StuckPos2 ) < 20^2 and DistToSqr2D( myPos, self.StuckPos3 ) < 20^2

    local nextPosUpdate = self.nextPosUpdate or 0

    if nextPosUpdate < _CurTime() and IsPath then
        if self:canDoRun() and not self:IsJumping() then
            self.nextPosUpdate = _CurTime() + 0.5
        else
            self.nextPosUpdate = _CurTime() + 0.9
        end
        self.StuckPos5 = self.StuckPos4
        self.StuckPos4 = self.StuckPos3
        self.StuckPos3 = self.StuckPos2
        self.StuckPos2 = self.StuckPos1
        self.StuckPos1 = myPos

        self.StuckEnt4 = self.StuckEnt3
        self.StuckEnt3 = self.StuckEnt2
        self.StuckEnt2 = self.StuckEnt1
        self.StuckEnt1 = blocker

    end

    --print( ( NotMoving or NotMovingAndSameBlocker ), FarFromStartAndNew, FarFromEnd, IsPath )
    local stuck = ( NotMoving or NotMovingAndSameBlocker ) and FarFromStartAndNew and FarFromEnd and IsPath
    if stuck then -- reset so chains of stuck events happen less
        self:ResetUnstuckInfo()

    end

    return stuck

end

function ENT:IsUnderDisplacement()
    local myPos = self:GetShootPos()

    -- get the sky
    local firstTraceDat = {
        start = myPos,
        endpos = myPos + vector6000ZUp,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local firstTraceResult = util.TraceLine( firstTraceDat )

    -- go back down
    local secondTraceDat = {
        start = firstTraceResult.HitPos,
        endpos = myPos,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local secondTraceResult = util.TraceLine( secondTraceDat )
    if secondTraceResult.HitTexture ~= "**displacement**" then return end

    -- final check to make sure
    local thirdTraceDat = {
        start = myPos,
        endpos = myPos + vector1000ZDown,
        mask = MASK_SOLID_BRUSHONLY,
    }
    local thirdTraceResult = util.TraceLine( thirdTraceDat )
    if thirdTraceResult.HitTexture ~= "TOOLS/TOOLSNODRAW" then return nil, true end -- we are probably under a displacement

    -- we are DEFINITely under one
    return true, nil
end


function ENT:GetTrueCurrentNavArea()
    -- don't redo this when we just updated it
    local area = NULL
    local nextTrueAreaCache = self.nextTrueAreaCache or 0
    if nextTrueAreaCache < _CurTime() then
        area = terminator_Extras.getNearestNavFloor( self:GetPos() )
        self.nextTrueAreaCache = _CurTime() + 0.08

    end
    if area == NULL then area = nil end
    self.cachedTrueArea = area

    return area
end

--do this so we can override the nextbot's current path
function ENT:ControlPath2( AimMode )
    local result = nil
    if self.blockControlPath and self.blockControlPath > _CurTime() then return end
    local badPathAndStuck = self.isUnstucking and not self:PathIsValid()
    local bashableWithinReasonableRange = self:GetCachedBashableWithinReasonableRange()

    if HunterIsStuck( self ) or badPathAndStuck then -- new unstuck
        self.startUnstuckDestination = self.PathEndPos -- save where we were going
        self.startUnstuckPos = self:GetPos()
        self.lastUnstuckStart = _CurTime()
        local myNav = self:GetTrueCurrentNavArea() or self:GetCurrentNavArea()
        local scoreData = {}

        scoreData.canDoUnderWater = self:isUnderWater()
        scoreData.self = self
        scoreData.dirToEnd = self:GetForward()
        scoreData.bearingPos = self.startUnstuckPos

        if self:PathIsValid() then
            scoreData.dirToEnd = terminator_Extras.dirToPos( self:GetPos(), self:GetPath():GetEnd() )
            local goalArea = self:GetNextPathArea( myNav )
            if not goalArea then goto skipTheShitConnectionFlag end
            if not goalArea:IsValid() then goto skipTheShitConnectionFlag end

            --print( "flag" )
            --debugoverlay.Line( myNav:GetCenter() + Vector( 0,0,30 ), goalArea:GetCenter() + Vector( 0,0,30 ), 120 )
            self:flagConnectionAsShit( myNav, goalArea )

            --debugoverlay.Line( myNav:GetCenter(), goalArea:GetCenter(), 5 )
            --debugoverlay.Cross( myNav:GetCenter(), 5 )

            ::skipTheShitConnectionFlag::

            self:GetPath():Invalidate()

        end

        for _ = 1, 4 do

            local randOffset = math.random( -40, 40 )

             -- find an area that is at least in the opposite direction of our current path
            local scoreFunction = function( scoreData, area1, area2 )
                local dirToEnd = scoreData.dirToEnd:Angle()
                local bearing = terminator_Extras.BearingToPos( scoreData.bearingPos, dirToEnd, area2:GetCenter(), dirToEnd )
                bearing = math.abs( bearing )
                bearing = bearing + randOffset
                local dropToArea = math.abs( area1:ComputeAdjacentConnectionHeightChange( area2 ) )
                local score = 5
                if area2:HasAttributes( NAV_MESH_TRANSIENT ) then
                    score = 0.1
                elseif bearing < 45 then
                    score = score * 15
                elseif bearing < 135 then
                    score = score * 5
                elseif bearing > 135 then
                    score = 0.1
                else
                    local dist = scoreData.bearingPos:Distance( area2:GetCenter() )
                    local removed = dist * 0.01
                    score = math.Clamp( 1 - removed, 0, 1 )
                end
                if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                    score = score * 0.001
                end
                if dropToArea > self.loco:GetStepHeight() then
                    score = score * 0.01
                end

                --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( bearing ) ), 4 )

                return score

            end

            local _, escapeArea = self:findValidNavResult( scoreData, self:GetPos(), 1000, scoreFunction )
            if not escapeArea then continue end
            if not escapeArea:IsValid() then continue end
            --debugoverlay.Cross( escapeArea:GetCenter(), 50, 100, Color( 255, 255, 0 ), true )
            self:SetupPath2( escapeArea:GetRandomPoint(), true )

            if self:PathIsValid() and myNav then
                self.initArea = myNav
                self.initAreaId = self.initArea:GetID()
                break

            end
        end

        if not self:PathIsValid() then return end

        self.isUnstucking = true
        self:ReallyAnger( 10 )
        self.unstuckingTimeout = _CurTime() + 10
        self.tryToHitUnstuck = true

    end
    if self.tryToHitUnstuck then
        local done = nil
        local toBeat = self.entToBeatUp
        local disrespector = self:GetCachedDisrespector()

        local newEnt = self.overrideStuckBeatupEnt or self.LastShootBlocker or bashableWithinReasonableRange[1] or disrespector

        if self.hitTimeout then
            if IsValid( toBeat ) then
                local valid, attacked, nearAndCanHit, closeAndCanHit, isNear, isClose, visible = self:beatUpEnt( toBeat, true )
                local isNailed = istable( toBeat.huntersglee_breakablenails )
                local isInDanger = self:getLostHealth() >= 20
                local dangerAndNotNailed = isInDanger and not isNailed
                -- door was bashed or we are bored
                if self.hitTimeout < _CurTime() or not toBeat:IsSolid() or dangerAndNotNailed then
                    done = true
                    self.lastBeatUpEnt = toBeat

                end
                if not closeAndCanHit or not visible then
                    self.entToBeatUp = nil
                    self.lastBeatUpEnt = toBeat

                end
                -- BEAT UP THE NAILED THING!
                if isNailed and visible and nearAndCanHit and closeAndCanHit then
                    self.hitTimeout = _CurTime() + 3

                elseif isNailed and not isClose and visible and self:GetWeaponRange() > 500 then
                    self:shootAt( toBeat )

                end
            -- was valid
            elseif not IsValid( toBeat ) then
                -- something new to break
                local somethingNewToBeatup = bashableWithinReasonableRange[1]
                local newWithinBashRange = IsValid( somethingNewToBeatup ) and self.lastBeatUpEnt ~= somethingNewToBeatup
                local newDisrespector = IsValid( disrespector ) and self.lastBeatUpEnt ~= disrespector
                if newWithinBashRange or newDisrespector then
                    toBeat = bashableWithinReasonableRange[1] or disrespector
                    self.entToBeatUp = toBeat
                    self.hitTimeout = _CurTime() + 3

                else
                    done = true

                end
            end
        elseif ( IsValid( self.LastShootBlocker ) and self.LastShootBlocker ~= self.lastBeatUpEnt ) or ( IsValid( newEnt ) and newEnt ~= self.lastBeatUpEnt ) then
            self.hitTimeout = _CurTime() + 3

            self.overrideStuckBeatupEnt = nil

        else
            done = true

        end
        if done or ( self.hitTimeout + 1 ) < _CurTime() then
            self.entToBeatUp = nil
            self.hitTimeout = nil
            self.tryToHitUnstuck = nil

        end
    elseif self.isUnstucking then
        local result = self:ControlPath( AimMode )
        local DistToStart = self:GetPos():Distance( self.startUnstuckPos )
        local FarEnough = DistToStart > 200
        local MyNavArea = self:GetTrueCurrentNavArea() or self:GetCurrentNavArea()
        if not MyNavArea then return end
        local NotStart = self.initAreaId ~= MyNavArea:GetID()

        local Escaped = nil
        local Failed = nil

        if FarEnough and NotStart then
            Escaped = true
        elseif result then
            Escaped = true
        elseif result == false then
            Failed = true
        end
        if Escaped or self.unstuckingTimeout < _CurTime() then
            self.isUnstucking = nil
            self:SetupPath2( self.startUnstuckDestination )
        end
    else
        local wep = self:GetWeapon()
        if wep and wep.worksWithoutSightline and IsValid( self:GetEnemy() ) and AimMode == true then
            AimMode = nil

        end
        result = self:ControlPath( AimMode )

    end
    return result
end

-- do this so we can get data about current tasks easily
function ENT:StartTask2( Task, Data, Reason )
    --if not Reason then
        --error( "task started with no reason" )

    --end
    --print( self:GetCreationID(), Task, self:GetEnemy(), Reason ) --global
    --if istable( Data ) then
    --    PrintTable( Data )

    --end
    self.BlockNewPaths = nil -- make sure this never persists between tasks
    Data2 = Data or {}
    Data2.taskStartTime = _CurTime()
    self:StartTask( Task, Data2 )

    if GetConVar( "sv_cheats" ):GetBool() ~= true then return end
    -- additional debugging tool
    self.taskHistory = self.taskHistory or {}

    table.insert( self.taskHistory, Task .. " " .. Reason )

end

-- super useful

function ENT:Use( user )
    if not user:IsPlayer() then return end
    if GetConVar( "sv_cheats" ):GetBool() ~= true then return end
    self.taskHistory = self.taskHistory or {}
    PrintTable( self.m_ActiveTasks )
    PrintTable( self.taskHistory )
    print( self.lastShootingType )
    print( self:GetEyeAngles() )
    print( self:GetEyeAngles(), self:GetAimVector() )

end


function ENT:canIntercept( data )
    local interceptTime = self.lastInterceptTime or 0
    local closeToEnd = self.lastInterceptPos and SqrDistGreaterThan( self.lastInterceptPos:DistToSqr( self:GetPath():GetEnd() ), 800 )
    local freshIntercept = true
    if data.taskStartTime then
        freshIntercept = interceptTime > ( data.taskStartTime + -1 ) and ( data.taskStartTime + 1 ) <= _CurTime()

    end
    local intercept = freshIntercept and not self.IsSeeEnemy and closeToEnd

    return intercept

end

function ENT:CanBashLockedDoor( reference, distNeeded )
    if not self.encounteredABlockedAreaWhenPathing then return end
    if not IsValid( self.awarnessLockedDoors[1] ) then return end

    if not reference then reference = self:GetPos() end
    if not distNeeded then distNeeded = 800 end

    if self.awarnessLockedDoors[1]:GetPos():DistToSqr( reference ) > distNeeded^2 then return end
    return true

end

function ENT:BashLockedDoor( currentTask )
    if not IsValid( self.awarnessLockedDoors[1] ) then return end
    self.encounteredABlockedAreaWhenPathing = nil
    self:TaskComplete( currentTask )
    self:StartTask2( "movement_bashobject", { object = self.awarnessLockedDoors[1], insane = true }, "there's a locked door and one of them blocked my path earlier" )
    return true

end

-- handle spotting enemy once here, instead of differently in every single task ever
function ENT:EnemyAcquired( currentTask )
    if not IsValid( self ) then return end -- i dont think i need to start a new task in this case
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_handler", nil, "ea, invalid enemy" )
        return

    end
    local tooDangerousToApproach = self:EnemyIsLethalInMelee()
    local enemPos = self:EntShootPos( enemy )
    local myPos = self:GetPos()
    local hp = self:Health()
    local maxHp = self:GetMaxHealth()
    local seeEnemy = self:CanSeePosition( enemy ) -- check here so it's always accurate, fucked me over tho
    local bearingToMeAbs = self:enemyBearingToMeAbs()
    local distToEnemySqr = myPos:DistToSqr( enemPos )
    local weapRange = self:GetWeaponRange()
    local notMelee = not self:IsMeleeWeapon( self:GetWeapon() )
    local reallyAngry = self:IsReallyAngry()

    local sameZ = ( myPos.z < enemPos.z + 200 ) and ( myPos.z > enemPos.z + -200 )
    local withinWeapRange = weapRange == math.huge or SqrDistGreaterThan( distToEnemySqr, weapRange )
    local damaged = hp < ( maxHp * 0.75 )
    local veryDamaged = hp < ( maxHp * 0.5 )
    local enemySeesMe = bearingToMeAbs < 20
    local lowOrRand = ( damaged and math.random( 0, 100 ) > 15 ) or math.random( 0, 100 ) > 85
    local boredOrRand = self.boredOfWatching or math.random( 0, 100 ) > 65

    local enemyIsNotVeryClose = SqrDistGreaterThan( distToEnemySqr, 300 )
    local enemyIsNotClose = SqrDistGreaterThan( distToEnemySqr, 500 )
    local enemyIsFar = SqrDistGreaterThan( distToEnemySqr, 2000 )
    local watchCount = self.watchCount or 0

    local veryHighHealth = hp == maxHp
    local campIsGood = ( boredOrRand and not veryHighHealth ) or weapRange > 6000

    -- when we haven't watched before, be very lenient with the distance
    local doFirstWatch = veryHighHealth and enemyIsNotVeryClose and watchCount == 0 and not enemy.isTerminatorHunterKiller
    local doNormalWatch = veryHighHealth and enemyIsNotClose and not self.boredOfWatching and not reallyAngry
    local doBaitWatch = not reallyAngry and enemyIsNotVeryClose and self:AnotherHunterIsHeadingToEnemy() and enemy.terminator_TerminatorsWatching and #enemy.terminator_TerminatorsWatching < 1
    local doCamp = SqrDistGreaterThan( distToEnemySqr, 1400 ) and ( not doWatch ) and campIsGood and withinWeapRange and notMelee
    local canRushKiller = enemy.isTerminatorHunterKiller and hp > ( maxHp * 0.80 ) and not tooDangerousToApproach
    local isBeingFooled = IsValid( enemy.terminator_crouchingbaited ) and enemy.terminator_crouchingbaited ~= self and enemy.terminator_crouchingbaited.IsSeeEnemy and not enemy.terminator_CantConvinceImFriendly
    local campDangerousEnemy = tooDangerousToApproach and enemyIsFar and withinWeapRange

    local doStalk = enemySeesMe and seeEnemy and ( lowOrRand or veryDamaged ) and sameZ
    doStalk = doStalk or tooDangerousToApproach -- always do stalking if the enemy has killed tons of terminators in close range 

    local doFlank = ( lowOrRand or enemy.isTerminatorHunterKiller ) and not SqrDistLessThan( distToEnemySqr, 400 )

    if not seeEnemy and self.lastInterceptPos and self:canIntercept( { startTime = 0 } ) then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_intercept", nil, "ea, i can intercept someone" )
    elseif isBeingFooled then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, this is gonna fool em so hard" )
    elseif not seeEnemy then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_approachlastseen", nil, "ea, where'd they go" )
    elseif doBaitWatch then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, another hunter will sneak up on them!" )
    elseif doFirstWatch or doNormalWatch then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, watching something" )
    elseif campDangerousEnemy then
        local tolerance = self:campingTolerance()
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_camp", { maxNoSeeing = tolerance }, "ea, enemy is scary! camp them" )
    elseif doCamp then
        self:TaskComplete( currentTask )
        if math.random( 0, 100 ) > 50 or SqrDistLessThan( distToEnemySqr, 2750 ) then
            local tolerance = self:campingTolerance()
            self:StartTask2( "movement_camp", { maxNoSeeing = tolerance }, "ea, camp or perch, camped because too close or random" )
        else
            self:StartTask2( "movement_perch", { requiredTarget = enemPos, cutFarther = true, perchRadius = math.sqrt( distToEnemySqr ), distanceWeight = 0.01 }, "ea, camp or perch, perch" )
        end
    elseif canRushKiller then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_flankenemy", nil, "ea, rush a killer" )
        self.PreventShooting = nil
    elseif doStalk then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_stalkenemy", nil, "ea, stalk them" )
    elseif doFlank then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_flankenemy", nil, "ea, flank them" )
        self.PreventShooting = nil
    else
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_followenemy", nil, "ea, im just gonna rush them, i couldnt do anything else" )
        self.PreventShooting = nil
    end
    return true
end

function ENT:markAsWalked( area )
    if not IsValid( area ) then return end
    self.walkedAreas[area:GetID()] = true
    self.walkedAreaTimes[area:GetID()] = CurTime()
    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        if not IsValid( area ) then return end
        table.remove( self.walkedAreas, area:GetID() )
        table.remove( self.walkedAreaTimes, area:GetID() )

    end )
end

local offset25z = Vector( 0, 0, 25 )

-- very useful for searching!
function ENT:walkArea()
    local walkedArea = self:GetCurrentNavArea()
    if not walkedArea then return end

    self:rememberAsReachable( walkedArea )

    local nextFloodMark = self.nextFloodMarkWalkable or 0

    if nextFloodMark > _CurTime() then return end
    self.nextFloodMarkWalkable = _CurTime() + math.Rand( 0.5, 1 )

    local scoreData = {}
    scoreData.currentWalked = self.walkedAreas
    scoreData.InitialArea = walkedArea
    scoreData.checkOrigin = self:GetShootPos()
    scoreData.self = self

    local scoreFunction = function( scoreData, area1, area2 )
        local score = 0
        if not area2 then return 0 end -- patch a script err?
        local areaCenter = area2:GetCenter()
        if scoreData.currentWalked[area2:GetID()] then
            score = 1

        elseif scoreData.InitialArea:IsCompletelyVisible( area2 ) or terminator_Extras.PosCanSee( areaCenter + offset25z, scoreData.checkOrigin ) then
            scoreData.currentWalked[area2:GetID()] = true
            scoreData.self:markAsWalked( area2 )
            score = math.abs( 1000 + -areaCenter:Distance( scoreData.checkOrigin ) )
            score = score / 1000
            score = score * 25
        end
        --debugoverlay.Text( areaCenter, tostring( math.Round( score ) ), 8 )
        return score

    end

    local _ = self:findValidNavResult( scoreData, self:GetPos(), 1000, scoreFunction )
end

-- did we already try, and fail, to path there?
function ENT:areaIsReachable( area )
    if not area then return end
    if not IsValid( area ) then return end
    if self.unreachableAreas[area:GetID()] then return end
    return true

end

-- don't build paths to these areas!
function ENT:rememberAsUnreachable( area )
    if not area then return end
    if not area:IsValid() then return end
    self.unreachableAreas[area:GetID()] = true
    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        if not IsValid( area ) then return end
        table.remove( self.unreachableAreas, area:GetID() )

    end )
    return true
end

-- undo the above
function ENT:rememberAsReachable( area )
    if not area then return end
    if not area:IsValid() then return end
    table.remove( self.unreachableAreas, area:GetID() )
    return true

end

function ENT:getLostHealth()
    if not self.VisibilityStartingHealth then return 0 end
    return math.abs( self:Health() - self.VisibilityStartingHealth )

end

function ENT:inSeriousDanger()
    if self:getLostHealth() > 75 then return true end
    if sound.GetLoudestSoundHint( SOUND_DANGER, self:GetPos() ) then return true end

end

function ENT:EnemyIsUnkillable( enemy )
    if not enemy then
        enemy = self:GetEnemy()

    end
    if not IsValid( enemy ) then return end

    return ( enemy.Health and enemy:Health() > 10000 ) or ( enemy.HasGodMode and enemy:HasGodMode() )

end

function ENT:EnemyIsLethalInMelee( enemy )
    if not enemy then
        enemy = self:GetEnemy()

    end
    if not IsValid( enemy ) then return end

    local isLethalInMelee = enemy.terminator_IsLethalInMelee
    local isLethal = ( isLethalInMelee and isLethalInMelee >= 2 ) or self:EnemyIsUnkillable( enemy )

    if isLethal then return true end

end

hook.Add( "OnNPCKilled", "terminator_markkillers", function( npc, attacker, inflictor )
    if not npc.isTerminatorHunterChummy then return end
    if not attacker then return end
    if not inflictor then return end

    if GetConVar( "ai_ignoreplayers" ):GetBool() and attacker:IsPlayer() then return end

    -- if someone has killed terminators, make them react
    attacker.isTerminatorHunterKiller = true

    if inflictor:IsWeapon() then
        local weapsWeightToTerm = npc:GetWeightOfWeapon( inflictor )
        terminator_Extras.OverrideWeaponWeight( inflictor:GetClass(), weapsWeightToTerm + 15 )

    end

    if DistToSqr2D( attacker:GetPos(), npc:GetPos() ) < 350^2 then
        local isLethalInMelee = attacker.terminator_IsLethalInMelee or 0
        attacker.terminator_IsLethalInMelee = isLethalInMelee + 1

    end

    local timerId = "terminator_undokillerstatus_" attacker:GetCreationID()

    local timeToForget = 60 * 15
    timer.Remove( timerId )
    timer.Create( timerId, timeToForget, 1, function()
        if not IsValid( attacker ) then return end
        attacker.isTerminatorHunterKiller = nil

    end )
end )

hook.Add( "PlayerDeath", "terminator_unmark_killers", function( plyDied, _, attacker )
    if not attacker.isTerminatorHunterChummy then return end
    if not attacker.isTerminatorHunterBased then return end

    if DistToSqr2D( plyDied:GetPos(), attacker:GetPos() ) < 350^2 then
        local isLethalInMelee = plyDied.terminator_IsLethalInMelee or 0
        plyDied.terminator_IsLethalInMelee = math.Clamp( isLethalInMelee + -1, 0, math.huge )

    end

end )

hook.Add( "PostCleanupMap", "terminator_clear_playerstatuses", function()
    for _, ply in ipairs( player.GetAll() ) do
        ply.terminator_CantConvinceImFriendly = nil
        ply.isTerminatorHunterKiller = nil
        ply.terminator_IsLethalInMelee = nil

    end
end )


-- custom values for the nextbot base to use
-- i set these as multiples of defaults
ENT.JumpHeight = 70 * 3.5
ENT.MaxJumpToPosHeight = ENT.JumpHeight
ENT.DefaultStepHeight = 18
-- allow us to have different step height when couching/standing
-- stops bot from sticking to ceiling with big step height
-- see crouch toggle in motionoverrides
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1.5
ENT.CrouchingStepHeight = ENT.DefaultStepHeight
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.DoMetallicDamage = true
ENT.SpawnHealth = 900
ENT.AimSpeed = 480
ENT.WalkSpeed = 130
ENT.MoveSpeed = 300
ENT.RunSpeed = 550 -- bit faster than players... in a straight line
ENT.AccelerationSpeed = 3000
ENT.DeathDropHeight = 2000 --not afraid of heights
ENT.LastEnemySpotTime = 0
ENT.InformRadius = 20000
ENT.FistDamageMul = 4

ENT.duelEnemyTimeoutMul = 1

-- translated to TERM_MODEL
ENT.Models = { "terminator" }

ENT.ReallyStrong = true
ENT.HasFists = true

ENT.DuelEnemyDist = 550 -- dist to move from flank or follow enemy, to duel enemy

function ENT:AdditionalThink()
end

function ENT:Think() -- true hack
    self:walkArea()
    self:AdditionalThink()
    if not self.loco:IsOnGround() then
        self:HandleInAir()

    end
    self:HandlePathRemovedWhileOnladder()

    -- very helpful to find missing taskcomplete/taskfails 
    --[[
    local doneTasks = {}
    for task, _ in pairs( self.m_ActiveTasks ) do
        if string.find( task, "movement_" ) then
            table.insert( doneTasks, task )
        end
    end

    if #doneTasks >= 2 then
        print( "DOUBLE!" )
        PrintTable( self.taskHistory )
        PrintTable( doneTasks )
        SafeRemoveEntity( self )

    end
    --]]

    if not self.ReallyStrong then return end
    local Mass = 5000
    local Obj = self:GetPhysicsObject()
    if not IsValid( Obj ) then return end
    if Obj:GetMass() ~= Mass then
        self:GetPhysicsObject():SetMass( Mass )
    end
end

function ENT:AdditionalInitialize()
end

function ENT:Initialize()

    if #navmesh.GetAllNavAreas() <= 0 then
        SafeRemoveEntity( self )
        PrintMessage( HUD_PRINTCENTER, "NO NAVMESH FOUND!" )
        PrintMessage( HUD_PRINTTALK, "NO NAVMESH FOUND!" )
        return

    end

    BaseClass.Initialize( self )
    self.terminator_DontImmiediatelyFire = CurTime()

    self:CreateShootingTimer()

    self.isTerminatorHunterBased = true
    self.isTerminatorHunterChummy = true -- are we pals with terminators?

    self.walkedAreas = {} -- useful table of areas we have been / have seen, for searching/wandering
    self.walkedAreaTimes = {} -- times we walked/saw them
    self.unreachableAreas = {}
    self.awarenessBash = {}
    self.awarenessMemory = {}
    self.awarenessUnknown = {}
    self.awarnessLockedDoors = {} -- locked doors are evil, catalog them so we can destroy them
    self.awarenessSubstantialStuff = {}

    self.heardThingCounts = {} -- so we can ignore stuff that's distracted us alot

    -- search stuff
    self.SearchCheckedNavs = {} -- add this here even if its hacky
    self.SearchBadNavAreas = {} -- nav areas that never should be checked

    -- used for jumping fall damage/effects
    self.lastGroundLeavingPos = self:GetPos()

    self.LineOfSightMask = LineOfSightMask

    self:SetCurrentWeaponProficiency( WEAPON_PROFICIENCY_PERFECT )
    self.WeaponSpread = 0

    local model = self.Models[ math.random( #self.Models ) ]
    if model == "terminator" then
        model = termModel()

    end
    self:SetModel( model )

    -- see enemyoverrides
    self:DoHardcodedRelations()
    self:SetFriendly( false )

    self:DoTasks()

    -- for stuff based on this
    self:AdditionalInitialize()

end

function ENT:DoTasks()
    self.TaskList = {
        ["shooting_handler"] = {
            OnStart = function( self, data )
            end,
            BehaveUpdate = function(self,data,interval)
                local enemy = self:GetEnemy()
                if not IsValid( self:GetWeapon() ) then
                    if self.HasFists then
                        self:Give( self.TERM_FISTS )
                        return

                    elseif IsValid( enemy ) then
                        self.lastShootingType = "noweapon"
                        self:shootAt( self.LastEnemyShootPos, self.PreventShooting )
                        return

                    end
                end

                local wep = self:GetActiveLuaWeapon() or self:GetActiveWeapon()
                -- edge case
                if not IsValid( wep ) then
                    return

                end
                local doShootingPrevent = self.PreventShooting

                if wep.terminatorCrappyWeapon == true and self.HasFists then
                    self:DoFists()

                elseif wep:Clip1() <= 0 and wep:GetMaxClip1() > 0 and not self.IsReloadingWeapon then
                    self:WeaponReload()

                -- allow us to not stop shooting at the witness player
                elseif IsValid( self.OverrideShootAtThing ) and self.OverrideShootAtThing:Health() > 0 then
                    self:shootAt( self:EntShootPos( self.OverrideShootAtThing ) )
                    self.lastShootingType = "witnessplayer"

                elseif IsValid( enemy ) and not ( self.blockAimingAtEnemy and self.blockAimingAtEnemy > _CurTime() ) then
                    local wepRange = self:GetWeaponRange()
                    local seeOrWeaponDoesntCare = self.IsSeeEnemy or wep.worksWithoutSightline
                    if not self:IsMeleeWeapon( wep ) and wep and seeOrWeaponDoesntCare then
                        local shootableVolatile = self:getShootableVolatiles( enemy )

                        if shootableVolatile then
                            self:shootAt( self:getBestPos( shootableVolatile ), doShootingPrevent )
                            self.lastShootingType = "shootvolatile"

                        -- does the weapon know better than us?
                        elseif wep.terminatorAimingFunc then
                            if wep.worksWithoutSightline then
                                doShootingPrevent = nil

                            end
                            self:shootAt( wep:terminatorAimingFunc(), doShootingPrevent )
                            self.lastShootingType = "aimingfuncranged"

                        else
                            if self.DistToEnemy > wepRange and not self:IsReallyAngry() then
                                doShootingPrevent = true

                            end
                            self:shootAt( self.LastEnemyShootPos, doShootingPrevent )
                            self.lastShootingType = "normalranged"

                        end
                    --melee
                    elseif self:IsMeleeWeapon( wep ) and wep then
                        local blockShoot = doShootingPrevent or true
                        local meleeAtPos = self.LastEnemyShootPos

                        -- dont just swing our weap around
                        if self.DistToEnemy < wepRange * 1.5 and self.IsSeeEnemy then
                            blockShoot = nil
                            -- fix bot looking around like an idiot when meleeing?
                            meleeAtPos = self:EntShootPos( enemy )

                        -- fallback?
                        elseif self.DistToEnemy < wepRange * 1 then
                            blockShoot = nil
                            meleeAtPos = self:EntShootPos( enemy )

                        end

                        self.lastShootingType = "melee"
                        self:shootAt( meleeAtPos, blockShoot )

                    end
                elseif ( wep:GetMaxClip1() > 0 ) and ( wep:Clip1() < wep:GetMaxClip1() / 2 ) and not self.IsReloadingWeapon then
                    self:WeaponReload()

                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "shooting_handler" )
            end,
        },
        ["awareness_handler"] = {
            BehaveUpdate = function( self, data, interval )
                local nextAware = data.nextAwareness or 0
                if nextAware < _CurTime() then
                    data.nextAwareness = _CurTime() + 1.5
                    self:understandSurroundings()
                end
            end,
        },
        ["reallystuck_handler"] = { -- it's really stuck!!!!!!!
            OnStart = function( self, data )
                data.historicPositions = {}
                data.historicNavs = {}
                data.historicStucks = {}
                data.maybeUnderCount = 0
            end,
            BehaveUpdate = function( self, data )
                if not extremeUnstucking:GetBool() then return end
                local nextCache = data.nextCache or 0
                if nextCache < _CurTime() then
                    local myPos = self:GetPos()
                    local currentNav = navmesh.GetNearestNavArea( myPos, false, 50, false, false, -2 )
                    local size = 80

                    --debugoverlay.Cross( myPos, 10, 10, Color( 255,255,255 ), true )

                    local staringAtEnemy = not self:PathIsValid() and self.IsSeeEnemy
                    data.nextCache = _CurTime() + 1

                    local noNav = self.loco:IsOnGround() and not ( currentNav and currentNav.IsValid and currentNav:IsValid() )
                    local doAddCount = 1
                    -- go faster
                    if noNav then
                        doAddCount = doAddCount * 4

                    end
                    if self.isUnstucking then
                        doAddCount = doAddCount * 2

                    end

                    if myPos then
                        for _ = 1, doAddCount do
                            table.insert( data.historicPositions, 1, myPos )

                        end
                    end
                    if currentNav then
                        for _ = 1, doAddCount do
                            table.insert( data.historicNavs, 1, currentNav )

                        end
                    end

                    local stuck = nil
                    local sortaStuck = nil
                    local overrideStuck = self.overrideVeryStuck

                    local nextDisplacementCheck = data.nextUnderDisplacementCheck or 0
                    if nextDisplacementCheck < _CurTime() then
                        data.nextUnderDisplacementCheck = _CurTime() + 5
                        isUnderDisplacement, maybeUnderDisplacement = self:IsUnderDisplacement()

                        if maybeUnderDisplacement then
                            data.maybeUnderCount = data.maybeUnderCount + 1

                        elseif isUnderDisplacement then
                            data.maybeUnderCount = data.maybeUnderCount + 3

                        else
                            data.maybeUnderCount = 0

                        end
                    end

                    local underDisplacement = data.maybeUnderCount > 6

                    if #data.historicPositions > size then
                        if data.historicPositions[size + 1] then
                            table.remove( data.historicPositions, size + 1 )
                            table.remove( data.historicPositions, size + 1 )

                        end
                        if data.historicNavs[size + 1] then
                            table.remove( data.historicNavs, size + 1 )
                            table.remove( data.historicNavs, size + 1 )

                        end

                        -- start with assuming its true
                        stuck = true
                        sortaStuck = true

                        for _, historicPos in ipairs( data.historicPositions ) do
                            local distSqr = myPos:DistToSqr( historicPos )
                            --debugoverlay.Line( myPos, historicPos, 1, color_white, true )
                            if SqrDistGreaterThan( distSqr, 15 ) then
                                stuck = nil
                                break

                            end
                        end
                        -- false if we haven't been here for x long
                        for blap, historicNav in ipairs( data.historicNavs ) do
                            maxExtent = blap
                            if historicNav ~= currentNav then
                                sortaStuck = nil
                                break

                            end
                        end
                        if noNav and not self:PathIsValid() and not stuck and not navmesh.GetNearestNavArea( myPos, false, 200, false, false, -2 ) then
                            if GAMEMODE.IsReallyHuntersGlee then
                                SafeRemoveEntity( self )

                            else
                                stuck = true

                            end
                        end
                    end

                    if not staringAtEnemy and ( stuck or sortaStuck or underDisplacement or overrideStuck ) then -- i have been in the same EXACT spot for S I Z E seconds
                        --print( self:GetCreationID(), "damnitfoundmeasstuck ", stuck, sortaStuck, underDisplacement, overrideStuck )
                        --PrintTable( data.historicNavs )
                        --debugoverlay.Cross( myPos, 100, 100, color_white, true )

                        self.overrideVeryStuck = nil
                        local distToEnemy = 0
                        local enemyPos = self:GetPos()
                        if IsValid( self:GetEnemy() ) then
                            distToEnemy = self.DistToEnemy
                            enemyPos = self.EnemyLastPos or self:GetEnemy():GetPos()

                        end

                        local scoreData = {}
                        scoreData.startPos = self:GetPos()
                        scoreData.distToEnemySqared = distToEnemy^2
                        scoreData.enemyPos = enemyPos

                        local scoreFunction = function( scoreData, area1, area2 )
                            local area2Center = area2:GetCenter()
                            local score = area2Center:DistToSqr( scoreData.startPos ) ^ math.Rand( 0.9, 1.1 )
                            if area2Center:DistToSqr( scoreData.enemyPos ) < scoreData.distToEnemySqared then -- dont get closer
                                --debugoverlay.Cross( area2Center, 10, 10, Color( 255,255,255 ), true )
                                score = 0
                            end

                            return score

                        end
                        local freedomPos = nil
                        -- foolproof.. maybe
                        local nearestNavArea = navmesh.GetNearestNavArea( self:GetPos(), false, 10000, false, true, 2 )

                        for _ = 1, 10 do
                            freedomPos = self:findValidNavResult( scoreData, nearestNavArea, math.random( 2000, 3000 ), scoreFunction ) -- huge position shunt since we're so stuck.
                            if freedomPos then break end
                        end


                        --debugoverlay.Cross( freedomPos, 50, 20, Color( 255, 0, 0 ), true )
                        --print( self:GetCreationID(), "bigunstuck ", stuck, sortastuck, underDisplacement, overrideStuck, noNavAndNotStaring )

                        if freedomPos then
                            self:SetPos( freedomPos )
                            self:GetPath():Invalidate()
                            self.loco:SetVelocity( vec_zero )
                            self.loco:ClearStuck()

                        elseif GAMEMODE.getValidHunterPos then
                            freedomPos = GAMEMODE:getValidHunterPos()

                            if freedomPos then
                                self:SetPos( freedomPos )
                                self:GetPath():Invalidate()

                                self.loco:SetVelocity( vec_zero )
                                self.loco:ClearStuck()

                            end
                        elseif not self:PathIsValid() then -- only remove if its not pathing!
                            SafeRemoveEntity( self )

                        end

                        data.nextUnderDisplacementCheck = 0 -- CHECK NOW!

                        data.historicPositions = {}
                        data.historicNavs = {}

                    end
                end
            end,
        },
        ["enemy_handler"] = {
            OnStart = function( self, data )
                data.UpdateEnemies = _CurTime()
                data.HasEnemy = false
                data.playerCheckIndex = 0
                self.IsSeeEnemy = false
                self.DistToEnemy = 0
                self:SetEnemy( NULL )

                self.UpdateEnemyHandler = function( forceupdateenemies )
                    local prevenemy = self:GetEnemy()
                    local newenemy = prevenemy

                    if forceupdateenemies or not data.UpdateEnemies or _CurTime() > data.UpdateEnemies or data.HasEnemy and not IsValid( prevenemy ) then
                        data.UpdateEnemies = _CurTime() + 0.5

                        self:FindEnemies()

                        -- here if the above stuff didnt find an enemy we force it to rotate through all players one by one
                        if not GetConVar( "ai_ignoreplayers" ):GetBool() then
                            local allPlayers = player.GetAll()
                            local pickedPlayer = allPlayers[data.playerCheckIndex]

                            if IsValid( pickedPlayer ) then
                                local isLinkedPlayer = pickedPlayer == self.linkedPlayer
                                local alive = pickedPlayer:Health() > 0
                                if alive and self:ShouldBeEnemy( pickedPlayer ) and terminator_Extras.PosCanSee( self:GetShootPos(), self:EntShootPos( pickedPlayer ) ) then
                                    self:UpdateEnemyMemory( pickedPlayer, pickedPlayer:GetPos() )

                                elseif isLinkedPlayer and alive then -- HACK
                                    self:SaveSoundHint( pickedPlayer:GetPos(), true )
                                end
                            end
                            local new = data.playerCheckIndex + 1
                            if new > #allPlayers then
                                data.playerCheckIndex = 1
                            else
                                data.playerCheckIndex = new
                            end
                        end

                        local enemy = self:FindPriorityEnemy()

                        if IsValid( enemy ) then
                            newenemy = enemy
                            local enemyPos = enemy:GetPos()
                            if not self.EnemyLastPos then self.EnemyLastPos = enemyPos end

                            self.LastEnemySpotTime = _CurTime()
                            self.DistToEnemy = self:GetPos():Distance( enemyPos )
                            self.IsSeeEnemy = self:CanSeePosition( enemy )

                            if self.IsSeeEnemy and not self.WasSeeEnemy then
                                hook.Run( "terminator_spotenemy", self, enemy )
                                self.terminator_DontImmiediatelyFire = math.max( CurTime() + math.Rand( 0.3, 0.6 ), self.terminator_DontImmiediatelyFire )

                            elseif not self.IsSeeEnemy and self.WasSeeEnemy then
                                hook.Run( "terminator_loseenemy", self, enemy )

                            end

                            hook.Run( "terminator_enemythink", self, enemy )

                            self.WasSeeEnemy = self.IsSeeEnemy

                            -- override enemy's relations to me
                            self:MakeFeud( enemy )
                            -- we cheatily store the enemy's stuff for a second to make bot feel smarter
                            -- people can intuit where someone ran off to after 1 second, so bot can too
                            local posCheatsLeft = self.EnemyPosCheatsLeft or 0
                            if self.IsSeeEnemy then
                                posCheatsLeft = 5
                            -- doesn't time out if we are too close to them
                            elseif self.DistToEnemy < 500 and posCheatsLeft >= 1 then
                                --debugoverlay.Line( enemyPos, self:GetPos(), 0.3, Color( 255,255,255 ), true )
                                posCheatsLeft = math.max( 1, posCheatsLeft )

                            end
                            if self.IsSeeEnemy or posCheatsLeft > 0 then
                                self.NothingOrBreakableBetweenEnemy = self:ClearOrBreakable( self:GetShootPos(), self:EntShootPos( enemy ) )
                                self.EnemyLastDir = terminator_Extras.dirToPos( self.EnemyLastPos, enemyPos )
                                self.LastEnemyForward = enemy:GetForward()
                                self.EnemyLastPos = enemyPos
                                self:RegisterForcedEnemyCheckPos( enemy )
                                --debugoverlay.Line( enemyPos, enemyPos + ( self.EnemyLastDir * 100 ), 5, Color( 255, 255, 255 ), true )

                            end
                            if enemy and enemy.Alive and enemy:Alive() then
                                self.EnemyPosCheatsLeft = posCheatsLeft + -1

                            else
                                self.EnemyPosCheatsLeft = nil

                            end
                        elseif self.forcedCheckPositions and table.Count( self.forcedCheckPositions ) >= 1 then
                            local myPos = self:GetPos()
                            for positionKey, position in pairs( self.forcedCheckPositions ) do
                                if SqrDistLessThan( position:DistToSqr( myPos ), 150 ) then
                                    self.forcedCheckPositions[ positionKey ] = nil
                                    break

                                end
                            end
                        end
                    end

                    if IsValid( newenemy ) then
                        if not data.HasEnemy then
                            self:RunTask( "EnemyFound", newenemy )
                        elseif prevenemy ~= newenemy then
                            self:RunTask( "EnemyChanged", newenemy, prevenemy )
                        end

                        data.HasEnemy = true

                        if self:CanSeePosition( newenemy ) then
                            self.LastEnemyShootPos = self:EntShootPos( newenemy )
                            self:UpdateEnemyMemory( newenemy, newenemy:GetPos() )
                        end
                    else
                        if data.HasEnemy then
                            self:RunTask( "EnemyLost", prevenemy )
                        end

                        data.HasEnemy = false
                        self.IsSeeEnemy = false
                    end
                    if self.IsSeeEnemy then
                        -- save old health
                        local oldHealth = self.VisibilityStartingHealth

                        if not isnumber( oldHealth ) then 
                            self.VisibilityStartingHealth = self:Health()

                        end

                    elseif self.VisibilityStartingHealth ~= nil then 
                        --print( self.VisibilityStartingHealth, "a" )
                        self.VisibilityStartingHealth = nil
                    end

                    self:SetEnemy(newenemy)
                end
            end,
            BehaveUpdate = function(self,data,interval)
                self.UpdateEnemyHandler()
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "enemy_handler" )
            end,
        },
        ["movement_handler"] = {
            OnStart = function( self, data )

                local canWep, potentialWep = self:canGetWeapon()

                if not self:nextNewPathIsGood() then
                    self:TaskComplete( "movement_handler" )
                    self:StartTask2( "movement_wait", { Time = 0.1 }, "wait..." )
                    return

                elseif canWep and self:getTheWeapon( "movement_handler", potentialWep ) then
                    return

                else
                    local wep = self:GetWeapon()
                    if self.forcedCheckPositions and table.Count( self.forcedCheckPositions ) >= 1 then
                        self:TaskComplete( "movement_handler" )
                        self:StartTask2( "movement_approachforcedcheckposition", nil, "i should check that spot" )

                    elseif IsValid( self:GetEnemy() ) then
                        if self.IsSeeEnemy then
                            -- this was causing stuck bots
                            self:EnemyAcquired( "movement_handler" )
                            return

                        else
                            self:TaskComplete( "movement_handler" )
                            self:StartTask2( "movement_approachlastseen", nil, "there's an enemy i dont see" )
                            return

                        end
                    else
                        if wep.scoringFunc and wep.placingFunc then
                            self:TaskComplete( "movement_handler" )
                            self:StartTask2( "movement_placeweapon", nil, "i can place this" )
                            return

                        elseif self:CanBashLockedDoor( self:GetPos(), 500 ) then
                            if not self:BashLockedDoor( "movement_handler" ) then
                                self:TaskComplete( "movement_handler" )
                                self:StartTask2( "movement_inertia", { Want = math.random( 1, 3 ) }, "nothing better to do" )

                            end
                            return

                        elseif IsValid( self.awarenessUnknown[1] ) then
                            if math.random( 0, 100 ) > 15 then
                                self:TaskComplete( "movement_handler" )
                                self:StartTask2( "movement_understandobject", nil, "im curious" )
                                return

                            else
                                self:TaskComplete( "movement_handler" )
                                self:StartTask2( "movement_biginertia", { Want = math.random( 2, 4 ), blockUnderstanding = true }, "i was curious, but i want to go somewhere else" )
                                return

                            end
                        else
                            self:TaskComplete( "movement_handler" )
                            self:StartTask2( "movement_inertia", { Want = math.random( 1, 3 ) }, "nothing better to do" )
                            return

                        end
                    end
                end
            end,
        },
        ["movement_bashobject"] = {
            OnStart = function( self, data )
                if not IsValid( data.object ) then
                    data.object = self.awarenessBash[1]
                    table.remove( self.awarenessBash, 1 )
                end

                if not IsValid( data.object ) then data.fail = true return end

                if data.object.huntersglee_breakablenails then data.insane = true end

                data.readHealth = data.object:Health()
                if data.insane then
                    data.timeout = _CurTime() + 50

                else

                    data.timeout = _CurTime() + 8
                end
            end,
            BehaveUpdate = function( self, data, interval )

                if #ents.FindByClass( self:GetClass() ) >= 2 and not IsValid( aBashingFrenzyTerminator ) then
                    -- global var!!!
                    aBashingFrenzyTerminator = self
                    -- automatically bash another thing after we're done with this one
                    data.frenzy = true

                end

                if not data.fail and not data.success and not data.exit then
                    local tooMuchHealthLost = 10
                    if data.insane then
                        tooMuchHealthLost = 100

                    end
                    if self:getLostHealth() > tooMuchHealthLost or self:inSeriousDanger() then
                        data.exit = true
                        self:EnemyAcquired( "movement_bashobject" )

                        self:ignoreEnt( data.object )
                        local obj = data.object
                        timer.Simple( 20, function()
                            if not IsValid( self ) then return end
                            self:unIgnoreEnt( obj )

                        end )

                    elseif self.IsSeeEnemy and self:GetEnemy() and not data.frenzy and not data.insane then
                        data.exit = true
                        self:EnemyAcquired( "movement_bashobject" )

                    elseif self:canIntercept( data ) and not data.frenzy and not data.insane then
                        data.exit = true
                        self:TaskFail( "movement_bashobject" )
                        self:StartTask2( "movement_intercept", nil, "i can intercept someone" )

                    elseif not IsValid( data.object ) then -- get broken nerd
                        data.success = _CurTime() + 0.1


                    elseif data.readHealth > 0 and data.object:Health() <= 0 then
                        data.success = _CurTime() + 0.1

                    elseif self:validSoundHint() and data.gotAHitIn and not data.frenzy and not data.insane then
                        data.exit = true
                        self:TaskComplete( "movement_bashobject" )
                        self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )

                    elseif data.timeout < _CurTime() or not data.object:IsSolid() then -- dont just do this forever
                        data.fail = true

                    end

                    -- BEATUP
                    local valid, attacked, nearAndCanHit, closeAndCanHit, isNear, isClose = self:beatUpEnt( data.object )
                    data.gotAHitIn = data.gotAHitIn or attacked

                    if data.insane and not isClose and visible and self:GetWeaponRange() > 500 then
                        self:shootAt( toBeat )

                    end
                end
                if not data.exit then
                    if data.fail then
                        self:TaskFail( "movement_bashobject" )
                        self:StartTask2( "movement_handler", nil, "nope cant bash that" )
                        aBashingFrenzyTerminator = nil
                        return

                    end
                    if data.success and data.success < _CurTime() then
                        local canWep, potentialWep = self:canGetWeapon()
                        if data.frenzy then
                            if #self.awarenessBash > 0 then
                                self:TaskComplete( "movement_bashobject" )
                                self:StartTask2( "movement_bashobject", { frenzy = true }, "FRENZY" )
                                return
                            else
                                self:TaskComplete( "movement_bashobject" )
                                self:StartTask2( "movement_handler", nil, "i bashed it" )
                                aBashingFrenzyTerminator = nil
                                return
                            end
                        elseif canWep and self:getTheWeapon( "movement_handler", potentialWep ) then
                            return

                        else
                            if data.insane then
                                self:TaskComplete( "movement_bashobject" )
                                self:StartTask2( "movement_searchlastdir", { Want = 8 }, "destroyed thing, time to search behind it!" )

                            else
                                self:TaskComplete( "movement_bashobject" )
                                self:StartTask2( "movement_handler", nil, "nothin better to do" )
                                return

                            end
                        end
                    end
                end
            end,
            ShouldRun = function( self, data )
                local length = self:GetPath():GetLength() or 0
                local goodRun = self:canDoRun() 
                return length > 200 and goodRun

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
                
            end,
        },
        ["movement_understandobject"] = {
            OnStart = function( self, data )
                data.object = self.awarenessUnknown[1]
                table.remove( self.awarenessUnknown, 1 )
                if not IsValid( data.object ) then return end

                data.timeout = _CurTime() + 15
                data.objectKey = self:getAwarenessKey( data.object )
                data.objectHealth = data.object:Health() or 0
                data.initToggleState = data.object:GetInternalVariable( "m_toggle_state" )

                if not istable( self.understandAttempts ) then
                    self.understandAttempts = {}
                end

                data.understandAttempts = self.understandAttempts[data.objectKey] or 0
                --print( data.object )

            end,
            BehaveUpdate = function(self,data,interval)
                local pathLengthThresh = 125
                local definitelyAttacked = ( data.definitelyAttacked or 0 ) < _CurTime() and data.attacked
                local internalUnderstandAtt = data.understandAttempts or 0
                local pathLength = self:GetPath():GetLength() or 0

                local unreachable = internalUnderstandAtt > 2 and SqrDistLessThan( self:GetPos():DistToSqr( data.object ), 400 )

                if self.IsSeeEnemy and self:GetEnemy() then
                    if data.object == self:GetEnemy() then
                        self:ignoreEnt( data.object )

                    end
                    data.exit = true
                    self:EnemyAcquired( "movement_understandobject" )

                elseif self:canIntercept( data ) then
                    data.exit = true
                    self:TaskFail( "movement_understandobject" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )

                elseif not IsValid( data.object ) or not data.object:IsSolid() then -- we lost the object OR we broke it
                    if not data.trackingBreakable then
                        data.fail = true

                    else
                        local lastTime = self.lastDamagedTime or 0
                        local lastTimeAdd = lastTime + 1
                        --print("break" )

                        if lastTimeAdd > _CurTime() then -- breaking it damaged me!!!!
                            self:memorizeEntAs( data.objectKey, MEMORY_VOLATILE )
                            self.lastHeardSoundHint = nil
                            --print("volatile" )

                        else
                            self:memorizeEntAs( data.objectKey, MEMORY_BREAKABLE )

                        end
                        data.success = true

                    end
                elseif self:getLostHealth() > 2 or self:inSeriousDanger() then
                    data.exit = true
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_handler", nil, "i was scared" )
                elseif self:validSoundHint() then
                    data.exit = true
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )

                elseif self.awarenessMemory[ self:getAwarenessKey( data.object ) ] ~= MEMORY_MEMORIZING then -- we memorized this already
                    data.fail = true

                elseif data.object:GetParent() == self then
                    self:ignoreEnt( data.object )
                    data.fail = true

                elseif data.timeout < _CurTime() then -- dont just do this forever
                    if data.attacked then
                        self:memorizeEntAs( data.object, MEMORY_INERT )

                    elseif pathLength < pathLengthThresh or not self:primaryPathIsValid() or data.understandAttempts > 3 or unreachable then
                        self:ignoreEnt( data.object )

                    else
                        self:memorizeEntAs( data.object, MEMORY_INERT )

                    end

                    data.fail = true
                elseif data.checkedUse and definitelyAttacked and not data.entTakingDamage and not data.isButton then -- eliminate if it's inert
                    self:memorizeEntAs( data.object, MEMORY_INERT )
                    data.success = true

                end
                if not data.fail and not data.success and not data.exit then
                    local valid, attacked, nearAndCanHit, closeAndCanHit, isClose
                    if not self.isUnstucking then
                        -- UNDERSTAND
                        valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose = self:beatUpEnt( data.object )
                        --print( valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose )
                        --debugoverlay.Cross( data.object:GetPos(), 100, 1, Color( 255,0,0 ), true )
                        if valid == false then
                            data.fail = true

                        end
                    else
                        self:ControlPath2( not self.IsSeeEnemy )

                    end

                    if not data.arrived and isClose and pathLength < pathLengthThresh then
                        data.arrived = true
                        data.timeout = _CurTime() + 5

                    end
                    if nearAndCanHit or closeAndCanHit then
                        -- button
                        if data.object:GetInternalVariable( "m_toggle_state" ) ~= data.initToggleState then
                            data.isButton = true
                            self:memorizeEntAs( data.object, MEMORY_INERT )
                            data.success = true

                        end
                        if data.objectHealth > 0 then
                            -- im not breaking this
                            if not hasReasonableHealth( data.object ) then
                                self:memorizeEntAs( data.object, MEMORY_INERT )
                                data.success = true

                            -- start the tracking
                            elseif not data.trackingBreakable then
                                data.trackingBreakable = true

                            end
                            -- ok its taking damage
                            if not data.entTakingDamage and data.object:Health() < data.objectHealth then
                                data.entTakingDamage = true
                                data.timeout = _CurTime() + 10

                            end
                        end
                        -- this handles the shooting at
                        if attacked and closeAndCanHit and not data.attacked then
                            data.definitelyAttacked = _CurTime() + 1.5
                            data.attacked = true

                        end
                        -- spam use on it
                        if ( data.nextUse or 0 ) < _CurTime() and nearAndCanHit then
                            data.nextUse = _CurTime() + math.random( 0.1, 1 )
                            self:Use2( data.object )
                            data.checkedUse = true

                        end
                    end
                end
                if not data.exit then
                    if data.fail then
                        self:TaskFail( "movement_understandobject" )
                        self:StartTask2( "movement_handler", nil, "man i wanted to know about that" )

                    end
                    if data.success then
                        self:TaskComplete( "movement_understandobject" )
                        self:StartTask2( "movement_handler", nil, "curiosity sated" )

                    end
                end
            end,
            ShouldRun = function( self, data )
                local length = self:GetPath():GetLength() or 0
                local goodRun = self:canDoRun() 
                return length > 200 and goodRun

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 

            end,
        },
        ["movement_wait"] = {
            OnStart = function( self, data )
                data.startedLooking = self.IsSeeEnemy
                data.Time = _CurTime() + ( data.Time or math.random( 1, 2 ) )
            end,
            BehaveUpdate = function( self, data, interval )
                if self.IsSeeEnemy and not data.startedLooking then
                    self:EnemyAcquired( "movement_wait" )

                elseif _CurTime() >= data.Time then
                    self:TaskComplete( "movement_wait" )
                    self:StartTask2( "movement_handler", nil, "all done waiting" )

                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_wait" )

            end,
        },
        ["movement_getweapon"] = {
            OnStart = function( self, data )

                data.nextWepFind = 0

                if not isstring( data.nextTask ) then
                    data.nextTask = "movement_wait"
                    data.nextTaskData = { Time = 0.1 }
                elseif not data.nextTaskData then
                    data.nextTaskData = {}
                end

                data.finishAfterwards = function()
                    data.taskKilled = true
                    local killerrrr = self:GetEnemy() and self:GetEnemy().isTerminatorHunterKiller
                    if killerrrr then
                        self.PreventShooting = nil

                    -- don't shoot right after we pick up the gun!
                    elseif self.PreventShooting ~= true then
                        self.PreventShooting = true

                        timer.Simple( 0.5, function()
                            if not IsValid( self ) then return end
                            if not self.PreventShooting then return end
                            self.PreventShooting = nil

                        end )
                    end

                    timer.Simple( 0.1, function()
                        if not IsValid( self ) then return end
                        if IsValid( data.Wep ) then
                            data.Wep.terminatorTaking = nil
                            if not IsValid( data.Wep:GetParent() ) then
                                data.Wep.blockWeaponNoticing = _CurTime() + 2.5

                            end
                        end
                        if data.nextTask == "movement_getweapon" then -- no loops pls
                            data.nextTask = "movement_wait"

                        end

                        self:TaskFail( "movement_getweapon" )
                        self:StartTask2( data.nextTask, data.nextTaskData, "finishAfterwards" )

                    end )
                end

                -- make bots bash crate
                -- discards nexttask but w/e
                data.handleCrate = function()
                    if data.Wep:GetClass() ~= "item_item_crate" then return end
                    if self.IsSeeEnemy and self:GetPath():GetLength() > 500 and self.DistToEnemy < self.DuelEnemyDist then
                        self:EnemyAcquired( "movement_getweapon" )
                        return true

                    end
                    if SqrDistLessThan( data.Wep:GetPos():DistToSqr( self:GetPos() ), 200 ) then
                        self:TaskFail( "movement_getweapon" )
                        self:StartTask2( "movement_bashobject", { object = data.Wep }, "the gun was right there" )
                        return true
                    end
                end

                data.updateWep = function()
                    if not IsValid( data.Wep ) or data.nextWepFind < CurTime() then
                        local canGetWeap, findWep = self:canGetWeapon()
                        data.nextWepFind = CurTime() + 1.75

                        if not canGetWeap then
                            if not IsValid( data.Wep ) then
                                data:finishAfterwards()
                                return

                            end
                        else
                            data.Wep = findWep

                        end
                    end
                    return true

                end

                if not self.isUnstucking then
                    self:GetPath():Invalidate()
                end

                if not data:updateWep() then return end

                if data:handleCrate() == true then return end

                if not self:nextNewPathIsGood() then
                    data:finishAfterwards()
                    return

                end

                data.Wep.terminatorTaking = self

                if self:GetRangeTo( data.Wep ) < 25 then
                    self:SetupWeapon( data.Wep )

                    data:finishAfterwards()
                    return

                end
            end,
            BehaveUpdate = function( self, data )
                if data.taskKilled then return end

                if not data:updateWep() then return end

                if self:EnemyIsLethalInMelee() then
                    local result = terminator_Extras.getNearestPosOnNav( self:GetEnemy():GetPos() )
                    if result and IsValid( result.area ) then
                        self:SetupFlankingPath( data.Wep:GetPos(), result.area, self.DistToEnemy * 0.8 )

                    end
                end

                if self:CanBashLockedDoor( self:GetPos(), 500 ) then
                    self:BashLockedDoor( "movement_getweapon" )

                end

                if not self:primaryPathIsValid() then
                    self:SetupPath2( data.Wep:GetPos() )

                end

                if not self:primaryPathIsValid() then
                    if self:CanBashLockedDoor( nil, 1000 ) then
                        self:BashLockedDoor( "movement_getweapon" )
    
                    end
                    local failedWeaponPaths = data.Wep.failedWeaponPaths or 0
                    data.Wep.failedWeaponPaths = failedWeaponPaths + 1
                    if data.Wep.failedWeaponPaths > 25 then
                        data.Wep.terminatorCrappyWeapon = true

                    end
                    data:finishAfterwards()
                    return
                end

                if not self:CanPickupWeapon( data.Wep ) then
                    data:finishAfterwards()

                    return
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )

                if data:handleCrate() == true then return end

                local rangeToWep = self:GetRangeTo( data.Wep )
                if rangeToWep < 125 then
                    local distIfCrouch = ( self:GetPos() + crouchingOffset ):DistToSqr( data.Wep:GetPos() )
                    local distIfStand = ( self:GetPos() + standingOffset ):DistToSqr( data.Wep:GetPos() )

                    if distIfCrouch < distIfStand then
                        self.overrideCrouch = _CurTime() + 0.3
                        self.forcedShouldWalk = _CurTime() + 0.2

                    end
                end

                if rangeToWep < 60 then
                    self:SetupWeapon( data.Wep )
                    data:finishAfterwards()

                end

                if result then
                    data:finishAfterwards()

                elseif result == false then
                    data:finishAfterwards()

                elseif not self:primaryPathIsValid() then
                    data:finishAfterwards()

                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_getweapon" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_followsound"] = {
            OnStart = function( self, data )
                if not self.isUnstucking then
                    self:GetPath():Invalidate()

                end
                data.UpdateSound = function( data, soundData )
                    if not soundData then return end
                    data.Sound = soundData.source
                    data.Valuable = soundData.valuable

                end
                data:UpdateSound( self.lastHeardSoundHint )
                self.lastHeardSoundHint = nil

                -- stagger so bots dont stack up on 1 frame and freeze the game
                local timeOffset = math.Rand( 0.01, 0.2 )
                if data.Valuable then-- we're gonna be doing flanking paths, stagger these out more!
                    timeOffset = math.Rand( 0.01, 0.4 )

                end
                data.Time = _CurTime() + timeOffset

            end,
            BehaveUpdate = function( self, data )
                if data.Time and data.Time > _CurTime() then return end
                local myPos = self:GetPos()

                if self.lastHeardSoundHint then
                    local hint = self.lastHeardSoundHint
                    local newSoundsPos = hint.source
                    local newSoundsValuable = hint.valuable
                    local distToCurrentSoundSqr = math.huge
                    if data.Sound then
                        distToCurrentSoundSqr = myPos:DistToSqr( data.Sound )

                    end

                    local closer = myPos:DistToSqr( newSoundsPos ) < distToCurrentSoundSqr
                    local worse = data.Valuable and not newSoundsValuable
                    local newSoundIsABetterSound = closer and not worse
                    --print( closer, better, math.sqrt( distToCurrentSoundSqr ), myPos:Distance( self.lastHeardSoundHint ) )
                    if newSoundIsABetterSound then
                        data:UpdateSound( self.lastHeardSoundHint )
                        data.newPath = true

                    end
                    self.lastHeardSoundHint = nil

                end
                local soundPos = data.Sound

                --debugoverlay.Cross( soundPos, 100, 5 )

                if not soundPos then
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_handler", nil, "no more sound to follow" )
                    return

                end

                if soundPos then
                    local newPath = data.newPath or not self:primaryPathIsValid() or ( self:primaryPathIsValid() and self:CanDoNewPath( soundPos ) )

                    local killerrr = self:GetEnemy() and self:GetEnemy().isTerminatorHunterKiller
                    local nextPathTime = data.nextPathTime or 0

                    if newPath and nextPathTime < CurTime() and self:nextNewPathIsGood() and not self.isUnstucking then -- HACK
                        self:GetPath():Invalidate()
                        data.newPath = nil
                        data.Unreachable = nil
                        -- BOX IT IN
                        local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()

                        -- only do this when sound is confirmed from something dangerous, and there is another hunter pathing
                        if data.Valuable and otherHuntersHalfwayPoint then
                            local result = terminator_Extras.getNearestPosOnNav( otherHuntersHalfwayPoint )
                            if result.area:IsValid() then
                                local flankBubble = myPos:Distance( otherHuntersHalfwayPoint ) * 0.7
                                -- create path, avoid simplest path
                                self:SetupFlankingPath( soundPos, result.area, flankBubble )

                            end
                        end
                        if self:primaryPathIsValid() then
                            -- not gonna surprise them
                            if killerrr then
                                self.PreventShooting = nil
                            else
                                self.PreventShooting = true
                            end
                        else
                            self:SetupPath2( soundPos )

                        end
                        if not self:primaryPathIsValid() then
                            data.Unreachable = true

                        end
                        data.nextPathTime = CurTime() + 0.5
                    end
                end

                local toBashAfterSound = nil
                if #self.awarenessBash > 0 and soundPos then
                    for _, currBashObj in ipairs( self.awarenessBash ) do
                        if not IsValid( currBashObj ) then continue end

                        local bashDistToSound = currBashObj:GetPos():DistToSqr( soundPos )
                        if SqrDistGreaterThan( bashDistToSound, 100 ) then continue end

                        local myDistToBash = currBashObj:GetPos():DistToSqr( myPos )
                        if SqrDistGreaterThan( myDistToBash, 800 ) then continue end

                        toBashAfterSound = currBashObj

                    end
                end


                local result = self:ControlPath2( not self.IsSeeEnemy )
                local Done = nil
                local searchWant = 60
                if data.Valuable ~= true then
                    searchWant = 4
                end

                local nearPathEnd = self:primaryPathIsValid() and self:GetPath():GetLength() < 75
                local closeToSoundAndVis = SqrDistLessThan( ( myPos - soundPos ):Length2DSqr(), 100 ) and terminator_Extras.PosCanSee( self:GetShootPos(), soundPos )
                local reachedSound = result == true or closeToSoundAndVis or nearPathEnd

                local doWep, potentialWep = self:canGetWeapon()
                local wepIsFurther = nil
                if doWep then
                    local wepPos = potentialWep:GetPos()
                    local _, currPoint = self:GetNextPathArea( nil, 0 )
                    local _, aheadPoint = self:GetNextPathArea( nil, 5 )
                    -- only pick up weapons when we're arriving to them.
                    -- stops bot from flip flopping back and fourth when it finds an obstacle
                    if aheadPoint and currPoint then
                        wepIsFurther = wepPos:DistToSqr( aheadPoint.pos ) < wepPos:DistToSqr( currPoint.pos )

                    end
                end

                if doWep and wepIsFurther and self:getTheWeapon( "movement_followsound", potentialWep, "movement_followsound", { Sound = soundPos } ) then
                    Done = true
                elseif self.IsSeeEnemy then
                    Done = true
                    self:EnemyAcquired( "movement_followsound" )
                elseif self:canIntercept( data ) and not data.Valuable then
                    data.exit = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone and my sound isn't valuable" )
                elseif data.Unreachable then
                    Done = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_search", { searchWant = searchWant, searchCenter = soundPos }, "cant reach the sound" )
                    --debugoverlay.Cross( soundPos, 100, 10, Color( 0,255,255 ), true )
                elseif IsValid( toBashAfterSound ) then
                    Done = true
                    self:TaskComplete( "movement_followsound" )
                    self:StartTask2( "movement_bashobject", { object = toBashAfterSound }, "the loud thing's breakable" )
                elseif reachedSound then
                    Done = true
                    self:TaskComplete( "movement_followsound" )
                    self:StartTask2( "movement_search", { searchWant = searchWant, searchCenter = soundPos }, "look for what made the sound" )
                    --debugoverlay.Cross( soundPos, 100, 10, Color( 0,255,255 ), true )
                elseif not data.Sound then
                    Done = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_handler", nil, "no sound to follow" )
                end
                if Done then
                    self.PreventShooting = nil
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_followsound" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_search"] = {
            OnStart = function( self, data )
                --debugoverlay.Cross( self:GetPos(), 50,1, Color(255,255,255), true )

                data.searchRadius = data.searchRadius or 5000
                data.searchWant = data.searchWant or 50
                data.Time = data.Time or 0
                data.doneSearchesNearby = data.doneSearchesNearby or 0

                --print( "Search!" .. data.searchWant .. " " .. data.searchRadius )
                local toPick = { nil, data.searchCenter, self.EnemyLastPos, self:GetPos() }
                local pickedSearchCenter = PickRealVec( toPick )
                local needsToDoANearbySearch = data.searchCenter and not data.searchedNearCenter and data.searchWant > 0

                -- focus search on where a "hint" was, or first operation, focus our search on where the code says we should be
                if needsToDoANearbySearch then
                    local result = terminator_Extras.getNearestPosOnNav( data.searchCenter )
                    if result and result.pos then
                        --debugoverlay.Cross( result.pos, 100, 10, Color( 255,255,0 ), true )
                        pickedSearchCenter = result.pos
                        data.searchCenter = result.pos

                    end
                end

                data.nextForcedSearch = _CurTime() + 10
                data.searchWant = data.searchWant + -1
                data.Time = _CurTime() + data.Time

                if not data.hidingToCheck then
                    local Options = {
                        Type = 1,
                        Pos = pickedSearchCenter,
                        Radius = data.searchRadius,
                        MinRadius = 1,
                        Stepup = 200,
                        Stepdown = 200,
                        AllowWet = self:isUnderWater()

                    }
                    data.hidingToCheck = FindSpot2( self, Options )

                end

                if data.hidingToCheck == nil then
                    if needsToDoANearbySearch then
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    else
                        data.InvalidAfterwards = true
                        return

                    end
                end
                local checkNav = terminator_Extras.getNearestNav( data.hidingToCheck )
                if not checkNav or not checkNav:IsValid() then
                    if needsToDoANearbySearch then
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    else
                        data.InvalidAfterwards = true
                        return

                    end
                end
                data.CheckNavId = checkNav:GetID()

            end,
            BehaveUpdate = function( self, data )
                local Done = false -- break the search and forget all the spots we already searched
                local doneCount = data.doneCount or 0
                if self:canIntercept( data ) then
                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                    done = true
                    data.tryAndSearchNearbyAfterwards = nil

                elseif self:validSoundHint() and self:CanDoNewPath( self.lastHeardSoundHint.source ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                    done = true
                    data.tryAndSearchNearbyAfterwards = nil

                elseif self.IsSeeEnemy and self:GetEnemy() then
                    self:EnemyAcquired( "movement_search" )
                    done = true
                    data.tryAndSearchNearbyAfterwards = nil

                end
                if data.tryAndSearchNearbyAfterwards then
                    local rand2DOffset = VectorRand()
                    rand2DOffset.z = 0.1
                    rand2DOffset:Normalize()
                    rand2DOffset = rand2DOffset * math.random( 100, 200 )

                    local searchesNearbyExp = data.doneSearchesNearby ^ 1.8
                    local offsetScalar = 1 + ( searchesNearbyExp * 0.15 )

                    rand2DOffset = rand2DOffset * offsetScalar

                    local newSearchCenter = data.searchCenter + rand2DOffset
                    local result = terminator_Extras.getNearestPosOnNav( newSearchCenter )
                    if not result.area or not result.area.IsValid or not result.area:IsValid() then
                        -- nope, this pos is out of the navmesh, stay here!
                        newSearchCenter = data.searchCenter

                    end
                    --print( rand2DOffset )
                    --debugoverlay.Cross( newSearchCenter, 100, 10, Color( 255,255,0 ), true )

                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_search", {
                        doneCount = doneCount,
                        searchWant = data.searchWant + -1,
                        searchCenter = newSearchCenter,
                        searchedNearCenter = data.searchedNearCenter,
                        doneSearchesNearby = data.doneSearchesNearby + 1,
                        hateLockedDoorDist = 2000

                    },
                    "i couldnt reach where i wanted to search, ill try somewhere nearby" )
                    return

                end
                if data.InvalidAfterwards then
                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_searchlastdir", { Want = 8, wasNormalSearch = true }, "i couldnt find somewhere to search" )
                    return

                end

                if data.Time > _CurTime() then return end

                local myPos = self:GetPos()
                local hidingToCheck = data.hidingToCheck or vec_zero
                local CheckNavId = data.CheckNavId
                local DistToHideSqr = myPos:DistToSqr( hidingToCheck )

                if not self:primaryPathIsValid() or self:CanDoNewPath( hidingToCheck ) then
                    self:SetupPath2( hidingToCheck )
                    -- search failed, try and get somewhere close!
                    if data.searchCenter and not self:primaryPathIsValid() then
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    end
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local Continue = false -- do another search
                local BadArea = false -- unreachable
                local waitTime = math.random( 0.2, 0.4 )
                local searchWantInternal = data.searchWant or 0
                local hateLockedDoorDist = data.hateLockedDoorDist or 350
                local needsToDoANearbySearch = data.searchCenter and not data.searchedNearCenter and data.searchWant > 0

                if searchWantInternal <= 0 then
                    Done = true
                    self:TaskComplete( "movement_search" )
                    if math.random( 0, 100 ) > 80 and not self:IsMeleeWeapon( self:GetWeapon() ) then
                        self:StartTask2( "movement_perch", nil, "i was done searching with some luck and a real gun" )
                    else
                        self:StartTask2( "movement_handler", nil, "i was done searching" )
                    end
                elseif doneCount >= 25 and IsValid( self.awarenessUnknown[1]  ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_understandobject", nil, "im curious and i've been searching a while" )

                elseif self:canGetWeapon() and not self.IsSeeEnemy and not needsToDoANearbySearch then
                    if self:getTheWeapon( "movement_search", nil, "movement_search" ) then
                        Done = true

                    end
                elseif self:validSoundHint() and self.lastHeardSoundHint.time > data.taskStartTime and myPos:DistToSqr( self.lastHeardSoundHint.source ) < myPos:DistToSqr( hidingToCheck ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_search", {
                        doneCount = doneCount,
                        searchRadius = data.searchRadius,
                        hidingToCheck = self.lastHeardSoundHint.source,
                        searchWant = data.searchWant,
                        Time = 0,
                        searchCenter = data.searchCenter,
                        searchedNearCenter = data.searchedNearCenter

                    }, "i heard something nearby, i will search there!" )

                elseif self:CanBashLockedDoor( nil, hateLockedDoorDist ) then
                    self:BashLockedDoor( "movement_search" )
                elseif not result and terminator_Extras.PosCanSee( myPos, hidingToCheck ) and SqrDistLessThan( DistToHideSqr, 300 ) then
                    waitTime = 0
                    Continue = true
                elseif data.nextForcedSearch < _CurTime() then
                    Continue = true
                elseif result then
                    if not terminator_Extras.PosCanSee( myPos, hidingToCheck ) or SqrDistLessThan( DistToHideSqr, 300 ) then
                        BadArea = true
                    end
                    Continue = true
                elseif result == false then
                    Continue = true
                    BadArea = true
                elseif self.isUnstucking then
                    Continue = true
                    BadArea = true
                end

                if Done then
                    self.SearchCheckedNavs = self.SearchBadNavAreas
                end
                if Continue then
                    if not istable( self.SearchCheckedNavs ) then
                        self.SearchCheckedNavs = self.SearchBadNavAreas
                    end
                    self:TaskFail( "movement_search" )
                    if not isnumber( CheckNavId ) then
                        self:StartTask2( "movement_handler", nil, "i couldnt find somewhere to search" )
                        return

                    else
                        local newRadius = data.searchRadius + 200
                        doneCount = doneCount + 1

                        if not data.searchCenter then
                            data.searchedNearCenter = true

                        elseif data.searchedNearCenter ~= true then
                            data.searchedNearCenter = self:GetPos():DistToSqr( data.searchCenter ) < 1000^2

                        end

                        self:StartTask2( "movement_search", {
                            doneCount = doneCount,
                            searchRadius = newRadius,
                            searchWant = data.searchWant,
                            Time = waitTime,
                            searchCenter = data.searchCenter,
                            searchedNearCenter = data.searchedNearCenter

                        }, "i still want to keep searching" )
                        table.insert( self.SearchCheckedNavs, CheckNavId, true )

                    end
                end
                if BadArea then
                    table.insert( self.SearchBadNavAreas, CheckNavId, true )
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_search" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() 
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        ["movement_searchlastdir"] = {
            OnStart = function( self, data )
                data.expiryTime = _CurTime() + 10
                if not isnumber( data.Want ) then
                    data.Want = 10
                end
                data.Want = data.Want + -1

                if data.Want <= 0 then
                    data.InvalidAfterwards = true
                else
                    local scoreData = {}
                    scoreData.canDoUnderWater = self:isUnderWater()
                    scoreData.self = self
                    scoreData.bearingCompare = self.EnemyLastPos or self:GetPos()
                    scoreData.visCheckArea = self:GetCurrentNavArea()

                    local scoreFunction = function( scoreData, area1, area2 )
                        local dropToArea = area1:ComputeAdjacentConnectionHeightChange( area2 )
                        local score = math.Rand( 100, 150 )
                        if scoreData.self.walkedAreas[area2:GetID()] then
                            local time = scoreData.self.walkedAreaTimes[ area2:GetID() ]
                            local timeSince = math.abs( time - CurTime() )
                            score = score / timeSince

                        end
                        if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                            score = score * 0.001

                        end
                        if math.abs( dropToArea ) > scoreData.self.loco:GetMaxJumpHeight() then
                            score = 0

                        end

                        --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( score ) ), 8 )

                        return math.Clamp( score, 1, math.huge )

                    end

                    local searchPos = self:findValidNavResult( scoreData, self:GetPos(), math.random( 2000, 3500 ), scoreFunction )
                    --debugoverlay.Cross( searchPos, 150, 10, Color( 255,255,255 ), true )
                    self:SetupPath2( searchPos )

                    if self:primaryPathIsValid() then return end
                    --nothing worked, fail the task next tick.
                    data.InvalidAfterwards = true
                end
            end,
            BehaveUpdate = function( self, data )
                if data.InvalidAfterwards then
                    if self.IsSeeEnemy then
                        self:EnemyAcquired( "movement_searchlastdir" )
                        return

                    end
                    local searchFailures = self.searchFailures or 0
                    self.searchFailures = searchFailures + 1

                    if self.searchFailures > 20 then
                        self.searchFailures = 0
                        self:TaskFail( "movement_searchlastdir" )
                        self:StartTask2( "movement_handler", nil, "i failed searching too much" )
                        return

                    else
                        self:TaskFail( "movement_searchlastdir" )
                        self:StartTask2( "movement_search", { searchWant = 60, searchCenter = self.EnemyLastPos or nil }, "nope try normal searching" )
                        return

                    end
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local newSearch = result or data.expiryTime < _CurTime()
                local canWep, potentialWep = self:canGetWeapon()

                if canWep and not self.IsSeeEnemy and self:getTheWeapon( "movement_searchlastdir", potentialWep, "movement_searchlastdir" ) then
                    return
                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_searchlastdir" )
                elseif self:canIntercept( data ) then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                elseif newSearch and data.Want > 0 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want, wasNormalSearch = data.wasNormalSearch }, "i can search somewhere else" )
                elseif newSearch and data.Want <= 0 then
                    if not data.wasNormalSearch then
                        self:TaskComplete( "movement_searchlastdir" )
                        self:StartTask2( "movement_search", { searchWant = 60, Time = 1.5, searchCenter = self.EnemyLastPos or nil }, "im all done searching" )

                    else
                        self:TaskComplete( "movement_searchlastdir" )
                        self:StartTask2( "movement_biginertia", { Want = 50 }, "im all done searching and i was in a loop" )

                    end
                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_searchlastdir" )
                elseif IsValid( self.awarenessUnknown[1]  ) and data.Want < 1 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_understandobject", nil, "im curious" )
                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                elseif result == false then
                    self:TaskFail( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want, wasNormalSearch = data.wasNormalSearch }, "my path failed" )
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_searchlastdir" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() 
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        ["movement_watch"] = {
            OnStart = function( self, data )
                path = self:GetPath()
                path:Invalidate()

                if not data.tooCloseDist then
                    if self:IsReallyAngry() then
                        data.tooCloseDist = 1500

                    elseif self:IsAngry() then
                        data.tooCloseDist = 1000

                    else
                        data.tooCloseDist = 500

                    end
                end

                data.tooCloseDist = math.Clamp( data.tooCloseDist, 75, math.huge )


                local enem = self:GetEnemy()
                local killerrr = enem and enem.isTerminatorHunterKiller
                if killerrr then -- ok u deserve to be sniped
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_camp", { maxNoSeeing = 100 }, "i want to kill this thing" )

                else
                    self.PreventShooting = true -- this is not a SNIPING behaviour!

                end
                local range1, range2 = 10, 20
                local watchCount = self.watchCount or 0
                if watchCount < 1 then 
                    range1, range2 = 10, 15 --40, 60
                end
                data.giveUpWatchingTime = _CurTime() + math.random( range1, range2 )

                if enem then
                    local old = enem.terminator_TerminatorsWatching or {}
                    table.insert( old, self )
                    enem.terminator_TerminatorsWatching = old

                end
            end,
            BehaveUpdate = function( self, data )
                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local enemyBearingToMeAbs = math.huge
                local goodEnemy = nil
                local enemShootPos = enemyPos
                if IsValid( enemy ) then
                    enemShootPos = self:EntShootPos( enemy )
                    data.dirToEnemy = ( self:GetShootPos() - enemShootPos ):GetNormalized()
                    goodEnemy = self.IsSeeEnemy
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                end

                if data.enemyIsBoxedIn == nil or data.nextCheckIfBoxedIn < CurTime() then
                    data.enemyIsBoxedIn = self:EnemyIsBoxedIn()
                    data.nextCheckIfBoxedIn = CurTime() + 1.5

                end
                local theyreInForASurprise = self:AnotherHunterIsHeadingToEnemy()

                local tooCloseDist = data.tooCloseDist
                if data.enemyIsBoxedIn == true or theyreInForASurprise then
                    tooCloseDist = 380

                end

                local lookingAtBearing = 9

                if goodEnemy and enemyBearingToMeAbs > lookingAtBearing then
                    data.SneakyStaring = true

                elseif enemyBearingToMeAbs < lookingAtBearing and not data.slinkAway and data.enemyIsBoxedIn ~= true then
                    local min, max = 8, 10
                    local watchCount = self.watchCount or 0
                    if watchCount > 1 then
                        min, max = 1, 2

                    end
                    data.slinkAway = _CurTime() + math.random( min, max )

                elseif theyreInForASurprise and not data.doneSurpriseSetup then
                    data.doneSurpriseSetup = true
                    data.slinkAway = _CurTime() + math.Rand( 2, 5 )

                elseif data.SneakyStaring then
                    data.SneakyStaring = nil

                end

                local beingFooled = IsValid( enemy.terminator_crouchingbaited ) and enemy.terminator_crouchingbaited ~= self and enemy.terminator_crouchingbaited.IsSeeEnemy
                -- and and and
                local canFool = goodEnemy
                and enemyBearingToMeAbs < lookingAtBearing
                and not IsValid( enemy.terminator_crouchingbaited ) -- another one of us is getting em
                and not enemy.isTerminatorHunterKiller -- they are mean!
                and math.random( 0, 100 ) > 85 -- dont do it first opportunity, that wouldnt be fun
                and not self:EnemyIsLethalInMelee() -- they are meaner!
                and not enemy.terminator_CantConvinceImFriendly -- already tried to do it to em
                and enemy:IsOnGround() -- not crouch jumping
                and enemy.Crouching and enemy:Crouching()
                and enemy.GetVelocity and enemy:GetVelocity():Length2DSqr() < 75

                -- trick them into thinking we're friendly via the universal language of crouching
                if canFool then
                    data.baitcrouching = CurTime()
                    enemy.terminator_crouchingbaited = self

                elseif beingFooled then
                    if enemy.terminator_CantConvinceImFriendly then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "i gotta get close to them, hi, yeah im friendly!" )
                        self.PreventShooting = nil
                        return
                    else
                        self.PreventShooting = true
                        data.slinkAway = data.slinkAway or 0
                        data.slinkAway = data.slinkAway + 400
                        data.giveUpWatchingTime = _CurTime() + 400

                    end
                end

                self:HandleFakeCrouching( data, enemy )

                -- don't watch too much
                local maxWatches = 4 -- should be 4!

                -- the player looked at us earlier and is still looking
                local slinkAwayTime = data.slinkAway or math.huge
                local canWep, potentialWep = self:canGetWeapon()

                if ( enemy and enemy.isTerminatorHunterKiller ) and canWep and self:getTheWeapon( "movement_watch", potentialWep, "movement_handler" ) then
                    return

                elseif slinkAwayTime < _CurTime() then
                    -- yup they are staring
                    if data.crouchbaitcount then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "friendly, that's me, im friendly!" )
                        self.PreventShooting = true
                    elseif theyreInForASurprise then
                        -- lots of bots watching
                        if enemy.terminator_TerminatorsWatching and #enemy.terminator_TerminatorsWatching > 1 then
                            self:TaskComplete( "movement_watch" )
                            self:StartTask2( "movement_stalkenemy", nil, "thats enough looking" )
                            self.PreventShooting = true -- keep

                        -- its just me!
                        else
                            data.slinkAway = _CurTime() + math.Rand( 2, 4 )
                            data.giveUpWatchingTime = _CurTime() + math.Rand( 4, 8 )

                        end
                    -- don't do this forever!
                    elseif enemyBearingToMeAbs < 15 then
                        local watchCount = self.watchCount or 0
                        self.watchCount = watchCount + 0.4
                        if self.watchCount > maxWatches then
                            self.boredOfWatching = true
                        end
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_stalkenemy", nil, "thats enough looking" )
                        self.PreventShooting = true -- keep
                    -- they didnt notice us!
                    else
                        data.slinkAway = nil

                    end
                 -- the surprise has happened!
                elseif data.doneSurpriseSetup and not theyreInForASurprise and not beingFooled then
                    if enemy and enemy.isTerminatorHunterKiller then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_flankenemy", nil, "surprise has happened, time to close in.. carefully!" )
                        self.PreventShooting = nil

                    else
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "surprise has happened, time to close in!" )
                        self.PreventShooting = nil

                    end
                -- too close bub!
                elseif not beingFooled and ( self.DistToEnemy < tooCloseDist or ( enemy and enemy.isTerminatorHunterKiller ) ) then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_flankenemy", nil, "it is too close" )
                    self.PreventShooting = nil
                    if data.enemyIsBoxedIn == true then
                        -- charge enemy
                        self:ReallyAnger( 20 )

                    end
                -- where'd you go...
                elseif not self.IsSeeEnemy then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_approachlastseen", { pos = self.EnemyLastPos }, "where'd you go" )
                    self.PreventShooting = true
                -- i've been watching long enough
                elseif data.giveUpWatchingTime < _CurTime() then
                    local watchCount = self.watchCount or 0
                    self.watchCount = watchCount + 1
                    if self.watchCount > maxWatches then
                        self.boredOfWatching = true
                    end
                    if data.enemyIsBoxedIn == true then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "they're boxed in!" )
                        self.PreventShooting = true
                        -- charge enemy
                        self:ReallyAnger( 20 )

                    else
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_stalkenemy", nil, "all done watching" )
                        self.PreventShooting = true

                    end
                -- that's quite a weapon!
                elseif self:getLostHealth() > 10 or self:inSeriousDanger() then
                    if enemy then
                        enemy.terminator_CantConvinceImFriendly = true

                    end
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_stalkenemy", { flee = true }, "that really hurt!" )
                    self.PreventShooting = nil
                -- you shot me!!
                elseif self:getLostHealth() > 1 and not beingFooled then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_followenemy", nil, "that hurt a bit" )
                    self.PreventShooting = nil
                    if enemy then
                        enemy.terminator_CantConvinceImFriendly = true

                    end
                end
            end,
            OnDelete = function( self, _ )
                local enem = self:GetEnemy()
                -- this is over-engineered
                if not IsValid( enem ) then return end
                if not enem.terminator_TerminatorsWatching then return end

                table.RemoveByValue( enem.terminator_TerminatorsWatching, self )
                if not IsTableOfEntitiesValid( enem.terminator_TerminatorsWatching ) then
                    for index, ent in ipairs( enem.terminator_TerminatorsWatching ) do
                        if IsValid( ent ) then continue end
                        table.remove( enem.terminator_TerminatorsWatching, index )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_watch" )
                self.PreventShooting = nil
            end
        },
        ["movement_stalkenemy"] = {
            OnStart = function( self, data )

                --print( "stalkstart" )

                data.want = data.want or 8
                data.distMul = data.distMul or 1

                local myPos = self:GetPos()
                local enemy = self:GetEnemy()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or data.lastKnownStalkPos or self:GetPos()
                if not enemyPos then
                    data.InvalidAfterwards = true
                    return

                end

                local enemyDir = data.lastKnownStalkDir or self:GetForward()
                local enemyDis = data.lastKnownStalkDist or Distance2D( enemyPos, myPos ) or 1000

                if IsValid( enemy ) then
                    enemyDir = enemy:GetForward()

                    if data.forcedOrbitDist then
                        enemyDis = data.forcedOrbitDist

                    elseif self.IsSeeEnemy then
                        enemyDis = Distance2D( myPos, enemyPos )

                    end
                end

                local hp = self:Health()
                local maxHp = self:GetMaxHealth()

                local result = terminator_Extras.getNearestPosOnNav( enemyPos )

                if enemyPos and result.area:IsValid() then

                    local minEnemyDist = 0
                    if tooDangerousToApproach then
                        minEnemyDist = math.max( self.DistToEnemy * 0.75, 500 )

                    end

                    enemyDis = math.Clamp( enemyDis, minEnemyDist, math.huge )

                    local innerBoundary = math.Clamp( enemyDis + -300, 0, math.huge )
                    local outerBoundary = innerBoundary + 1000
                    local hardInnerBoundary = math.Clamp( enemyDis + -1000, minEnemyDist, math.huge )
                    local hardOuterBoundary = innerBoundary + 2000
                    local enemyArea = result.area
                    local enemyAreaCenter = enemyArea:GetCenter()

                    if myPos:DistToSqr( enemyAreaCenter ) > hardOuterBoundary^2 and self:areaIsReachable( enemyArea ) then
                        self:TaskFail( "movement_stalkenemy" )
                        self:StartTask2( "movement_flankenemy", { Time = 0.2 }, "got too far, i'll just close in" )
                        return

                    end

                    local scoreData = {}
                    scoreData.lethalCloseRange = tooDangerousToApproach
                    scoreData.hateVisible = hp < maxHp * 0.5
                    scoreData.enemyArea = enemyArea
                    scoreData.enemyAreaCenter = enemyAreaCenter
                    scoreData.innerBoundary = innerBoundary
                    scoreData.outerBoundary = outerBoundary
                    scoreData.hardInnerBoundary = hardInnerBoundary
                    scoreData.hardOuterBoundary = hardOuterBoundary
                    scoreData.lastStalkFromPos = data.lastStalkFromPos or myPos
                    scoreData.stalkStartPos = myPos

                    scoreData.lowestHeightAllowed = math.min( scoreData.enemyAreaCenter.z, myPos.z )
                    --debugoverlay.Cross( scoreData.lastStalkFromPos, 10, 20, color_white, true )

                    scoreData.canGoUnderwater = self:isUnderWater()

                    local scoreFunction = function( scoreData, area1, area2 )

                        if area2:IsBlocked() then return 0 end

                        local area2Center = area2:GetCenter()
                        local distanceTravelled = DistToSqr2D( area2Center, scoreData.lastStalkFromPos )
                        local wrongDirection = area2Center:DistToSqr( scoreData.lastStalkFromPos ) < area2Center:DistToSqr( scoreData.stalkStartPos )
                        local score = distanceTravelled
                        local areaDistanceToEnemy2 = DistToSqr2D( area2Center, scoreData.enemyAreaCenter )
                        local tooClose = SqrDistLessThan( areaDistanceToEnemy2, scoreData.innerBoundary )
                        local tooFar = SqrDistGreaterThan( areaDistanceToEnemy2, scoreData.outerBoundary )
                        local breakingLightRing = tooClose or tooFar
                        local bigTooClose = SqrDistLessThan( areaDistanceToEnemy2, scoreData.hardInnerBoundary )
                        local bigTooFar = SqrDistGreaterThan( areaDistanceToEnemy2, scoreData.hardOuterBoundary )
                        local breakingHardRing = bigTooFar or bigTooClose
                        local heightChange = math.abs( area2:ComputeAdjacentConnectionHeightChange( area1 ) )

                        if heightChange > self.loco:GetMaxJumpHeight() then
                            return 0

                        end

                        if not area2:IsCompletelyVisible( scoreData.enemyArea ) then
                            score = score^ 1.45

                        elseif scoreData.hateVisible then
                            score = score^0.1

                        end

                        if self.walkedAreas[area2:GetID()] then
                            score = score^0.85

                        end
                        if area2:IsUnderwater() and not scoreData.canGoUnderwater then
                            score = score^0.08

                        end
                        if wrongDirection then
                            -- you know what's really cool? NOT going where we just were!
                            score = score / ( score * 10000 )

                        end

                        if breakingHardRing then
                            if bigTooClose then
                                if scoreData.lethalCloseRange then
                                    score = score / ( score * 10000 )

                                else
                                    score = score^0.4

                                end
                            elseif bigTooFar then
                                score = score^0.2

                            end
                        elseif breakingLightRing then
                            if tooClose then
                                score = score^0.9

                            elseif tooFar then
                                score = score^0.8

                            end
                        end
                        if area2Center.z < scoreData.lowestHeightAllowed + -100 then
                            score = score^0.08

                        end
                        if heightChange > self.loco:GetStepHeight() * 2 then
                            score = score^0.2

                        end

                        --debugoverlay.Text( area2Center, tostring( math.Round( score, 2 ) ), 10, false )

                        return score

                    end
                    local stalkPos = self:findValidNavResult( scoreData, self:GetPos(), math.Rand( 4000, 5000 ), scoreFunction )

                    if stalkPos then
                        --debugoverlay.Cross( stalkPos, 40, 5, Color( 255, 255, 0 ), true )
                        -- build path left or right, weight it to never get too close to enemy aswell.
                        self:SetupFlankingPath( stalkPos, result.area, self.DistToEnemy * 0.8 )

                    end
                end

                if self:primaryPathIsValid() then
                    local stalksSinceLastSeen

                    if self.IsSeeEnemy then
                        stalksSinceLastSeen = 0

                    else
                        stalksSinceLastSeen = data.stalksSinceLastSeen or 0
                        stalksSinceLastSeen = stalksSinceLastSeen + 1

                    end

                    data.stalksSinceLastSeen = stalksSinceLastSeen
                    data.lastKnownStalkPos = enemyPos
                    data.lastKnownStalkDir = enemyDir
                    data.lastKnownStalkDist = enemyDis
                    data.lastStalkFromPos = myPos
                    return
                end
                data.InvalidAfterwards = true
            end,
            BehaveUpdate = function( self, data )
                local exit = nil
                local valid = nil

                local enemy = self:GetEnemy()
                local myPos = self:GetPos()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local enemyNav = terminator_Extras.getNearestPosOnNav( enemyPos ).area
                local reachable = self:areaIsReachable( enemyNav )

                if data.InvalidAfterwards then
                    if self.IsSeeEnemy then
                        -- missing a fail here caused massive cascade
                        self:TaskFail( "movement_stalkenemy" )
                        if reachable and not tooDangerousToApproach then
                            self:StartTask2( "movement_flankenemy", { Time = 0.2 }, "i can reach them, ill just go around" )
                        else
                            self:StartTask2( "movement_stalkenemy", { Time = 0.2, PerchWhenHidden = true }, "i cant reach them, ill stand somewhere high up i can see them" )
                        end
                        self.WasHidden = nil
                        self.PreventShooting = nil
                        return
                    end
                    if not data.invalidateTime then
                        data.invalidateTime = _CurTime() + math.Rand( 0.3, 1 )
                    elseif data.invalidateTime < _CurTime() then
                        self:TaskFail( "movement_stalkenemy" )
                        if data.want > 0 then
                            local newDat = {}
                            newDat.want = data.want + -1
                            newDat.stalksSinceLastSeen = data.stalksSinceLastSeen
                            newDat.lastStalkFromPos = data.lastStalkFromPos
                            newDat.lastKnownStalkDist = data.lastKnownStalkDist
                            newDat.lastKnownStalkDir = data.lastKnownStalkDir
                            newDat.lastKnownStalkPos = data.lastKnownStalkPos
                            newDat.PerchWhenHidden = data.PerchWhenHidden
                            newDat.PerchWhenHiddenPos = data.PerchWhenHiddenPos
                            self:StartTask2( "movement_stalkenemy", newDat, "i still want to stalk" )
                            self.WasHidden = nil
                        elseif data.lastKnownStalkPos then
                            self:StartTask2( "movement_approachlastseen", nil, "im gonna check where they were" )
                            self.WasHidden = nil
                            self.PreventShooting = nil
                        else
                            self:StartTask2( "movement_search", nil, "time to look for em" )
                            self.WasHidden = nil
                            self.PreventShooting = nil
                        end
                    end
                    return
                end

                local enemyBearingToMeAbs = math.huge
                local maxHealth = self:Health() == self:GetMaxHealth()
                if IsValid( enemy ) then
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                end
                local exposed = self.IsSeeEnemy and enemyBearingToMeAbs < 15
                if not exposed then
                    local hiddenCount = data.hiddenCount or 0
                    data.hiddenCount = hiddenCount + 1
                    if data.hiddenCount > 5 then
                        self.WasHidden = true

                    end
                end

                if self.PreventShooting then
                    if self.IsSeeEnemy and enemyBearingToMeAbs < 5 and self:Health() < self:GetMaxHealth() then
                        self.PreventShooting = nil

                    elseif tooDangerousToApproach then
                        self.PreventShooting = nil

                    end
                end

                if data.distMul and not self.IsSeeEnemy then
                    data.distMul = 1
                end

                local myPath = self:GetPath()
                local pathEndNav = terminator_Extras.getNearestPosOnNav( myPath:GetEnd() ).area
                local enemySeesDestination = nil

                if pathEndNav:IsValid() and enemyNav:IsValid() then
                    local enemOffsetted = enemyPos + vecFiftyZ
                    enemySeesDestination = terminator_Extras.PosCanSeeComplex( pathEndNav:GetCenter() + vecFiftyZ, enemOffsetted, self )
                    if self:PathIsValid() then
                        local segments = self:getCachedPathSegments()
                        local middleIndex = math.Round( #segments / 2 )
                        local middleSegment = segments[middleIndex]
                        if middleSegment.area.IsValid and middleSegment.area:IsValid() then
                            enemySeesMiddle = terminator_Extras.PosCanSeeComplex( middleSegment.area:GetCenter() + vecFiftyZ, enemOffsetted, self )

                        end
                    end
                end

                local tooCloseToDangerous = 900
                local tooCloseDistance = 900 * data.distMul
                local farTooCloseDistance = 700 * data.distMul
                local farFarTooCloseDistance = math.Clamp( 200 * data.distMul, 100, 800 )

                farTooCloseDistance = math.Clamp( farTooCloseDistance, 100, math.huge )

                local notLookingOrBeenAWhile = enemyBearingToMeAbs > 10 or data.stalksSinceLastSeen > 2

                local watch = notLookingOrBeenAWhile and IsValid( enemy ) and self.IsSeeEnemy and self.WasHidden and not self.boredOfWatching and maxHealth and self.DistToEnemy > 1000
                local ambush = enemyBearingToMeAbs > 90 and IsValid( enemy ) and self.IsSeeEnemy and not exposed and reachable and not tooDangerousToApproach and not self:inSeriousDanger()
                local tooClose = self.DistToEnemy < tooCloseDistance and self.IsSeeEnemy and reachable
                local farTooClose = self.DistToEnemy < farTooCloseDistance
                local farFarTooClose = self.DistToEnemy < farFarTooCloseDistance
                local intercept = self.lastInterceptPos or data.lastKnownStalkPos or myPos
                local newLocationCompare = data.lastKnownStalkPos or self.EnemyLastPos
                local newLocationInfo = SqrDistGreaterThan( newLocationCompare:DistToSqr( intercept ), 1500 )


                local pathGoal = self:GetPath():GetCurrentGoal()
                local posImHeadingTo
                if pathGoal then
                    dirToGoal = terminator_Extras.dirToPos( myPos, pathGoal.pos )
                    posImHeadingTo = myPos + dirToGoal * 100

                end
                local tooCloseToDangerousAndGettingCloser = tooDangerousToApproach and self.DistToEnemy < tooCloseToDangerous and posImHeadingTo and enemyPos and SqrDistLessThan( posImHeadingTo:DistToSqr( enemyPos ), self.DistToEnemy )

                local canGetWeap, potentialWep = self:canGetWeapon()

                local result = self:ControlPath2( not self.IsSeeEnemy and self.WasHidden )
                -- weap
                if canGetWeap and self:getTheWeapon( "movement_stalkenemy", potentialWep, "movement_stalkenemy" ) then
                    exit = true
                elseif self:canIntercept( data ) and ( self.WasHidden or newLocationInfo ) then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                elseif tooCloseToDangerousAndGettingCloser then
                    local orbitDist = math.Clamp( self.DistToEnemy * 2, 1000, math.huge )
                    self:TaskFail( "movement_stalkenemy" )
                    self:StartTask2( "movement_stalkenemy", { forcedOrbitDist = orbitDist, PerchWhenHidden = true }, "im too close to it!!" )
                    exit = true
                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_stalkenemy" )
                    exit = true
                -- really lame to get close and have it run away
                elseif farFarTooClose and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_duelenemy_near", { stalkDeathLoop = true }, "hey pal, you're way too close" )
                    exit = true
                -- really lame to get close and have it run away
                elseif farTooClose and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy", { Time = 0.1 }, "too close pal" )
                    exit = true
                -- we are too close and we just jumped out of somewhere hidden
                elseif tooClose and self.WasHidden and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy", { Time = 0.3 }, "too close" )
                    exit = true
                -- enemy isnt looking at us so we can observe them
                elseif watch then
                    if enemy.isTerminatorHunterKiller then
                        self.PreventShooting = nil
                        if result ~= nil then
                            valid = true
                        end
                    else
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_watch", nil, "i want to watch" )
                        exit = true
                    end
                -- we ended up behind the enemy and they haven't seen us yet
                elseif ambush then
                    self:TaskComplete( "movement_stalkenemy" )
                    if maxHealth and not self.boredOfWatching then
                        self:StartTask2( "movement_watch", nil, "i could shoot you, but not yet" )
                    else
                        self:StartTask2( "movement_followenemy", nil, "im behind the enemy!" )
                    end
                    exit = true
                -- we are exposed and we're about to walk even further into the enemy
                elseif exposed and enemySeesDestination then
                    self.WasHidden = false
                    valid = true
                -- we just exited from being hidden, and the enemy sees us
                elseif exposed and self.WasHidden then
                    self.WasHidden = false
                    valid = true
                -- we hit the end of our path, keep stalking
                elseif result then
                    valid = true
                -- invalid path, keep stalking
                elseif result == false then
                    valid = true
                end
                if exit then
                    self.WasHidden = nil
                    self.PreventShooting = nil
                end
                if valid then
                    self.PreventShooting = true
                    local myHp = self:Health()
                    local myMaxHp = self:GetMaxHealth()
                    local ratio = 0
                    if myHp == myMaxHp then
                        ratio = 1

                    else
                        ratio = myHp / myMaxHp
                        ratio = math.abs( ratio - 1 )
                        ratio = ratio + 2

                    end
                    local watchCount = self.watchCount or 0

                    if watchCount > 2 or myHp < ( myMaxHp * 0.95 ) or self:IsAngry() then
                        data.lastKnownStalkDist = math.Clamp( data.lastKnownStalkDist + -self.MoveSpeed, 0, math.huge )

                    end

                    local shouldPerchBecauseTheyTooDeadly = self:GetWeaponRange() > self.DistToEnemy and tooDangerousToApproach

                    -- this activates when ply is somewhere impossible to reach
                    if self.WasHidden and ( data.PerchWhenHidden or shouldPerchBecauseTheyTooDeadly ) then
                        local whereWeNeedToSee = data.PerchWhenHiddenPos or self.EnemyLastPos
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_perch", { requiredTarget = whereWeNeedToSee, cutFarther = true, perchRadius = self:GetRangeTo( whereWeNeedToSee ) * 1.5, distanceWeight = 0.01 }, "i cant reach ya, time to snipe!" )

                    -- if bot is low health then it does perching
                    elseif ratio < 1 and data.stalksSinceLastSeen > 2 then
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_perch", { requiredTarget = self.EnemyLastPos, cutFarther = true, perchRadius = self:GetRangeTo( self.EnemyLastPos ) * 1.5, distanceWeight = 0.01 }, "time to snipe!" )

                    elseif ( data.stalksSinceLastSeen or 0 ) < ( ratio * 5 ) then
                        local newDat = {}
                        newDat.distMul = data.distMul
                        newDat.stalksSinceLastSeen = data.stalksSinceLastSeen
                        newDat.lastStalkFromPos = data.lastStalkFromPos
                        newDat.lastKnownStalkDist = data.lastKnownStalkDist
                        newDat.lastKnownStalkDir = data.lastKnownStalkDir
                        newDat.lastKnownStalkPos = data.lastKnownStalkPos
                        newDat.PerchWhenHidden = data.PerchWhenHidden
                        newDat.PerchWhenHiddenPos = data.PerchWhenHiddenPos
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_stalkenemy", newDat, "i did a good stalk and i want to do more" )

                    else -- all done!
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_approachlastseen", { pos = data.lastKnownStalkPos or self.EnemyLastPos }, "im all done stalking" )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_stalkenemy" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_flankenemy"] = {
            OnStart = function( self, data )

                -- wait!
                if not self:nextNewPathIsGood() then
                    self:TaskFail( "movement_flankenemy" )
                    timer.Simple( 0.1, function()
                        if not IsValid( self ) then return end
                        self:StartTask2( "movement_flankenemy", nil, "i tried to path too early" )

                    end )
                    return

                end

                --find a simple path
                local enemy = self:GetEnemy()
                local bearingToMeAbs = self:enemyBearingToMeAbs()
                local enemySeesMe = bearingToMeAbs < 70

                if not IsValid( enemy ) then
                    data.InvalidAfterwards = true
                    return
                end
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local flankAroundPos = enemyPos
                local flankBubble

                local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                if otherHuntersHalfwayPoint then
                    flankAroundPos = otherHuntersHalfwayPoint
                    flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.7

                end
                local result = terminator_Extras.getNearestPosOnNav( flankAroundPos )

                if enemyPos and result.area:IsValid() and self:areaIsReachable( result.area ) then
                    -- flank em!
                    self:SetupFlankingPath( enemyPos, result.area, flankBubble )

                end
                if self:primaryPathIsValid() then
                    self.PreventShooting = ( not enemySeesMe and self.WasHidden ) and not enemy.isTerminatorHunterKiller
                    return
                end
                data.InvalidAfterwards = true
            end,
            BehaveUpdate = function( self, data )
                local exit = nil
                local keepHidden = nil
                if data.InvalidAfterwards then
                    self.WasHidden = nil
                    self.PreventShooting = nil
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_followenemy", nil, "nope couldnt flank em" )
                    --print( "flankquit" )
                    return
                end

                local enemy = self:GetEnemy()
                local goodEnemy = IsValid( enemy ) and self.IsSeeEnemy
                local enemyBearingToMeAbs = math.huge
                if IsValid( enemy ) then
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                end
                local goodBearing = enemyBearingToMeAbs < 30
                local exposed = self.IsSeeEnemy and goodBearing

                if not exposed then
                    self.WasHidden = true
                    if not self.IsSeeEnemy then
                        self.PreventShooting = true

                    end
                else
                    self.PreventShooting = nil
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and not self.IsSeeEnemy and self:getTheWeapon( "movement_flankenemy", potentialWep, "movement_flankenemy" ) then
                    exit = true
                elseif self:inSeriousDanger() or self:EnemyIsLethalInMelee() then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "that hurt!" )
                    exit = true
                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_flankenemy" )
                    exit = true
                elseif self.IsSeeEnemy and self.DistToEnemy < self.DuelEnemyDist then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_duelenemy_near", nil, "im close enough!" )
                    exit = true
                elseif self:canIntercept( data ) and not self.IsSeeEnemy and self.WasHidden then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                    exit = true
                elseif exposed and self.WasHidden then
                    if self:GetPath():GetLength() < 3000 then
                        self:TaskFail( "movement_flankenemy" )
                        self:StartTask2( "movement_flankenemy", nil, "they saw me sneaking" )
                        exit = true
                    else
                        self:TaskFail( "movement_flankenemy" )
                        self:StartTask2( "movement_stalkenemy", { Want = math.random( 1, 3 ) }, "they saw me sneaking" )
                        exit = true
                        keepHidden = true
                    end
                elseif result == true and goodEnemy then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_flankenemy", nil, "i got to my path's goal" )
                    exit = true
                    keepHidden = true
                elseif result == true and not goodEnemy then
                    --print( "bap" )
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "i got to my goal, but they aren't here" )
                elseif result == false then
                    --print( "bap2" )
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "my path failed for some reason" )
                    exit = true
                end
                if exit then
                    if not keepHidden then
                        self.WasHidden = nil
                    end
                    self.PreventShooting = nil
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_flankenemy" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() 
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        ["movement_intercept"] = { -- activates when alerted of enemy by our buddy
            OnStart = function( self, data )
                if not self.isUnstucking then
                    self:GetPath():Invalidate()
                end
                data.gaveItAChanceTime = _CurTime() + 4
                data.Time = _CurTime() + math.Rand( 0.01, 0.2 )
            end,
            BehaveUpdate = function( self, data )
                if data.Time and data.Time > _CurTime() then return end

                local lastInterceptPos              = self.lastInterceptPos
                local lastInterceptDir              = self.lastInterceptDir or vec_zero
                local lastInterceptDist2            = data.lastInterceptDistance2 or 0

                local nextPath = data.nextPath or 0
                if lastInterceptPos and nextPath < _CurTime() then

                    lastInterceptPosOffsetted = lastInterceptPos + Vector( 0, 0, 20 )
                    data.nextPath = _CurTime() + 0.8

                    local predictedRelativeEnd = ( lastInterceptDir * math.random( 2500, 3500 ) )
                    local predictedTraceStart = lastInterceptPosOffsetted + ( lastInterceptDir * 100 )
                    local predictionTr = util.QuickTrace( predictedTraceStart, predictedRelativeEnd, nil )
                    -- in wall
                    if predictionTr.StartSolid or predictionTr.Entity:IsPlayer() then goto terminatorInterceptNewPathFail end
                    local predictedPos = predictionTr.HitPos

                    --debugoverlay.Line( predictedTraceStart, predictedPos, 20, Color( 255,255,255 ), true )
                    -- bring it down the the ground
                    local floorTraceDat = {
                        start = predictedPos,
                        endpos = predictedPos + Vector( 0, 0, -2000 ),
                    }
                    predictedPos = util.TraceLine( floorTraceDat ).HitPos or predictedPos

                    -- first proper check
                    if not self:CanDoNewPath( predictedPos ) then goto terminatorInterceptNewPathFail end

                    local currDist2 = predictedPos:DistToSqr( lastInterceptPosOffsetted )
                    -- end here if this would place us closer to the enemy vs last time
                    if SqrDistGreaterThan( lastInterceptDist2, currDist2 + 50 ) then goto terminatorInterceptNewPathFail end

                    local gotoResult = terminator_Extras.getNearestPosOnNav( predictedPos )
                    if not gotoResult then data.Unreachable = true goto terminatorInterceptNewPathFail end

                    local reachable = self:areaIsReachable( gotoResult.area )
                    if not reachable then data.Unreachable = true goto terminatorInterceptNewPathFail end

                    local flankAroundPos = lastInterceptPosOffsetted
                    local flankBubble

                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                    -- BOX THEM IN BOX THEM IN
                    if otherHuntersHalfwayPoint then
                        flankAroundPos = otherHuntersHalfwayPoint
                        flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.7

                    end

                    local interceptResult = terminator_Extras.getNearestPosOnNav( flankAroundPos )

                    if interceptResult.area:IsValid() then
                        self:SetupFlankingPath( gotoResult.pos, interceptResult.area, flankBubble )
                        if self:primaryPathIsValid() then
                            data.lastInterceptDistance2 = currDist2

                        end
                    end

                    if not self:primaryPathIsValid() then
                        self:SetupPath2( gotoResult.pos )
                        if not self:primaryPathIsValid() then data.Unreachable = true goto terminatorInterceptNewPathFail end
                        data.lastInterceptDistance2 = currDist2

                    end
                end
                ::terminatorInterceptNewPathFail::

                local myPos = self:GetPos()
                local pathIsMostlyDone = self:primaryPathIsValid() and SqrDistLessThan( myPos:DistToSqr( self:GetPath():GetEnd() ), self:GetPath():GetLength() / 2 )

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                -- get WEAP
                if canWep and self:getTheWeapon( "movement_intercept", potentialWep, "movement_intercept" ) then
                    return
                elseif data.Unreachable then
                    --print( "unreach" )
                    self:TaskFail( "movement_intercept" )
                    self:StartTask2( "movement_handler", nil, "can't reach there" ) -- exit
                elseif self.IsSeeEnemy and pathIsMostlyDone then
                    self:EnemyAcquired( "movement_intercept" )
                elseif result then
                    self:TaskComplete( "movement_intercept" )
                    self:StartTask2( "movement_approachlastseen", { pos = self.lastInterceptPos }, "i got to the intercept" )
                elseif result == false and data.gaveItAChanceTime < _CurTime() then
                    self:TaskFail( "movement_intercept" )
                    self:StartTask2( "movement_handler", nil, "something went wrong" ) -- exit
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_intercept" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_approachforcedcheckposition"] = {
            OnStart = function( self, data )
                --print( "forcedcheck!" )
                data.approachAfter = _CurTime() + 0.1
                if not self.isUnstucking then
                    self:GetPath():Invalidate()
                end
            end,
            BehaveUpdate = function( self, data )
                local approachPos = data.forcedCheckPosition
                if not approachPos then
                    data.forcedCheckPosition, data.forcedCheckKey = table.Random( self.forcedCheckPositions )
                    approachPos = data.forcedCheckPosition

                end

                local enemy = self:GetEnemy()
                local goodEnemy = self.IsSeeEnemy and IsValid( enemy )
                local givenItAChance = data.approachAfter < _CurTime() -- this schedule didn't JUST start.

                if approachPos and not data.Unreachable then
                    local newPosToGoto = data.lastApproachPos and approachPos ~= data.lastApproachPos
                    local newPath = not self:primaryPathIsValid() or newPosToGoto or ( self:primaryPathIsValid() and self:CanDoNewPath( approachPos ) )
                    if newPath and self:nextNewPathIsGood() then
                        local snappedResult = terminator_Extras.getNearestPosOnNav( approachPos )
                        local posOnNav = snappedResult.pos

                        local reachable = self:areaIsReachable( snappedResult.area )
                        if not reachable then data.Unreachable = true return end

                        -- BOX IT IN
                        local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                        if otherHuntersHalfwayPoint then
                            local flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.5
                            self:SetupFlankingPath( posOnNav, snappedResult.area, flankBubble )
                            if not self:primaryPathIsValid() then data.Unreachable = true return end

                        else
                            self:SetupPath2( posOnNav )
                            if not self:primaryPathIsValid() then data.Unreachable = true return end

                        end
                        data.lastApproachPos = approachPos

                    end
                end
                local result = self:ControlPath2( not self.IsSeeEnemy )
                -- get WEAP
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:getTheWeapon( "movement_approachforcedcheckposition", potentialWep, "movement_approachforcedcheckposition" ) then
                    return
                elseif self:CanBashLockedDoor( approachPos, 800 ) then
                    self:BashLockedDoor( "movement_approachforcedcheckposition" )
                -- cant get to them
                elseif data.Unreachable and givenItAChance then
                    self:TaskFail( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_stalkenemy", { PerchWhenHidden = true, PerchWhenHiddenPos = approachPos }, "i couldnt reach the pos" )
                    self.forcedCheckPositions[ data.forcedCheckKey ] = nil
                -- i see you...
                elseif goodEnemy then
                    self:EnemyAcquired( "movement_approachforcedcheckposition" )
                -- i got there and you're nowhere to be seen
                elseif result == true and givenItAChance then
                    self:TaskComplete( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_searchlastdir", { Want = 4 }, "i got there but nobody's here" )
                    self.forcedCheckPositions[ data.forcedCheckKey ] = nil
                    self.PreventShooting = nil
                -- bad path
                elseif result == false and givenItAChance then
                    self:TaskFail( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_search", { searchWant = 80 }, "my path doesn't exist" )
                    self.PreventShooting = nil
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_approachforcedcheckposition" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_approachlastseen"] = {
            OnStart = function( self, data )
                data.approachAfter = _CurTime() + 0.1
                data.dontGetWepsForASec = _CurTime() + 1
                if not self.isUnstucking then
                    self:GetPath():Invalidate()
                end
            end,
            BehaveUpdate = function( self, data )
                local enemy = self:GetEnemy()
                local approachPos = data.pos or self.EnemyLastPos or self:GetLastEnemyPosition( enemy ) or nil
                local goodEnemy = self.IsSeeEnemy and IsValid( enemy )
                local givenItAChance = data.approachAfter < _CurTime() -- this schedule didn't JUST start.

                if approachPos and not data.Unreachable then
                    local newPosToGoto = data.lastApproachPos and approachPos ~= data.lastApproachPos
                    local newPath = not self:primaryPathIsValid() or newPosToGoto or ( self:primaryPathIsValid() and self:CanDoNewPath( approachPos ) )
                    if newPath and self:nextNewPathIsGood() then
                        local snappedResult = terminator_Extras.getNearestPosOnNav( approachPos )
                        local posOnNav = snappedResult.pos

                        local reachable = self:areaIsReachable( snappedResult.area )
                        if not reachable then data.Unreachable = true return end

                        -- BOX IT IN
                        local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                        if otherHuntersHalfwayPoint then
                            local flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.5
                            flankBubble = math.Clamp( flankBubble, 0, 3000 )
                            self:SetupFlankingPath( posOnNav, snappedResult.area, flankBubble )
                            if not self:primaryPathIsValid() then data.Unreachable = true return end

                        else
                            self:SetupPath2( posOnNav )
                            if not self:primaryPathIsValid() then data.Unreachable = true return end

                        end
                        data.lastApproachPos = approachPos

                    end
                end
                local result = self:ControlPath2( not self.IsSeeEnemy )
                -- get WEAP
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and data.dontGetWepsForASec < CurTime() and self:getTheWeapon( "movement_approachlastseen", potentialWep, "movement_approachlastseen" ) then
                    return
                elseif self:CanBashLockedDoor( approachPos, 800 ) then
                    self:BashLockedDoor( "movement_approachlastseen" )
                -- cant get to them
                elseif self:canIntercept( data ) then
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                elseif data.Unreachable and givenItAChance then
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_stalkenemy", { PerchWhenHidden = true, PerchWhenHiddenPos = approachPos }, "i cant get to the pos" )
                -- i see you...
                elseif goodEnemy then
                    self:EnemyAcquired( "movement_approachlastseen" )
                -- i got there and you're nowhere to be seen
                elseif result == true and givenItAChance then
                    if self.forcedCheckPositions and table.Count( self.forcedCheckPositions ) >= 1 then
                        self:TaskComplete( "movement_approachlastseen" )
                        self:StartTask2( "movement_approachforcedcheckposition", nil, "i reached the goal and there's another spot i can check" )
                    else
                        self:TaskComplete( "movement_approachlastseen" )
                        self:StartTask2( "movement_searchlastdir", { Want = 4 }, "i reached the goal, ill just look around" )
                        self.PreventShooting = nil
                    end
                -- bad path
                elseif result == false and givenItAChance then
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_search", { searchWant = 80 }, "something failed" )
                    self.PreventShooting = nil
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_approachlastseen" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_followenemy"] = {
            BehaveUpdate = function( self, data )

                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or self.EnemyLastPos or nil
                local GoodEnemy = self.IsSeeEnemy and IsValid( enemy )

                if enemyPos then
                    local newPath = not self:primaryPathIsValid() or ( self:primaryPathIsValid() and self:CanDoNewPath( enemyPos ) )
                    if newPath and not self.isUnstucking and not data.Unreachable then -- HACK
                        local result = terminator_Extras.getNearestPosOnNav( enemyPos )
                        local reachable = self:areaIsReachable( result.area )
                        if not reachable then data.Unreachable = true return end
                        local posOnNav = result.pos
                        self:SetupPath2( posOnNav )
                        if not self:primaryPathIsValid() then data.Unreachable = true return end
                    end
                end

                local distToExit = self.DuelEnemyDist
                if data.baitcrouching then
                    distToExit = 200

                end

                self:HandleFakeCrouching( data, enemy )

                if data.baitcrouching and enemy and self:getLostHealth() > 1 then
                    enemy.terminator_CantConvinceImFriendly = true

                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and not GoodEnemy and self:getTheWeapon( "movement_followenemy", potentialWep, "movement_followenemy" ) then
                    return
                elseif ( self:inSeriousDanger() and GoodEnemy ) or self:EnemyIsLethalInMelee() then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i dont want to die" )
                elseif self:CanBashLockedDoor( self:GetPos(), 1000 ) then
                    self:BashLockedDoor( "movement_followenemy" )
                elseif data.Unreachable and GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i cant get to them" )
                elseif data.Unreachable and not GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_search", { searchWant = 3 }, "i cant get there, and they're gone" )
                elseif self.IsSeeEnemy and self.DistToEnemy < distToExit then
                    if data.baitcrouching then
                        enemy.terminator_CantConvinceImFriendly = true
                        self.PreventShooting = nil
                        self.forcedShouldWalk = 0

                    end
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_duelenemy_near", nil, "i gotta punch em" )
                elseif result and not GoodEnemy then
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "where did they go" )
                elseif result == false then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_search", { searchWant = 80 }, "my path failed" )
                elseif not GoodEnemy and not self:primaryPathIsValid() then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "they're gone and im done" )
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_followenemy" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_duelenemy_near"] = {
            OnStart = function( self, data )

                data.duelQuitCount = self.duelQuitCount or 0
                local quitEat = -data.duelQuitCount * 4
                if self:IsAngry() then
                    quitEat = quitEat + -4

                end
                -- bot just chasing people feels like crap, so depending on dynamic stuff, just stop chasing people
                local duelEnemyTimeoutMul = self.duelEnemyTimeoutMul or 1
                local startingVal = 15 * duelEnemyTimeoutMul
                data.quitTime = _CurTime() + math.Clamp( startingVal + quitEat, 4, 8 )

                data.minNewPathTime = 0
                if not isnumber( data.NextPathAtt ) then
                    data.NextPathAtt = 0
                    data.NextRandPathAtt = 0
                end
            end,
            BehaveUpdate = function( self, data )
                local enemy = self:GetEnemy()
                local enemyPos = self.EnemyLastPos or self:GetLastEnemyPosition( enemy ) or nil
                local _ = self:ControlPath2( not self.IsSeeEnemy )
                local MaxDuelDist = self.DuelEnemyDist + 200
                local enemyNavArea = terminator_Extras.getNearestNav( enemyPos ) or NULL

                local badEnemy = nil
                local badEnemyCounts = data.badEnemyCounts or 0

                if IsValid( enemy ) and enemy:IsPlayer() then
                    data.fightingPlayer = true

                end

                if IsValid( enemy ) and enemy:Health() <= 0 then
                    badEnemy = true

                elseif not enemy or not self.IsSeeEnemy then
                    badEnemy = true

                end

                if not badEnemy then
                    data.badEnemyCounts = nil

                end

                local fisticuffsDist = 135
                local getWepDist = fisticuffsDist + 10
                local canWep, potentialWep = self:canGetWeapon()
                local distToWeapSqr = math.huge
                local wepDistToEnemySqr = math.huge

                if IsValid( potentialWep ) and IsValid( enemy ) then
                    distToWeapSqr = self:GetPos():DistToSqr( potentialWep:GetPos() )
                    wepDistToEnemySqr = enemy:GetPos():DistToSqr( potentialWep:GetPos() )

                end

                if badEnemy then
                    data.badEnemyCounts = badEnemyCounts + 1
                    if data.badEnemyCounts > 10 or data.fightingPlayer then
                        -- find weapons NOW!
                        self:NextWeapSearch( -1 )
                        canWep, potentialWep = self:canGetWeapon()

                        if canWep and self:getTheWeapon( "movement_duelenemy_near", potentialWep, "movement_handler" ) then
                            return

                        elseif enemyNavArea and enemyNavArea.IsValid and self:areaIsReachable( enemyNavArea ) then
                            self:TaskComplete( "movement_duelenemy_near" )
                            self:StartTask2( "movement_followenemy", nil, "my enemy left" )

                        else
                            self:TaskComplete( "movement_duelenemy_near" )
                            self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPos, searchWant = 10, searchRadius = 2000 }, "my enemy is gone and i cant get to where they were" )

                        end
                    end
                elseif self:EnemyIsLethalInMelee() or ( self:inSeriousDanger() or self:getLostHealth() > 140 ) and enemy and not data.stalkDeathLoop then
                    self:TaskFail( "movement_duelenemy_near" )
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i dont want to die" )
                elseif ( not self:areaIsReachable( enemyNavArea ) or data.Unreachable ) and enemy then
                    if data.stalkDeathLoop then
                        self:TaskFail( "movement_duelenemy_near" )
                        self:StartTask2( "movement_inertia", {}, "i cant reach them" )

                    else
                        self:TaskFail( "movement_duelenemy_near" )
                        self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i cant reach them" )

                    end
                elseif self.DistToEnemy > MaxDuelDist and self:areaIsReachable( enemyNavArea ) then
                    self:EnemyAcquired( "movement_duelenemy_near" )
                    --print("dist" )
                elseif IsValid( enemy ) and self.IsSeeEnemy then
                    local MyNavArea = self:GetCurrentNavArea()
                    local canDoNewPath = data.minNewPathTime < _CurTime()
                    local pathAttemptTime = 0.1
                    local reallyCloseToEnemy = self.DistToEnemy < 200

                    local wepIsOk = true
                    local wepIsReallyGood = nil
                    local wep = self:GetActiveWeapon()
                    if IsValid( wep ) then
                        wepIsOk = self:GetWeightOfWeapon( wep ) >= 4
                        wepIsReallyGood = self:GetWeightOfWeapon( wep ) >= 100

                    end
                    local reallyLowHealth = self:Health() < ( self:GetMaxHealth() * 0.25 )

                    -- drop our weap because fists will serve us better!
                    if self.DistToEnemy < 500 and not self:IsMeleeWeapon( wep ) and wep then
                        local blockFisticuffs = wepIsReallyGood or ( enemy:IsPlayer() and enemy:GetMoveType() == MOVETYPE_NOCLIP ) -- not dropping it if you're just gonna fly away with it!
                        local canDoFisticuffss = self.DistToEnemy < fisticuffsDist or ( data.quitTime < _CurTime() and ( math.random( 0, 100 ) < 25 ) ) or reallyLowHealth
                        local fistiCuffs = canDoFisticuffss and not blockFisticuffs
                        if fistiCuffs and self.HasFists then
                            if self:EnemyIsLethalInMelee() and not data.stalkDeathLoop then
                                self:TaskFail( "movement_duelenemy_near" )
                                self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 2 }, "i wanted to punch them, but ill back up instead" )

                            else
                                -- put weap on back
                                self:DropWeapon( false )
                                -- do this after dropweapon so we can set it a bit bigger!
                                self.terminator_NextWeaponPickup = _CurTime() + math.Rand( 1.5, 3 )

                            end
                        end
                    end

                    local FinishedOrInvalid = ( Result == true or not self:primaryPathIsValid() or not terminator_Extras.PosCanSeeComplex( self:EyePos(), enemy:EyePos(), self ) ) and canDoNewPath

                    local newPathIsGood = FinishedOrInvalid or reallyCloseToEnemy or data.NextPathAtt < _CurTime()
                    local wepIsUseful = not self:IsMeleeWeapon( wep ) and wep and wepIsOk

                    -- ranged weap
                    if newPathIsGood and wepIsUseful and not reallyLowHealth then
                        data.minNewPathTime = _CurTime() + 0.3
                        pathAttemptTime = 3
                        local adjAreas = MyNavArea:GetAdjacentAreas()
                        table.Shuffle( adjAreas )

                        local successfulPath

                        -- pick an adjacent area
                        for _, area in ipairs( adjAreas ) do
                            if not area then continue end
                            if not area:IsCompletelyVisible( MyNavArea ) then continue end -- dont go behind corners!
                            if area:HasAttributes( NAV_MESH_JUMP ) then continue end -- avoid attrib JUMP
                            local PathPos = area:GetRandomPoint()
                            if not terminator_Extras.PosCanSeeComplex( PathPos + plus25Z, self:EntShootPos( enemy ), self ) then continue end
                            if SqrDistGreaterThan( self:GetPos():DistToSqr( PathPos ), MaxDuelDist ) then continue end

                            self:SetupPath2( PathPos )
                            if not self:primaryPathIsValid() then break end
                            successfulPath = true
                            break

                        end
                        if not successfulPath then
                            goto SkipRemainingCriteria

                        end
                        data.NextPathAtt = _CurTime() + pathAttemptTime
                    --melee
                    elseif newPathIsGood then
                        data.minNewPathTime = _CurTime() + 0.05

                        local range = self:GetWeaponRange()
                        local zDist = math.abs( self:GetPos().z - enemyPos.z )
                        local highUp = zDist > range
                        -- closerToWeapon is more lenient, so bot gets weapons more often
                        local closerToWeapon = distToWeapSqr^2 < self.DistToEnemy^2
                        local weaponToMeLessThanWeaponToEnemy = distToWeapSqr < wepDistToEnemySqr
                        local badDist = ( closerToWeapon and weaponToMeLessThanWeaponToEnemy and self.DistToEnemy > getWepDist and not reallyLowHealth ) or highUp
                        local unholster = math.random( 1, 100 ) < 15 and self.DistToEnemy > getWepDist and self:IsHolsteredWeap( potentialWep )

                        local enemyBearingToMe = self:enemyBearingToMeAbs()
                        local quitEat = 10
                        if enemyBearingToMe < 30 then -- i stop running sooner when they lookin at me
                            quitEat = -4
                        end
                        local quitTime = data.quitTime + quitEat
                        local tooAngryToQuit = enemy.isTerminatorHunterKiller or self:IsReallyAngry()

                        -- i got close! im not giving up.
                        if self.DistToEnemy < 75 and terminator_Extras.PosCanSeeComplex( self:GetShootPos(), self:EntShootPos( enemy ), self ) then
                            data.quitTime = _CurTime() + 10

                        end

                        -- enemy isn't noving, don't quit!
                        if enemy:GetVelocity():Length2DSqr() < 1600 then
                            data.quitTime = data.quitTime + 0.5

                        end

                        local bored = quitTime <= _CurTime()
                        local wepIsGoodIdea = unholster or badDist or bored

                        if wepIsGoodIdea and canWep and self:getTheWeapon( "movement_duelenemy_near", potentialWep, "movement_handler" ) then
                            return

                        elseif reallyCloseToEnemy and ( not self.LastShootBlocker or self.LastShootBlocker == enemy ) then
                            if self:primaryPathIsValid() then
                                self:GetPath():Invalidate()

                            end
                            self:GotoPosSimple( enemyPos, 10 )

                        elseif not bored or tooAngryToQuit then

                            local enemVel = enemy:GetVelocity()
                            local velProduct = math.Clamp( enemVel:Length() * 1.4, 0, self.DistToEnemy * 0.8 )
                            local Offset = enemVel:GetNormalized() * velProduct

                            -- determine where player CAN go
                            -- dont build path to somewhere behind walls
                            local mymins,mymaxs = self:GetCollisionBounds()
                            mymins = mymins * 0.5
                            mymaxs = mymaxs * 0.5

                            local pathHull = {}
                            pathHull.start = enemyPos
                            pathHull.endpos = enemyPos + Offset
                            pathHull.mask = MASK_SOLID_BRUSHONLY
                            pathHull.mins = mymins
                            pathHull.maxs = mymaxs

                            local whereToInterceptTr = util.TraceHull( pathHull )

                            local PathPos = whereToInterceptTr.HitPos

                            --debugoverlay.Cross( PathPos, 10, 1, Color( 255,255,0 ) )
                            local interceptResult = terminator_Extras.getNearestPosOnNav( PathPos )
                            local timeAdd = math.Clamp( velProduct / 200, 0.1, 1 )

                            data.NextPathAtt = _CurTime() + timeAdd
                            --print( timeAdd )

                            self:SetupPath2( interceptResult.pos )
                            if self:primaryPathIsValid() then goto SkipRemainingCriteria end
                            data.Unreachable = true

                        -- the bot isnt just gonna follow you around forever
                        else
                            self.duelQuitCount = data.duelQuitCount + 1
                            self:TaskFail( "movement_duelenemy_near" )
                            self:StartTask2( "movement_watch", { tooCloseDist = 150 }, "they're just running" )

                        end
                        data.NextPathAtt = _CurTime() + pathAttemptTime

                    end

                    ::SkipRemainingCriteria::
                    if data.Unreachable and data.NextRandPathAtt < _CurTime() then
                        data.NextRandPathAtt = _CurTime() + math.random( 1, 2 )
                        self:SetupPath2( MyNavArea:GetRandomPoint() )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_duelenemy_near" )
            end,
            ShouldRun = function( self, data )
                local caps = self:CapabilitiesGet()
                local ranged = bit.band( caps, CAP_WEAPON_RANGE_ATTACK1 ) > 0
                local killerrr = self:GetEnemy() and self:GetEnemy().isTerminatorHunterKiller
                local isRandomOrIsMelee = ( _CurTime() + self:GetCreationID() ) % 10 > 8 or not ranged
                local randomOrMeleeOrDamaged = isRandomOrIsMelee or self:getLostHealth() > 3 or killerrr -- if player is engaging us, dont walk
                return randomOrMeleeOrDamaged and self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_inertia"] = {
            OnStart = function( self, data )
                if not isnumber( data.Want ) then
                    data.Want = 30
                end
                data.PathStart = self:GetPos()
                data.Want = data.Want + -1

                local canDoUnderWater = self:isUnderWater()
                local wanderPos = nil
                local myNavArea = self:GetCurrentNavArea()

                if not myNavArea then
                    data.InvalidateAfterwards = true
                    return
                end

                --normal path
                local Dir = data.Dir or self:GetForward()
                local scoreData = {}
                scoreData.canDoUnderWater = canDoUnderWater
                scoreData.self = self
                scoreData.forward = Dir:Angle()
                scoreData.startArea = myNavArea
                scoreData.startPos = scoreData.startArea:GetCenter()

                local scoreFunction = function( scoreData, area1, area2 )
                    local ang = scoreData.forward
                    local dropToArea = area2:ComputeAdjacentConnectionHeightChange(area1)
                    local score = area2:GetCenter():DistToSqr( scoreData.startPos ) * math.Rand( 0.8, 1.4 )
                    if scoreData.self.walkedAreas[area2:GetID()] then
                        return 1
                    end
                    if not area2:IsPotentiallyVisible( scoreData.startArea ) then
                        score = score*2
                    end
                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = score * 0.01
                    end
                    if dropToArea > self.loco:GetMaxJumpHeight() then
                        score = score * 0.01
                    end

                    --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( math.sqrt( score ) ) ), 8 )

                    return score

                end

                wanderPos = self:findValidNavResult( scoreData, self:GetPos(), math.random( 3000, 4000 ), scoreFunction )

                if wanderPos then
                    self:SetupPath2( wanderPos )

                    if not self:primaryPathIsValid() then
                        data.InvalidateAfterwards = true
                        return
                    end
                else
                    data.InvalidateAfterwards = true
                    return
                end
            end,
            BehaveUpdate = function( self, data )
                local result = self:ControlPath2( not self.IsSeeEnemy )

                local canWep, potentialWep = self:canGetWeapon()

                if data.InvalidateAfterwards then
                    self:TaskFail( "movement_inertia" )
                    timer.Simple( 0.1, function()
                        if not IsValid( self ) then return end
                        self:StartTask2( "movement_biginertia", nil, "i couldnt find somewhere to wander" )

                    end )
                    return

                elseif canWep and self:getTheWeapon( "movement_inertia", potentialWep, "movement_inertia" ) then 
                    return
                elseif self:canIntercept( data ) then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_inertia" )
                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                elseif IsValid( self.awarenessUnknown[1]  ) then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_understandobject", nil, "im curious" )
                elseif data.Want > 0 then
                    if result == true then
                        self:TaskComplete( "movement_inertia" )
                        self:StartTask2( "movement_inertia", { Want = data.Want, Dir = terminator_Extras.dirToPos( data.PathStart, self:GetPos() ) }, "i still want to wander" )
                    else
                        self:TaskComplete( "movement_inertia" )
                        self:StartTask2( "movement_inertia", { Want = data.Want, Dir = -self:GetForward() }, "i want to wander behind me" )
                    end
                elseif ( data.want or 0 ) <= 0 then -- no want, end the inertia
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_biginertia", { Want = 20 }, "im bored of small wandering" )
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_inertia" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        ["movement_biginertia"] = {
            OnStart = function( self, data )

                -- wait!
                if not self:nextNewPathIsGood() then
                    self:TaskFail( "movement_biginertia" )
                    timer.Simple( 0.1, function()
                        if not IsValid( self ) then return end
                        self:StartTask2( "movement_biginertia", nil, "i tried to path too early" )

                    end )
                    return

                end

                if not isnumber( data.Want ) then
                    data.Want = 30
                end
                data.PathStart = self:GetPos()
                data.Want = data.Want + -1
                -- continue, or start where we left off, or don't throw errors
                data.beenAreas = data.beenAreas or self.bigInertiaPreserveBeenAreas or {}

                self.bigInertiaPreserveBeenAreas = nil

                local canDoUnderWater = self:isUnderWater()
                local wanderPos = nil
                local myNavArea = self:GetCurrentNavArea()

                if not myNavArea then
                    self:TaskFail( "movement_biginertia" )
                    self:StartTask2( "movement_wait", nil, "i dont know where i am" )
                    return
                end

                local foundSomewhereNotBeen = nil

                --normal path
                local dir = data.dir or self:GetForward()
                dir = -dir
                local scoreData = {}
                scoreData.canDoUnderWater = canDoUnderWater
                scoreData.self = self
                scoreData.forward = dir:Angle()
                scoreData.startArea = myNavArea
                scoreData.startPos = scoreData.startArea:GetCenter()
                scoreData.beenAreas = data.beenAreas

                local scoreFunction = function( scoreData, area1, area2 ) -- this is the function that determines the score of a navarea
                    local ang = scoreData.forward
                    local dropToArea = area2:ComputeAdjacentConnectionHeightChange(area1)
                    local score = area2:GetCenter():DistToSqr( scoreData.startPos ) * math.Rand( 0.8, 1.4 )

                    if dropToArea > self.loco:GetJumpHeight() then 
                        return 0

                    end

                    if scoreData.beenAreas[area2:GetID()] then -- if the npc has already been to this area, return a score of 1
                        score = score * 0.0001
                    else
                        foundSomewhereNotBeen = true
                    end
                    if math.abs( terminator_Extras.BearingToPos( scoreData.startPos, scoreData.forward, area2:GetCenter(), scoreData.forward ) ) < 22.5 then
                        score = score^1.5
                    end
                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = score * 0.001
                    end
                    if math.abs( dropToArea ) > 50 then
                        score = score * 0.001
                    end

                    --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( score ) ), 8 )

                    return score

                end

                wanderPos = self:findValidNavResult( scoreData, self:GetPos(), math.random( 5000, 6000 ), scoreFunction )

                if foundSomewhereNotBeen == nil then
                    self.bigInertiaPreserveBeenAreas = {}
                    data.beenAreas = {}
                    local fails = data.fails or 0
                    if self.IsSeeEnemy then
                        self:EnemyAcquired( "movement_biginertia" )
                        self.bigInertiaPreserveBeenAreas = nil

                    elseif not self:IsMeleeWeapon( self:GetWeapon() ) and self:GetWeaponRange() > 2000 then
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_perch", nil, "i ran out of places, and i have a real weapon" )

                    elseif fails < 10 then
                        self:TaskFail( "movement_biginertia" )
                        timer.Simple( 0.1, function()
                            if not IsValid( self ) then return end
                            self:StartTask2( "movement_biginertia", { fails = fails + 1 }, "i ran out of unreached spots, going back" )

                        end )
                    else
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_handler", nil, "my biginertia ended up in a death spiral" )

                    end

                elseif wanderPos then
                    self:SetupPath2( wanderPos )

                    if not self:primaryPathIsValid() then
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_wait", nil, "i couldnt make a path" )
                        self.bigInertiaPreserveBeenAreas = data.beenAreas

                    end
                else
                    self:TaskFail( "movement_biginertia" )
                    self:StartTask2( "movement_search", nil, "i couldnt find somewhere to wander to" ) -- just do something!
                    self.bigInertiaPreserveBeenAreas = data.beenAreas

                end
            end,
            BehaveUpdate = function( self, data )

                -- give up on self.bigInertiaPreserveBeenAreas if enemy has been known to move!

                local want = data.Want or 0
                local canWep, potentialWep = self:canGetWeapon()

                local result = self:ControlPath2( not self.IsSeeEnemy )
                if canWep and self:getTheWeapon( "movement_biginertia", potentialWep, "movement_biginertia" ) then
                    self.bigInertiaPreserveBeenAreas = data.beenAreas
                    return
                elseif self:canIntercept( data ) then
                    self:TaskComplete( "movement_biginertia" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                    self.bigInertiaPreserveBeenAreas = nil
                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_biginertia" )
                    self.bigInertiaPreserveBeenAreas = nil
                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_biginertia" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, " i heard something" )
                    self.bigInertiaPreserveBeenAreas = nil
                elseif not data.blockUnderstanding and IsValid( self.awarenessUnknown[1] ) and self:nextNewPathIsGood() then
                    self:TaskComplete( "movement_biginertia" )
                    self:StartTask2( "movement_understandobject", nil, "im curious" )
                    self.bigInertiaPreserveBeenAreas = data.beenAreas
                elseif want > 0 then
                    if result ~= nil then
                        local potentiallyBeenAreas = navmesh.Find( data.PathStart, self:GetPos():Distance( data.PathStart ), self.loco:GetStepHeight() * 2, self.loco:GetStepHeight() )

                        for _, potentiallyBeenArea in ipairs( potentiallyBeenAreas ) do
                            local areaId = potentiallyBeenArea:GetID()
                            if not data.beenAreas[ areaId ] then
                                data.beenAreas[ areaId ] = true
                                --debugoverlay.Text( potentiallyBeenArea:GetCenter(), "IBEEN", 20 )

                            end
                        end
                    end

                    if result == true then
                        self:TaskComplete( "movement_biginertia" )
                        local wepRange = self:GetWeaponRange()
                        local chanceNeeded = 85
                        if wepRange == math.huge or SqrDistGreaterThan( wepRange, 2500 ) then
                            chanceNeeded = 15

                        end
                        if table.Count( data.beenAreas ) > self.RunSpeed * 3 and math.random( 0, 100 ) > chanceNeeded then
                            self:StartTask2( "movement_perch", nil, "i wandered a long time, ill wait here" )
                            self.bigInertiaPreserveBeenAreas = nil

                        else
                            self:StartTask2( "movement_biginertia", { Want = want, dir = terminator_Extras.dirToPos( data.PathStart, self:GetPos() ), beenAreas = data.beenAreas }, "i still want to wander" )
                            self.bigInertiaPreserveBeenAreas = data.beenAreas

                        end
                    elseif result == false then
                        self:TaskComplete( "movement_biginertia" )
                        self:StartTask2( "movement_biginertia", { Want = want, beenAreas = data.beenAreas }, "my path failed, but i still want to wander" )
                        self.bigInertiaPreserveBeenAreas = data.beenAreas

                    end

                else -- no want, end the inertia
                    self:TaskComplete( "movement_biginertia" )
                    self:StartTask2( "movement_handler", nil, "im all done wandering" )
                    self.bigInertiaPreserveBeenAreas = data.beenAreas
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_biginertia" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        -- enemy dependant, stand totally still and fire our gun when our enemy is also standing still 
        ["movement_camp"] = {
            OnStart = function( self, data )

                data.startingEnemyPos = self.EnemyLastPos

                path = self:GetPath()
                if not self.isUnstucking then
                    path:Invalidate()

                end

                self.campingFailures = self.campingFailures or 0

                data.campingStaringTolerance = math.Clamp( 50 + -( self.campingFailures * 5 ), 10, 50 ) -- increases if the player gets wise to our camping
                data.maxNoSeeing = data.maxNoSeeing or 150
                data.tooCloseDist = data.tooCloseDist or 1500
                data.campingCounter = 0
                data.notSeeCount = 0
                data.campingTarget = math.random( 40, 90 )
                data.targetModulo = data.campingTarget

                if IsValid( self:GetEnemy() ) and self:enemyBearingToMeAbs() < 15 then
                    -- we aint foolin nobody!
                    data.startedAsSeen = true

                end

                self.totalCampingCount = self.totalCampingCount or 0

                if self:Health() < ( self:GetMaxHealth() * 0.9 ) or data.startedAsSeen then
                    data.campingTarget = data.campingTarget * 0.15

                end

                local notGonnaBeSurprised = enemy and ( enemy.isTerminatorHunterKiller or self:EnemyIsLethalInMelee() )
                if notGonnaBeSurprised then
                    self.PreventShooting = nil

                else
                    self.PreventShooting = true -- this IS a SNIPING behaviour, not a "fire everything we have" behaviour!

                end
            end,
            BehaveUpdate = function( self, data )
                local enemy = self:GetEnemy()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee()
                local enemyBearingToMeAbs = math.huge
                local enemStandingStill = nil
                local standingSortaStillAndBored = nil
                local veryBored = nil

                if IsValid( enemy ) then
                    local velLengSqr = enemy:GetVelocity():Length2DSqr()
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                    enemStandingStill = velLengSqr < 15^2

                    local walkSpeed = 0
                    if enemy.GetWalkSpeed then walkSpeed = enemy:GetWalkSpeed() end

                    standingSortaStillAndBored = velLengSqr <= walkSpeed and self.totalCampingCount > 500
                    -- get it over with already!
                    veryBored = self.totalCampingCount > 1000

                end

                local lostHp = self:getLostHealth()

                self.blockReallyStuckAccumulate = _CurTime() + 5

                if self.IsSeeEnemy then
                    -- oh sh-
                    if lostHp > 10 or self:inSeriousDanger() then
                        self:TaskComplete( "movement_camp" )
                        self:StartTask2( "movement_stalkenemy", nil, "it shot me" )
                        self.PreventShooting = nil
                        return

                    end

                    data.wasEnemy = true
                    data.notSeeCount = 0
                    self.totalCampingCount = self.totalCampingCount + 3
                    if enemyBearingToMeAbs > 15 or standingSortaStillAndBored or veryBored or data.startedAsSeen then
                        if enemStandingStill or standingSortaStillAndBored or veryBored or data.startedAsSeen then
                            if data.startedAsSeen and data.campingCounter < data.campingTarget then
                                data.campingCounter = data.campingCounter + 8

                            else
                                data.campingCounter = data.campingCounter + 4

                            end

                            if enemy and enemy.isTerminatorHunterKiller then
                                self.PrevenetShooting = nil

                            elseif data.campingCounter >= data.campingTarget then
                                self.PreventShooting = ( data.campingCounter % data.targetModulo * 0.5 ) > data.targetModulo * 0.25

                            else
                                self.PreventShooting = true

                            end
                        else
                            data.campingCounter = data.campingCounter + 1

                        end
                    elseif enemyBearingToMeAbs < 5 then
                        if enemy and enemy.isTerminatorHunterKiller then
                            -- nopenope
                            self.PreventShooting = nil
                            data.campingCounter = data.campingCounter + -40

                        else
                            -- they see us!
                            self.PreventShooting = nil
                            data.campingCounter = data.campingCounter + -4

                        end
                    else
                        -- don't reveal our pos!
                        data.campingCounter = 0

                    end
                else
                    self.totalCampingCount = self.totalCampingCount + 1
                    if data.wasEnemy then
                        if enemy and enemy.isTerminatorHunterKiller then
                            -- dont run away
                            data.notSeeCount = data.notSeeCount + 40

                        else
                            -- get bored faster
                            data.notSeeCount = data.notSeeCount + 20

                        end
                    elseif self:canIntercept( data ) then
                        data.notSeeCount = data.notSeeCount + 10

                    else
                        data.notSeeCount = data.notSeeCount + 1

                    end

                end

                local enemyMovedReallyFar = nil

                if data.startingEnemyPos then
                    enemyMovedReallyFar = SqrDistGreaterThan( data.startingEnemyPos:DistToSqr( self.EnemyLastPos ), 1000 )

                end

                if self.IsSeeEnemy and self.DistToEnemy < data.tooCloseDist then
                    self:TaskComplete( "movement_camp" )
                    if tooDangerousToApproach then
                        self:StartTask2( "movement_stalkenemy", nil, "they got too close, and they scary!" )

                    else
                        self:StartTask2( "movement_flankenemy", nil, "they got too close to me" )

                    end
                    self.PreventShooting = nil

                -- where'd you go...
                elseif enemyMovedReallyFar or ( not self.IsSeeEnemy and data.notSeeCount > data.maxNoSeeing ) then
                    local perchRadius = self:GetRangeTo( self.EnemyLastPos ) * 1.5

                    -- start a new perching where we pick a pos with tighter criteria
                    self:TaskComplete( "movement_camp" )
                    self:StartTask2( "movement_perch", { requiredTarget = self.EnemyLastPos, cutFarther = true, perchRadius = perchRadius, distanceWeight = 0.1 }, "i lost sight of them" )

                    self.PreventShooting = nil

                -- bored
                elseif ( not self.IsSeeEnemy and lostHp > 1 ) or data.campingCounter < -data.campingStaringTolerance or self:IsFists() then

                    self.campingFailures = self.campingFailures + 1

                    self:TaskComplete( "movement_camp" )
                    self:StartTask2( "movement_stalkenemy", nil, "im bored" )
                    self.PreventShooting = nil

                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_camp" )
                self.PreventShooting = nil
            end,
            ShouldCrouch = function( self )
                return true
            end,
        },

        -- NOT IMPLIMENTED 
        -- find 2 functions
            -- wep.scoringFunc -- takes navarea and returns value, higher value for better placement
            -- wep.placingFunc -- returns pos that terminator should aim at before pri attacking

        ["movement_placeweapon"] = {
            OnStart = function( self, data )
                local wep = self:GetWeapon()
                local range = wep.Range or 5000
                data.potentialPlaceables = navmesh.Find( self:GetPos(), range, 100, 100 )
                data.scoredPlaceables = {}

            end,
            BehaveUpdate = function( self, data )
                local wep = self:GetWeapon()
                local armed = not self:IsFists()
                local myPos = self:GetPos()

                if not armed or not isfunction( wep.placingFunc ) or not isfunction( wep.scoringFunc ) then
                    self:TaskFail( "movement_placeweapon" )
                    self:StartTask2( "movement_handler" )
                elseif self:canIntercept( data ) then
                    self:TaskComplete( "movement_placeweapon" )
                    self:StartTask2( "movement_intercept" )
                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_placeweapon" )
                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_placeweapon" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                elseif #data.potentialPlaceables >= 1 then
                    for _ = 1, 20 do
                        if #data.potentialPlaceables == 0 then break end
                        local perchableArea = table.remove( data.potentialPlaceables, 1 )
                        local checkPositions = getUsefulPositions( perchableArea )

                        for _, checkPos in ipairs( checkPositions ) do
                            checkPos = checkPos + Vector( 0,0,5 )
                            local dat = {
                                start = checkPos,
                                endpos = checkPos + negativeFiveHundredZ,
                                mask = MASK_SOLID
                            }
                            local trace = util.TraceLine( dat )
                            local flooredPos = trace.HitPos
                            checkPos = flooredPos + plus25Z
                            local nookScore = terminator_Extras.GetNookScore( checkPos, 6000, nookOverrideDirections )
                            local distance = checkPos:Distance( myPos )
                            local zOffset = checkPos.z - myPos.z

                            local score = ( ( distance * 0.01 ) + zOffset * 4 ) / nookScore

                            data.scoredPlaceables[ score ] = checkPos

                        end
                    end
                elseif not data.bestPos then
                    data.bestPosScore = table.maxn( data.scoredPlaceables )
                    data.bestPos = data.scoredPlaceables[ data.bestPosScore ]
                    --debugoverlay.Text( data.bestPos, "a" .. data.bestPosScore, 10, false )

                else
                    if not self:primaryPathIsValid() or self:primaryPathIsValid() and self:CanDoNewPath( data.bestPos ) then
                        self:SetupPath2( data.bestPos )
                    end
                    local result = self:ControlPath2( not self.IsSeeEnemy )
                    if result == true then
                        self:TaskComplete( "movement_placeweapon" )
                        self:StartTask2( "movement_camp", { maxNoSeeing = 800 / terminator_Extras.GetNookScore( data.bestPos, 6000 ) } )

                    elseif result == false then
                        self:TaskComplete( "movement_placeweapon" )
                        self:StartTask2( "movement_biginertia" )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_inertia" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() and not SqrDistLessThan( self:GetPos():DistToSqr( self:GetPath():GetEnd() ), 600 )
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk() 
            end,
        },
        ["movement_perch"] = {
            OnStart = function( self, data )
                data.perchRadius = data.perchRadius or 10000
                data.distanceWeight = data.distanceWeight or 1 
                data.potentialPerchables = navmesh.Find( self:GetPos(), data.perchRadius, self.loco:GetMaxJumpHeight(), self.loco:GetMaxJumpHeight() )
                -- cut potential perchables that take me farther away from the enemy
                if data.cutFarther and data.requiredTarget then
                    local myPos = self:GetPos()
                    local myDistToTarget = myPos:DistToSqr( data.requiredTarget )
                    local perchablesOld = table.Copy( data.potentialPerchables )
                    data.potentialPerchables = {}

                    for _, perchableArea in ipairs( perchablesOld ) do
                        if perchableArea:GetCenter():DistToSqr( data.requiredTarget ) < myDistToTarget then
                            table.insert( data.potentialPerchables, perchableArea )

                        end
                    end
                end

                data.scoredPerchables = {}
                data.nookOverrideDirections = {
                    -- cardinal directions with a bias downwards
                    Vector( 0.7, 0, -0.3 ),
                    Vector( -0.7, 0, -0.3 ),
                    Vector( 0, 0.7, -0.3 ),
                    Vector( 0, -0.7, -0.3 ),

                    -- 45 degree directions with a bias downwards
                    Vector( -0.35, 0.35, -0.3 ),
                    Vector( -0.35, -0.35, -0.3 ),
                    Vector( 0.35, 0.35, -0.3 ),
                    Vector( 0.35, -0.35, -0.3 ),

                    -- up
                    Vector( 0, 0, 1 ),
                }

            end,
            BehaveUpdate = function( self, data )
                if self.IsSeeEnemy and IsValid( self:GetEnemy() ) and self:GetEnemy().isTerminatorHunterKiller then
                    self.PreventShooting = nil

                end

                local myPos = self:GetPos()
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and self:getTheWeapon( "movement_perch", potentialWep, "movement_perch" ) then
                    return
                elseif self:canIntercept( data ) and not data.requiredTarget then
                    self:TaskComplete( "movement_perch" )
                    self:StartTask2( "movement_intercept", nil, "i can intercept someone" )
                elseif self.IsSeeEnemy and IsValid( self:GetEnemy() ) and ( self:getLostHealth() > 1 or SqrDistLessThan( self:GetEnemy():GetPos():DistToSqr( myPos ), 700 ) ) then
                    self:EnemyAcquired( "movement_perch" )
                elseif self:validSoundHint() and not data.requiredTarget then
                    self:TaskComplete( "movement_perch" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                elseif #data.potentialPerchables >= 1 then
                    for _ = 1, 18 do
                        if #data.potentialPerchables == 0 then break end
                        local perchableArea = table.remove( data.potentialPerchables, 1 )
                        local center = perchableArea:GetCenter()
                        local checkPositions = getUsefulPositions( perchableArea )

                        for _, checkPos in ipairs( checkPositions ) do
                            checkPos = checkPos + plus25Z
                            local dat = {
                                start = checkPos,
                                endpos = checkPos + negativeFiveHundredZ,
                                mask = MASK_SOLID
                            }
                            local trace = util.TraceLine( dat )
                            local flooredPos = trace.HitPos
                            checkPos = flooredPos + plus25Z
                            local nookScore = terminator_Extras.GetNookScore( checkPos, 6000, data.nookOverrideDirections )
                            local distance = checkPos:Distance( myPos ) * data.distanceWeight
                            local canSeeTargetMul = 1
                            if data.requiredTarget then
                                local _, canSeeTr = terminator_Extras.PosCanSeeComplex( checkPos, data.requiredTarget, self )
                                local canSee = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( data.requiredTarget ), 150 )
                                if canSee then
                                    canSeeTargetMul = 8

                                else
                                    canSeeTargetMul = 0.01

                                end
                            end
                            local zOffset = checkPos.z - myPos.z

                            local score = ( ( distance * 0.01 ) + zOffset * 4 ) / nookScore
                            score = score * canSeeTargetMul

                            data.scoredPerchables[ score ] = checkPos

                        end
                    end
                elseif not data.bestPos then
                    data.bestPosScore = table.maxn( data.scoredPerchables )
                    data.bestPos = data.scoredPerchables[ data.bestPosScore ]

                    if data.requiredTarget and data.bestPos then
                        local _, canSeeTr = terminator_Extras.PosCanSeeComplex( data.bestPos, data.requiredTarget, self )
                        local canSee = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( data.requiredTarget ), 200 )
                        if not canSee then
                            self:TaskFail( "movement_perch" )
                            self:StartTask2( "movement_approachlastseen", nil, "i couldnt find a spot that sees what i want" )
                            return
                        end
                    else
                        self:TaskFail( "movement_perch" )
                        self:StartTask2( "movement_approachlastseen", nil, "i couldnt find a good spot" )

                    end
                    --debugoverlay.Text( data.bestPos, "a" .. data.bestPosScore, 10, false )

                else
                    if not self:primaryPathIsValid() or self:primaryPathIsValid() and self:CanDoNewPath( data.bestPos ) then
                        self:SetupPath2( data.bestPos )
                    end
                    local result = self:ControlPath2( not self.IsSeeEnemy )
                    if result == true or SqrDistLessThan( myPos:DistToSqr( data.bestPos ), 75 ) then
                        local tolerance = self:campingTolerance()
                        --debugoverlay.Text( data.bestPos, tolerance .. " " .. nookScore, 240 )
                        self:TaskComplete( "movement_perch" )
                        self:StartTask2( "movement_camp", { maxNoSeeing = tolerance }, "i got to my camping spot" )

                    elseif result == false then
                        self:TaskComplete( "movement_perch" )
                        self:StartTask2( "movement_biginertia", nil, "i couldnt get there" )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "movement_perch" )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() and not SqrDistLessThan( self:GetPos():DistToSqr( self:GetPath():GetEnd() ), 600 )
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["inform_handler"] = {
            OnStart = function( self, data )
                data.Inform = function( enemy, pos, senderPos )
                    for _, ent in ipairs( ents.FindByClass( self:GetClass() ) ) do
                        if ent == self or SqrDistGreaterThan( self:GetPos():DistToSqr( ent:GetPos() ), self.InformRadius ) then continue end

                        ent:RunTask( "InformReceive", enemy, pos, senderPos )
                    end
                end
            end,
            BehaveUpdate = function( self, data, interval )

                if IsValid( self:GetEnemy() ) and self.IsSeeEnemy and ( !data.EnemyPosInform or _CurTime() >= data.EnemyPosInform ) then
                    data.EnemyPosInform = _CurTime() +  math.Rand( 3, 5 )
                    data.Inform( self:GetEnemy(), self:EntShootPos( self:GetEnemy() ), self:GetPos() )
                end
            end,
            InformReceive = function( self, data, enemy, pos, senderpos )
                if not senderpos or not IsValid( enemy ) then return end

                -- it made another terminator mad! it makes me mad!
                self:MakeFeud( enemy )

                if IsValid( self:GetEnemy() ) and self.IsSeeEnemy then return end

                local enemVel = enemy:GetVelocity()
                local velLeng = enemVel:LengthSqr()

                self.EnemyLastPos = pos

                self.lastInterceptTime          = _CurTime()
                self.lastInterceptPos           = pos

                self:RegisterForcedEnemyCheckPos( enemy )

                -- they arent moving, just go the opposite side of them!
                if velLeng < 5^2 then
                    local enemDir = -terminator_Extras.dirToPos( enemy:GetPos(), senderpos )
                    self.lastInterceptDir = enemDir

                -- they moving fast in one direction!
                elseif velLeng > 50^2 then
                    local enemVelFlat = enemVel * Vector( 1, 1, 0 )
                    self.lastInterceptDir = ( enemVelFlat ):GetNormalized()

                -- they are moving a bit, go left or right
                else
                    local enemDir = terminator_Extras.dirToPos( self:GetPos(), enemy:GetPos() )
                    local upOrDown = { 1, -1 }
                    self.lastInterceptDir = enemDir:Cross( Vector( 0, 0, table.Random( upOrDown ) ) )

                end
            end,
            OnKilled = function( self, data, dmg )
            end,
        },
        ["playercontrol_handler"] = {
            StopControlByPlayer = function( self, data, ply )
                self:StartTask2( "enemy_handler", nil, "begin" )
                self:StartTask2( "movement_wait", nil, "begin" )
                self:StartTask2( "shooting_handler", nil, "begin" )
            end,
        },
    }
end

function ENT:SetupTasks()
    BaseClass.SetupTasks( self )

    self:StartTask( "enemy_handler" )
    self:StartTask( "shooting_handler" )
    self:StartTask( "playercontrol_handler" )
    self:StartTask( "awareness_handler" )
    self:StartTask( "reallystuck_handler" )
    self:StartTask( "inform_handler" )

end