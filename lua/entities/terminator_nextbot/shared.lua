AddCSLuaFile()

ENT.Base = "terminator_nextbot_base"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"
ENT.Author = "StrawWagen"

list.Set( "NPC", "terminator_nextbot", {
    Name = "Terminator Overcharged",
    Class = "terminator_nextbot",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },
} )

include( "sharedextras.lua" )

-- these need to be shared
include( "compatibilityhacks.lua" )

ENT.isTerminatorHunterBased = true -- used to see if ent is an actual terminator

if CLIENT then
    language.Add( "terminator_nextbot", ENT.PrintName )

    function ENT:AdditionalClientInitialize() end

    function ENT:Initialize()
        BaseClass.Initialize( self )
        self:AdditionalClientInitialize()

    end

    include( "cl_ragdolldeaths.lua" )

    return

elseif SERVER then
    include( "behaviouroverrides.lua" )
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
    include( "damageandhealth.lua" )
    -- glee thing
    include( "overcharging.lua" )
    -- sounds, used by supercop
    include( "spokenlines.lua" )

    AddCSLuaFile( "cl_ragdolldeaths.lua" )

end

local LineOfSightMask = MASK_BLOCKLOS
terminator_Extras.LineOfSightMask = LineOfSightMask

-- dont try to bash locked doors that have timed out
-- this is wiped whenever any bot's fists hit a locked door
terminator_Extras.lockedDoorAttempts = terminator_Extras.lockedDoorAttempts or {}

local extremeUnstucking = CreateConVar( "termhunter_doextremeunstucking", 1, FCVAR_ARCHIVE, "Teleport terminators medium distances if they get really stuck?", 0, 1 )

local debugPrintTasks = CreateConVar( "term_debugtasks", 0, FCVAR_NONE, "Debug terminator tasks? Also enables a task history dump on bot +use." )

local vec_zero = Vector( 0 )
local vectorUp = Vector( 0, 0, 1 )
local vecFiftyZ = Vector( 0, 0, 50 )
local negativeFiveHundredZ = Vector( 0,0,-500 )
local plus25Z = Vector( 0,0,25 )
local plus15Z = Vector( 0,0,15 )

local vecMeta = FindMetaTable( "Vector" )
local entMeta = FindMetaTable( "Entity" )
local strMeta = FindMetaTable( "String" )
local wepMeta = FindMetaTable( "Weapon" )

local math = math -- math is math!

local distToSqr = vecMeta.DistToSqr
local CurTime = CurTime
local IsValid = IsValid
local table_insert = table.insert
local table_Random = table.Random

--utility functions begin

local function hasReasonableHealth( ent )
    local entsHp = entMeta.Health( ent )
    return entsHp > 0 and entsHp < 300

end

function ENT:campingTolerance()
    local myPos = self:GetPos()
    -- lower is better
    local nookScore = terminator_Extras.GetNookScore( myPos + plus25Z, 6000 )
    local tolerance
    if nookScore < 3 then-- 3 score is a really good spot
        tolerance = 5000 / nookScore

    elseif nookScore < 4 then
        tolerance = 3000 / nookScore

    else
        tolerance = 200 / nookScore

    end
    return tolerance

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

function ENT:getBestPos( ent )
    if not IsValid( ent ) then return nil end
    local shootPos = self:GetShootPos()
    local obj = ent:GetPhysicsObject()
    local pos = ent:GetPos()
    if IsValid( obj ) and not obj:IsMotionEnabled() then
        pos = ent:NearestPoint( shootPos )
        -- put the nearest point a bit inside the entity
        pos = ent:WorldToLocal( pos )
        pos = pos * 0.6
        pos = ent:LocalToWorld( pos )

    elseif IsValid( obj ) then
        local center = obj:GetMassCenter()
        if center ~= vec_zero then
            pos = ent:LocalToWorld( center )

        end
    end


    --debugoverlay.Cross( pos, 5, 5 )

    if pos and ent:GetClass() ~= "func_breakable_surf" and terminator_Extras.PosCanSee( shootPos, pos ) then
        return pos

    end

    return pos

end

local function getUsefulPositions( area )
    local out = {}
    local center = area:GetCenter()
    table.Add( out, area:GetHidingSpots( 8 ) )

    if #out >= 1 then
        return out

    end

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

local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local function yieldIfWeCan( reason )
    if not coroutine_running() then return end
    coroutine_yield( reason )

end
-- util funcs end

-- detect small areas that don't have incoming connections! stops huuuuge lagspikes on big maps
function ENT:AreaIsOrphan( potentialOrphan, ignoreMyNav )

    local myNav = self:GetTrueCurrentNavArea() or self:GetCurrentNavArea()

    if not IsValid( myNav ) then return nil, nil end

    if potentialOrphan == myNav and not ignoreMyNav then return nil, nil end

    local loopedBackAreas = { myNav = true }
    for _, area in ipairs( myNav:GetIncomingConnections() ) do
        loopedBackAreas[area] = true

    end

    local checkedSurfaceArea = 0
    local unConnectedAreasSequential = {}
    local unConnectedAreas = {}
    local connectedAreasSequential = {}
    local scoreData = {}
    scoreData.decreasingScores = {}
    scoreData.encounteredABlockedArea = nil
    scoreData.encounteredALadder = nil
    scoreData.botsJumpHeight = self.loco:GetMaxJumpHeight()
    scoreData.loopedBackAreas = loopedBackAreas

    --debugoverlay.Cross( myNav:GetCenter(), 10, 10, Color( 255, 255, 0 ), true )

    local scoreFunction = function( scoreData, area1, area2 )
        if area2:IsBlocked() then scoreData.encounteredABlockedArea = true return 0 end

        local nextAreaId = area2:GetID()
        local currAreaId = area1:GetID()
        local score = scoreData.decreasingScores[currAreaId] or 10000

        checkedSurfaceArea = area2:GetSizeX() * area2:GetSizeY()

        -- area has shit connection or we left from an area with shit connection
        if not area2:IsConnected( area1 ) or unConnectedAreas[currAreaId] or area1:ComputeAdjacentConnectionHeightChange( area2 ) > scoreData.botsJumpHeight then
            unConnectedAreas[nextAreaId] = true
            score = -1
            table.insert( unConnectedAreasSequential, nextAreaId )
            --debugoverlay.Text( area2:GetCenter(), "unConnected", 8 )

        -- good connection
        else
            -- just return early if we're in the same group
            if not ignoreMyNav and scoreData.loopedBackAreas[ area2 ] then
                scoreData.sameGroupAsUs = true
                --print( "SAMEGROUP" )
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

    -- who cares if it's an orphan, we can get there
    if scoreData.sameGroupAsUs then return nil, scoreData.encounteredABlockedArea end

    local escapable = escaped

    local lessNoWaysBackThanWaysBack = ( #unConnectedAreasSequential <= #connectedAreasSequential )
    local isSubstantiallySized = checkedSurfaceArea > ( checkRadius^2 ) * 0.15
    local isPotentiallyPartOfWhole = lessNoWaysBackThanWaysBack and isSubstantiallySized

    --print( "orphanstatus", escapable, scoreData.sameGroupAsUs, isPotentiallyPartOfWhole, isSubstantiallySized )

    -- could not confirm that it's an orphan
    if escapable or isPotentiallyPartOfWhole then return nil, scoreData.encounteredABlockedArea end

    -- is an orphan
    return true, scoreData.encounteredABlockedArea

end

local function resetBoxedIn( self )
    timer.Simple( 0.25, function()
        if not IsValid( self ) then return end
        self.term_CachedIsBoxedIn = nil

    end )
end

function ENT:EnemyIsBoxedIn()
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then return end

    local cachedBoxedIn = self.term_CachedIsBoxedIn
    if cachedBoxedIn ~= nil then return cachedBoxedIn end

    local enemysNavArea = terminator_Extras.getNearestPosOnNav( enemy:GetPos() ).area
    if not IsValid( enemysNavArea ) then
        resetBoxedIn( self )
        self.term_CachedIsBoxedIn = false
        return false

    end
    local stepH = self.loco:GetStepHeight()

    local dangerAreas = {}
    local allies = self:GetNearbyAllies()
    table.insert( allies, self )

    for _, ally in ipairs( allies ) do
        if not IsValid( ally ) then continue end
        table.Add( dangerAreas, navmesh.Find( ally:GetPos(), 350, stepH, stepH ) )

    end

    local areasThatAreEntrance = {}
    for _, entranceArea in ipairs( dangerAreas ) do
        areasThatAreEntrance[ entranceArea ] = true

    end
    -- not boxed in, we're just close
    if areasThatAreEntrance[ entranceArea ] then
        resetBoxedIn( self )
        return false

    end

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

        if areasThatAreEntrance[ area2 ] then
            return 0

        end
        scoreData.decreasingScores[area2Id] = score + -1

        --debugoverlay.Text( area2:GetCenter() + Vector( 0,0,10 ), tostring( score ), 8 )

        return score

    end

    local checkRadius = 1350
    local _, _, escaped = self:findValidNavResult( scoreData, enemy:GetPos(), checkRadius, scoreFunction, 10 )

    local boxedIn = not escaped and not scoreData.hasEscape

    self.term_CachedIsBoxedIn = boxedIn
    resetBoxedIn( self )
    return boxedIn

end

local MEMORY_MEMORIZING = 1
local MEMORY_INERT = 2
local MEMORY_BREAKABLE = 4
local MEMORY_VOLATILE = 8
--local MEMORY_THREAT = 16
local MEMORY_WEAPONIZEDNPC = 32
local MEMORY_DAMAGING = 64

function ENT:ignoreEnt( ent, time )
    ent.terminatorIgnoreEnt = true

    if not time then return end
    timer.Simple( time, function()
        if not IsValid( self ) then return end
        self:unIgnoreEnt( ent )

    end )
end
function ENT:unIgnoreEnt( ent )
    if not IsValid( ent ) then return end
    ent.terminatorIgnoreEnt = nil

end

do
    local IsValidAwareness = IsValid
    local isstring = isstring
    local isentity = isentity
    local isfunction = isfunction
    local table = table
    local table_insertAware = table_insert
    local string_find = string.find

    -- i love overoptimisation
    local notInterestingCache = {}
    hook.Add( "terminator_nextbot_oneterm_exists", "setup_notinterestingcache", function()
        timer.Create( "term_cache_isnotinteresting", 10, 0, function()
            notInterestingCache = {}

        end )
    end )
    hook.Add( "terminator_nextbot_noterms_exist", "teardown_notinterestingcache", function()
        timer.Remove( "term_cache_isnotinteresting" )
        notInterestingCache = {}

    end )

    local function boring( ent )
        if not ent then return end
        notInterestingCache[ent] = true

    end

    function ENT:caresAbout( ent )
        if notInterestingCache[ent] then return end
        if not IsValidAwareness( ent ) then boring( ent ) return end
        if ent == self then return end
        if not IsValidAwareness( entMeta.GetPhysicsObject( ent ) ) then boring( ent ) return end
        if not entMeta.IsSolid( ent ) then return end
        if entMeta.IsFlagSet( ent, FL_WORLDBRUSH ) then boring( ent ) return end
        if entMeta.IsFlagSet( ent, FL_STATICPROP ) then boring( ent ) return end
        return true

    end

    function ENT:getAwarenessKey( ent )
        if notInterestingCache[ent] then return end
        if not IsValidAwareness( ent ) then boring( ent ) return end
        local model = entMeta.GetModel( ent )
        local class = entMeta.GetClass( ent )
        if not isstring( class ) or not isstring( model ) then boring( ent ) return end
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

    function ENT:getMemoryOfObject( myTbl, ent )
        if not ent then ErrorNoHaltWithStack() end
        local key = myTbl.getAwarenessKey( self, ent )
        local memory = nil
        local overrideResponse = ent.terminatorHunterInnateReaction
        if overrideResponse and isfunction( overrideResponse ) then
            memory = overrideResponse( ent, self )
        else
            memory = myTbl.awarenessMemory[key]
        end
        return memory, key

    end

    function ENT:memorizedAsBreakable( myTbl, ent )
        local memory, _ = myTbl.getMemoryOfObject( self, myTbl, ent )

        if isnumber( memory ) and memory == MEMORY_BREAKABLE then
            return true

        end
    end

    function ENT:understandObject( myTbl, ent )
        if notInterestingCache[ent] then return end
        if not IsValidAwareness( ent ) then boring( ent ) return end

        local entsTbl = ent:GetTable()
        local class = entMeta.GetClass( ent )

        -- locked doors create navmesh blocker flags under them even though we can bash them down
        -- KILL ALL LOCKED DOORS!
        local isLockedDoor = class == "prop_door_rotating" and entMeta.GetInternalVariable( ent, "m_bLocked" ) ~= false and entMeta.IsSolid( ent ) and terminator_Extras.CanBashDoor( ent )
        if isLockedDoor then
            table_insertAware( myTbl.awarenessLockedDoors, ent )
            table_insertAware( myTbl.awarenessBash, ent )

        end

        if entsTbl.terminatorIgnoreEnt then return end

        local memory, _ = myTbl.getMemoryOfObject( self, myTbl, ent )

        if isnumber( memory ) then
            if memory == MEMORY_MEMORIZING then
                table_insertAware( myTbl.awarenessUnknown, ent )

            elseif memory == MEMORY_INERT then
                return
                -- do nothing, it's inert

            elseif memory == MEMORY_BREAKABLE then -- entities that we can shoot if they're blocking us
                table_insertAware( myTbl.awarenessBash, ent )

            elseif memory == MEMORY_VOLATILE or memory == MEMORY_DAMAGING then -- stay away, it hurt us before!
                table_insertAware( myTbl.awarenessDamaging, ent )

                if memory == MEMORY_VOLATILE then -- entities that we can shoot to damage enemies
                    table_insertAware( myTbl.awarenessVolatiles, ent )

                end
            elseif memory == MEMORY_WEAPONIZEDNPC and ( ent:IsNPC() or ent:IsNextBot() ) then
                myTbl.MakeFeud( self, ent )

            end
        else
            if class == "player" then return end

            local mdl = entMeta.GetModel( ent )
            local isFunc = strMeta.StartWith( class, "func_" )
            local isDynamic = strMeta.StartWith( class, "prop_dynamic" )
            local isWoodBoard = mdl and string_find( mdl, "wood_board" )
            local isVentGuard = mdl and string_find( mdl, "/vent" )
            local isExplosiveBarrel = mdl and string_find( mdl, "oildrum001_explosive" )
            local isSlam = class and ( class == "npc_satchel" or class == "npc_tripmine" )
            if isFunc then
                local isFuncBreakable = strMeta.StartWith( class, "func_breakable" )
                if isFuncBreakable and hasReasonableHealth( ent ) then
                    myTbl.memorizeEntAs( self, ent, MEMORY_BREAKABLE )

                else
                    myTbl.memorizeEntAs( self, ent, MEMORY_INERT )

                end
            elseif ent.huntersglee_breakablenails then
                table_insertAware( myTbl.awarenessBash, ent )

            elseif isDynamic or class == "base_entity" then
                myTbl.memorizeEntAs( self, ent, MEMORY_INERT )

            elseif isWoodBoard or isVentGuard then
                myTbl.memorizeEntAs( self, ent, MEMORY_BREAKABLE )

            elseif isExplosiveBarrel or isSlam then
                myTbl.memorizeEntAs( self, ent, MEMORY_VOLATILE )

            else
                if entsTbl.isTerminatorHunterChummy == myTbl.isTerminatorHunterChummy then
                    myTbl.memorizeEntAs( self, ent, MEMORY_INERT )

                else
                    myTbl.memorizeEntAs( self, ent, MEMORY_MEMORIZING ) -- need to beat this up
                    table_insertAware( myTbl.awarenessUnknown, ent )

                end
            end
        end
    end

    function ENT:AdditionalUnderstand( _substantialStuff ) -- stub
    end

    function ENT:understandSurroundings( myTbl )
        myTbl = myTbl or entMeta.GetTable( self )
        myTbl.awarenessSubstantialStuff = {}
        myTbl.awarenessUnknown = {}
        myTbl.awarenessBash = {}
        myTbl.awarenessDamaging = {}
        myTbl.awarenessVolatiles = {}
        myTbl.awarenessLockedDoors = {}
        coroutine_yield()

        local add = 2
        if myTbl.IsFodder then
            add = math.Rand( 8, 12 )

        end
        myTbl.term_NextAwareness = CurTime() + add

        local pos = entMeta.GetPos( self )
        local rawSurroundings = ents.FindInSphere( pos, myTbl.AwarenessCheckRange )

        local enemy = myTbl.GetEnemy( self )
        if IsValidAwareness( enemy ) and not myTbl.IsFodder and myTbl.IsSeeEnemy and myTbl.DistToEnemy > 1250 then
            local enemSurroundings = ents.FindInSphere( entMeta.GetPos( enemy ), 400 ) -- shoot explosive barrels next to enemies!
            table.Add( rawSurroundings, enemSurroundings )

        end

        local surroundings = {}
        for _, ent in ipairs( rawSurroundings ) do
            if not notInterestingCache[ent] then
                table.insert( surroundings, ent )

            end
        end


        coroutine_yield()

        local centers = {}

        for _, ent in ipairs( surroundings ) do
            if not IsValidAwareness( ent ) then continue end
            centers[ent] = entMeta.WorldSpaceCenter( ent )

        end

        table.sort( surroundings, function( a, b ) -- sort ents by distance to me
            if not IsValidAwareness( a ) then return false end
            if not IsValidAwareness( b ) then return true end
            local ADist = distToSqr( centers[a], pos )
            local BDist = distToSqr( centers[b], pos )
            return ADist < BDist

        end )

        coroutine_yield()

        local added = 0
        local substantialStuff = {}
        local caresAbout = myTbl.caresAbout
        for _, currEnt in ipairs( surroundings ) do
            if ( added % 40 ) == 0 then coroutine_yield() end
            if added > 400 then -- cap this!
                break

            end
            if caresAbout( self, currEnt ) then
                added = added + 1
                table_insert( substantialStuff, currEnt )

            end
        end

        coroutine_yield()

        added = 0
        local understandObject = myTbl.understandObject

        for _, currEnt in ipairs( substantialStuff ) do
            if not IsValid( currEnt ) then continue end
            if ( added % 40 ) == 0 then coroutine_yield() end
            added = added + 1
            understandObject( self, currEnt )
            table_insert( myTbl.awarenessSubstantialStuff, currEnt )

        end

        coroutine_yield()

        myTbl.AdditionalUnderstand( self, substantialStuff )

    end
end

function ENT:getShootableVolatile( enemy )
    if not self.awarenessVolatiles then return end
    if not enemy then return end

    for _, currVolatile in ipairs( self.awarenessVolatiles ) do
        if not IsValid( currVolatile ) then continue end

        local pos = self:getBestPos( currVolatile )
        if SqrDistGreaterThan( pos:DistToSqr( enemy:GetPos() ), 300 ) then continue end
        local _, trResult = terminator_Extras.PosCanSeeComplex( self:GetShootPos(), pos, self )

        local hitEnt = trResult.Entity
        if trResult.Hit and ( not IsValid( hitEnt ) or hitEnt ~= currVolatile ) then continue end

        return currVolatile

    end
end

function ENT:GetCachedBashableWithinReasonableRange()
    local nextCache = self.nextBashablesNearbyCache or 0
    local doCache = nextCache < CurTime()

    if doCache or not self.bashableWithinReasonableRange then
        self.nextBashablesNearbyCache = CurTime() + 0.8

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

-- override this to remove path recalculating, we already do that
function ENT:ControlPath( lookatgoal, myTbl )
    myTbl = myTbl or self:GetTable()
    if not myTbl.PathIsValid( self ) then return false end

    local pos = myTbl.GetPathPos( self )

    local range = self:GetRangeTo( pos )

    if range < myTbl.PathGoalToleranceFinal then
        myTbl.InvalidatePath( self, "i reached the end of my path!" )
        return true

    end

    -- beartrap
    if IsValid( myTbl.terminatorStucker ) then
        return false

    end

    if myTbl.MoveAlongPath( self, lookatgoal, myTbl ) then
        return true

    end
end

function ENT:GetDisrespectingEnt( myTbl )
    local myShootPos = myTbl.GetShootPos( self )
    local myPos = entMeta.GetPos( self )
    local disrespector = nil
    local disrespectorRange = 75
    local notClose = 0

    for _, potentialDisrespect in ipairs( myTbl.awarenessSubstantialStuff ) do
        if IsValid( potentialDisrespect ) and not potentialDisrespect:IsWeapon() then
            if hook.Run( "terminator_blocktarget", self, potentialDisrespect ) == true then continue end -- fix supercop attacking specdm players on cfcttt
            if entMeta.IsFlagSet( self, FL_NOTARGET ) then continue end

            local disrespectBestPos = entMeta.NearestPoint( self, myShootPos )
            local close = SqrDistLessThan( vecMeta.DistToSqr( disrespectBestPos, myShootPos ), disrespectorRange )
            close = close or SqrDistLessThan( vecMeta.DistToSqr( disrespectBestPos, myPos ), disrespectorRange )

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

function ENT:GetCachedDisrespector( myTbl )
    myTbl = myTbl or self:GetTable()
    local cur = CurTime()
    local nextDisrespectorCache = myTbl.terminator_NextDisrespectorCache or 0
    if nextDisrespectorCache < cur then
        local add
        if myTbl.IsFodder then
            add = 0.75
        else
            add = 0.1
        end
        myTbl.terminator_NextDisrespectorCache = cur + add
        myTbl.terminator_CachedDisrespectingEnt = myTbl.GetDisrespectingEnt( self, myTbl )

    end

    return myTbl.terminator_CachedDisrespectingEnt

end

do
    -- interacting with shootblocker START

    local nextbotMeta = FindMetaTable( "NextBot" )
    local hullminFists = Vector( -20, -20, -30 )
    local hullmaxFists = Vector( 20, 20, 30 )

    local hullminOtherwise = Vector( -5, -5, -5 )
    local hullmaxOtherwise = Vector( 5, 5, 5 )

    local function hullmin( ref, refTbl )
        if refTbl.IsFists and refTbl.IsFists( ref ) then
            return hullminFists

        end
        return hullminOtherwise

    end


    local function hullmax( ref, refTbl )
        if refTbl.IsFists and refTbl.IsFists( ref ) then
            return hullmaxFists

        end
        return hullmaxOtherwise

    end

    function ENT:ShootBlockerWorld( myTbl, start, pos, filter )

        local nextWorldBlockerCheck = myTbl.nextWorldBlockerCheck or 0
        local readyForCheck = not myTbl.oldWorldBlocker or nextWorldBlockerCheck < CurTime()

        if not readyForCheck then return myTbl.oldWorldBlocker end

        local traceStruc = {
            start = start,
            endpos = pos,
            filter = filter,
            mask = bit.bor( MASK_SOLID_BRUSHONLY ),
            mins = hullmin( self, myTbl ),
            maxs = hullmax( self, myTbl ),
        }
        local tr = util.TraceHull( traceStruc )

        if tr.Hit then
            myTbl.nextWorldBlockerCheck = CurTime() + 0.1
        else
            myTbl.nextWorldBlockerCheck = CurTime() + 0.5
        end

        myTbl.oldWorldBlocker = tr

        return tr
    end

    function ENT:ShootBlocker( myTbl, start, pos, filter )
        local traceStruc = {
            start = start,
            endpos = pos,
            filter = filter,
            mask = nextbotMeta.GetSolidMask( self ),
        }
        local tr = util.TraceLine( traceStruc )
        if tr.Hit and not tr.HitWorld then return tr.Entity, tr end

        traceStruc = {
            start = start,
            endpos = pos,
            filter = filter,
            mask = nextbotMeta.GetSolidMask( self ),
            mins = hullmin( self, myTbl ),
            maxs = hullmax( self, myTbl ),
        }
        tr = util.TraceHull( traceStruc )

        return tr.Entity, tr

    end
end

function ENT:markAsTermUsed( ent )
    ent.usedByTerm = true
    local time = CurTime()
    ent.usedByTermTime = time
    timer.Simple( 15, function()
        if not IsValid( ent ) then return end
        if ent.usedByTermTime ~= time then return end
        ent.usedByTerm = nil

    end )
end

-- handle double doors
local function handleDoubleDoors( ent, user )
    local ourName = ent:GetName()
    local parentDoor = ent

    local keys = parentDoor:GetKeyValues()
    local doubleDoorName = keys["slavename"]
    if not doubleDoorName or doubleDoorName == "" then
        if not ourName or ourName == "" then return end
        local doors = ents.FindByClass( "prop_door_rotating" )
        for _, currDoor in ipairs( doors ) do
            local potientalParentKeys = currDoor:GetKeyValues()
            doubleDoorName = potientalParentKeys["slavename"]

            if doubleDoorName == ourName then
                user:markAsTermUsed( currDoor )
                return

            end
        end
    end

    local doubleDoors = ents.FindByName( doubleDoorName )
    for _, doubleDoor in ipairs( doubleDoors ) do
        if not IsValid( doubleDoor ) then continue end
        user:markAsTermUsed( doubleDoor )

    end
end

do
    local useClassBlacklist = {}
    local blacklistCount = {}
    local stopBlaming = 0
    local lastTermUseClass

    hook.Add( "OnLuaError", "term_blameuseerrors", function()
        if stopBlaming < CurTime() then return end

        local old = blacklistCount[lastTermUseClass] or 0
        if old > 10 then -- nah not our fault
            useClassBlacklist[lastTermUseClass] = nil

        end

        useClassBlacklist[lastTermUseClass] = true
        blacklistCount[lastTermUseClass] = old + 1

        if old >= 1 then return end
        print( "TERM potentially caught error when using " .. lastTermUseClass .. "\nadding to session use blacklist..." )

    end )

    function ENT:Use2( toUse )
        if not self.CanUseStuff then return end

        -- vehicles dont expect us to use em
        if toUse.GetDriver then return end

        local class = toUse:GetClass()
        if useClassBlacklist[class] then return end

        self:markAsTermUsed( toUse )
        if class == "prop_door_rotating" then
            handleDoubleDoors( toUse, self )

        end

        stopBlaming = CurTime() + 0.025
        lastTermUseClass = class

        hook.Run( "TerminatorUse", self, toUse )
        local successful = ProtectedCall( function() toUse:Use( self, self, USE_ON ) end )

        if not successful then
            print( "TERM caught error when using " .. class .. "\nadding to session use blacklist..." )
            useClassBlacklist[class] = true
            return

        end

        local nextUseSound = self.nextUseSound or 0
        if nextUseSound < CurTime() and not self:IsSilentStepping() then
            self.nextUseSound = CurTime() + math.Rand( 0.05, 0.1 )
            self:EmitSound( "common/wpn_select.wav", 65, math.random( 95, 105 ) )

            if not toUse.GetPhysicsObject then return end
            local obj = toUse:GetPhysicsObject()
            if not obj or not obj.IsValid or not obj:IsValid() then return end
            if self:GetRangeTo( toUse:GetPos() ) > 100 then return end

            obj:ApplyForceCenter( VectorRand() * 1000 )

        end
    end
end

function ENT:tryToOpen( myTbl, blocker, blockerTrace )
    if not IsValid( blocker ) then return end
    local blockerTbl = blocker:GetTable()

    local OpenTime = myTbl.OpenDoorTime or 0
    if blocker and blocker ~= myTbl.oldBlockerITriedToOpen then
        myTbl.oldBlockerITriedToOpen = blocker
        myTbl.startedTryingToOpen = CurTime()

    end

    local class = blocker:GetClass()
    local startedTryingToOpen = myTbl.startedTryingToOpen or 0
    local sinceStarted = CurTime() - startedTryingToOpen

    if blockerTbl.isTerminatorHunterChummy == myTbl.isTerminatorHunterChummy then
        if ( myTbl.GetCurrentSpeed( self ) <= 5 or blockerTbl.GetCurrentSpeed( blocker ) <= 5 ) then
            blockerTbl.RunTask( blocker, "OnBlockingAlly", self, sinceStarted )
            myTbl.RunTask( self, "OnBlockedByAlly", blocker, sinceStarted )

        end
        return
    end

    local doorTimeIsGood = CurTime() - OpenTime > 2
    local doorIsStale = sinceStarted > 2
    local doorIsVeryStale = sinceStarted > 8


    local memory, _ = myTbl.getMemoryOfObject( self, myTbl, blocker )
    local breakableMemory = memory == MEMORY_BREAKABLE

    if myTbl.IsStupid then
        local attack
        if myTbl.IsReallyAngry( self ) then
            attack = true

        elseif sinceStarted > 0.75 and math.random( 0, 100 ) < 40 then
            attack = true

        elseif sinceStarted > 0.5 and math.random( 0, 100 ) < 10 then
            attack = true

        elseif doorIsStale then
            attack = true

        elseif math.random( 0, 100 ) < 15 then
            attack = true

        end
        if attack then
            myTbl.WeaponPrimaryAttack( self )

        end
        return

    end

    local blockerHp = blocker:Health()
    local isFists = myTbl.IsFists( self, myTbl )
    local angry = myTbl.IsAngry( self )
    local reallyAngry = myTbl.IsReallyAngry( self )

    -- i hate the floppy things on the parking garage map
    local theFloppyThingsAndBash = class == "prop_ragdoll" and isFists
    local shouldAttack = string.find( class, "breakable" ) or theFloppyThingsAndBash or ( string.find( class, "prop_" ) and blockerHp > 0 and blockerHp < 100 )

    local range = myTbl.GetWeaponRange( self, myTbl )
    local traceDistanceSqr = blockerTrace.StartPos:DistToSqr( blockerTrace.HitPos )
    local blockerAtGoodRange = range and traceDistanceSqr < range^2

    local directlyInMyWay, blockersBearingToPath = myTbl.EntIsInMyWay( self, blocker, 140 )

    local attack
    local use

    if blockerTbl.huntersglee_breakablenails then
        myTbl.GetTheBestWeapon( self )
        myTbl.ReallyAnger( self, 5 )
        myTbl.beatUpEnt( self, myTbl, blocker, true )
        myTbl.overrideStuckBeatupEnt = blocker

    elseif class == "prop_door_rotating" and doorTimeIsGood then
        local doorState = blocker:GetInternalVariable( "m_eDoorState" )
        if blocker:GetInternalVariable( "m_bLocked" ) == true and isFists and blockerAtGoodRange then
            attack = true

        elseif ( angry and doorIsStale and isFists and terminator_Extras.CanBashDoor( blocker ) and blockerAtGoodRange ) or ( reallyAngry and doorIsVeryStale and isFists ) then
            attack = true

        elseif doorState ~= 2 then -- door is not open
            myTbl.OpenDoorTime = CurTime()
            use = true

        -- door is open but it opened in a way that blocked me 
        elseif doorState == 2 and blockerAtGoodRange and directlyInMyWay then
            if doorIsStale then
                if isFists then
                    attack = true

                elseif myTbl.HasFists then
                    myTbl.DoFists( self )

                end
            elseif CurTime() - OpenTime > 1 then
                use = true

            end
        end
    elseif shouldAttack or breakableMemory then
        if breakableMemory and blockerAtGoodRange and myTbl.GetCachedDisrespector( self, myTbl ) and hasReasonableHealth( blocker ) and not myTbl.IsSeeEnemy then
            attack = true

        elseif reallyAngry or ( blockersBearingToPath and blockersBearingToPath > 120 ) then
            if range and blockerAtGoodRange then
                attack = true

            elseif not isFists then
                attack = true

            end
        end
    elseif ( class == "func_door_rotating" or class == "func_door" ) and blocker:GetInternalVariable( "m_toggle_state" ) == 1 and doorTimeIsGood then
        myTbl.OpenDoorTime = CurTime()
        use = true

    elseif doorTimeIsGood and not myTbl.ShouldBeEnemy( self, blocker, nil, myTbl, blockerTbl ) then
        myTbl.OpenDoorTime = CurTime()

    -- generic, kill the blocker
    elseif reallyAngry and myTbl.caresAbout( self, blocker ) and not blocker:IsNextBot() and not blocker:IsPlayer() then
        local isFunc = class:StartWith( "func_" )
        local isDynamic = class:StartWith( "prop_dynamic" )
        local interactable = not ( isFunc or isDynamic )
        if interactable and directlyInMyWay and blockerAtGoodRange then
            attack = true

        elseif interactable and myTbl.GetCurrentSpeed( self ) < 25 then
            attack = true

        end
    end
    if string.find( class, "door" ) and reallyAngry then
        if isFists then
            attack = true
            myTbl.ReallyAnger( self, 10 )

        elseif myTbl.HasFists then
            myTbl.DoFists( self )

        end
    end
    if attack then
        myTbl.WeaponPrimaryAttack( self )

    end
    if use then
        myTbl.Use2( self, blocker )

    end
end

function ENT:BehaviourThink( myTbl )
    myTbl.LastShootBlocker = false
    if myTbl.IsControlledByPlayer( self ) then return end
    if myTbl.DisableBehaviour( self, myTbl ) then return end

    local filter = self:GetChildren()
    filter[#filter + 1] = self

    yieldIfWeCan()
    local pos = myTbl.GetShootPos( self )
    local aimVec = myTbl.GetAimVector( self, myTbl )
    local endpos1 = pos + aimVec * 150
    local blocker, blockerTrace = myTbl.ShootBlocker( self, myTbl, pos, endpos1, filter )
    local worldBlocker
    if not myTbl.IsFodder then
        local endpos2 = pos + aimVec * 100
        worldBlocker = myTbl.ShootBlockerWorld( self, myTbl, pos, endpos2, filter ) or {}

    end

    if IsValid( blocker ) and not blocker:IsWorld() then
        yieldIfWeCan()
        myTbl.tryToOpen( self, myTbl, blocker, blockerTrace )

    end

    myTbl.LastShootBlocker = blocker

    local blocks = { blockerTrace, worldBlocker }
    -- slow down bot when it has stuff in front of it
    for _, blocked in ipairs( blocks ) do
        if blocked and blocked.Hit and blocked.Fraction < 0.25 then
            local fractionAsTime = math.abs( blocked.Fraction - 1 )
            local time = math.Clamp( fractionAsTime, 0.2, 1 ) * 0.6
            local finalTime = CurTime() + time
            local oldTime = myTbl.nearObstacleBlockRunning or 0
            if oldTime < finalTime then
                myTbl.nearObstacleBlockRunning = finalTime
            end
            break
        end
    end
end

function ENT:nextNewPathIsGood()
    local nextNewPath = self.nextNewPath or 0
    if nextNewPath > CurTime() then return end
    if self.terminator_HandlingLadder then self:TermHandleLadder() return end
    if self.isHoppingOffLadder then
        self.isHoppingOffLadderCount = ( self.isHoppingOffLadderCount or 0 ) + 1
        if self.isHoppingOffLadderCount > 20 then
            self.isHoppingOffLadder = false
            self.isHoppingOffLadderCount = nil

        end
        return

    end

    return true
end

function ENT:YieldUntilNextNewPath()
    while not self:nextNewPathIsGood() do
        yieldIfWeCan( "wait" )

    end
end

function ENT:CanDoNewPath( pathTarget )
    if not isvector( pathTarget ) then return false end
    if not self:nextNewPathIsGood() then return false end
    if self.isUnstucking and self:PathIsValid() then return false end -- dont rebuild the path if we're handling an unstuck
    if self:primaryPathIsValid() and self.terminator_HandlingLadder then self:TermHandleLadder() return false end
    local NewPathDist = 1
    local mul = 1
    if self.term_ExpensivePath then
        mul = 5

    end
    local Dist = self:MyPathLength() or 0
    local pathPos = self.PathEndPos or vec_zero

    if Dist > 10000 then
        NewPathDist = 3000 -- dont do pathing as often if the target is far away from me!
    elseif Dist > 5000 then
        NewPathDist = 1500
    elseif Dist > 500 then
        NewPathDist = 300
    elseif Dist > 100 then
        NewPathDist = 50
    end

    NewPathDist = NewPathDist * mul

    local needsNew = SqrDistGreaterThan( pathTarget:DistToSqr( pathPos ), NewPathDist ) or self.needsPathRecalculate
    self.needsPathRecalculate = nil
    return needsNew

end

-- this is a stupid hack
-- fixes bot firing guns slow in multiplayer, without making bot think faster.
-- eg fixes m9k minigun firing at one tenth its actual fire rate
function ENT:CreateShootingTimer( myTbl )
    local timerName = "terminator_fastshootingthink_" .. self:GetCreationID()
    timer.Create( timerName, 0, 0, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        if myTbl.terminator_FiringIsAllowed ~= true then return end

        myTbl.WeaponPrimaryAttack( self )

        if math.abs( myTbl.terminator_LastFiringIsAllowed - CurTime() ) > 0.25 then -- stops firing
            myTbl.terminator_FiringIsAllowed = nil

        end
    end )
end

-- DONT touch terminator_FiringIsAllowed and terminator_LastFiringIsAllowed
-- use shootAt to set them, anything else is a super hack
-- use blockShoot to make bot just look at the endPos

function ENT:shootAt( endPos, blockShoot, angTolerance )
    if not endPos then return end
    local myTbl = self:GetTable()
    myTbl.terminator_FiringIsAllowed = nil

    local endPosOffsetted = endPos
    local enemy = myTbl.GetEnemy( self )
    local wep = self:GetActiveWeapon()
    local validEnemy

    local dmgTracker = myTbl.Term_GetDamageTrackerOf( self, wep )

    if IsValid( enemy ) then
        validEnemy = true
        if dmgTracker and not dmgTracker.noLeading then
            endPosOffsetted = endPosOffsetted + ( enemy:GetVelocity() * 0.08 )
            endPosOffsetted = endPosOffsetted - ( self:GetVelocity() * 0.08 )

        end
    end
    local attacked = nil
    local out = nil
    local myShoot = myTbl.GetShootPos( self )
    local dir = endPosOffsetted - myShoot

    dir:Normalize()

    myTbl.SetDesiredEyeAngles( self, dir:Angle() )

    angTolerance = angTolerance or 11.25
    if myTbl.IsMeleeWeapon( self ) then
        angTolerance = 60

    elseif dmgTracker and dmgTracker.isBurst then
        angTolerance = 4

    end

    local dot = math.Clamp( myTbl.GetAimVector( self, myTbl ):Dot( dir ), 0, 1 )
    local ang = math.deg( math.acos( dot ) )

    if ang <= angTolerance and not blockShoot then

        if dmgTracker then
            myTbl.TryAndUseWeaponRight( self, wep, dmgTracker )

        end

        local wepRange = myTbl.GetWeaponRange( self, myTbl )

        local filter = self:GetChildren()
        filter[#filter + 1] = self
        filter[#filter + 1] = enemy
        local blockAttack = nil
        -- witness me hack for glee
        if validEnemy and enemy.AttackConfirmed then
            if not blockShoot and enemy:Health() > 0 and myTbl.DistToEnemy < wepRange * 1.25 then
                enemy.AttackConfirmed( enemy, self )

            end
            if not enemy.attackConfirmedBlock then
                attacked = true

            else
                blockAttack = true

            end
        end
        -- wep judging, drops weapons that don't do enough damage/aren't compatible with this npc
        if not attacked and not blockAttack and myTbl.DistToEnemy < wepRange * 1.25 then
            -- think is spammed a bit in singleplayer, don't over-judge
            local nextJudge = myTbl.term_NextJudge or 0
            if validEnemy and nextJudge < CurTime() then
                myTbl.term_NextJudge = CurTime() + 0.08
                myTbl.JudgeWeapon( self, wep )
                myTbl.JudgeEnemy( self, enemy )

            end
            attacked = true

        end
    end

    if attacked then
        myTbl.terminator_LastFiringIsAllowed = CurTime()
        myTbl.terminator_FiringIsAllowed = true -- tell the ShootingTimer that it's shooting time

    end

    if ang < 1 then
        out = true

    end
    return out, attacked

end

function ENT:canHitEnt( myTbl, ent )
    if not IsValid( ent ) then return end
    local myShootPos = self:GetShootPos()
    local objPos = myTbl.getBestPos( self, ent )
    local behindObj = objPos + terminator_Extras.dirToPos( myShootPos, objPos ) * 40

    -- use fist's mask!
    local mask = nil
    local wepsMask = myTbl.IsFists( self ) and myTbl.GetWeapon( self ).HitMask or nil
    if wepsMask then
        mask = wepsMask

    end

    local _, hitTrace = terminator_Extras.PosCanSeeComplex( myShootPos, behindObj, self, mask )
    --debugoverlay.Cross( hitTrace.HitPos, 10, 10 )

    local closenessSqr
    if hitTrace.Entity == ent then
        closenessSqr = myShootPos:DistToSqr( hitTrace.HitPos )

    else
        closenessSqr = myShootPos:DistToSqr( objPos )

    end
    local weapDist = myTbl.GetWeaponRange( self, myTbl ) + -20
    local hitReallyClose = SqrDistLessThan( hitTrace.HitPos:DistToSqr( behindObj ), 30 ) or SqrDistLessThan( hitTrace.HitPos:DistToSqr( objPos ), 30 )
    local visible = ( hitTrace.Entity == ent ) or hitReallyClose

    local canHit = visible and ( weapDist == math.huge or SqrDistLessThan( closenessSqr, weapDist ) )

    return canHit, closenessSqr, objPos, hitTrace.HitPos, visible

end

local crouchingOffset = Vector( 0,0,30 )
local standingOffset = Vector( 0,0,50 )

function ENT:crouchToGetCloserTo( pos )
    local myPos = self:GetPos()
    local distIfCrouch = ( myPos + crouchingOffset ):DistToSqr( pos )
    local distIfStand = ( myPos + standingOffset ):DistToSqr( pos )

    if distIfCrouch < distIfStand then
        self.overrideCrouch = CurTime() + 0.3
        self.forcedShouldWalk = CurTime() + 0.2

    end
end

-- throw away swep, go towards ent, and beat it up
function ENT:beatUpEnt( myTbl, ent, unstucking )
    if not IsValid( ent ) then return end
    myTbl = myTbl or self:GetTable()

    local entsCreationId = ent:GetCreationID()
    local oldCount = terminator_Extras.lockedDoorAttempts[entsCreationId] or 0

    -- stupid hack for when there's extremely busted locked doors
    if oldCount > 45 then
        for _, door in ipairs( myTbl.awarenessLockedDoors ) do
            local doorPos = myTbl.getBestPos( self, door )
            if terminator_Extras.PosCanSee( self:GetShootPos(), doorPos ) then
                ent = door
                myTbl.GotoPosSimple( self, myTbl, nil, doorPos, 10 )
                myTbl.ReallyAnger( self, 10 )
                break

            end
        end
    end

    local valid = true
    local forcePath = nil
    local alwaysValid = nil
    local canHit, closenessSqr, entsRealPos, _, visible = myTbl.canHitEnt( self, myTbl, ent )

    local isNear = SqrDistLessThan( closenessSqr, 500 )
    local quiteNear = SqrDistLessThan( closenessSqr, 150 )
    local isClose = SqrDistLessThan( closenessSqr, 40 )

    local nearAndCanHit = canHit and isNear
    local closeAndCanHit = canHit and isClose
    if quiteNear then
        myTbl.crouchToGetCloserTo( self, entsRealPos )

    end
    --debugoverlay.Cross( entsRealPos, 50, 1, Color( 255, 255, 0 ), true )

    local attacked = nil

    if canHit then
        if closeAndCanHit and not myTbl.IsFists( self ) and myTbl.HasFists then
            myTbl.DoFists( self )

        end
        _, attacked = myTbl.shootAt( self, entsRealPos, nil )
        myTbl.blockAimingAtEnemy = CurTime() + 0.2

    end

    local pathValid = myTbl.primaryPathIsValid( self )
    if unstucking then
        pathValid = myTbl.PathIsValid( self )

    end

    local newPathWouldBeCheap = pathValid and myTbl.CanDoNewPath( self, entsRealPos )
    local newPath = not pathValid or newPathWouldBeCheap
    newPath = newPath and not closeAndCanHit

    if newPath and not unstucking then
        if myTbl.term_ExpensivePath then -- lagging the session
            yieldIfWeCan( "wait" )
            return -- invalid

        elseif not myTbl.nextNewPathIsGood( self ) then -- just not ready, sill valid, wait
            yieldIfWeCan( "wait" )
            return true

        end

        local pathPos = entsRealPos
        local area = terminator_Extras.getNearestPosOnNav( entsRealPos ).area

        local validArea = IsValid( area ) and myTbl.areaIsReachable( self, area )

        if validArea then
            local adjacents = area:GetAdjacentAreas()
            local foundBlocker = area:IsBlocked()
            if not foundBlocker and #adjacents > 0 then -- locked door hack
                for _, adjArea in ipairs( adjacents ) do
                    if adjArea:IsBlocked() and not foundBlocker then
                        adjacents = adjArea:GetAdjacentAreas()
                        foundBlocker = true
                        break
                    end
                end
            end

            -- the beating up is a blocker, build a path to one of the areas next to it, and make sure that path gets us close to the blocker!
            -- basically a locked door hack
            if foundBlocker then
                forcePath = true
                terminator_Extras.lockedDoorAttempts[entsCreationId] = oldCount + 1

                local thaArea = table_Random( adjacents )
                if IsValid( thaArea ) then
                    -- the adjacent area is also blocked....
                    if thaArea:IsBlocked() then
                        forcePath = false

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
        end

        if validArea then
            myTbl.SetupPathShell( self, pathPos, forcePath )

        end

        if not myTbl.primaryPathIsValid( self ) and not alwaysValid then
            myTbl.ignoreEnt( self, ent, 20 )
            valid = false

        end
    -- valid path and unstucker is not handling path
    elseif pathValid and not unstucking then
        myTbl.ControlPath2( self, not myTbl.IsSeeEnemy )

    -- no valid path and one doesnt need to be built
    elseif not unstucking then
        myTbl.GotoPosSimple( self, myTbl, entsRealPos, 5 )

        myTbl.forcedShouldWalk = CurTime() + 0.3
        myTbl.blockControlPath = CurTime() + 0.15

    end

    return valid, attacked, nearAndCanHit, closeAndCanHit, isNear, isClose, visible

end

function ENT:ResetUnstuckInfo()
    self.StuckPos5 = vec_zero
    self.StuckPos4 = vec_zero
    self.StuckPos3 = vec_zero
    self.StuckPos2 = vec_zero

    self.StuckEnt3 = nil
    self.StuckEnt2 = nil
    self.StuckEnt1 = nil

    --print( "reset" )

end

function ENT:TryGeneratingAreas()
    local oldArea = self.term_OldAreaWeTriedGeneratingAt
    if oldArea then
        local currArea = self:GetTrueCurrentNavArea()
        if oldArea == currArea then return end

        self.term_OldAreaWeTriedGeneratingAt = currArea

    end

    terminator_Extras.dynamicallyPatchPos( self:GetPos() )

end

-- MoveAlongPath found this segment to be impossible to cross 
function ENT:OnHardBlocked()
    --print( "hardblocked" )
    self:Anger( 1 )
    -- check FAST
    self.nextUnstuckCheck = CurTime()
    self.nextPosUpdate = CurTime()
    self.blockUnstuckRetrace = CurTime() + 1

    self:TryGeneratingAreas()

end

-- unstuck that flags a connection as bad, then the bot will bash anything nearby, then it will back up.
-- there are 2 more unstucks.
-- one that first makes the bot walk somewhere random, then if that fails and the bot is REALLY stuck, teleports/removes it ( reallystuck_handler task )
-- the base one ( in motionoverrides ) that teleports it to a clear spot next to it, if it's intersecting anything
local function HunterIsStuck( self, myTbl )
    local nextUnstuck = myTbl.nextUnstuckCheck or 0
    if nextUnstuck > CurTime() then return end

    if IsValid( myTbl.terminatorStucker ) then return true end

    if myTbl.overrideMiniStuck then myTbl.overrideMiniStuck = nil return true end

    if not myTbl.nextUnstuckCheck then
        myTbl.nextUnstuckCheck = CurTime() + 0.1
        myTbl.ResetUnstuckInfo( self )

    end
    myTbl.nextUnstuckCheck = CurTime() + 0.2

    local HasAcceleration = myTbl.loco:GetAcceleration()
    if HasAcceleration <= 0 then return end

    local myPos = self:GetPos()
    local StartPos = myTbl.LastMovementStartPos or vec_zero
    local GoalPos = myTbl.PathEndPos or vec_zero
    local NotMoving
    -- laddering? check 3d dist, not 2d dist!
    if myTbl.terminator_HandlingLadder and myTbl.StuckPos5 and myTbl.StuckPos3 then
        NotMoving = myPos:DistToSqr( myTbl.StuckPos5 ) < 20^2 and myPos:DistToSqr( myTbl.StuckPos3 ) < 20^2

    else
        NotMoving = DistToSqr2D( myPos, myTbl.StuckPos5 ) < 20^2 and DistToSqr2D( myPos, myTbl.StuckPos3 ) < 20^2

    end

    --[[if self.StuckPos3 and self.StuckPos5 then
        --debugoverlay.Sphere( self.StuckPos3, 20, 2, color_white, true )
        --debugoverlay.Sphere( self.StuckPos5, 20, 2, color_white, true )

    end--]]

    local blocker = myTbl.LastShootBlocker
    if not IsValid( blocker ) then
        blocker = myTbl.GetCachedDisrespector( self, myTbl )

    end
    if IsValid( blocker ) and ( blocker:IsNPC() or blocker:IsPlayer() ) then
        blocker = nil

    end

    local FarFromStart = DistToSqr2D( myPos, StartPos ) > 15^2
    local FarFromStartAndNew = FarFromStart or ( myTbl.LastMovementStart and ( myTbl.LastMovementStart + 1 < CurTime() ) )
    local FarFromEnd = DistToSqr2D( myPos, GoalPos ) > 15^2
    local IsPath = myTbl.PathIsValid( self )

    local NotMovingAndSameBlocker = myTbl.StuckEnt1 and ( myTbl.StuckEnt1 == myTbl.StuckEnt2 ) and ( myTbl.StuckEnt1 == myTbl.StuckEnt3 ) and DistToSqr2D( myPos, myTbl.StuckPos2 ) < 20^2 and DistToSqr2D( myPos, myTbl.StuckPos3 ) < 20^2

    local nextPosUpdate = myTbl.nextPosUpdate or 0

    if nextPosUpdate < CurTime() and IsPath then
        if myTbl.canDoRun( self ) and not myTbl.IsJumping( self, myTbl ) then
            myTbl.nextPosUpdate = CurTime() + 0.25

        else
            myTbl.nextPosUpdate = CurTime() + 0.55

        end
        myTbl.StuckPos5 = myTbl.StuckPos4
        myTbl.StuckPos4 = myTbl.StuckPos3
        myTbl.StuckPos3 = myTbl.StuckPos2
        myTbl.StuckPos2 = myTbl.StuckPos1
        myTbl.StuckPos1 = myPos

        myTbl.StuckEnt3 = myTbl.StuckEnt2
        myTbl.StuckEnt2 = myTbl.StuckEnt1
        myTbl.StuckEnt1 = blocker

    end

    --print( ( NotMoving or NotMovingAndSameBlocker ), FarFromStartAndNew, FarFromEnd, IsPath )
    local stuck = ( NotMoving or NotMovingAndSameBlocker ) and FarFromStartAndNew and FarFromEnd and IsPath
    if stuck then -- reset so chains of stuck events happen less
        myTbl.ResetUnstuckInfo( self )

    end

    return stuck

end

function ENT:IsUnderDisplacement()
    local myPos = self:GetShootPos()
    return terminator_Extras.posIsUnderDisplacement( myPos )

end

--do this so we can override the nextbot's current path
function ENT:ControlPath2( AimMode )
    local myTbl = self:GetTable()
    local result = nil

    if myTbl.blockControlPath and myTbl.blockControlPath > CurTime() then return end

    local validPath = myTbl.PathIsValid( self )
    local badPathAndStuck = myTbl.isUnstucking and not validPath
    local bashableWithinReasonableRange = myTbl.GetCachedBashableWithinReasonableRange( self )

    local blockUnstuckRetrace = myTbl.blockUnstuckRetrace or 0 -- allow this to be blocked
    local doUnstuckPath = blockUnstuckRetrace < CurTime()
    myTbl.blockUnstuckRetrace = nil

    local posBasedStuck = HunterIsStuck( self, myTbl )

    if badPathAndStuck or posBasedStuck then -- new unstuck
        local myPos = self:GetPos()
        myTbl.startUnstuckDestination = myTbl.PathEndPos -- save where we were going
        myTbl.startUnstuckPos = myPos
        myTbl.lastUnstuckStart = CurTime()

        if validPath and not terminator_Extras.IsLivePatching then
            self:TryGeneratingAreas()

        end

        local myNav = myTbl.GetTrueCurrentNavArea( self ) or self:GetCurrentNavArea()
        if not IsValid( myNav ) then return end --- AAAAH

        local scoreData = {}

        scoreData.canDoUnderWater = self:isUnderWater()
        scoreData.self = self
        scoreData.dirToEnd = self:GetForward()
        scoreData.bearingPos = myTbl.startUnstuckPos

        if validPath then -- we were pathing, time to flag this connection
            local path = self:GetPath()
            local _, aheadSegment = myTbl.GetNextPathArea( self, myNav ) -- top of the jump
            local currSegment = path:GetCurrentGoal() -- maybe bottom of the jump, paths are stupid
            local dirPathGoes
            local areasInDir

            if not aheadSegment then goto skipTheShitConnectionFlag end

            scoreData.dirToEnd = terminator_Extras.dirToPos( self:GetPos(), path:GetEnd() )
            if not aheadSegment or not currSegment then goto skipTheShitConnectionFlag end
            if not aheadSegment.area or not currSegment.area then goto skipTheShitConnectionFlag end
            if not aheadSegment.area:IsValid() or not currSegment.area:IsValid() then goto skipTheShitConnectionFlag end

            dirPathGoes = myNav:ComputeDirection( aheadSegment.pos )
            areasInDir = myNav:GetAdjacentAreasAtSide( dirPathGoes )

            for _, area in ipairs( areasInDir ) do
                --debugoverlay.Line( myNav:GetCenter(), area:GetCenter(), 5, Color( 255, 255, 0 ), true )
                myTbl.flagConnectionAsShit( self, myNav, area )

            end
            myTbl.flagConnectionAsShit( self, currSegment.area, aheadSegment.area )

            --debugoverlay.Line( currSegment.area:GetCenter(), aheadSegment.area:GetCenter(), 5, Color( 255, 255, 0 ), true )

            ::skipTheShitConnectionFlag::

            myTbl.InvalidatePath( self, "connection was flagged, killing my path for a new one!" )

        end

        if doUnstuckPath then -- get OUTTA here
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
                self:SetupPathShell( escapeArea:GetRandomPoint(), true )

                if self:PathIsValid() and myNav then
                    self.initArea = myNav
                    self.initAreaId = self.initArea:GetID()
                    break

                end
            end
            if not self:PathIsValid() then return false end
            self.isUnstucking = true

        end

        myTbl.tryToHitUnstuck = true
        myTbl.unstuckingTimeout = CurTime() + 10
        myTbl:ReallyAnger( 10 )

    end

    yieldIfWeCan()
    validPath = myTbl.PathIsValid( self )

    if myTbl.tryToHitUnstuck then
        local done = nil
        local toBeat = myTbl.entToBeatUp
        local lastShootBlocker = myTbl.LastShootBlocker

        local disrespector = myTbl.overrideStuckBeatupEnt or lastShootBlocker or bashableWithinReasonableRange[1]
        if not disrespector then
            disrespector = myTbl.GetCachedDisrespector( self, myTbl )

        end

        if myTbl.hitTimeout then
            if IsValid( toBeat ) then
                local valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose, visible = myTbl.beatUpEnt( self, myTbl, toBeat, true )
                local isNailed = istable( toBeat.huntersglee_breakablenails )
                local isInDanger = myTbl.getLostHealth( self ) >= 20
                local dangerAndNotNailed = isInDanger and not isNailed
                -- door was bashed or we are bored, or scared
                if myTbl.hitTimeout < CurTime() or not toBeat:IsSolid() or dangerAndNotNailed then
                    done = true
                    myTbl.lastBeatUpEnt = toBeat

                end
                if not closeAndCanHit or not visible then
                    myTbl.entToBeatUp = nil
                    myTbl.lastBeatUpEnt = toBeat

                end
                -- BEAT UP THE NAILED THING!
                if isNailed and visible and nearAndCanHit and closeAndCanHit and valid and attacked then
                    myTbl.GetTheBestWeapon( self )
                    myTbl.hitTimeout = CurTime() + 3

                -- shoot the nailed thing
                elseif isNailed and not isClose and visible and myTbl.IsRangedWeapon( self ) then
                    myTbl.shootAt( self, myTbl.getBestPos( self, toBeat ) )

                end
            -- was valid
            elseif not IsValid( toBeat ) then
                -- something new to break
                local somethingNewToBeatup = bashableWithinReasonableRange[1]
                local newWithinBashRange = IsValid( somethingNewToBeatup ) and myTbl.lastBeatUpEnt ~= somethingNewToBeatup
                local newDisrespector = IsValid( disrespector ) and myTbl.lastBeatUpEnt ~= disrespector
                if newWithinBashRange or newDisrespector then
                    toBeat = bashableWithinReasonableRange[1] or disrespector
                    myTbl.entToBeatUp = toBeat
                    myTbl.hitTimeout = CurTime() + 3

                else
                    done = true

                end
            end
        elseif ( IsValid( lastShootBlocker ) and lastShootBlocker ~= myTbl.lastBeatUpEnt ) or ( IsValid( disrespector ) and disrespector ~= myTbl.lastBeatUpEnt ) then
            myTbl.hitTimeout = CurTime() + 3

            myTbl.overrideStuckBeatupEnt = nil

        else
            done = true

        end
        if done or ( myTbl.hitTimeout + 1 ) < CurTime() then
            myTbl.entToBeatUp = nil
            myTbl.hitTimeout = nil
            myTbl.tryToHitUnstuck = nil

        end
    elseif myTbl.isUnstucking then
        if not validPath then
            myTbl.isUnstucking = false
            return false

        end
        result = myTbl.ControlPath( self, AimMode )
        local DistToStart = self:GetPos():Distance( myTbl.startUnstuckPos )
        local FarEnough = DistToStart > 200
        local myNavArea = myTbl.GetTrueCurrentNavArea( self ) or self:GetCurrentNavArea()

        if not IsValid( myNavArea ) then return end
        local NotStart = myTbl.initAreaId ~= myNavArea:GetID()

        local Escaped = nil

        if FarEnough and NotStart then
            Escaped = true

        elseif result then
            Escaped = true

        end
        if Escaped or myTbl.unstuckingTimeout < CurTime() then
            myTbl.isUnstucking = nil
            if myTbl.startUnstuckDestination then
                myTbl.SetupPathShell( self, myTbl.startUnstuckDestination )

            end
        end
    else
        if not validPath then return false end
        local wep = myTbl.GetWeapon( self, myTbl )
        if wep and wep.worksWithoutSightline and IsValid( myTbl.GetEnemy( self ) ) and AimMode == true then
            AimMode = nil

        end
        result = myTbl.ControlPath( self, AimMode )

    end
    return result

end

-- do this so we can get data about current tasks easily
function ENT:StartTask2( Task, Data, Reason )
    yieldIfWeCan()
    local Data2 = Data or {}
    Data2.taskStartTime = CurTime()
    self:StartTask( Task, Data2 )

    -- additional debugging tool
    if not debugPrintTasks:GetBool() then return end

    print( self:GetCreationID(), Task, self:GetEnemy(), Reason ) --global

    self.taskHistory = self.taskHistory or {}

    table.insert( self.taskHistory, SysTime() .. " " .. Task .. " " .. Reason )

end

-- super useful

function ENT:Use( user )
    if not user:IsPlayer() then return end

    -- only dump task history when the task debugger is true
    if not debugPrintTasks:GetBool() then return end

    if ( self.nextCheatUse or 0 ) > CurTime() then return end
    self.nextCheatUse = CurTime() + 1

    local fourSpaces = "    "

    self.taskHistory = self.taskHistory or {}
    print( "taskhistory" )
    PrintTable( self.taskHistory )
    print( "activetasks", self )
    for taskName, _ in pairs( self.m_ActiveTasks ) do
        print( fourSpaces .. taskName )

    end
    print( "lastShootType", self.lastShootingType )
    print( "lastPathKillReason", self.lastPathInvalidateReason )

end


function ENT:interceptIfWeCan( currTask, data )
    local interceptTime = self.lastInterceptTime or 0
    local notHeadingToEnd = self.lastInterceptPos and SqrDistGreaterThan( self.lastInterceptPos:DistToSqr( self:GetPath():GetEnd() ), 600 )
    local freshIntercept = true
    local shouldIntercept
    if data and data.taskStartTime then
        local taskDidntJustStart = ( data.taskStartTime + 1 ) <= CurTime()
        local interceptIsNewer = interceptTime > ( data.taskStartTime + -1 )
        freshIntercept = interceptIsNewer and taskDidntJustStart
        shouldIntercept = freshIntercept and notHeadingToEnd and not self.IsSeeEnemy

    elseif not data then
        shouldIntercept = true

    end

    if shouldIntercept and currTask then
        self:TaskComplete( currTask )
        self:StartTask2( "movement_intercept", nil, "intercepting because i can!" )

    end
    return shouldIntercept

end

function ENT:beatupVehicleIfWeCan( currTask )
    if self.IsSeeEnemy then return end

    local sinceLastSeenEnemy = CurTime() - self.LastEnemySpotTime
    if sinceLastSeenEnemy < 10 then return end

    local vehicleIHate = self.term_VehicleIHateAlot
    if not IsValid( vehicleIHate ) then return end

    local vehiclesBestPos = self:getBestPos( vehicleIHate )
    local distToVehicle = self:GetRangeTo( vehiclesBestPos )
    if distToVehicle > self.AwarenessCheckRange then return end

    local seeVehicle = self:CanSeePosition( vehiclesBestPos )
    if not seeVehicle then return end

    self:TaskComplete( currTask )
    self:StartTask2( "movement_bashobject", { object = vehicleIHate, insane = self:IsReallyAngry() }, "i found your car, i will now destroy it!" )
    return true

end

function ENT:GetLockedDoorToBash()
    local globalAttempts = terminator_Extras.lockedDoorAttempts
    local leastAttempts = math.huge
    local bestDoor

    local doors = self.awarenessLockedDoors

    for _, currDoor in ipairs( doors ) do
        local currAttempts = globalAttempts[ currDoor:GetCreationID() ] or 0
        if currAttempts < leastAttempts then
            bestDoor = currDoor
            leastAttempts = currAttempts

        end
    end
    return bestDoor

end

function ENT:CanBashLockedDoor( reference, distNeeded )
    if not self.encounteredABlockedAreaWhenPathing then return end
    local door = self:GetLockedDoorToBash()
    if not IsValid( door ) then return end

    if not reference then reference = self:GetPos() end
    if not distNeeded then distNeeded = 800 end

    if door:GetPos():DistToSqr( reference ) > distNeeded^2 then return end

    return true, door

end

function ENT:BashLockedDoor( currentTask )
    local theDoor = self:GetLockedDoorToBash()
    if not IsValid( theDoor ) then return end
    self.encounteredABlockedAreaWhenPathing = nil

    self:TaskComplete( currentTask )
    self:StartTask2( "movement_bashobject", { object = theDoor, insane = true, doorBash = true }, "there's a locked door and one of them blocked my path earlier" )

    local oldCount = terminator_Extras.lockedDoorAttempts[theDoor:GetCreationID()] or 0
    terminator_Extras.lockedDoorAttempts[theDoor:GetCreationID()] = oldCount + 1

    return true

end

-- handle spotting enemy once here, instead of differently in every single task ever
function ENT:EnemyAcquired( currentTask )
    if not IsValid( self ) then return end -- hrm... i dont think i need to start a new task in this case
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_approachlastseen", nil, "ea, enemy is invalid?" )
        return true

    end
    -- tackle the ladder!
    if self.terminator_HandlingLadder then
        self:TermHandleLadder()
        return

    end
    -- dont throw away an expensive path!
    if self.term_ExpensivePath and self:primaryPathIsValid() then return end

    local tooDangerousToApproach = self:EnemyIsLethalInMelee( enemy )
    local enemPos = self:EntShootPos( enemy )
    local myPos = self:GetPos()
    local myHp = self:Health()
    local maxHp = self:GetMaxHealth()
    local seeEnemy = self:CanSeePosition( enemy ) -- check here so it's always accurate, fucked me over tho
    local bearingToMeAbs = self:enemyBearingToMeAbs()
    local distToEnemySqr = myPos:DistToSqr( enemPos )
    local weapRange = self:GetWeaponRange()
    local notMelee = not self:IsMeleeWeapon( self:GetWeapon() )
    local reallyAngry = self:IsReallyAngry()

    local sameZ = ( myPos.z < enemPos.z + 200 ) and ( myPos.z > enemPos.z + -200 )
    local withinWeapRange = weapRange == math.huge or SqrDistGreaterThan( distToEnemySqr, weapRange )
    local damaged = myHp < ( maxHp * 0.75 )
    local veryDamaged = myHp < ( maxHp * 0.5 )
    local enemySeesMe = bearingToMeAbs < 20
    local lowOrRand = ( damaged and math.random( 0, 100 ) > 15 ) or math.random( 0, 100 ) > 85
    local boredOrRand = self.boredOfWatching or math.random( 0, 100 ) > 65

    local enemyIsNotVeryClose = SqrDistGreaterThan( distToEnemySqr, 125 )
    local enemyIsNotClose = SqrDistGreaterThan( distToEnemySqr, 500 )
    local enemyIsFar = SqrDistGreaterThan( distToEnemySqr, 2000 )

    local veryHighHealth = myHp == maxHp
    local campIsGood = ( boredOrRand and not veryHighHealth ) or weapRange > 6000

    -- when we haven't watched before, be very lenient with the distance
    local beginFirstWatch = self.watchCount == 0 and not reallyAngry and enemy and not enemy.terminator_endFirstWatch
    local stillInFirstWatch = enemy and ( enemy.terminator_endFirstWatch or 0 ) > CurTime() and not reallyAngry
    local doNormalWatch = veryHighHealth and enemyIsNotClose and not self.boredOfWatching and not reallyAngry
    local doBaitWatch = not reallyAngry and enemyIsNotVeryClose and self:AnotherHunterIsHeadingToEnemy() and enemy.terminator_TerminatorsWatching and #enemy.terminator_TerminatorsWatching < 1
    local doCamp = SqrDistGreaterThan( distToEnemySqr, 1400 ) and ( not doWatch ) and campIsGood and withinWeapRange and notMelee
    local canRushKiller = enemy.isTerminatorHunterKiller and myHp > ( maxHp * 0.80 ) and not tooDangerousToApproach
    local isBeingFooled = IsValid( enemy.terminator_crouchingbaited ) and enemy.terminator_crouchingbaited ~= self and enemy.terminator_crouchingbaited.IsSeeEnemy and not enemy.terminator_CantConvinceImFriendly
    local campDangerousEnemy = tooDangerousToApproach and enemyIsFar and withinWeapRange

    local doStalk = enemySeesMe and seeEnemy and ( lowOrRand or veryDamaged ) and sameZ
    doStalk = doStalk or tooDangerousToApproach -- always do stalking if the enemy has killed tons of terminators in close range 

    local doFlank = ( lowOrRand or enemy.isTerminatorHunterKiller ) and not SqrDistLessThan( distToEnemySqr, 400 )

    if not seeEnemy and self.lastInterceptPos and self:interceptIfWeCan( currentTask ) then
        -- we intercepted
    elseif isBeingFooled then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, this is gonna fool em so hard" )
    elseif not seeEnemy then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_approachlastseen", nil, "ea, where'd they go" )
    elseif doBaitWatch then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, another hunter will sneak up on them!" )
        self:Anger( 12 )
    elseif doNormalWatch or beginFirstWatch or stillInFirstWatch then
        if beginFirstWatch then
            self.PreventShooting = true
            enemy.endFirstWatch = CurTime() + 75

        end
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_watch", nil, "ea, watching something" )
    elseif campDangerousEnemy then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_camp", nil, "ea, enemy is scary! camp them" )
    elseif doCamp then
        self:TaskComplete( currentTask )
        local tolerance = self:campingTolerance()
        if tolerance > math.random( 1000, 3000 ) then
            self:StartTask2( "movement_camp", { maxNoSeeing = tolerance }, "ea, camp or perch, camped because we're already in a good spot" )
        else
            self:StartTask2( "movement_perch", { requiredTarget = enemPos, earlyQuitIfSeen = true, perchRadius = math.sqrt( distToEnemySqr ), distanceWeight = 0.01 }, "ea, camp or perch, perch" )
        end
    elseif canRushKiller then
        self:TaskComplete( currentTask )
        if self.term_DoesntFlank then
            self:StartTask2( "movement_followenemy", nil, "ea, rush a killer" )
        else
            self:StartTask2( "movement_flankenemy", nil, "ea, rush a killer" )
        end
        self.PreventShooting = nil
    elseif doStalk then
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_stalkenemy", nil, "ea, stalk them" )
    elseif doFlank then
        self:TaskComplete( currentTask )
        if self.term_DoesntFlank then
            self:StartTask2( "movement_followenemy", nil, "ea, flank them but i dont like flanking" )
        else
            self:StartTask2( "movement_flankenemy", nil, "ea, flank them" )
        end
        self.PreventShooting = nil
    else
        self:TaskComplete( currentTask )
        self:StartTask2( "movement_followenemy", nil, "ea, im just gonna rush them, nothing fancy" )
        self.PreventShooting = nil
    end
    return true
end

function ENT:markAsWalked( area )
    if not IsValid( area ) then return end
    local areasId = area:GetID()
    self.walkedAreas[areasId] = true
    self.walkedAreaTimes[areasId] = CurTime()

    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        if not IsValid( area ) then return end
        self.walkedAreas[areasId] = nil
        self.walkedAreaTimes[areasId] = nil

    end )
end

local offset25z = Vector( 0, 0, 25 )

-- very useful for searching, going places the bot hasn't been to yet
function ENT:WalkArea( myTbl )
    local walkedArea = myTbl:GetCurrentNavArea( self )
    if not IsValid( walkedArea ) then return end

    if not myTbl.areaIsReachable( self, walkedArea ) and myTbl.nextUnreachableWipe < CurTime() then -- we got somewhere unreachable, probably should reset this
        if myTbl.IsFodder then -- order the fodder enemies to rebuild the unreachable cache
            local ourClass = entMeta.GetClass( self )
            terminator_Extras.unreachableAreasForClasses[ ourClass ] = {}

            for _, ent in ipairs( ents.FindByClass( ourClass ) ) do
                if ent == myTbl then continue end -- self gets a special case

                ent.unreachableAreas = terminator_Extras.unreachableAreasForClasses[ ourClass ]
                ent.nextUnreachableWipe = CurTime() + 15 -- never ever ever spam this

            end
        end
        myTbl.unreachableAreas = {} -- fodder enemies get this too, they break off from the global unreachable table
        myTbl.nextUnreachableWipe = CurTime() + 15 -- never ever ever spam this

    end

    if not myTbl.walkedAreas then return end -- set as nil to disable this, for fodder enemies, etc

    local nextFloodMark = myTbl.nextFloodMarkWalkable or 0

    local cur = CurTime()

    if nextFloodMark > cur then return end
    local add = math.Rand( 1, 1.5 )
    if myTbl.IsFodder then
        add = add * math.Rand( 2, 3 )

    end
    myTbl.nextFloodMarkWalkable = cur + add

    local scoreData = {}
    scoreData.currentWalked = myTbl.walkedAreas
    scoreData.InitialArea = walkedArea
    scoreData.checkOrigin = myTbl.GetShootPos( self )
    scoreData.self = self
    local dist = 750

    local scoreFunction = function( scoreData, _, area2 )
        local score = 0
        if not area2 then return 0 end -- patch a script err?
        local areaCenter = area2:GetCenter()
        if scoreData.currentWalked[area2:GetID()] then
            score = 1

        elseif scoreData.InitialArea:IsCompletelyVisible( area2 ) or terminator_Extras.PosCanSee( areaCenter + offset25z, scoreData.checkOrigin ) then
            scoreData.currentWalked[area2:GetID()] = true
            scoreData.self:markAsWalked( area2 )
            score = math.abs( dist + -areaCenter:Distance( scoreData.checkOrigin ) )
            score = score / dist
            score = score * 25
        end
        --debugoverlay.Text( areaCenter, tostring( math.Round( score ) ), 8 )
        return score

    end

    local _ = myTbl.findValidNavResult( self, scoreData, self:GetPos(), dist, scoreFunction )

end

-- marks areas as searched as we walk around in the searching tasks
function ENT:SimpleSearchNearbyAreas( myPos, myShootPos )
    myShootPos = myShootPos or self:GetShootPos()
    myPos = myPos or self:GetPos()

    local myAng = self:GetEyeAngles()
    local myFov = self.Term_FOV
    local checkedNavs = self.SearchCheckedNavs
    local PosIsInFov = self.PosIsInFov

    local walkedAreas = navmesh.Find( myPos, 500, 10, 10 )
    local max = 25
    for ind, area in ipairs( walkedAreas ) do
        if ind > max then break end
        yieldIfWeCan()

        local areasId = area:GetID()
        local checked = checkedNavs[areasId]
        local sawArea
        local hidingSpots = area:GetHidingSpots( 1 )

        if not checked and #hidingSpots <= 0 then
            local centerOffsetted = area:GetCenter() + plus25Z
            -- check fov too, so we dont mark areas as searched unless we actually looked at em
            sawArea = PosIsInFov( self, myAng, myPos, centerOffsetted, myFov ) and terminator_Extras.PosCanSeeComplex( myShootPos, centerOffsetted, self )

        elseif not checked then
            local seen = 0
            for _, spot in ipairs( hidingSpots ) do
                yieldIfWeCan()
                local spotOffsetted = spot + plus25Z
                local inFov = PosIsInFov( self, myAng, myPos, spotOffsetted, myFov )
                if inFov and terminator_Extras.PosCanSeeComplex( myShootPos, spotOffsetted, self ) then
                    --debugoverlay.Line( myShootPos, spotOffsetted, 5, color_white, true )
                    seen = seen + 1

                elseif not inFov and math.random( 1, 100 ) < 25 then
                    --debugoverlay.Line( myShootPos, spotOffsetted, 5, Color( 255, 0, 0 ), true )
                    self.term_GenericLookAtPos = { source = spotOffsetted, time = CurTime() }

                end
            end
            sawArea = seen >= ( #hidingSpots * 0.75 )

        end
        if sawArea then
            checkedNavs[areasId] = true
            self.SearchCheckedNavsCount = self.SearchCheckedNavsCount + 1

        end
    end
end

function ENT:EnemyIsReachable()
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then return end
    local enemyPos = enemy:GetPos()

    local enemyNavArea = terminator_Extras.getNearestNav( enemyPos ) or NULL
    return self:areaIsReachable( enemyNavArea )

end
    

-- did we already try, and fail, to path there?
function ENT:areaIsReachable( area )
    if not area then return end
    if not IsValid( area ) then return end
    if self.unreachableAreas[area:GetID()] then return end
    return true

end

-- don't build paths to these areas!
function ENT:rememberAsUnreachable( area, areasId )
    if not IsValid( area ) then return end
    areasId = areasId or area:GetID()
    self.unreachableAreas[areasId] = true
    if self.IsFodder then
        hook.Run( "term_updateunreachableareas", self:GetClass(), area )

    end

    --debugoverlay.Cross( area:GetCenter(), 20, 20, Color( 255, 0, 0 ), true )

    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        self:rememberAsReachable( area, areasId )

    end )
    return true
end

-- undo the above
function ENT:rememberAsReachable( area, areasId )
    if not IsValid( area ) then return end
    areasId = areasId or area:GetID()

    self.unreachableAreas[areasId] = nil
    return true
end

function ENT:resetLostHealth()
    self.VisibilityStartingHealth = nil

end

function ENT:getLostHealth()
    if not self.VisibilityStartingHealth then return 0 end
    return math.abs( self:Health() - self.VisibilityStartingHealth )

end

function ENT:inSeriousDanger()
    if self:getLostHealth() > 100 then return true end
    if sound.GetLoudestSoundHint( SOUND_DANGER, self:GetPos() ) then return true end
    if self.DistToEnemy < 800 and self:EnemyIsLethalInMelee() then return true end

end

function ENT:EnemyIsUnkillable( enemy )
    if not enemy then
        enemy = self:GetEnemy()

    end
    if not IsValid( enemy ) then return end

    local unkillable = ( entMeta.Health( enemy ) > 10000 ) or ( enemy.HasGodMode and enemy:HasGodMode() )

    local increasedPriorities = self.terminator_IncreasedPriorities or {}

    if unkillable and not increasedPriorities[enemy] then
        self.terminator_IncreasedPriorities = increasedPriorities
        self:Term_SetEntityRelationship( enemy, D_HT, 2000 )

    end
    return unkillable

end

function ENT:EnemyIsLethalInMelee( enemy )
    enemy = enemy or self:GetEnemy()
    if not IsValid( enemy ) then return end

    if self.IsEldritch then return end -- im the lethal one

    if enemy.IsEldritch then return true end

    local isLethalInMelee = enemy.terminator_IsLethalInMelee
    local isLethal = ( isLethalInMelee and isLethalInMelee >= 2 ) or self:EnemyIsUnkillable( enemy )

    if isLethal then return true end

end

hook.Add( "OnNPCKilled", "terminator_markkillers", function( npc, attacker, inflictor )
    if not npc.isTerminatorHunterChummy then return end
    if not attacker then return end
    if not inflictor then return end

    if attacker.isTerminatorHunterChummy == npc.isTerminatorHunterChummy then return end

    if npc:IgnoringPlayers() and attacker:IsPlayer() then return end

    local maxHp = npc:GetMaxHealth()
    local value = math.Clamp( maxHp / 500, 0, 1 )

    -- if someone has killed terminators, make them react
    local old = attacker.isTerminatorHunterKiller or 0
    if old <= 0 and value < 0.5 then return end

    attacker.isTerminatorHunterKiller = old + value

    if maxHp < 500 then return end

    if inflictor:IsWeapon() then
        local weapsWeightToTerm = npc:GetWeightOfWeapon( inflictor )
        terminator_Extras.OverrideWeaponWeight( inflictor:GetClass(), weapsWeightToTerm + 15 )

    end

    if DistToSqr2D( attacker:GetPos(), npc:GetPos() ) < 350^2 then
        local isLethalInMelee = attacker.terminator_IsLethalInMelee or 0
        attacker.terminator_IsLethalInMelee = isLethalInMelee + 1

    end

    local timerId = "terminator_undokillerstatus_" .. attacker:GetCreationID()

    local timeToForget = 60 * 15 -- 15 mins!!!
    timer.Remove( timerId )
    timer.Create( timerId, timeToForget, 1, function()
        if not IsValid( attacker ) then return end
        attacker.isTerminatorHunterKiller = nil

    end )
end )

hook.Add( "PlayerDeath", "terminator_unmark_killers", function( plyDied, _, attacker )
    if not attacker.isTerminatorHunterChummy then return end
    if not attacker.isTerminatorHunterBased then return end

    local isLethalInMelee = plyDied.terminator_IsLethalInMelee or 0
    plyDied.terminator_IsLethalInMelee = math.Clamp( isLethalInMelee + -1, 0, math.huge )

    local oldKillerWeight = plyDied.isTerminatorHunterKiller
    if oldKillerWeight then
        plyDied.isTerminatorHunterKiller = math.Clamp( oldKillerWeight + -0.25, 0, math.huge )

        if plyDied.isTerminatorHunterKiller <= 0 then
            plyDied.isTerminatorHunterKiller = nil

        end
    end
end )

local function resetPlysKillerStatus( ply )
    ply.terminator_CantConvinceImFriendly = nil
    ply.terminator_IsLethalInMelee = nil
    ply.terminator_endFirstWatch = nil

    ply.isTerminatorHunterKiller = nil
    timer.Remove( "terminator_undokillerstatus_" .. ply:GetCreationID() )

end

function ENT:DistAddedByKillerEnemy( enemy )
    if not enemy or not IsValid( enemy ) then return 0 end
    if not enemy.isTerminatorHunterKiller then return 0 end

    local dist = math.Clamp( enemy.isTerminatorHunterKiller / 4, 0, 1500 )
    return dist

end


hook.Add( "PostCleanupMap", "terminator_clear_playerstatuses", function()
    for _, ply in ipairs( player.GetAll() ) do
        resetPlysKillerStatus( ply )

    end
end )
hook.Add( "terminator_nextbot_noterms_exist", "terminator_clear_playerstatuses", function()
    for _, ply in player.Iterator() do
        resetPlysKillerStatus( ply )

    end
end )

function ENT:SetupDefaultCapabilities()
    BaseClass.SetupDefaultCapabilities(self)

    self:CapabilitiesAdd(CAP_MOVE_JUMP)
end



local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"
ENT.ARNOLD_MODEL = ARNOLD_MODEL

local mdlVar = CreateConVar( "termhunter_modeloverride", ARNOLD_MODEL, FCVAR_ARCHIVE, "Override the terminator nextbot's spawned-in model. Model needs to be rigged for player movement" )

local function termModel()
    local model = ARNOLD_MODEL
    if mdlVar then
        local varModel = mdlVar:GetString()
        if varModel and util.IsValidModel( varModel ) then
            model = varModel
        end
    end
    return model

end

if not termModel() then
    RunConsoleCommand( "termhunter_modeloverride", ARNOLD_MODEL )

end

local fovDefault = 95
local fovVar = CreateConVar( "termhunter_fovoverride", -1, FCVAR_ARCHIVE, "Override the terminator's FOV, -1 for default, ( " .. fovDefault .. ")", -1, fovDefault )
local fovCached

local function fovVarThink()
    local valRaw = fovVar:GetInt()
    if valRaw <= -1 then
        fovCached = fovDefault

    else
        fovCached = valRaw

    end
    for _, ent in ents.Iterator() do
        if ent.isTerminatorHunterBased and ent.Term_FOV and ent.AutoUpdateFOV then
            ent.Term_FOV = fovCached

        end
    end
end

fovVarThink()

cvars.AddChangeCallback( "termhunter_fovoverride", function()
    fovVarThink()

end )


local healthVar = CreateConVar( "termhunter_health", -1, FCVAR_ARCHIVE, "Override the terminator's health, -1 for default, ( " .. terminator_Extras.healthDefault .. " )", -1, 99999999 )

local function healthFunc()
    local valRaw = healthVar:GetInt()
    if valRaw <= -1 then
        return terminator_Extras.healthDefault -- defined in sh_terminator_funcs

    else
        return valRaw

    end
end

-- config vars
ENT.TERM_FISTS = "weapon_terminatorfists_term"
ENT.CoroutineThresh = 0.003 -- how much processing time this bot is allowed to take up per tick, check behaviouroverrides
ENT.ThreshMulIfDueling = nil -- thresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = nil -- if we're closer than DuelEnemyDist * 2
ENT.MaxPathingIterations = 30000 -- set this to like 5000 if you dont care about a specific bot having perfect ( read, expensive ) paths

ENT.SpawnHealth = healthFunc
ENT.DoMetallicDamage = true -- terminator model damage logic
ENT.HealthRegen = nil -- health regen per interval
ENT.HealthRegenInterval = nil -- time between health regens

-- custom values for the nextbot base to use
-- i set these as multiples of defaults ( 70 )
ENT.JumpHeight = 70 * 3.5
ENT.DefaultStepHeight = 18
-- allow us to have different step height when couching/standing
-- stops bot from sticking to ceiling with big step height
-- see crouch toggle in motionoverrides
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1.5
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.CanUseLadders = true
ENT.CanSwim = false
ENT.BreathesAir = false
ENT.BreathesWater = false

ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_PERFECT
ENT.AimSpeed = 480
ENT.WalkSpeed = 130
ENT.MoveSpeed = 300
ENT.RunSpeed = 550 -- bit faster than players... in a straight line
ENT.AccelerationSpeed = 3000
ENT.DeathDropHeight = 2000 --not afraid of heights
ENT.LastEnemySpotTime = 0
ENT.InformRadius = 20000
ENT.WeaponSearchRange = 1500 -- dynamically increased in below tasks to 32k if the enemy is unreachable or lethal in melee
ENT.AwarenessCheckRange = 1500 -- used by weapon searching too if wep search radius is <= this

ENT.CanHolsterWeapons = true
ENT.CanUseStuff = true
ENT.JudgesEnemies = true -- dynamically ignore enemies if they aren't taking damage?
ENT.IsFodder = nil -- enables optimisations that make sense on bullet fodder enemies
ENT.IsStupid = nil -- enables optimisations/simplifcations that make sense for dumb enemies

ENT.TakesFallDamage = true
ENT.HeightToStartTakingDamage = ENT.JumpHeight
ENT.FallDamagePerHeight = 0.05

ENT.FistDamageMul = 4
ENT.ThrowingForceMul = 1000 -- speed we throw crowbars, this is the overcharged one so it's 1k

ENT.duelEnemyTimeoutMul = 1
ENT.CloseEnemyDistance = 50 -- bot ignores enemy priority if enemy is this close

ENT.AutoUpdateFOV = true

-- translated to TERM_MODEL
ENT.Models = { "terminator" }

ENT.ReallyStrong = true
ENT.ReallyHeavy = true
ENT.HasFists = true
ENT.MetallicMoveSounds = true
ENT.FootstepClomping = true
ENT.Term_BaseTimeBetweenSteps = 400
ENT.Term_StepSoundTimeMul = 0.6

-- enable/disable spokenlines logic
ENT.CanSpeak = false

-- enable/disable hearing things
ENT.CanHearStuff = true

ENT.DuelEnemyDist = 700 -- dist to move from flank or follow enemy, to duel enemy

-- all other relationships are created by MakeFeud in enemyoverrides when something damages us
-- means bot viciously attacks enemies that can hurt it
-- while ignoring harmless stuff, like seagulls
function ENT:DoHardcodedRelations()
    self.term_HardCodedRelations = {
        ["npc_lambdaplayer"] = { D_HT, D_HT, 1000 },
    }
end

function ENT:AdditionalThink( _myTbl ) -- THINK stub, inside coroutine! for your convenience
end

function ENT:TermThink( myTbl ) -- inside coroutine :)
    myTbl.AdditionalThink( self, myTbl )
    if myTbl.CanSpeak then
        myTbl.SpokenLinesThink( self, myTbl )

    end
    if myTbl.HealthRegen then
        myTbl.HealthRegenThink( self )

    end
    if myTbl.DrowningThink then
        myTbl.DrowningThink( self, myTbl )

    end
    if not myTbl.loco:IsOnGround( myTbl.loco ) then
        local swimming, waterLevel = myTbl.IsSwimming( self, myTbl )
        if swimming then
            myTbl.HandleSwimming( self, myTbl, waterLevel )

        else
            myTbl.HandleInAir( self, myTbl )

        end
    end

    --[[
    if debugPrintTasks:GetBool() then
        local myShoot = self:GetShootPos()
        local upOffs = vectorUp * 15
        for ind, dat in ipairs( self.m_ActiveTasksNum ) do
            debugoverlay.Text( myShoot + upOffs * ind, dat[1], 0.02, false )

        end
    end
    ]]--

    -- very helpful to find missing taskcomplete/taskfails
    --[[
    local doneTasks = {}
    for task, _ in pairs( self.m_ActiveTasks ) do
        if string.find( task, "movement_" ) then
            table.insert( doneTasks, task )
        end
    end

    if #doneTasks >= 2 then
        ErrorNoHaltWithStack()
        print( "DOUBLE!" )
        PrintTable( doneTasks )
        SafeRemoveEntityDelayed( self )

    end
    --]]
end

function ENT:AdditionalInitialize( _myTbl )
end


function ENT:Initialize()
    -- internal stuff, don't edit unless you know what you're doing!
    -- use additionalInitialize for your own entities based off this

    BaseClass.Initialize( self )

    local myTbl = self:GetTable()
    local myPos = self:GetPos()

    myTbl.terminator_DontImmiediatelyFire = CurTime()
    myTbl.CreateShootingTimer( self, myTbl )

    myTbl.DoNotDuplicate = true -- TODO; somehow fix the loco being nuked when duped

    myTbl.walkedAreas = {} -- useful table of areas we have been / have seen, for searching/wandering
    myTbl.walkedAreaTimes = {} -- times we walked/saw them
    myTbl.hazardousAreas = {} -- areas we took damage in, used in pathoverrides
    myTbl.unreachableAreas = {} -- set this here early, special case for fodder enemies below
    myTbl.nextUnreachableWipe = 0
    myTbl.failedPlacingAreas = {} -- areas we couldnt place stuff at
    myTbl.awarenessBash = {}
    myTbl.awarenessMemory = {}
    myTbl.awarenessUnknown = {}
    myTbl.awarenessLockedDoors = {} -- locked doors are evil, catalog them so we can destroy them
    myTbl.awarenessSubstantialStuff = {} -- things with physobjs, just a cache for other stuff to use

    -- for the system that checks if bot has stuff that would make it angry, makes bot run, destroy props, locked doors
    -- we delay it a bit after the bot spawns
    myTbl.terminator_CheckIsAngry = CurTime() + 1
    myTbl.terminator_CheckIsReallyAngry = CurTime() + 1

    myTbl.heardThingCounts = {} -- so we can ignore stuff that's distracted us alot

    -- search stuff
    myTbl.SearchCheckedNavs = {} -- add this here even if its hacky
    myTbl.SearchCheckedNavsCount = 0
    myTbl.SearchBadNavAreas = {} -- nav areas that never should be checked

    -- used for jumping fall damage/effects
    myTbl.lastGroundLeavingPos = myPos

    -- just here so these are never nil
    myTbl.EnemyLastPos = myPos
    myTbl.EnemyLastPosOffsetted = myPos

    myTbl.LineOfSightMask = LineOfSightMask

    local model = myTbl.Models[ math.random( #myTbl.Models ) ]
    if model == "terminator" then
        model = termModel()

    end
    self:SetModel( model )
    local scale = myTbl.TERM_MODELSCALE or 1
    if isfunction( scale ) then
        scale = scale( self )

    end
    self:SetModelScale( scale, .00001 )

    -- "config" stuff, ONLY edit if you DONT know what you're doing!
    myTbl.isTerminatorHunterChummy = "terminators" -- are we pals with terminators?
    myTbl.Term_FOV = fovCached

    myTbl.SetCurrentWeaponProficiency( self, myTbl.TERM_WEAPON_PROFICIENCY )
    myTbl.WeaponSpread = 0

    -- end lil config
    myTbl.SetupTasks( self, myTbl )

    -- for stuff based on this
    myTbl.AdditionalInitialize( self, myTbl )
    myTbl.InitializeSpeaking( self )
    myTbl.InitializeHealthRegen( self )
    myTbl.InitializeDrowning( self, myTbl )
    myTbl.InitializeListening( self, myTbl )

    myTbl.DoHardcodedRelations( self )

    if myTbl.IsReallyHeavy and myTbl.MyPhysicsMass == 85 then
        myTbl.MyPhysicsMass = 5000

    end

    myTbl.InitializeCollisionBounds( self, scale )

    myTbl.InitializeLagCompensation( self )

    timer.Simple( 0.1, function()
        if not IsValid( self ) then return end
        if navmesh.GetNavAreaCount() <= 0 then
            local myCreator = self:GetCreator()
            if not IsValid( myCreator ) and CPPI then
                myCreator = self:CPPIGetOwner()

            end
            local canPatch = GetConVar( "terminator_areapatching_enable" ):GetBool()
            if IsValid( myCreator ) then
                if canPatch then
                    local msg = "NO NAVMESH FOUND! ATTEMPTING PATCH... EXPECT BAD RESULTS, ERRORS!\n!!!!!YOU should REALLY!! nav_generate a proper navmesh!!!!!"
                    myCreator:PrintMessage( HUD_PRINTCENTER, msg )
                    myCreator:PrintMessage( HUD_PRINTTALK, msg )
                    myCreator:PrintMessage( HUD_PRINTCONSOLE, msg )

                else
                    local msg = "NO NAVMESH FOUND!"
                    myCreator:PrintMessage( HUD_PRINTCENTER, msg )
                    myCreator:PrintMessage( HUD_PRINTTALK, msg )
                    myCreator:PrintMessage( HUD_PRINTCONSOLE, msg )
                    SafeRemoveEntity( self )
                    return

                end
            end
            if not terminator_Extras.IsLivePatching then
                self:TryGeneratingAreas()

            end
        end
        myTbl.RunTask( self, "OnCreated" )
        -- see enemyoverrides
        myTbl.SetupRelationships( self, myTbl )

        if myTbl.IsFodder then
            local ourClass = self:GetClass()
            terminator_Extras.unreachableAreasForClasses = terminator_Extras.unreachableAreasForClasses or {}
            terminator_Extras.unreachableAreasForClasses[ ourClass ] = terminator_Extras.unreachableAreasForClasses[ ourClass ] or {}
            myTbl.unreachableAreas = terminator_Extras.unreachableAreasForClasses[ ourClass ]

        end
    end )

end

function ENT:DoDefaultTasks()
    self.TaskList = {
        ["shooting_handler"] = {
            StartsOnInitialize = true,
            OnStart = function( self, data )
            end,
            BehaveUpdatePriority = function( self, data, interval )
                local myTbl = data.myTbl
                local enemy = myTbl.GetEnemy( self )

                local wep = myTbl.GetActiveLuaWeapon( self, myTbl ) or myTbl.GetActiveWeapon( self )
                -- edge case
                if not IsValid( wep ) then
                    if myTbl.HasFists then
                        self:DoFists()
                        return

                    elseif IsValid( enemy ) then
                        myTbl.lastShootingType = "noweapon"
                        myTbl.shootAt( self, myTbl.LastEnemyShootPos, myTbl.PreventShooting )
                        return

                    else
                        return

                    end
                end

                local forcedToLook = myTbl.Term_LookAround( self, myTbl ) -- handle looking around while pathing, with no enemy
                if forcedToLook then return end

                local doShootingPrevent = myTbl.PreventShooting

                -- drop crap wep
                if wep.terminatorCrappyWeapon == true and myTbl.HasFists then
                    myTbl.DoFists( self )

                elseif wep.Clip1 and wepMeta.Clip1( wep ) <= 0 and wepMeta.GetMaxClip1( wep ) > 0 and not myTbl.IsReloadingWeapon then
                    myTbl.WeaponReload( self )

                -- allow us to not stop shooting at the witness player, glee
                elseif IsValid( myTbl.OverrideShootAtThing ) and entMeta.Health( myTbl.OverrideShootAtThing ) > 0 then
                    myTbl.shootAt( self, self:EntShootPos( myTbl.OverrideShootAtThing ) )
                    myTbl.lastShootingType = "witnessplayer"

                elseif IsValid( enemy ) and not ( myTbl.blockAimingAtEnemy and myTbl.blockAimingAtEnemy > CurTime() ) then
                    local wepRange = myTbl.GetWeaponRange( self, myTbl )
                    local seeOrWeaponDoesntCare = myTbl.IsSeeEnemy or wep.worksWithoutSightline
                    if wep and myTbl.IsRangedWeapon( self, wep ) and seeOrWeaponDoesntCare then
                        local shootableVolatile = myTbl.getShootableVolatile( self, enemy )

                        if IsValid( shootableVolatile ) and not doShootingPrevent then
                            myTbl.shootAt( self, myTbl.getBestPos( self, shootableVolatile ), nil )
                            myTbl.lastShootingType = "shootvolatile"

                        -- does the weapon know better than us?
                        elseif wep.terminatorAimingFunc then
                            if wep.worksWithoutSightline then
                                doShootingPrevent = nil

                            end
                            myTbl.shootAt( self, wep:terminatorAimingFunc(), doShootingPrevent )
                            myTbl.lastShootingType = "aimingfuncranged"

                        else
                            if myTbl.DistToEnemy > wepRange and not myTbl.IsReallyAngry( self ) then -- too far, dont shoot
                                doShootingPrevent = true

                            end
                            myTbl.shootAt( self, myTbl.LastEnemyShootPos, doShootingPrevent )
                            myTbl.lastShootingType = "normalranged"

                        end
                    --melee
                    elseif wep and myTbl.IsMeleeWeapon( self, wep ) then
                        local blockShoot = doShootingPrevent or true
                        local meleeAtPos = myTbl.LastEnemyShootPos

                        -- dont just swing our weap around
                        if myTbl.DistToEnemy < wepRange * 1.5 and myTbl.IsSeeEnemy then
                            blockShoot = nil
                            -- fix bot looking around like an idiot when meleeing?
                            meleeAtPos = myTbl.EntShootPos( self, enemy )

                        -- fallback?
                        elseif myTbl.DistToEnemy < wepRange * 1 then
                            blockShoot = nil
                            meleeAtPos = myTbl.EntShootPos( self, enemy )

                        end

                        myTbl.lastShootingType = "melee"
                        myTbl.shootAt( self, meleeAtPos, blockShoot )

                    end
                else
                    if wep.Clip1 and ( wepMeta.GetMaxClip1( wep ) > 0 ) and ( wepMeta.Clip1( wep ) < wepMeta.GetMaxClip1( wep ) / 2 ) and not myTbl.IsReloadingWeapon then
                        myTbl.WeaponReload( self )

                    end
                end
            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "shooting_handler" )
            end,
        },
        ["enemy_handler"] = {
            StartsOnInitialize = true,
            OnKillEnemy = function( self, data )
                if data.myTbl.IsFodder then return end -- search NOW!
                data.UpdateEnemies = CurTime()

            end,
            OnInstantKillEnemy = function( self, data )
                if data.myTbl.IsFodder then return end
                data.UpdateEnemies = CurTime()

            end,
            OnStart = function( self, data )
                data.UpdateEnemies = CurTime()
                data.HasEnemy = false
                data.playerCheckIndex = 0
                data.blockSwitchingEnemies = 0
                local myTbl = data.myTbl
                myTbl.IsSeeEnemy = false
                myTbl.NothingOrBreakableBetweenEnemy = false
                myTbl.DistToEnemy = 0
                myTbl.SetEnemy( self, NULL )
                data.nextCheck = 0

            end,
            BehaveUpdatePriority = function( self, data )
                local cur = CurTime()
                if data.nextCheck > cur then return end
                local myTbl = data.myTbl
                local fodder = myTbl.IsFodder

                local add
                if fodder then
                    add = 0.25

                else
                    add = 0.1

                end
                data.nextCheck = cur + add

                myTbl.ForgetOldEnemies( self, myTbl )

                local prevEnemy = myTbl.GetEnemy( self )
                local newEnemy = prevEnemy
                local myShoot = myTbl.GetShootPos( self )
                local myPos = entMeta.GetPos( self )

                myTbl.IsSeeEnemy = false -- assume false
                myTbl.NothingOrBreakableBetweenEnemy = false
                myTbl.EnemiesVehicle = false

                if ( not data.UpdateEnemies ) or ( cur > data.UpdateEnemies ) or ( data.HasEnemy and not IsValid( prevEnemy ) ) then
                    data.UpdateEnemies = cur + 0.5

                    myTbl.FindEnemies( self, myTbl )

                    local potentialNewEnemy = myTbl.FindPriorityEnemy( self, myTbl )
                    local validPotentialNew = IsValid( potentialNewEnemy )
                    local toPotentialNew

                    local pickedPlayer

                    if not fodder and not validPotentialNew and not myTbl.IgnoringPlayers( self ) then -- cheap infinite view distance
                        -- only run this code if no enemies, go thru player table one-by-one and check los to see if they can be enemy
                        local allPlayers = player.GetAll()
                        -- check only one ply per run
                        pickedPlayer = allPlayers[data.playerCheckIndex]

                        local new = data.playerCheckIndex + 1
                        if new > #allPlayers then
                            data.playerCheckIndex = 1

                        else
                            data.playerCheckIndex = new

                        end
                    elseif validPotentialNew then
                        toPotentialNew = vecMeta.Distance( myPos, entMeta.GetPos( potentialNewEnemy ) )

                    end
                    if IsValid( pickedPlayer ) then
                        local isLinkedPlayer = pickedPlayer == myTbl.linkedPlayer
                        local alive = entMeta.Health( pickedPlayer ) > 0

                        if alive and myTbl.ShouldBeEnemy( self, pickedPlayer ) and myTbl.IsInMyFov( self, pickedPlayer ) then
                            local theirShoot = myTbl.EntShootPos( self, pickedPlayer )
                            local canSee = terminator_Extras.PosCanSee( myShoot, theirShoot )
                            local clearOrBreakable = canSee and myTbl.ClearOrBreakable( self, myShoot, theirShoot )
                            if clearOrBreakable then -- perfect visibility
                                myTbl.UpdateEnemyMemory( self, pickedPlayer, entMeta.GetPos( pickedPlayer ) )

                            elseif canSee then -- they are obscured by a prop
                                myTbl.RegisterForcedEnemyCheckPos( self, pickedPlayer )

                            elseif isLinkedPlayer and alive then -- GLEE HACK
                                myTbl.SaveSoundHint( self, entMeta.GetPos( pickedPlayer ), true )

                            end
                        end
                    end

                    local decentOldEnemy = IsValid( potentialNewEnemy ) and IsValid( prevEnemy ) and potentialNewEnemy ~= prevEnemy and entMeta.Health( prevEnemy ) > 0
                    local friction

                    -- conditional friction for switching enemies.
                    -- fixes bot jumping between two enemies that get obscured as it paths, and doing a little dance

                    if decentOldEnemy and myTbl.PrefersVehicleEnemies then -- .PrefersVehicleEnemies, always stick to enemies in vehicles, good for big boss npcs
                        local oldInVehicle = myTbl.EnemiesVehicle
                        local newEnemyInVehicle = entMeta.GetClass( potentialNewEnemy ) == "player" and IsValid( potentialNewEnemy:GetVehicle() )
                        if oldInVehicle and not newEnemyInVehicle and myTbl.DistToEnemy < ( toPotentialNew + -3000 ) then -- block switching away from vehicle enemy until they get really far away from the new enemy
                            friction = true
                            data.blockSwitchingEnemies = 80 -- REALLY STICK ON THIS ENEMY!

                        end
                    end
                    if decentOldEnemy and not friction then
                        if not myTbl.IsSeeEnemy then -- cant see old enemy, switch now!
                            friction = false

                        else -- stick to the old enemy for a second, unless they're more obscured than the old one!
                            local stillGoodFrictionCount = data.blockSwitchingEnemies > 0
                            local moreObscured = ( myTbl.NothingOrBreakableBetweenEnemy and not myTbl.ClearOrBreakable( self, myShoot, myTbl.EntShootPos( self, potentialNewEnemy ) ) )
                            friction = stillGoodFrictionCount and not moreObscured

                        end
                    end

                    if friction and toPotentialNew < myTbl.CloseEnemyDistance then -- new enemy is too far, dont switch
                        friction = true

                    end

                    if friction then
                        local removed = 1
                        if not myTbl.NothingOrBreakableBetweenEnemy then -- our current enemy is crap
                            removed = removed + 4

                        end
                        if vecMeta.Distance( myPos, entMeta.GetPos( potentialNewEnemy ) ) < myTbl.DuelEnemyDist then -- new enemy is too close
                            removed = removed * 4

                        end
                        data.blockSwitchingEnemies = math.max( data.blockSwitchingEnemies - removed, 0 )
                        potentialNewEnemy = prevEnemy

                    elseif IsValid( potentialNewEnemy ) then -- no friction blocking us, new enemy!
                        newEnemy = potentialNewEnemy

                    elseif myTbl.forcedCheckPositions and table.Count( myTbl.forcedCheckPositions ) >= 1 then -- nuke these
                        for positionKey, position in pairs( myTbl.forcedCheckPositions ) do
                            if SqrDistLessThan( distToSqr( position, myPos ), 200 ) then
                                myTbl.forcedCheckPositions[ positionKey ] = nil
                                break

                            end
                        end
                    end
                end

                if IsValid( newEnemy ) then
                    local newEnemysTbl = entMeta.GetTable( newEnemy )
                    local newEnemsHealth = entMeta.Health( newEnemy )
                    local enemyPos = entMeta.GetPos( newEnemy )
                    local enemIsPlayer = entMeta.GetClass( newEnemy ) == "player"
                    local theirCar = enemIsPlayer and newEnemy:GetVehicle()
                    if IsValid( theirCar ) then
                        local carsParent = entMeta.GetParent( theirCar )
                        if IsValid( carsParent ) and carsParent:IsVehicle() then -- sim fphys ( or glide... )....
                            theirCar = carsParent

                        end
                    end

                    local newEnemsShoot = myTbl.EntShootPos( self, newEnemy, newEnemysTbl )
                    myTbl.DistToEnemy = vecMeta.Distance( myPos, enemyPos )
                    myTbl.IsSeeEnemy = myTbl.CanSeePosition( self, newEnemsShoot, myTbl )
                    myTbl.EnemiesVehicle = IsValid( theirCar ) and theirCar

                    if myTbl.IsSeeEnemy and not myTbl.WasSeeEnemy then
                        local added = math.Rand( 0.4, 0.7 )
                        if myTbl.DistToEnemy > 2500 then
                            added = math.Rand( 0.9, 1.5 )

                        end
                        myTbl.terminator_DontImmiediatelyFire = math.max( cur + added, myTbl.terminator_DontImmiediatelyFire )

                    end

                    myTbl.WasSeeEnemy = myTbl.IsSeeEnemy

                    if myTbl.EnemiesVehicle and myTbl.IsSeeEnemy then
                        myTbl.term_VehicleIHateAlot = myTbl.EnemiesVehicle

                    end

                    -- we cheatily store the enemy's stuff for a second to make bot feel smarter
                    -- people can intuit where someone ran off to after 1 second, so bot can too
                    local posCheatsLeft = myTbl.EnemyPosCheatsLeft or 0
                    if myTbl.IsSeeEnemy then
                        posCheatsLeft = 5
                        myTbl.LastEnemyShootPos = newEnemsShoot

                    elseif myTbl.DistToEnemy < 500 and posCheatsLeft >= 1 then -- doesn't time out if we are too close to them
                        --debugoverlay.Line( enemyPos, self:GetPos(), 0.3, Color( 255,255,255 ), true )
                        posCheatsLeft = math.max( 1, posCheatsLeft )

                    end

                    if ( myTbl.IsSeeEnemy or posCheatsLeft > 0 ) and newEnemsHealth > 0 then -- health check fixed some silly problems
                        myTbl.NothingOrBreakableBetweenEnemy = myTbl.ClearOrBreakable( self, myShoot, newEnemsShoot )
                        myTbl.EnemyLastPosOffsetted = myTbl.EnemyLastPos + terminator_Extras.dirToPos( myTbl.EnemyLastPos, enemyPos ) * 150
                        myTbl.EnemyLastPos = enemyPos
                        myTbl.RegisterForcedEnemyCheckPos( self, newEnemy )
                        myTbl.UpdateEnemyMemory( self, newEnemy, enemyPos )
                        --debugoverlay.Line( enemyPos, enemyPos + ( myTbl.EnemyLastDir * 100 ), 5, Color( 255, 255, 255 ), true )

                    end

                    if newEnemy and newEnemy.Alive and newEnemsHealth > 0 then
                        myTbl.EnemyPosCheatsLeft = posCheatsLeft + -1

                    else -- they died, cheating stops here
                        myTbl.EnemyPosCheatsLeft = nil

                    end

                    if not data.HasEnemy then
                        local sinceLastFound = cur - myTbl.LastEnemySpotTime

                        -- override enemy's relations to me
                        myTbl.MakeFeud( self, newEnemy )
                        myTbl.RunTask( self, "EnemyFound", newEnemy, sinceLastFound )
                        hook.Run( "terminator_spotenemy", self, newEnemy )

                    elseif prevEnemy ~= newEnemy then
                        local blockSwitch = math.random( 2, 4 )
                        if myTbl.IsReallyAngry( self ) then
                            blockSwitch = blockSwitch + math.random( 5, 8 )

                        elseif myTbl.IsAngry( self ) then
                            blockSwitch = blockSwitch + 3

                        end
                        data.blockSwitchingEnemies = blockSwitch
                        -- override enemy's relations to me
                        myTbl.MakeFeud( self, newEnemy )
                        myTbl.RunTask( self, "EnemyChanged", newEnemy, prevEnemy )
                        hook.Run( "terminator_enemychanged", self, newEnemy, prevEnemy )

                    elseif prevEnemy == newEnemy then
                        hook.Run( "terminator_enemythink", self, newEnemy )

                    end

                    data.HasEnemy = true

                    if myTbl.IsSeeEnemy then
                        myTbl.LastEnemySpotTime = cur

                    end
                else
                    if data.HasEnemy then
                        local memory, _ = myTbl.getMemoryOfObject( self, myTbl, prevEnemy )

                        if prevEnemy:IsPlayer() --[[ leaving this index, its rare ]] or memory == MEMORY_WEAPONIZEDNPC then
                            -- reset searching progress!
                            myTbl.SearchCheckedNavs = myTbl.SearchBadNavAreas
                            myTbl.SearchCheckedNavsCount = 0

                        end
                        myTbl.RunTask( self, "EnemyLost", prevEnemy )
                        hook.Run( "terminator_loseenemy", self, prevEnemy )

                    end

                    data.HasEnemy = false

                end
                local decayTime = myTbl.VisibilityStartingHealthDecay or 0

                if myTbl.IsSeeEnemy then
                    -- save old health
                    local myHealth = entMeta.Health( self )
                    local oldHealth = myTbl.VisibilityStartingHealth
                    local ratio = myHealth / entMeta.GetMaxHealth( self )

                    myTbl.VisibilityStartingHealthDecay = cur + ratio * 5

                    if not isnumber( oldHealth ) then
                        myTbl.VisibilityStartingHealth = myHealth

                    end

                elseif myTbl.VisibilityStartingHealth ~= nil and decayTime and decayTime < CurTime() then
                    --print( myTbl.VisibilityStartingHealth, "a" )
                    myTbl.VisibilityStartingHealth = nil

                end

                myTbl.SetEnemy( self, newEnemy )

            end,
            StartControlByPlayer = function( self, data, ply )
                self:TaskFail( "enemy_handler" )
            end,
        },
        ["awareness_handler"] = {
            StartsOnInitialize = true,
            BehaveUpdatePriority = function( self, data, interval )
                local myTbl = data.myTbl
                local nextAware = myTbl.term_NextAwareness or 0
                if nextAware < CurTime() then
                    myTbl.understandSurroundings( self, myTbl )
                end
            end,
        },
        ["reallystuck_handler"] = { -- it's really stuck!!!!!!!
            StartsOnInitialize = true,
            OnStart = function( self, data )
                data.historicPositions = {}
                data.historicNavs = {}
                data.historicStucks = {}
                data.maybeUnderCount = 0
                data.extremeUnstucking = 0
                data.nextUnstuckGotoEscape = 0
                data.freedomGotoPosSimple = nil
            end,
            BehaveUpdatePriority = function( self, data )
                local myTbl = data.myTbl
                if data.freedomGotoPosSimple and data.extremeUnstucking > CurTime() then -- try and unstuck without teleporting!
                    local dist = self:GetPos():Distance2D( data.freedomGotoPosSimple )
                    if dist < 150 then
                        data.freedomGotoPosSimple = nil
                        myTbl.KillAllTasksWith( self, "movement" )
                        myTbl.StartTask2( self, "movement_handler", nil, "yay, i got back on the navmesh!" )
                        return

                    else
                        if data.oldNavArea and data.oldNavArea ~= self:GetCurrentNavArea() then -- we're doing something!
                            myTbl.overrideVeryStuck = nil
                            data.oldNavArea = nil

                        end

                        myTbl.GotoPosSimple( self, myTbl, data.freedomGotoPosSimple, 0 )
                        myTbl.nextNewPath = CurTime() + 0.5

                    end
                end
                local nextCache = data.nextCache or 0
                if nextCache < CurTime() then -- heavy staggered checks
                    local myPos = self:GetPos()
                    local currentNav = navmesh.GetNearestNavArea( myPos, false, 50, false, false, -2 ) -- pretty tight criteria
                    local size = 80

                    --debugoverlay.Cross( myPos, 10, 10, Color( 255,255,255 ), true )

                    data.nextCache = CurTime() + 1

                    local noNav = myTbl.loco:IsOnGround() and ( not IsValid( currentNav ) or #currentNav:GetAdjacentAreas() <= 0 )
                    local doAddCount = 1

                    if noNav then -- more likely to be stuck!
                        size = size / 8
                        doAddCount = doAddCount * 4
                        if not terminator_Extras.IsLivePatching then
                            self:TryGeneratingAreas()

                        end
                    end
                    if myTbl.isUnstucking then
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
                    local overrideStuck = myTbl.overrideVeryStuck

                    local nextDisplacementCheck = data.nextUnderDisplacementCheck or 0
                    if nextDisplacementCheck < CurTime() then
                        data.nextUnderDisplacementCheck = CurTime() + 5
                        local isUnderDisplacement, maybeUnderDisplacement = self:IsUnderDisplacement()

                        if maybeUnderDisplacement then
                            data.maybeUnderCount = data.maybeUnderCount + 1

                        elseif isUnderDisplacement then
                            data.maybeUnderCount = data.maybeUnderCount + 3

                        else
                            data.maybeUnderCount = 0

                        end
                    end

                    local underDisplacement = data.maybeUnderCount > 6

                    if #data.historicPositions > size then -- we built up a stack of historic positions, use them to determine if we're stuck!
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
                        for _, historicNav in ipairs( data.historicNavs ) do
                            if historicNav ~= currentNav then
                                sortaStuck = nil
                                break

                            end
                        end
                        -- instant unstuck check if we're REALLY off the navmesh
                        if noNav and not self:PathIsValid() and not stuck and not navmesh.GetNearestNavArea( myPos, false, 200, false, false, -2 ) then
                            stuck = true

                        end
                    end

                    if stuck or sortaStuck or underDisplacement or overrideStuck then -- i have been in the same EXACT spot for S I Z E seconds
                        self:ReallyAnger( 60 )

                        myTbl.overrideVeryStuck = nil
                        local distToEnemy = 0
                        local enemyPos = self:GetPos()
                        if IsValid( self:GetEnemy() ) then
                            distToEnemy = myTbl.DistToEnemy
                            enemyPos = myTbl.EnemyLastPos or self:GetEnemy():GetPos()

                        end

                        local freedomPos

                        local nearestNavArea = navmesh.GetNearestNavArea( self:GetPos(), false, 10000, false, true, 2 )
                        local myShootPos = self:GetShootPos()
                        local maxs = Vector( 1000, 1000, 1000 )
                        local bestDist = math.huge
                        for _, area in ipairs( navmesh.FindInBox( myPos + maxs, myPos + -maxs ) ) do -- try and find a good freedomPos
                            if area == nearestNavArea then continue end
                            yieldIfWeCan()
                            if not IsValid( area ) then continue end

                            local areasCenter = area:GetCenter()

                            if areasCenter:Distance( enemyPos ) < distToEnemy then continue end -- dont unstuck us closer to the enemy
                            local distToMe = areasCenter:Distance( myPos )

                            if not freedomPos then -- always pick some area
                                freedomPos = areasCenter

                            elseif distToMe < bestDist and area:IsVisible( myShootPos ) then -- perfect candidate, pick this one!
                                bestDist = distToMe
                                freedomPos = areasCenter

                            end
                        end


                        --debugoverlay.Cross( freedomPos, 100, 20, Color( 255, 0, 0 ), true )
                        --print( self:GetCreationID(), "bigunstuck ", stuck, sortastuck, underDisplacement, overrideStuck, noNavAndNotStaring )

                        local extremeStuck = underDisplacement or not freedomPos
                        local canGotoEscape = data.nextUnstuckGotoEscape < CurTime() and data.extremeUnstucking < CurTime()

                        -- teleports us to the unstuck position if we dont see an enemy and we've tried walking there
                        if not myTbl.IsSeeEnemy and extremeUnstucking:GetBool() and ( extremeStuck or not canGotoEscape ) then
                            data.extremeUnstucking = 0
                            data.freedomGotoPosSimple = nil
                            data.oldNavArea = nil
                            if freedomPos then -- teleport us there
                                self:SetPosNoTeleport( freedomPos )
                                self:InvalidatePath( "i was hard unstucked! bailing path." )
                                myTbl.loco:SetVelocity( vec_zero )
                                myTbl.loco:ClearStuck()

                            elseif GAMEMODE.getValidHunterPos then -- GLEE specific fallback
                                freedomPos = GAMEMODE:getValidHunterPos()

                                if freedomPos then
                                    self:SetPosNoTeleport( freedomPos )
                                    self:InvalidatePath( "i was hard unstucked! bailing path. 2" )

                                    myTbl.loco:SetVelocity( vec_zero )
                                    myTbl.loco:ClearStuck()

                                end
                            -- only remove if its not pathing!
                            -- set ReallyStuckNeverRemove in a bot if you never want it to be removed
                            elseif not self:PathIsValid() and not myTbl.ReallyStuckNeverRemove then
                                SafeRemoveEntity( self )

                            end
                        -- walk to the freedomPos instead
                        elseif data.extremeUnstucking < CurTime() then
                            if not freedomPos then -- fallback
                                local offset = VectorRand()
                                offset = offset * Vector( 1, 1, 0.5 ) -- flatten the vec
                                offset:Normalize()

                                freedomPos = self:GetPos() + offset * math.random( 300, 600 )

                            end

                            data.nextUnstuckGotoEscape = CurTime() + 80 -- if the walk to freedomPos finishes, but we're still stuck, do the teleporting
                            data.freedomGotoPosSimple = freedomPos
                            data.extremeUnstucking = CurTime() + 10 -- try and walk to the freedomPos for this long
                            data.oldNavArea = currentNav
                            data.nextCache = CurTime() + 5

                            self:KillAllTasksWith( "movement" ) -- jump us out of any infinite loops
                            self:StartTask2( "movement_wait", { time = 11 }, "gotta let the reallystuck handler do its thing" )

                        end

                        data.nextUnderDisplacementCheck = 0 -- CHECK NOW!

                        data.historicPositions = {}
                        data.historicNavs = {}

                    end
                end
            end,
        },
        ["movement_handler"] = {
            StartsOnInitialize = true,
            BehaveUpdateMotion = function( self, data, interval )
                if not self:nextNewPathIsGood() then
                    self:TaskComplete( "movement_handler" )
                    self:StartTask2( "movement_wait", { time = math.abs( self.nextNewPath - CurTime() ) }, "wait..." )
                    return

                elseif self.term_WaitingForEnemy then
                    self:TaskComplete( "movement_handler" )
                    self:StartTask2( "movement_waitforenemy", nil, "wait... ( for enemy )" )

                else
                    local canWep, potentialWep = self:canGetWeapon()
                    if IsValid( self:GetEnemy() ) and self:EnemyAcquired( "movement_handler" ) then
                        return

                    elseif self.forcedCheckPositions and table.Count( self.forcedCheckPositions ) >= 1 then
                        self:TaskComplete( "movement_handler" )
                        self:StartTask2( "movement_approachforcedcheckposition", nil, "i should check that spot" )
                        return

                    elseif canWep and self:getTheWeapon( "movement_handler", potentialWep ) then
                        return

                    else
                        local wep = self:GetWeapon()
                        if self:WeaponIsPlacable( wep ) then
                            self:TaskComplete( "movement_handler" )
                            self:StartTask2( "movement_placeweapon", nil, "i can place this" )
                            return

                        elseif self:CanBashLockedDoor( self:GetPos(), 500 ) then
                            if not self:BashLockedDoor( "movement_handler" ) then
                                self:TaskComplete( "movement_handler" )
                                self:StartTask2( "movement_inertia", { Want = math.random( 1, 3 ) }, "failed to bash door" )

                            end
                            return

                        elseif self:beatupVehicleIfWeCan( "movement_handler" ) then
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

                if data.object.huntersglee_breakablenails then
                    self:GetTheBestWeapon()
                    data.insane = true

                end

                data.readHealth = data.object:Health()
                if data.insane then
                    data.timeout = CurTime() + 50

                else
                    data.timeout = CurTime() + 8

                end
            end,
            BehaveUpdateMotion = function( self, data, interval )

                if not IsValid( aBashingFrenzyTerminator ) and #self:GetNearbyAllies() >= 2 then
                    -- global var!!!
                    aBashingFrenzyTerminator = self
                    -- automatically bash another thing after we're done with this one
                    data.frenzy = true

                end

                -- thinking
                if not data.fail and not data.success then
                    local tooMuchHealthLost = 10
                    if data.insane then
                        tooMuchHealthLost = 100

                    end
                    local canBash, toBash = self:CanBashLockedDoor( self:GetPos(), 4000 )
                    if canBash and toBash and data.objectand and toBash ~= data.object and self:BashLockedDoor( "movement_bashobject" ) then
                        return

                    elseif self:getLostHealth() > tooMuchHealthLost or self:inSeriousDanger() then
                        self:EnemyAcquired( "movement_bashobject" )

                        self:ignoreEnt( data.object, 15 )
                        return

                    elseif self.IsSeeEnemy and self:GetEnemy() and not data.frenzy and not data.insane then
                        self:EnemyAcquired( "movement_bashobject" )
                        return

                    elseif not data.frenzy and not data.insane and self:interceptIfWeCan( "movement_bashobject", data ) then
                        return

                    -- get broken nerd
                    elseif not IsValid( data.object ) or ( data.object:GetClass() == "prop_door_rotating" and not terminator_Extras.CanBashDoor( data.object ) ) then
                        data.success = true

                    elseif data.readHealth > 0 and data.object:Health() <= 0 then
                        data.success = true

                    elseif self:validSoundHint() and data.gotAHitIn and not data.frenzy and not data.insane then
                        self:TaskComplete( "movement_bashobject" )
                        self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                        return

                     -- dont just do this forever
                    elseif data.timeout < CurTime() or not data.object:IsSolid() then
                        data.fail = true

                    end

                    if IsValid( data.object ) then
                        -- BEATUP
                        local old = SysTime()
                        local valid, attacked, nearAndCanHit, closeAndCanHit, isNear, isClose, visible = data.myTbl.beatUpEnt( self, data.myTbl, data.object )
                        data.gotAHitIn = data.gotAHitIn or attacked

                        if data.insane and not isClose and visible and self:GetWeaponRange() > 500 then
                            self:shootAt( toBeat )

                        end
                        -- edge case
                        if not valid and visible then
                            data.myTbl.GotoPosSimple( self, data.myTbl, data.object:WorldSpaceCenter(), 5 )
                            self:Anger( 1 )

                        elseif not valid and not visible then
                            data.success = true
                            data.frenzy = true -- mad!
                            self:Anger( 30 )
                            data.fail = true

                        end
                    end
                end
                -- all done
                if data.fail then
                    self:TaskFail( "movement_bashobject" )
                    self:StartTask2( "movement_handler", nil, "nope cant bash that" )
                    if data.frenzy then
                        aBashingFrenzyTerminator = nil

                    end
                    return

                end
                if data.success then
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
                    elseif canWep and self:getTheWeapon( "movement_bashobject", potentialWep ) then
                        return

                    else
                        if data.insane then
                            self:TaskComplete( "movement_bashobject" )
                            self:StartTask2( "movement_searchlastdir", { Want = 8 }, "destroyed thing, time to search behind it!" )
                            return

                        else
                            self:TaskComplete( "movement_bashobject" )
                            self:StartTask2( "movement_handler", nil, "nothin better to do" )
                            return

                        end
                    end
                end
            end,
            ShouldRun = function( self, data )
                local length = self:MyPathLength() or 0
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

                data.timeout = CurTime() + 15
                data.objectKey = self:getAwarenessKey( data.object )
                data.objectHealth = data.object:Health() or 0
                data.initToggleState = data.object:GetInternalVariable( "m_toggle_state" )

                if not istable( self.understandAttempts ) then
                    self.understandAttempts = {}
                end

                data.understandAttempts = self.understandAttempts[data.objectKey] or 0
                --print( data.object )

            end,
            BehaveUpdateMotion = function( self, data, interval )
                local pathLengthThresh = 125
                local definitelyAttacked = ( data.definitelyAttacked or 0 ) < CurTime() and data.attacked
                local internalUnderstandAtt = data.understandAttempts or 0
                local pathLength = self:MyPathLength() or 0

                local unreachable = internalUnderstandAtt > 2 and SqrDistLessThan( self:GetPos():DistToSqr( data.object ), 400 )

                if self:CanBashLockedDoor( self:GetPos(), 500 ) and self:BashLockedDoor( "movement_understandobject" ) then
                    return

                elseif self.IsSeeEnemy and self:GetEnemy() then
                    if data.object == self:GetEnemy() then
                        self:ignoreEnt( data.object )

                    end
                    self:EnemyAcquired( "movement_understandobject" )
                    return

                elseif self:interceptIfWeCan( "movement_understandobject", data ) then
                    return

                elseif self:beatupVehicleIfWeCan( "movement_understandobject" ) then
                    return

                elseif not IsValid( data.object ) or not data.object:IsSolid() then -- we lost the object OR we broke it
                    if not data.trackingBreakable then
                        data.fail = true

                    else
                        local lastTime = self.lastDamagedTime or 0
                        local lastTimeAdd = lastTime + 1
                        --print("break" )

                        if lastTimeAdd > CurTime() then -- breaking it damaged me!!!!
                            self:memorizeEntAs( data.objectKey, MEMORY_VOLATILE )
                            self.lastHeardSoundHint = nil
                            --print("volatile" )

                        else
                            self:memorizeEntAs( data.objectKey, MEMORY_BREAKABLE )

                        end
                        data.success = true

                    end
                elseif self:getLostHealth() > 2 or self:inSeriousDanger() then
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_handler", nil, "i was scared" )
                    return

                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )
                    return

                elseif self.awarenessMemory[ self:getAwarenessKey( data.object ) ] ~= MEMORY_MEMORIZING then -- we memorized this already
                    data.fail = true

                elseif data.object:GetParent() == self then
                    self:ignoreEnt( data.object )
                    data.fail = true

                elseif data.timeout < CurTime() then -- dont just do this forever
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
                -- do understanding
                if not data.fail and not data.success then
                    local valid, attacked, nearAndCanHit, closeAndCanHit, isClose
                    if not self.isUnstucking and IsValid( data.object ) then
                        -- UNDERSTAND
                        valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose = self:beatUpEnt( data.myTbl, data.object )
                        --print( valid, attacked, nearAndCanHit, closeAndCanHit, _, isClose )
                        --debugoverlay.Cross( data.object:GetPos(), 100, 1, Color( 255,0,0 ), true )
                        if valid == false then
                            data.fail = true

                        end
                    elseif self.isUnstucking then
                        self:ControlPath2( not self.IsSeeEnemy )

                    end

                    if not data.arrived and isClose and pathLength < pathLengthThresh then
                        data.arrived = true
                        data.timeout = CurTime() + 5

                    end
                    if ( nearAndCanHit or closeAndCanHit ) and IsValid( data.object ) then
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
                                data.timeout = CurTime() + 10

                            end
                        end
                        -- this handles the shooting at
                        if attacked and closeAndCanHit and not data.attacked then
                            data.definitelyAttacked = CurTime() + 1.5
                            data.attacked = true

                        end
                        -- spam use on it
                        if ( data.nextUse or 0 ) < CurTime() and nearAndCanHit then
                            data.nextUse = CurTime() + math.random( 0.1, 1 )
                            self:Use2( data.object )
                            data.checkedUse = true

                        end
                    end
                -- all done!
                elseif data.fail then
                    self:TaskFail( "movement_understandobject" )
                    self:StartTask2( "movement_handler", nil, "man i wanted to know about that" )

                elseif data.success then
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_handler", nil, "curiosity sated" )

                end
            end,
            ShouldRun = function( self, data )
                local length = self:MyPathLength() or 0
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
                data.time = CurTime() + ( data.time or math.Rand( 0.1, 0.2 ) )
            end,
            BehaveUpdateMotion = function( self, data, interval )
                if self.IsSeeEnemy and not data.startedLooking then
                    self:EnemyAcquired( "movement_wait" )

                elseif CurTime() >= data.time then
                    self:TaskComplete( "movement_wait" )
                    self:StartTask2( "movement_handler", nil, "all done waiting" )

                end
            end,
        },
        ["movement_waitforenemy"] = {
            OnStart = function( self, data )
            end,
            BehaveUpdateMotion = function( self, data, interval )
                self.term_WaitingForEnemy = nil
                self:StartTask2( "movement_handler", nil, "spotted enemy!" )

            end,
        },
        ["movement_getweapon"] = {
            OnStart = function( self, data )

                data.failedCount = 0
                data.giveUpTime = CurTime() + 5

                if not isstring( data.nextTask ) then
                    data.nextTask = "movement_wait"
                    data.nextTaskData = { time = 0.1 }

                elseif not data.nextTaskData then
                    data.nextTaskData = {}

                end

                data.crapWep = function()
                    local failedWeaponPaths = data.Wep.failedWeaponPaths or 0
                    local wasExpensivePath = self.term_ExpensivePath
                    local added = 1
                    if wasExpensivePath then
                        added = 5

                    end
                    data.Wep.failedWeaponPaths = failedWeaponPaths + added
                    if data.Wep.failedWeaponPaths > 5 then
                        data.Wep.terminatorCrappyWeapon = true

                    end
                end

                data.finishAfterwards = function( data2, afterwardsReason )
                    if data2.taskKilled then return end
                    data2.taskKilled = true
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

                    yieldIfWeCan()

                    if IsValid( data2.Wep ) and not IsValid( data2.Wep:GetParent() ) then
                        data2.Wep.blockWeaponNoticing = CurTime() + 2.5 -- this wep was invalid!

                    end
                    if data2.nextTask == "movement_getweapon" then -- no loops pls
                        data2.nextTask = "movement_wait"

                    end

                    -- search for a new weapon NOW!
                    self:ResetWeaponSearchTimers()
                    self:TaskFail( "movement_getweapon" )
                    self:StartTask2( data2.nextTask, data2.nextTaskData, "finishAfterwards " .. afterwardsReason )

                end

                -- make bots bash crate
                -- discards nexttask but w/e
                data.handleCrate = function()
                    if not IsValid( data.Wep ) then return end
                    if data.Wep:GetClass() ~= "item_item_crate" then return end
                    if self.IsSeeEnemy and self:MyPathLength() > 500 and self.DistToEnemy < self.DuelEnemyDist then
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
                    if data.failedCount > 3 then
                        data:finishAfterwards( "wep is invalid" )
                        return

                    end
                    if not IsValid( data.Wep ) then
                        local canGetWeap, findWep = self:canGetWeapon()

                        if canGetWeap == false then
                            if not IsValid( data.Wep ) then
                                data.failedCount = data.failedCount + 1

                            end
                        else
                            data.Wep = findWep
                            data.giveUpTime = CurTime() + 5

                        end
                    elseif not self:CanPickupWeapon( data.Wep ) then
                        self:ResetWeaponSearchTimers()
                        data.Wep = nil
                        data.failedCount = data.failedCount + 0.5

                    end
                    return true

                end

                self:InvalidatePath( "getting weapon, killing old path" )

                if not data:updateWep() then return end
                if not IsValid( data.Wep ) then return end

                if data:handleCrate() == true then return end

                if self:GetRangeTo( data.Wep ) < 25 and self:CanPickupWeapon( data.Wep ) then
                    self:RunTask( "GetWeapon" )
                    self:SetupWeapon( data.Wep )

                    data:finishAfterwards( "i started the task on top of the wep!" )
                    return

                end

            end,
            BehaveUpdateMotion = function( self, data )
                if data.taskKilled then return end

                if not data:updateWep() then return end
                local currWep = data.Wep
                if not IsValid( currWep ) then return end
                local wepsPos = currWep:GetPos()

                if self:CanBashLockedDoor( self:GetPos(), 500 ) and self:BashLockedDoor( "movement_getweapon" ) then
                    return

                end

                local canNewPath = self:primaryPathInvalidOrOutdated( wepsPos )

                if canNewPath then
                    self:InvalidatePath( "getweapon" )

                    if self:EnemyIsLethalInMelee() then
                        local result = terminator_Extras.getNearestPosOnNav( self:GetEnemy():GetPos() )
                        if result and IsValid( result.area ) then
                            self:SetupFlankingPath( wepsPos, result.area, self.DistToEnemy * 0.8 )
                            data.wasAValidPath = true
                            yieldIfWeCan()

                        end
                    end

                    if not self:primaryPathIsValid() then
                        local result = terminator_Extras.getNearestPosOnNav( wepsPos )
                        if result and IsValid( result.area ) and self:areaIsReachable( result.area ) then
                            self:SetupPathShell( wepsPos )
                            data.wasAValidPath = true

                        end
                    end

                    if not self:primaryPathIsValid() then
                        -- something is wrong, bigger radius 
                        if self:CanBashLockedDoor( nil, 1500 ) and self:BashLockedDoor( "movement_getweapon" ) then
                            return

                        else
                            data.crapWep()
                            data:finishAfterwards( "path was invalid!" )
                            return

                        end
                    end
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )

                if data:handleCrate() == true then return end
                if not IsValid( currWep ) then return end

                local rangeToWep = self:GetRangeTo( currWep )
                if rangeToWep < 125 then
                    self:crouchToGetCloserTo( currWep:GetPos() )

                end

                if rangeToWep < self.PathGoalToleranceFinal + 20 and self:CanPickupWeapon( currWep ) then
                    self:RunTask( "GetWeapon" )
                    self:SetupWeapon( currWep )
                    data:finishAfterwards( "reached the wep" )
                    return

                end

                local bestFound = self.terminator_BestWeaponIEverFound or NULL
                -- dont give up if we NEED the weapon!
                local giveUp = data.giveUpTime < CurTime() and currWep ~= bestFound

                if self.IsSeeEnemy and ( self.DistToEnemy < self.CloseEnemyDistance or giveUp ) then
                    self:EnemyAcquired( "movement_getweapon" )
                    return

                end

                if self.isUnstucking then return end

                if result == true then
                    data.crapWep()
                    data:finishAfterwards( "reached the end of my path, no weapon tho" )
                    return

                elseif result == false then
                    data:finishAfterwards( "my path failed!" )
                    return

                elseif not self:primaryPathIsValid() and data.wasAValidPath then
                    data.crapWep()
                    data:finishAfterwards( "my path was invalid!" )
                    return

                end
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
                    self:InvalidatePath( "checking sound, killing old path" )

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
                    timeOffset = math.Rand( 0.05, 0.4 )

                end
                data.time = CurTime() + timeOffset

            end,
            BehaveUpdateMotion = function( self, data )
                if data.time and data.time > CurTime() then return end
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

                -- manage path!
                elseif soundPos then
                    local newPath = data.newPath or self:primaryPathInvalidOrOutdated( soundPos )

                    local killerrr = self:GetEnemy() and self:GetEnemy().isTerminatorHunterKiller
                    local nextPathTime = data.nextPathTime or 0

                    if newPath and nextPathTime < CurTime() and self:nextNewPathIsGood() and not self.isUnstucking then -- HACK
                        self:InvalidatePath( "checking new sound, killing old path" )
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
                                yieldIfWeCan()

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
                            self:SetupPathShell( soundPos )
                            yieldIfWeCan()

                        end
                        if not self:primaryPathIsValid() then
                            data.Unreachable = true

                        end
                        data.nextPathTime = CurTime() + 0.5
                    end
                end

                local toBashAfterSound = nil
                if #self.awarenessBash > 0 and soundPos then
                    for _, currBashEnt in ipairs( self.awarenessBash ) do
                        if not IsValid( currBashEnt ) then continue end

                        local bashDistToSound = currBashEnt:GetPos():DistToSqr( soundPos )
                        if SqrDistGreaterThan( bashDistToSound, 100 ) then continue end

                        local myDistToBash = currBashEnt:GetPos():DistToSqr( myPos )
                        if SqrDistGreaterThan( myDistToBash, 800 ) then continue end

                        toBashAfterSound = currBashEnt

                    end
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local Done = nil
                local searchWant = 60
                if data.Valuable ~= true then
                    searchWant = 5
                end

                local nearPathEnd = self:primaryPathIsValid() and self:MyPathLength() < 75
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

                elseif self:CanBashLockedDoor( self:GetPos(), 500 ) and self:BashLockedDoor( "movement_followsound" ) then
                    Done = true

                elseif self.IsSeeEnemy then
                    Done = true
                    self:EnemyAcquired( "movement_followsound" )

                elseif data.Valuable and self:interceptIfWeCan( "movement_followsound", data ) then
                    Done = true

                elseif self:beatupVehicleIfWeCan( "movement_followsound" ) then
                    Done = true

                elseif data.Unreachable then
                    Done = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_search", { searchWant = searchWant, searchCenter = soundPos }, "cant reach the sound" )
                    --debugoverlay.Cross( soundPos, 100, 10, Color( 0,255,255 ), true )

                elseif IsValid( toBashAfterSound ) then
                    Done = true
                    self:TaskComplete( "movement_followsound" )
                    self:StartTask2( "movement_bashobject", { object = toBashAfterSound }, "the loud thing's breakable?!" )

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

                data.searchRadius = data.searchRadius or 4000
                data.searchWant = data.searchWant or 50
                data.time = data.time or 0
                data.doneSearchesNearby = data.doneSearchesNearby or 0

                --print( "Search!" .. data.searchWant .. " " .. data.searchRadius )
                local toPick = { data.searchCenter, self.EnemyLastPosOffsetted, self:GetPos() }
                local pickedSearchCenter
                for index = 1, table.Count( toPick ) do
                    local picked = toPick[ index ]
                    if isvector( picked ) then
                        pickedSearchCenter = picked
                        break

                    end
                end
                local needsToDoANearbySearch = data.searchCenter and not data.searchedNearCenter and data.searchWant > 0

                -- focus search on where a "hint" was, or first operation, focus our search on where the code says we should be
                -- added so bot always checks the center at least once
                if needsToDoANearbySearch then
                    -- snap it to the navmesh
                    local result = terminator_Extras.getNearestPosOnNav( data.searchCenter )
                    if result and result.pos then
                        --debugoverlay.Cross( result.pos, 100, 10, Color( 255,255,0 ), true )
                        pickedSearchCenter = result.pos
                        data.searchCenter = result.pos

                    end
                end

                local _
                local checkNav

                data.nextForcedSearch = CurTime() + 25
                data.searchWant = data.searchWant + -1
                data.time = CurTime() + data.time

                local scoreData = {}
                scoreData.blockRadiusEnd = true
                scoreData.searchRadius = data.searchRadius
                scoreData.searchCenter = pickedSearchCenter
                scoreData.canDoUnderWater = self:isUnderWater()
                scoreData.decreasingScores = {}
                scoreData.self = self
                scoreData.walkedAreas = self.walkedAreas
                scoreData.walkedAreaTimes = self.walkedAreas

                local checkSpot
                local checkCenter

                local scoreFunction = function( scoreData, area1, area2 )
                    local localSelf = scoreData.self
                    if not localSelf:areaIsReachable( area2 ) then return 0 end
                    if area2:IsBlocked() then return 0 end

                    local score = scoreData.decreasingScores[area1:GetID()] or 10000
                    local area2sId = area2:GetID()

                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = 1

                    end
                    -- cant jump back up
                    local jumpHeight = scoreData.self.loco:GetMaxJumpHeight()
                    local heightDiff = area1:ComputeAdjacentConnectionHeightChange( area2 )
                    if heightDiff < -jumpHeight * 1.5 then
                        score = 1

                    elseif heightDiff > jumpHeight then
                        return 1

                    end

                    -- search parts of the map we haven't seen yet
                    local timeSince = 1
                    if scoreData.walkedAreas[area2sId] then
                        local time = scoreData.self.walkedAreaTimes[area2sId]
                        timeSince = math.abs( time - CurTime() )

                    end

                    if not localSelf.SearchCheckedNavs[area2sId] then
                        local hidingSpots = area2:GetHidingSpots( 1 )
                        for _, spot in ipairs( hidingSpots ) do
                            local myShootPos = localSelf:GetShootPos()
                            local spotOffsetted = spot + plus25Z
                            if not util.IsInWorld( spotOffsetted ) then continue end -- corrupt navarea
                            if terminator_Extras.PosCanSeeComplex( myShootPos, spotOffsetted, localSelf ) then
                                localSelf.SearchCheckedNavs[area2sId] = true
                                localSelf.SearchCheckedNavsCount = localSelf.SearchCheckedNavsCount + 1
                                score = 100 / timeSince -- this spot makes us curious, search here
                                break

                            end
                            local distToNew = spotOffsetted:Distance( scoreData.searchCenter )
                            local distToOld
                            if checkSpot then
                                distToOld = checkSpot:Distance( scoreData.searchCenter )

                            end
                            if not checkSpot then
                                checkSpot = spotOffsetted

                            elseif distToOld and distToNew > ( distToOld + 1000 ) then -- trash search spot, we stop now
                                return math.huge

                            elseif distToNew < distToOld then
                                checkSpot = spotOffsetted
                                return 200 / timeSince -- makes us curious, keep checking here

                            end
                        end
                    else
                        score = math.min( score, 100 ) / timeSince

                    end

                    scoreData.decreasingScores[area2sId] = score + -1

                    if needsToDoANearbySearch then
                        score = score / area2:GetCenter():Distance( scoreData.searchCenter )

                    end
                    return score

                end

                yieldIfWeCan()

                checkCenter, checkNav = self:findValidNavResult( scoreData, self:GetPos(), scoreData.searchRadius, scoreFunction )
                checkSpot = checkSpot or checkCenter

                if not checkSpot then
                    yieldIfWeCan( "wait" )
                    if needsToDoANearbySearch then
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    else
                        -- fail on next tick
                        data.InvalidAfterwards = true
                        return

                    end
                end

                if not IsValid( checkNav ) then
                    yieldIfWeCan( "wait" )
                    if needsToDoANearbySearch then
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    else
                        data.InvalidAfterwards = true
                        return

                    end
                end

                data.hidingToCheck = checkSpot
                data.checkNavId = checkNav:GetID()

            end,
            BehaveUpdateMotion = function( self, data )
                local doneCount = data.doneCount or 0
                local hidingToCheck = data.hidingToCheck

                if not hidingToCheck then -- :clueless:
                    data.InvalidAfterwards = true

                end

                if data.InvalidAfterwards and data.doneSearchesNearby < 5 then
                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_searchlastdir", { Want = 8, wasNormalSearch = true }, "i couldnt find somewhere to search" )
                    return

                elseif data.InvalidAfterwards and data.doneSearchesNearby >= 5 then
                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_biginertia", { Want = 10 }, "im all done searching and i was in a loop" )
                    return

                elseif self.IsSeeEnemy and self:GetEnemy() then
                    self:EnemyAcquired( "movement_search" )
                    return

                elseif self:CanBashLockedDoor( data.searchCenter, 800 ) and self:BashLockedDoor( "movement_search" ) then
                    return

                elseif data.tryAndSearchNearbyAfterwards then
                    yieldIfWeCan( "wait" )

                    local rand2DOffset = VectorRand()
                    rand2DOffset.z = 0.1
                    rand2DOffset:Normalize()
                    rand2DOffset = rand2DOffset * math.random( 100, 200 )

                    local searchesNearbyExp = data.doneSearchesNearby ^ 1.8
                    local offsetScalar = 1 + ( searchesNearbyExp * 0.15 )

                    rand2DOffset = rand2DOffset * offsetScalar

                    local newSearchCenter = data.searchCenter + rand2DOffset
                    -- snap new center to the navmesh
                    local result = terminator_Extras.getNearestPosOnNav( newSearchCenter )
                    if not IsValid( result.area ) then
                        -- nope, this pos is out of the navmesh, stay here!
                        newSearchCenter = data.searchCenter

                    end
                    if IsValid( result.area ) and not self:areaIsReachable( result.area ) then
                        -- nope, cant reach this nav!
                        newSearchCenter = data.searchCenter

                    end
                    --print( rand2DOffset )
                    --debugoverlay.Cross( newSearchCenter, 100, 10, Color( 255,255,0 ), true )

                    yieldIfWeCan( "wait" )

                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_search", {
                        doneCount = doneCount,
                        searchWant = data.searchWant + -1,
                        searchRadius = data.searchRadius + 500,
                        searchCenter = newSearchCenter,
                        searchedNearCenter = data.searchedNearCenter,
                        doneSearchesNearby = data.doneSearchesNearby + 1,
                        hateLockedDoorDist = 2000

                    },
                    "i couldnt reach where i wanted to search, ill try somewhere nearby" )
                    return

                end

                -- wait
                if data.time > CurTime() then return end

                local myPos = self:GetPos()
                local checkNavId = data.checkNavId
                local distToHideSqr = myPos:DistToSqr( hidingToCheck )

                if self:primaryPathInvalidOrOutdated( hidingToCheck ) then
                    self:SetupPathShell( hidingToCheck )
                    --debugoverlay.Cross( hidingToCheck, 10, 10, color_white, true )
                    -- search failed, try and get somewhere close!
                    if data.searchCenter and not self:primaryPathIsValid() then
                        self.SearchCheckedNavs[checkNavId] = true
                        self.SearchCheckedNavsCount = self.SearchCheckedNavsCount + 1
                        self.SearchBadNavAreas[checkNavId] = true
                        data.tryAndSearchNearbyAfterwards = true
                        return

                    end
                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local continueSearch = false -- do another search
                local continueReason = ""
                local unreachable = false
                local waitTime = math.random( 0.2, 0.4 )
                local searchWantInternal = data.searchWant or 0
                local hateLockedDoorDist = data.hateLockedDoorDist or 350
                local needsToDoANearbySearch = data.searchCenter and not data.searchedNearCenter and data.searchWant > 0

                local myWep = self:GetWeapon()
                local myShootPos = self:GetShootPos()

                local isSoundHint = self:validSoundHint()
                local isValuableSound
                local distToSound
                local soundSpammed
                if isSoundHint then
                    local nextSearch = data.nextSoundSearch or 0
                    soundSpammed = nextSearch > CurTime()
                    distToSound = myPos:DistToSqr( self.lastHeardSoundHint.source )
                    isValuableSound = self.lastHeardSoundHint.valuable

                end
                local checkedNavsCount = self.SearchCheckedNavsCount or 0
                local soundHintDistNeeded = ( checkedNavsCount ^ 1.5 ) * 120
                soundHintDistNeeded = soundHintDistNeeded^2

                local valuableSoundDistNeeded = ( checkedNavsCount ^ 1.5 ) * 20
                valuableSoundDistNeeded = soundHintDistNeeded^2

                local nextCheck = data.nextCheck or 0

                if nextCheck < CurTime() then
                    data.nextCheck = CurTime() + math.Rand( 0.25, 0.5 )
                    self:SimpleSearchNearbyAreas( myPos, myShootPos )

                end

                local canGet, potentialWep = self:canGetWeapon()
                yieldIfWeCan()

                -- all done!
                if searchWantInternal <= 0 then
                    self:TaskComplete( "movement_search" )
                    if math.random( 0, 100 ) < 40 and not self:IsMeleeWeapon( myWep ) then
                        self:StartTask2( "movement_perch", nil, "i was done searching with some luck and a real gun" )

                    else
                        self:StartTask2( "movement_handler", nil, "i was done searching" )

                    end
                    return

                elseif doneCount > 2 and self:interceptIfWeCan( "movement_search", data ) then
                    return

                elseif self:beatupVehicleIfWeCan( "movement_search" ) then
                    return

                elseif doneCount >= 4 and self:WeaponIsPlacable( myWep ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_placeweapon", nil, "i can place my wep and ive been searching a lil bit" )
                    return

                elseif doneCount >= 40 and IsValid( self.awarenessUnknown[1]  ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_understandobject", nil, "im curious and i've been searching a while" )
                    return

                elseif canGet and not self.IsSeeEnemy and not needsToDoANearbySearch and self:getTheWeapon( "movement_search", potentialWep, "movement_search" ) then
                    return

                elseif self:CanBashLockedDoor( nil, hateLockedDoorDist ) and self:BashLockedDoor( "movement_search" ) then
                    return

                elseif isSoundHint and isValuableSound and not needsToDoANearbySearch and distToSound < valuableSoundDistNeeded then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard a valuable sound" )
                    return

                elseif not soundSpammed and isSoundHint and distToSound < soundHintDistNeeded then
                    self:InvalidatePath( "searching nearby sound" )
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_search", {
                        doneCount = doneCount,
                        searchRadius = 500,
                        searchWant = data.searchWant,
                        Time = 0,
                        searchCenter = self.lastHeardSoundHint.source,
                        searchedNearCenter = false,
                        nextSoundSearch = CurTime() + 0.5

                    }, "i heard something nearby, i will search there!" )
                    self.lastHeardSoundHint = nil
                    return

                elseif not result and terminator_Extras.PosCanSee( myPos, hidingToCheck ) and SqrDistLessThan( distToHideSqr, 150 ) then
                    waitTime = 0
                    continueSearch = true
                    continueReason = "arrived"

                elseif data.nextForcedSearch < CurTime() and not needsToDoANearbySearch then
                    continueSearch = true
                    continueReason = "timed out"

                elseif result then
                    if not terminator_Extras.PosCanSee( myPos, hidingToCheck ) or SqrDistLessThan( distToHideSqr, 150 ) then
                        unreachable = true

                    end
                    continueSearch = true
                    continueReason = "arrived, result"

                elseif self.isUnstucking then
                    unreachable = true

                end

                if not self.SearchCheckedNavs then
                    self.SearchCheckedNavs = self.SearchBadNavAreas
                    self.SearchCheckedNavsCount = 0

                end

                if continueSearch then
                    self:TaskFail( "movement_search" )

                    if not isnumber( checkNavId ) then
                        self:StartTask2( "movement_handler", nil, "i couldnt find somewhere to search" )
                        data.finishUp()
                        return

                    else
                        local newRadius = data.searchRadius + 200
                        doneCount = doneCount + 1

                        if not data.searchCenter then
                            data.searchedNearCenter = true

                        elseif data.searchedNearCenter ~= true then
                            data.searchedNearCenter = self:GetPos():DistToSqr( data.searchCenter ) < 1500^2

                        end

                        self.SearchCheckedNavs[checkNavId] = true
                        self.SearchCheckedNavsCount = self.SearchCheckedNavsCount + 1

                        self:StartTask2( "movement_search", {
                            doneCount = doneCount,
                            searchRadius = newRadius,
                            searchWant = data.searchWant,
                            Time = waitTime,
                            searchCenter = data.searchCenter,
                            searchedNearCenter = data.searchedNearCenter

                        }, continueReason .. ", but i still want to keep searching" )

                    end
                end

                if unreachable then
                    self.SearchBadNavAreas[checkNavId] = true
                    self.SearchCheckedNavs[checkNavId] = true

                end
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
                data.expiryTime = CurTime() + 10
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
                    scoreData.bearingCompare = self.EnemyLastPos

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
                    if not searchPos then
                        data.InvalidAfterwards = true
                        return

                    end

                    self:SetupPathShell( searchPos )

                    if self:primaryPathIsValid() then return end
                    data.InvalidAfterwards = true
                end
            end,
            BehaveUpdateMotion = function( self, data )
                if data.InvalidAfterwards then
                    if self.IsSeeEnemy then
                        self:EnemyAcquired( "movement_searchlastdir" )
                        return

                    end
                    local searchFailures = self.searchLastDirFailures or 0
                    searchFailures = searchFailures + 1

                    self.searchLastDirFailures = searchFailures

                    if searchFailures > 20 then
                        self.searchLastDirFailures = 0
                        self:TaskFail( "movement_searchlastdir" )
                        self:StartTask2( "movement_handler", nil, "i failed searching too much" )
                        return

                    elseif data.wasNormalSearch then
                        self:TaskFail( "movement_searchlastdir" )
                        self:StartTask2( "movement_biginertia", { Want = math.random( 1, 2 ) }, "i got in a loop, time to go somewhere else" )

                    else
                        self:TaskFail( "movement_searchlastdir" )
                        self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 60 }, "nope try normal searching" )
                        return

                    end
                end

                local nextCheck = data.nextCheck or 0

                if nextCheck < CurTime() then
                    data.nextCheck = CurTime() + math.Rand( 0.25, 0.5 )
                    local myShootPos = self:GetShootPos()
                    local myPos = self:GetPos()
                    self:SimpleSearchNearbyAreas( myPos, myShootPos )

                end
                yieldIfWeCan()

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local newSearch = result or data.expiryTime < CurTime()
                local canWep, potentialWep = self:canGetWeapon()

                if canWep and not self.IsSeeEnemy and self:getTheWeapon( "movement_searchlastdir", potentialWep, "movement_searchlastdir" ) then
                    return

                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_searchlastdir" )

                elseif self:interceptIfWeCan( "movement_searchlastdir", data ) then
                    return

                elseif self:beatupVehicleIfWeCan( "movement_searchlastdir" ) then
                    return

                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_searchlastdir" )

                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )

                elseif newSearch and data.Want > 0 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want, wasNormalSearch = data.wasNormalSearch }, "i can search somewhere else" )

                elseif newSearch and data.Want <= 0 then
                    if not data.wasNormalSearch then
                        self:TaskComplete( "movement_searchlastdir" )
                        self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 60, Time = 1.5 }, "im all done searching" )
                        self.searchLastDirFailures = 0

                    else
                        self:TaskComplete( "movement_searchlastdir" )
                        self:StartTask2( "movement_biginertia", { Want = 50 }, "im all done searching and i was in a loop" )

                    end
                elseif IsValid( self.awarenessUnknown[1]  ) and data.Want < 1 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_understandobject", nil, "im curious" )

                elseif result == false then
                    self:TaskFail( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want, wasNormalSearch = data.wasNormalSearch }, "my path failed" )

                end
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
                self:InvalidatePath( "watching enemy, killing old path" )

                local enemy = self:GetEnemy()
                local reallyAngry = self:IsReallyAngry()
                local angry = self:IsAngry()

                data.killCount = 0

                if not data.tooCloseDist then
                    if reallyAngry then
                        data.tooCloseDist = 1250

                    elseif angry then
                        data.tooCloseDist = 500

                    else
                        data.tooCloseDist = 250

                    end

                    data.tooCloseDist = data.tooCloseDist + self:DistAddedByKillerEnemy( enemy )

                end

                local tillWalkToSmallestDistTime = 20
                if reallyAngry then
                    tillWalkToSmallestDistTime = 0

                elseif angry then
                    tillWalkToSmallestDistTime = 1

                elseif self.watchCount and self.watchCount >= 1 then
                    tillWalkToSmallestDistTime = 2

                elseif enemy.terminator_endFirstWatch and ( enemy.terminator_endFirstWatch < CurTime() ) then
                    tillWalkToSmallestDistTime = 4

                end

                data.tillWalkToSmallestDist = CurTime() + tillWalkToSmallestDistTime

                data.tooCloseDist = math.Clamp( data.tooCloseDist, 75, math.huge )
                data.oldDistToEnemy = self.DistToEnemy

                local killerrr = enemy and enemy.isTerminatorHunterKiller
                if killerrr and self:IsRangedWeapon() then -- ok u deserve to be sniped
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_camp", { maxNoSeeing = 400 }, "i want to kill this thing" )

                else
                    self.PreventShooting = true -- this is not a SNIPING behaviour!

                end

                local timeMin, timeMax = 10, 20
                local watchCount = self.watchCount or 0
                if watchCount < 1 then
                    timeMin, timeMax = 10, 15 --40, 60
                end
                data.giveUpWatchingTime = CurTime() + math.random( timeMin, timeMax )

                if enemy then
                    local old = enemy.terminator_TerminatorsWatching or {}
                    table.insert( old, self )
                    enemy.terminator_TerminatorsWatching = old

                end

                self:RunTask( "StartStaring" )

            end,
            BehaveUpdateMotion = function( self, data )
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
                if data.enemyIsBoxedIn == true or theyreInForASurprise or self:Health() < self:GetMaxHealth() * 0.9 then
                    tooCloseDist = math.min( tooCloseDist, 400 )

                end

                local lookingAtBearing = 9
                local lookingAtLenient = 15
                local enemyIsLookingAtMe = enemyBearingToMeAbs < lookingAtBearing

                if goodEnemy and not enemyIsLookingAtMe then
                    data.SneakyStaring = true

                elseif enemyIsLookingAtMe and not data.slinkAway and data.enemyIsBoxedIn ~= true then
                    local min, max = 8, 10
                    local watchCount = self.watchCount or 0
                    if watchCount > 1 then
                        min, max = 1, 2

                    end
                    data.slinkAway = CurTime() + math.random( min, max )

                elseif theyreInForASurprise and not data.doneSurpriseSetup then
                    data.doneSurpriseSetup = true
                    data.slinkAway = CurTime() + math.Rand( 2, 5 )

                elseif data.SneakyStaring then
                    data.SneakyStaring = nil

                end

                local beingFooled = IsValid( enemy.terminator_crouchingbaited ) and enemy.terminator_crouchingbaited ~= self and enemy.terminator_crouchingbaited.IsSeeEnemy
                -- and and and and and and
                local canFool = goodEnemy
                    and enemyIsLookingAtMe
                    and not IsValid( enemy.terminator_crouchingbaited ) -- another one of us is getting em
                    and not enemy.isTerminatorHunterKiller -- they are mean!
                    and math.random( 0, 100 ) > 85 -- dont do it first opportunity, that wouldnt be fun
                    and not self:EnemyIsLethalInMelee( enemy ) -- they are meaner!
                    and not enemy.terminator_CantConvinceImFriendly -- already tried to do it to em
                    and enemy:IsOnGround() -- ignore crouch jumping
                    and enemy.Crouching and enemy:Crouching()
                    and enemy.GetVelocity and enemy:GetVelocity():Length2D() < 75

                -- trick them into thinking we're friendly via the universal language of crouching
                if canFool then
                    data.baitcrouching = CurTime()
                    enemy.terminator_crouchingbaited = self

                elseif beingFooled then
                    -- fool em!!!
                    if enemy.terminator_CantConvinceImFriendly then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "i gotta get close to them, hi, yeah im friendly!" )
                        self.PreventShooting = nil
                        return
                    -- another bot is fooling THEM!
                    else
                        self.PreventShooting = true
                        data.slinkAway = data.slinkAway or 0
                        data.slinkAway = data.slinkAway + 400
                        data.giveUpWatchingTime = CurTime() + 400

                    end
                end

                self:HandleFakeCrouching( data, enemy )

                -- don't watch too much
                local maxWatches = 4 -- should be 4!

                -- the player looked at us earlier and is still looking
                local slinkAwayTime = data.slinkAway or math.huge
                local canWep, potentialWep = self:canGetWeapon()

                -- move forward if enemy moves around!
                -- slinkAwayTime check means it only happens if enemy has looked directly at us at least once
                if not data.Unreachable and goodEnemy and slinkAwayTime > CurTime() then
                    local walkedInStepChance = self.walkedInStepWant or math.random( 4, 10 )
                    local chanceInternal = walkedInStepChance * 0.1
                    local canWalkInStep = IsValid( enemy ) and enemy:GetVelocity():Length() > self.WalkSpeed and math.Rand( 0, 100 ) < chanceInternal
                    if canWalkInStep and enemyBearingToMeAbs < lookingAtLenient then
                        self.walkedInStepWant = walkedInStepChance - 1
                        data.wasWalkingInStep = true

                    end
                    local lastPos = data.lastEnemyDistPos
                    local needsToSave = not lastPos or ( lastPos and enemyPos:DistToSqr( lastPos ) > self.MoveSpeed^2 )

                    local add

                    -- if we've been close to the enemy before in a watch, walk up to them
                    if data.tillWalkToSmallestDist < CurTime() then
                        local oldNearest = self.term_WatchTask_NearestDistToEnemy
                        if not oldNearest or self.DistToEnemy < oldNearest then
                            self.term_WatchTask_NearestDistToEnemy = self.DistToEnemy

                        else
                            add = math.Rand( 0.4, 0.5 )
                            self.term_WatchTask_NearestDistToEnemy = oldNearest + ( add * 200 )

                        end
                    end


                    if data.wasWalkingInStep and needsToSave then
                        data.lastEnemyDistPos = enemyPos
                        add = math.Rand( 0.2, 0.5 )

                    end

                    local tooCloseStepForward = data.oldDistToEnemy - self.MoveSpeed / 2
                    if self.DistToEnemy < tooCloseStepForward then
                        if not data.nextWalkingForward or data.nextWalkingForward < CurTime() then
                            data.oldDistToEnemy = self.DistToEnemy
                            add = math.Rand( 0.5, 1.5 )
                        end
                        data.nextWalkingForward = CurTime() + math.Rand( 1, 5 )

                    else
                        data.nextWalkingForward = nil

                    end

                    if add then
                        local oldTimeNeededToMove = data.timeNeededToMove or 0
                        local timeNeededToMove = math.max( oldTimeNeededToMove + add, CurTime() + add )
                        data.timeNeededToMove = timeNeededToMove

                    end

                    local _, canShootTr = terminator_Extras.PosCanSeeComplex( self:GetShootPos(), self:EntShootPos( enemy ), self, MASK_SHOT )
                    local canShoot = not canShootTr.Hit or canShootTr.Entity == enemy

                    if not canShoot or self.terminator_HandlingLadder or self:WaterLevel() >= 3 or ( data.timeNeededToMove and data.timeNeededToMove > CurTime() ) then
                        if self:primaryPathInvalidOrOutdated( enemyPos ) then
                            local result = terminator_Extras.getNearestPosOnNav( enemyPos )
                            if not IsValid( result.area ) then data.Unreachable = true end

                            self:SetupPathShell( enemyPos )
                            if not self:primaryPathIsValid() then data.Unreachable = true end

                        end

                        self:ControlPath2()

                    end
                end

                if ( enemy and enemy.isTerminatorHunterKiller ) and canWep and self:getTheWeapon( "movement_watch", potentialWep, "movement_handler" ) then
                    return

                elseif slinkAwayTime < CurTime() then
                    -- yup they are staring
                    if data.crouchbaitcount then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_followenemy", nil, "friendly, that's me, im friendly!" )
                        self.PreventShooting = true
                    elseif theyreInForASurprise then
                        -- lots of bots watching
                        if enemy.terminator_TerminatorsWatching and #enemy.terminator_TerminatorsWatching > math.random( 1, 4 ) then
                            self:TaskComplete( "movement_watch" )
                            self:StartTask2( "movement_stalkenemy", nil, "thats enough looking" )
                            self.PreventShooting = true -- keep

                        -- its just me!
                        else
                            data.slinkAway = CurTime() + math.Rand( 2, 4 )
                            data.giveUpWatchingTime = CurTime() + math.Rand( 4, 8 )

                        end
                    -- don't do this forever!
                    elseif enemyBearingToMeAbs < lookingAtLenient then
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
                        self:StartTask2( "movement_stalkenemy", nil, "surprise has happened, time to close in.. carefully!" )
                        self.PreventShooting = nil

                    else
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_flankenemy", nil, "surprise has happened, time to close in!" )
                        self.PreventShooting = nil

                    end
                -- too close bub!
                elseif not beingFooled and ( self.DistToEnemy < tooCloseDist or ( enemy and enemy.isTerminatorHunterKiller ) ) then
                    if self:EnemyIsReachable() then
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_flankenemy", nil, "it is too close" )
                        self.PreventShooting = nil
                        if data.enemyIsBoxedIn == true then
                            -- charge enemy
                            self:ReallyAnger( 40 )

                        end
                    else
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_stalkenemy", nil, "they're close and i cant reach them, slinking!" )
                        self.PreventShooting = nil

                    end
                elseif data.killCount >= 3 then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_camp", { maxNoSeeing = 300 }, "this spot is great, im killing so many enemies!" )
                -- where'd you go...
                elseif not self.IsSeeEnemy then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_approachlastseen", { pos = self.EnemyLastPos }, "where'd you go" )
                    self.PreventShooting = true
                -- i've been watching long enough
                elseif data.giveUpWatchingTime < CurTime() then
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
                        self:ReallyAnger( 40 )

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
                    self:ReallyAnger( 40 )
                    self.PreventShooting = nil
                    if enemy then
                        enemy.terminator_CantConvinceImFriendly = true

                    end
                end
            end,
            OnKillEnemy = function( self, data )
                data.killCount = data.killCount + 1

            end,
            OnInstantKillEnemy = function( self, data )
                data.killCount = data.killCount + 1

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
            ShouldRun = function( self, data )
                return false
            end,
            ShouldWalk = function( self, data )
                return true
            end,
        },
        ["movement_stalkenemy"] = {
            OnStart = function( self, data )
                --print( "stalkstart" )

                data.want = data.want or 8
                data.distMul = data.distMul or 1
                data.stalksSinceLastSeen = 0

                local myPos = self:GetPos()
                local enemy = self:GetEnemy()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee( enemy )
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

                local oldBearing = data.bearingAdded
                -- increment the "behind enemy" check, for big open maps where we never get a chance to be hidden.
                if oldBearing then
                    local step = 1
                    if self:IsReallyAngry() then
                        step = 5

                    elseif self:IsAngry() then
                        step = 2

                    end

                    data.bearingAdded = math.Clamp( data.bearingAdded + -step, -80, 0 )

                else
                    data.bearingAdded = 0

                end

                local hp = self:Health()
                local maxHp = self:GetMaxHealth()

                local result = terminator_Extras.getNearestPosOnNav( enemyPos )

                local enemyOnNav = result.area:IsValid()
                if enemyPos then

                    local minEnemyDist = 0
                    if tooDangerousToApproach then
                        minEnemyDist = math.max( self.DistToEnemy * 0.75, 500 )

                    end

                    enemyDis = math.Clamp( enemyDis, minEnemyDist, math.huge )

                    local distAddedByKiller = self:DistAddedByKillerEnemy( enemy )

                    local innerBoundary = math.Clamp( enemyDis + -300, 0, math.huge ) + distAddedByKiller
                    local outerBoundary = innerBoundary + 1000 + distAddedByKiller
                    local hardInnerBoundary = math.Clamp( enemyDis + -1000, minEnemyDist, math.huge ) + distAddedByKiller
                    local hardOuterBoundary = innerBoundary + 2000 + distAddedByKiller
                    local enemyArea = result.area
                    local enemyAreaCenter = enemyOnNav and enemyArea:GetCenter() or enemyPos

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
                    scoreData.unreachableAreasCached = self.unreachableAreas

                    scoreData.lowestHeightAllowed = math.min( scoreData.enemyAreaCenter.z, myPos.z )
                    --debugoverlay.Cross( scoreData.lastStalkFromPos, 10, 20, color_white, true )

                    scoreData.canGoUnderwater = self:isUnderWater()

                    -- find area to my left or right, relative to enemy, basically circle the enemy 
                    local scoreFunction = function( scoreData, area1, area2 )
                        if area2:IsBlocked() then return 0 end
                        if not area2:IsConnected( area1 ) then return 0 end

                        local area2sId = area2:GetID()
                        if scoreData.unreachableAreasCached[ area2sId ] then return 0 end

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

                        if not IsValid( scoreData.enemyArea ) then return math.huge end

                        if enemyOnNav and not area2:IsCompletelyVisible( scoreData.enemyArea ) then
                            score = score^ 1.45

                        elseif scoreData.hateVisible then
                            score = score^0.1

                        end

                        if self.walkedAreas[area2sId] then
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

                        --debugoverlay.Text( area2Center, tostring( math.Round( score, 2 ) ), 1, false )

                        return score

                    end
                    local stalkPos = self:findValidNavResult( scoreData, self:GetPos(), math.Clamp( self.DistToEnemy * 2, 1000, math.Rand( 5000, 7000 ) ), scoreFunction )

                    if stalkPos then
                        --debugoverlay.Cross( stalkPos, 40, 5, Color( 255, 255, 0 ), true )
                        if enemyOnNav then
                            -- build path left or right, weight it to never get too close to enemy aswell.
                            self:SetupFlankingPath( stalkPos, result.area, self.DistToEnemy * 0.8 )
                            yieldIfWeCan()

                        else
                            self:SetupPathShell( stalkPos )

                        end
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
            BehaveUpdateMotion = function( self, data )
                local exit = nil
                local valid = nil

                local enemy = self:GetEnemy()
                local myPos = self:GetPos()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee( enemy )
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local enemyNav = terminator_Extras.getNearestPosOnNav( enemyPos ).area
                local reachable = self:areaIsReachable( enemyNav )

                if data.InvalidAfterwards then
                    if self.IsSeeEnemy then
                        -- missing a fail here caused massive cascade
                        local oldUpHighFails = data.standUpHighFails or 0
                        local doBackupCamp = oldUpHighFails > 5 and self.IsSeeEnemy
                        self:GetTheBestWeapon()

                        if reachable and not tooDangerousToApproach then
                            self:TaskFail( "movement_stalkenemy" )
                            self:StartTask2( "movement_flankenemy", { Time = 0.2 }, "i can reach them, ill just go around" )

                        elseif doBackupCamp then
                            self:TaskFail( "movement_stalkenemy" )
                            self:StartTask2( "movement_camp", { maxNoSeeing = 300 }, "i failed to stand somewhere high too much, SHOOT!" )

                        else
                            self:TaskFail( "movement_stalkenemy" )
                            self:StartTask2( "movement_stalkenemy", { Time = 0.2, perchWhenHidden = true, standUpHighFails = oldUpHighFails + 1, bearingAdded = data.bearingAdded }, "i cant reach them, ill stand somewhere high up i can see them" )

                        end
                        self.WasHidden = nil
                        self.PreventShooting = nil
                        return
                    end
                    if not data.invalidateTime then
                        data.invalidateTime = CurTime() + math.Rand( 0.3, 1 )
                    elseif data.invalidateTime < CurTime() then
                        self:TaskFail( "movement_stalkenemy" )
                        if data.want > 0 then
                            local newDat = {}
                            newDat.want = data.want + -1
                            newDat.stalksSinceLastSeen = data.stalksSinceLastSeen
                            newDat.lastStalkFromPos = data.lastStalkFromPos
                            newDat.lastKnownStalkDist = data.lastKnownStalkDist
                            newDat.lastKnownStalkDir = data.lastKnownStalkDir
                            newDat.lastKnownStalkPos = data.lastKnownStalkPos
                            newDat.perchWhenHidden = data.perchWhenHidden
                            newDat.perchWhenHiddenPos = data.perchWhenHiddenPos
                            newDat.bearingAdded = data.bearingAdded
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
                local theyLookin = enemyBearingToMeAbs < 15
                -- they saw me!
                local exposed = self.IsSeeEnemy and theyLookin
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
                local enemySeesDestination
                local enemySeesMiddle

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

                if data.KilledEnemy then
                    local old = data.KilledEnemyNoEnemCount or 0
                    data.KilledEnemyNoEnemCount = old + 1

                end
                if data.KilledEnemyNoEnemCount and self.IsSeeEnemy then
                    data.KilledEnemy = nil
                    data.KilledEnemyNoEnemCount = nil

                end

                local distAddedByKiller = self:DistAddedByKillerEnemy( enemy )

                local tooCloseToDangerous = 900 + distAddedByKiller
                local tooCloseDistance = ( 900 * data.distMul ) + distAddedByKiller
                local farTooCloseDistance = ( 700 * data.distMul ) + distAddedByKiller
                local farFarTooCloseDistance = math.Clamp( 200 * data.distMul, 100, 800 ) + distAddedByKiller

                farTooCloseDistance = math.Clamp( farTooCloseDistance, 100, math.huge )

                local notLookingOrBeenAWhile = not theyLookin or data.stalksSinceLastSeen > 2

                local scary = ( self:inSeriousDanger() and IsValid( enemy ) and not self:IsReallyAngry() ) or self:EnemyIsLethalInMelee( enemy )

                local behindEnemyBearing = 90 + data.bearingAdded
                local watch = notLookingOrBeenAWhile and IsValid( enemy ) and self.IsSeeEnemy and self.WasHidden and not self.boredOfWatching and maxHealth and self.DistToEnemy > 1000
                local ambush = enemyBearingToMeAbs > behindEnemyBearing and IsValid( enemy ) and self.IsSeeEnemy and not exposed and reachable and not scary

                local tooClose = self.DistToEnemy < tooCloseDistance and self.IsSeeEnemy and reachable
                local farTooClose = self.DistToEnemy < farTooCloseDistance
                local farFarTooClose = self.DistToEnemy < farFarTooCloseDistance

                local intercept = self.lastInterceptPos or data.lastKnownStalkPos or myPos
                local newLocationCompare = data.lastKnownStalkPos or self.EnemyLastPos
                local interceptIsVeryGood = SqrDistGreaterThan( newLocationCompare:DistToSqr( intercept ), 1500 )


                local pathGoal = self:GetPath():GetCurrentGoal()
                local posImHeadingTo
                if pathGoal then
                    local dirToGoal = terminator_Extras.dirToPos( myPos, pathGoal.pos )
                    posImHeadingTo = myPos + dirToGoal * 100

                end
                local tooCloseToDangerousAndGettingCloser = tooDangerousToApproach and self.DistToEnemy < tooCloseToDangerous and posImHeadingTo and enemyPos and SqrDistLessThan( posImHeadingTo:DistToSqr( enemyPos ), self.DistToEnemy )

                local canGetWeap, potentialWep = self:canGetWeapon()
                local unholstering = potentialWep and potentialWep:GetParent() == self
                local hiddenOrUnholstering = self.IsSeeEnemy or unholstering

                local result = self:ControlPath2( not self.IsSeeEnemy and self.WasHidden )
                -- weap
                if canGetWeap and hiddenOrUnholstering and self:getTheWeapon( "movement_stalkenemy", potentialWep, "movement_stalkenemy" ) then
                    exit = true

                elseif ( self.WasHidden or interceptIsVeryGood ) and self:interceptIfWeCan( "movement_stalkenemy", data ) then
                    exit = true

                elseif not self.IsSeeEnemy and self.WasHidden and self:beatupVehicleIfWeCan( "movement_stalkenemy" ) then
                    exit = true

                elseif data.KilledEnemy and data.KilledEnemyNoEnemCount > 30 then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_approachlastseen", { pos = data.lastKnownStalkPos or self.EnemyLastPos }, "i killed the enemy and nobody else showed up, checkin their body" )

                elseif tooCloseToDangerousAndGettingCloser then
                    local orbitDist = math.Clamp( self.DistToEnemy * 2, 1000, math.huge )
                    self:TaskFail( "movement_stalkenemy" )
                    self:GetTheBestWeapon()
                    self:StartTask2( "movement_stalkenemy", { forcedOrbitDist = orbitDist, perchWhenHidden = true, bearingAdded = data.bearingAdded }, "im too close to it!!" )
                    exit = true

                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_stalkenemy" )
                    exit = true

                -- really lame to get close and have it run away
                elseif self.NothingOrBreakableBetweenEnemy and farFarTooClose and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_duelenemy_near", { wasStalk = true }, "hey pal, you're way too close" )
                    exit = true

                -- really lame to get close and have it run away
                elseif farTooClose and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy", { Time = 0.1, wasStalk = true }, "too close pal" )
                    exit = true

                -- we are too close and we just jumped out of somewhere hidden
                elseif tooClose and self.WasHidden and reachable and not tooDangerousToApproach then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy", { Time = 0.3, wasStalk = true }, "too close" )
                    exit = true

                -- enemy isnt looking at us so we can observe them
                elseif watch then
                    -- AAH! shoot them and do another stalk!
                    if enemy.isTerminatorHunterKiller then
                        self.PreventShooting = nil
                        if result ~= nil then
                            valid = true

                        end
                    -- watch
                    else
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_watch", nil, "i want to watch" )
                        exit = true

                    end
                -- we ended up behind the enemy and they haven't seen us yet
                elseif ambush then
                    self:TaskComplete( "movement_stalkenemy" )
                    if maxHealth and not self.boredOfWatching then
                        self:StartTask2( "movement_watch", nil, "im behind the enemy! but im not bored of watching yet" )

                    elseif enemyBearingToMeAbs < 90 then
                        self:ReallyAnger( 30 )
                        self:resetLostHealth()
                        self:StartTask2( "movement_followenemy", nil, "they aren't paying attention to me, gotta rush em!" )

                    else
                        self:StartTask2( "movement_followenemy", nil, "im behind the enemy!" )

                    end
                    exit = true
                -- we are exposed and we're about to walk even further into the enemy
                elseif exposed and ( enemySeesDestination or enemySeesMiddle ) then
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

                -- invalid path again
                elseif not self:primaryPathIsValid() then
                    valid = true

                end
                if exit then -- we done
                    self.WasHidden = nil
                    self.PreventShooting = nil

                elseif valid then -- keep stalking
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

                    local currWep = self:GetActiveWeapon()
                    local coolWep
                    if IsValid( currWep ) then
                        local dmgTracker = self:Term_GetDamageTrackerOf( currWep )
                        coolWep = dmgTracker.reallyLikesThisOne or dmgTracker.noLeading

                    end

                    local shouldPerchBecauseTheyTooDeadly = self:GetWeaponRange() > self.DistToEnemy and tooDangerousToApproach

                    if data.quickFlank then
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_flankenemy", nil, "im gonna try another way" )

                    -- this activates when ply is somewhere impossible to reach
                    elseif self.WasHidden and ( data.perchWhenHidden or shouldPerchBecauseTheyTooDeadly ) then
                        local whereWeNeedToSee = data.perchWhenHiddenPos or self.EnemyLastPos
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_perch", { requiredTarget = whereWeNeedToSee, earlyQuitIfSeen = true, perchRadius = self:GetRangeTo( whereWeNeedToSee ) * 1.5, distanceWeight = 0.01 }, "i cant reach ya, time to snipe!" )

                    -- if bot is low health then it does perching
                    elseif not self:IsMeleeWeapon() and ratio < 1 and data.stalksSinceLastSeen > 2 then
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_perch", { requiredTarget = self.EnemyLastPos, earlyQuitIfSeen = true, perchRadius = self:GetRangeTo( self.EnemyLastPos ) * 1.5, distanceWeight = 0.01 }, "time to snipe!" )

                    elseif self.IsSeeEnemy and self:getLostHealth() <= 1 and self.NothingOrBreakableBetweenEnemy and self.DistToEnemy > 1000 and ( self:EnemyIsLethalInMelee() or enemy.isTerminatorHunterKiller or coolWep ) and self:GetWeaponRange() > 1250 then
                        self:TaskFail( "movement_stalkenemy" )
                        self:StartTask2( "movement_camp", nil, "im gonna camp this guy!" )

                    elseif ( data.stalksSinceLastSeen or 0 ) < ( ratio * 5 ) then
                        local newDat = {}
                        newDat.distMul = data.distMul
                        newDat.stalksSinceLastSeen = data.stalksSinceLastSeen
                        newDat.lastStalkFromPos = data.lastStalkFromPos
                        newDat.lastKnownStalkDist = data.lastKnownStalkDist
                        newDat.lastKnownStalkDir = data.lastKnownStalkDir
                        newDat.lastKnownStalkPos = data.lastKnownStalkPos
                        newDat.perchWhenHidden = data.perchWhenHidden
                        newDat.perchWhenHiddenPos = data.perchWhenHiddenPos
                        newDat.bearingAdded = data.bearingAdded
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_stalkenemy", newDat, "i did a good stalk and i want to do more" )

                    else -- all done!
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_approachlastseen", { pos = data.lastKnownStalkPos or self.EnemyLastPos }, "im all done stalking" )

                    end
                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
            OnKillEnemy = function( self, data )
                data.KilledEnemy = true
            end,
            OnInstantKillEnemy = function( self, data )
                data.KilledEnemy = true
            end,
        },
        ["movement_flankenemy"] = {
            OnStart = function( self, data )
                -- wait!
                self:YieldUntilNextNewPath()

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

                if enemyPos and self:areaIsReachable( result.area ) then
                    -- flank em!
                    self:SetupFlankingPath( enemyPos, result.area, flankBubble )
                    yieldIfWeCan()

                end
                if self:primaryPathIsValid() then
                    self.PreventShooting = ( not enemySeesMe and self.WasHidden ) and not enemy.isTerminatorHunterKiller
                    return
                end
                data.InvalidAfterwards = true
            end,
            BehaveUpdateMotion = function( self, data )
                local exit = nil
                local keepHidden = nil
                local duelEnemyDistInt = self.DuelEnemyDist
                if data.InvalidAfterwards then
                    self.WasHidden = nil
                    self.PreventShooting = nil
                    if self:EnemyIsReachable() then
                        self:TaskFail( "movement_flankenemy" )
                        self:StartTask2( "movement_followenemy", nil, "nope couldnt flank em" )

                    else
                        self:TaskFail( "movement_flankenemy" )
                        self:StartTask2( "movement_stalkenemy", nil, "i cant reach them, stalking instead" )

                    end
                    --print( "flankquit" )
                    return
                end

                local enemy = self:GetEnemy()
                local goodEnemy = IsValid( enemy ) and self.IsSeeEnemy
                local enemyBearingToMeAbs = math.huge
                if IsValid( enemy ) then
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                    if enemy.terminator_TerminatorsWatching and #enemy.terminator_TerminatorsWatching >= 1 and not self:IsAngry() then
                        duelEnemyDistInt = duelEnemyDistInt / 2

                    end
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

                local belowHalfHealth = ( self:Health() < self:GetMaxHealth() * 0.5 )
                local scared = ( belowHalfHealth and self:inSeriousDanger() ) or self:EnemyIsLethalInMelee( enemy )

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and not self.IsSeeEnemy and self:getTheWeapon( "movement_flankenemy", potentialWep, "movement_flankenemy" ) then
                    exit = true

                elseif scared and not data.wasStalk and enemyBearingToMeAbs < 80 then -- scary enemy and they can see us!
                    self:TaskComplete( "movement_flankenemy" )
                    self:GetTheBestWeapon()
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "that hurt!" )
                    exit = true

                elseif self:CanBashLockedDoor( nil, 800 ) then
                    self:BashLockedDoor( "movement_flankenemy" )
                    exit = true

                elseif self.NothingOrBreakableBetweenEnemy and self.DistToEnemy < duelEnemyDistInt and ( self:MyPathLength() * 0.5 ) < self.DistToEnemy then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_duelenemy_near", nil, "im close enough!" )
                    exit = true

                elseif not self.IsSeeEnemy and self.WasHidden and self:interceptIfWeCan( "movement_flankenemy", data ) then
                    exit = true

                elseif not self.IsSeeEnemy and self.WasHidden and self:beatupVehicleIfWeCan( "movement_flankenemy" ) then
                    exit = true

                elseif exposed and self.WasHidden then
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_flankenemy", nil, "they saw me sneaking" )
                    exit = true

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
                    self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 10, Time = 1.5 }, "my path failed for some reason" )
                    exit = true

                end
                if exit then
                    if not keepHidden then
                        self.WasHidden = nil
                    end
                    self.PreventShooting = nil
                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        -- make sure that bot goes to specific positions, eg, valuable sounds, old enemy positions
        ["movement_approachforcedcheckposition"] = {
            OnStart = function( self, data )
                --print( "forcedcheck!" )
                data.approachAfter = CurTime() + 0.1
                if not self.isUnstucking then
                    self:InvalidatePath( "approaching a forced check pos, killing old path" )
                end
            end,
            BehaveUpdateMotion = function( self, data )
                local toPos = data.forcedCheckPosition
                if not toPos then
                    data.forcedCheckPosition, data.forcedCheckKey = table.Random( self.forcedCheckPositions )
                    toPos = data.forcedCheckPosition

                end

                local enemy = self:GetEnemy()
                local goodEnemy = self.IsSeeEnemy and IsValid( enemy )
                local givenItAChance = data.approachAfter < CurTime() -- this schedule didn't JUST start.

                if toPos and not data.Unreachable and self:primaryPathInvalidOrOutdated( toPos ) then
                    local snappedResult = terminator_Extras.getNearestPosOnNav( toPos )

                    local reachable = self:areaIsReachable( snappedResult.area )
                    if not reachable then data.Unreachable = true return end

                    local posOnNav = snappedResult.pos

                    yieldIfWeCan()

                    -- BOX IT IN
                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                    if otherHuntersHalfwayPoint then
                        local flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.5
                        self:SetupFlankingPath( posOnNav, snappedResult.area, flankBubble )
                        if not self:primaryPathIsValid() then data.Unreachable = true return end

                    else
                        self:SetupPathShell( posOnNav )
                        if not self:primaryPathIsValid() then data.Unreachable = true return end

                    end
                elseif not toPos then
                    data.Unreachable = true

                end
                local result = self:ControlPath2( not self.IsSeeEnemy )
                -- get WEAP
                local canWep, potentialWep = self:canGetWeapon()
                if not data.forcedCheckKey then
                    self:TaskFail( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_handler", nil, "no pos to check!" )

                elseif canWep and self:getTheWeapon( "movement_approachforcedcheckposition", potentialWep, "movement_approachforcedcheckposition" ) then
                    return
                elseif self:CanBashLockedDoor( toPos, 800 ) then
                    self:BashLockedDoor( "movement_approachforcedcheckposition" )
                -- cant get to them
                elseif data.Unreachable and givenItAChance then
                    self:TaskFail( "movement_approachforcedcheckposition" )
                    if toPos then
                        self:StartTask2( "movement_perch", { requiredTarget = toPos, earlyQuitIfSeen = true, perchRadius = self:GetRangeTo( toPos ) * 1.5, distanceWeight = 0.01 }, "i cant reach the pos, ill try looking at it?" )

                    else
                        self:StartTask2( "movement_search", { searchWant = 5 }, "i never went anywhere in the first place" )

                    end
                    self.forcedCheckPositions[ data.forcedCheckKey ] = nil
                -- i see you...
                elseif goodEnemy then
                    self:EnemyAcquired( "movement_approachforcedcheckposition" )
                -- i got there and you're nowhere to be seen
                elseif result == true and givenItAChance then
                    self:TaskComplete( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_search", { searchWant = 60 }, "i got there but nobody's here" )
                    self.forcedCheckPositions[ data.forcedCheckKey ] = nil
                    self.PreventShooting = nil
                -- bad path
                elseif ( self:MyPathLength() < 50 and Distance2D( self:GetPos(), self:GetPath():GetEnd() ) < 300 ) and givenItAChance then
                    self:TaskFail( "movement_approachforcedcheckposition" )
                    self:StartTask2( "movement_search", { searchWant = 80 }, "my path doesn't exist" )
                    self.PreventShooting = nil
                end
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
                data.approachAfter = CurTime() + 0.5
                data.dontGetWepsForASec = CurTime() + 1
                if not self.isUnstucking then
                    self:InvalidatePath( "approaching last seen, killing old path" )
                end
            end,
            BehaveUpdateMotion = function( self, data )
                local enemy = self:GetEnemy()
                local toPos = data.pos or self.EnemyLastPos
                local goodEnemy = self.IsSeeEnemy and IsValid( enemy )
                local givenItAChance = data.approachAfter < CurTime() -- this schedule didn't JUST start.

                if toPos and not data.Unreachable and self:primaryPathInvalidOrOutdated( toPos ) then
                    local snappedResult = terminator_Extras.getNearestPosOnNav( toPos )
                    local posOnNav = snappedResult.pos

                    local reachable = self:areaIsReachable( snappedResult.area )
                    if not reachable then data.Unreachable = true return end

                    -- BOX IT IN
                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                    if otherHuntersHalfwayPoint then
                        local flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.5
                        flankBubble = math.Clamp( flankBubble, 0, 3000 )
                        self:AddAreasToAvoid( self.hazardousAreas, 50 )
                        self:SetupFlankingPath( posOnNav, snappedResult.area, flankBubble )
                        yieldIfWeCan()
                        if not self:primaryPathIsValid() then data.Unreachable = true return end

                    else
                        self:AddAreasToAvoid( self.hazardousAreas, 50 )
                        self:SetupPathShell( posOnNav )
                        if not self:primaryPathIsValid() then data.Unreachable = true return end

                    end
                end
                yieldIfWeCan()

                local result = self:ControlPath2( not self.IsSeeEnemy )
                -- get WEAP
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and data.dontGetWepsForASec < CurTime() and self:getTheWeapon( "movement_approachlastseen", potentialWep, "movement_approachlastseen" ) then
                    return

                elseif self:CanBashLockedDoor( toPos, 800 ) then
                    self:BashLockedDoor( "movement_approachlastseen" )

                elseif self:interceptIfWeCan( "movement_approachlastseen", data ) then
                    return

                elseif self:beatupVehicleIfWeCan( "movement_approachlastseen" ) then
                    return

                elseif data.Unreachable and givenItAChance then -- cant get to them
                    self:TaskFail( "movement_approachlastseen" )
                    self:GetTheBestWeapon()
                    self:StartTask2( "movement_perch", { requiredTarget = toPos, earlyQuitIfSeen = true }, "i cant reach the pos, ill try looking at it?" )

                elseif goodEnemy then -- i see you...
                    self:EnemyAcquired( "movement_approachlastseen" )

                elseif ( self:MyPathLength() < 50 and Distance2D( self:GetPos(), self:GetPath():GetEnd() ) < 300 ) and givenItAChance then -- catch bot bugging out at an unreachable spot or something
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_search", { searchWant = 80 }, "something failed" )
                    self.PreventShooting = nil

                elseif result == true and givenItAChance then -- i got there and you're nowhere to be seen
                    if self.forcedCheckPositions and table.Count( self.forcedCheckPositions ) >= 1 then
                        self:TaskComplete( "movement_approachlastseen" )
                        self:StartTask2( "movement_approachforcedcheckposition", nil, "i reached the goal and there's another spot i can check" )

                    else
                        self:TaskComplete( "movement_approachlastseen" )
                        self:StartTask2( "movement_search", { searchCenter = toPos, searchWant = 30 }, "i reached the goal, ill just look around" )
                        self.PreventShooting = nil

                    end
                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["movement_followenemy"] = {
            OnStart = function( self, data )
                if not self.isUnstucking then
                    self:InvalidatePath( "followenemy" )
                end
            end,
            BehaveUpdateMotion = function( self, data )

                local enemy = self:GetEnemy()
                local validEnemy = IsValid( enemy )
                local enemyPos = self:GetLastEnemyPosition( enemy ) or self.EnemyLastPosOffsetted
                local aliveOrHp = ( validEnemy and enemy.Alive and enemy:Alive() ) or ( validEnemy and enemy.Health and enemy:Health() > 0 )
                local GoodEnemy = self.IsSeeEnemy and validEnemy and aliveOrHp
                local toPos = enemyPos

                if toPos and not data.Unreachable and self:primaryPathInvalidOrOutdated( toPos ) then -- HACK
                    self:InvalidatePath( "new followenemy path time" )

                    local result = terminator_Extras.getNearestPosOnNav( toPos )
                    local reachable = self:areaIsReachable( result.area )
                    if not reachable then data.Unreachable = true return end

                    -- split up!
                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                    local splitUpResult
                    local splitUpPos
                    local splitUpBubble
                    if otherHuntersHalfwayPoint then
                        splitUpPos = otherHuntersHalfwayPoint
                        splitUpBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.7
                        splitUpResult = terminator_Extras.getNearestPosOnNav( splitUpPos )

                    end

                    if splitUpResult and self:areaIsReachable( splitUpResult.area ) then
                        -- flank em!
                        self:SetupFlankingPath( enemyPos, splitUpResult.area, splitUpBubble )
                        yieldIfWeCan()

                    end
                    -- cant flank
                    if not self:primaryPathIsValid() then
                        self:SetupPathShell( result.pos )

                    end
                    if not self:primaryPathIsValid() then data.Unreachable = true return end

                end

                local distToExit = self.DuelEnemyDist
                if data.baitcrouching then
                    distToExit = 200

                end

                self:HandleFakeCrouching( data, enemy )

                if data.baitcrouching and enemy and self:getLostHealth() > 1 then
                    enemy.terminator_CantConvinceImFriendly = true

                end

                local currWep = self:GetActiveWeapon()
                local coolWep
                if IsValid( currWep ) then
                    local dmgTracker = self:Term_GetDamageTrackerOf( currWep )
                    coolWep = dmgTracker.reallyLikesThisOne or dmgTracker.noLeading

                end

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                if canWep and not GoodEnemy and self:getTheWeapon( "movement_followenemy", potentialWep, "movement_followenemy" ) then
                    return
                elseif ( self:inSeriousDanger() and GoodEnemy and not ( self:IsReallyAngry() or self:Health() < self:GetMaxHealth() * 0.5 ) ) or self:EnemyIsLethalInMelee( enemy ) then
                    self:TaskFail( "movement_followenemy" )
                    self:GetTheBestWeapon()
                    self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5, quickFlank = true }, "i dont want to die" )
                elseif self.IsSeeEnemy and self:getLostHealth() <= 1 and self.NothingOrBreakableBetweenEnemy and self.DistToEnemy > 1000 and ( self:EnemyIsLethalInMelee() or enemy.isTerminatorHunterKiller or coolWep ) and self:GetWeaponRange() > 1250 then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_camp", nil, "im gonna camp this guy!" )
                elseif self:CanBashLockedDoor( self:GetPos(), 1000 ) then
                    self:BashLockedDoor( "movement_followenemy" )
                elseif data.Unreachable and GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:GetTheBestWeapon()
                    if self.IsSeeEnemy and self:IsFists() then
                        self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i cant get to them" )

                    else
                        self:StartTask2( "movement_perch", { requiredTarget = enemyPos, earlyQuitIfSeen = true, perchRadius = self:GetRangeTo( enemyPos ) * 1.5, distanceWeight = 0.01 }, "i cant get to them, lets see if i can get LOS" )

                    end
                elseif data.Unreachable and not GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:GetTheBestWeapon()
                    self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 10 }, "i cant get there, and they're gone" )
                elseif GoodEnemy and self.NothingOrBreakableBetweenEnemy and self.DistToEnemy < distToExit and ( self:MyPathLength() * 0.5 ) < self.DistToEnemy then
                    if data.baitcrouching then
                        enemy.terminator_CantConvinceImFriendly = true
                        self.PreventShooting = nil
                        self.forcedShouldWalk = 0

                    end
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_duelenemy_near", nil, "i gotta punch em" )
                    if self:Health() < self:GetMaxHealth() then
                        self:Anger( 10 )

                    end
                elseif self:MyPathLength() < 50 and Distance2D( self:GetPos(), self:GetPath():GetEnd() ) < 300 then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 80 }, "got there, but no enemy" )
                elseif result and not GoodEnemy then
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "where did they go" )
                elseif not GoodEnemy and not self:primaryPathIsValid() then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_approachlastseen", nil, "they're gone and im done" )
                end
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
                data.quitTime = CurTime() + math.Clamp( startingVal + quitEat, 4, 8 )
                data.wasReallyCloseToEnemy = nil
                data.failedToTakeCover = 0

                data.minNewPathTime = 0
                data.NextRandPathAtt = 0

                data.marchingOnDamagedNumber = 1

            end,
            OnDamaged = function( self, data, dmg )
                data.marchingOnDamagedNumber = data.marchingOnDamagedNumber + dmg:GetDamage()

            end,
            BehaveUpdateMotion = function( self, data )
                local onDamagedMarcher = data.marchingOnDamagedNumber
                if onDamagedMarcher > 1 then
                    data.marchingOnDamagedNumber = onDamagedMarcher * 0.9

                end
                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or self.EnemyLastPosOffsetted
                local myPos = self:GetPos()
                local _ = self:ControlPath2( not self.IsSeeEnemy )
                local maxDuelDist = self.DuelEnemyDist + 200
                local enemyNavArea = terminator_Extras.getNearestNav( enemyPos ) or NULL
                local enemyIsReachable = self:areaIsReachable( enemyNavArea )

                local badEnemy = nil
                local badEnemyCounts = data.badEnemyCounts or 0
                local myMyMaxHealth
                local myHealth
                local lowHealth
                local reallyLowHealth
                local wepIsOk = true
                local wepIsReallyGood = nil
                local wep = self:GetActiveWeapon()

                local canCover

                if IsValid( enemy ) and enemy:IsPlayer() then
                    data.fightingPlayer = true

                end
                if IsValid( enemy ) then
                    myMyMaxHealth = self:GetMaxHealth()
                    myHealth = self:Health()
                    lowHealth = myHealth < ( myMyMaxHealth * 0.5 )
                    reallyLowHealth = myHealth < ( myMyMaxHealth * 0.25 )

                    canCover = self:IsRangedWeapon( wep ) and ( self:EnemyIsLethalInMelee( enemy ) or lowHealth ) and data.failedToTakeCover < 2

                    if canCover then
                        maxDuelDist = maxDuelDist * 2

                    end
                end
                if IsValid( wep ) then
                    wepIsOk = self:GetWeightOfWeapon( wep ) >= 4
                    wepIsReallyGood = self:GetWeightOfWeapon( wep ) >= 100

                end

                if IsValid( enemy ) and enemy:Health() <= 0 then
                    badEnemy = true

                elseif not IsValid( enemy ) or ( not canCover and not self.NothingOrBreakableBetweenEnemy ) or ( canCover and not self.IsSeeEnemy ) then
                    badEnemy = true

                end

                local waterFight

                if not badEnemy then
                    data.badEnemyCounts = nil
                    waterFight = enemy:WaterLevel() >= 1 and not enemy:OnGround() and self:WaterLevel() >= 2
                    if waterFight and self.loco:IsOnGround() then
                        self:StartSwimming()

                    end
                end

                local fisticuffsDist = 135
                local getWepDist = fisticuffsDist + 10
                local canWep, potentialWep = self:canGetWeapon()
                local distToWeapSqr = math.huge
                local wepDistToEnemySqr = math.huge

                if IsValid( potentialWep ) and IsValid( enemy ) then
                    distToWeapSqr = myPos:DistToSqr( potentialWep:GetPos() )
                    wepDistToEnemySqr = enemyPos:DistToSqr( potentialWep:GetPos() )

                end

                if badEnemy then
                    data.badEnemyCounts = badEnemyCounts + 1
                    if data.badEnemyCounts > 2 or data.fightingPlayer then
                        -- find weapons NOW!
                        if self:IsReallyAngry() then
                            self:understandSurroundings( data.myTbl )
                            self:NextWeapSearch( -1 )
                            canWep, potentialWep = self:canGetWeapon()

                        end

                        if canWep and self:getTheWeapon( "movement_duelenemy_near", potentialWep, "movement_handler" ) then
                            return

                        elseif enemyIsReachable then
                            self:TaskComplete( "movement_duelenemy_near" )
                            self:StartTask2( "movement_approachlastseen", nil, "my enemy wasnt engagable!" )

                        else
                            self:TaskComplete( "movement_duelenemy_near" )
                            self:GetTheBestWeapon()
                            self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPosOffsetted, searchWant = 20, searchRadius = 2000 }, "my enemy is gone and i cant get to where they were" )

                        end
                    end
                elseif ( not enemyIsReachable or data.Unreachable ) and enemy then
                    if data.wasStalk then
                        self:TaskFail( "movement_duelenemy_near" )
                        self:GetTheBestWeapon()
                        self:StartTask2( "movement_perch", { requiredTarget = enemyPos }, "i cant reach them" )

                    else
                        self:TaskFail( "movement_duelenemy_near" )
                        self:GetTheBestWeapon()
                        self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 1.5 }, "i cant reach them" )

                    end
                elseif self.DistToEnemy > maxDuelDist and enemyIsReachable then
                    self:EnemyAcquired( "movement_duelenemy_near" )
                    --print("dist" )

                -- the dueling in question
                elseif IsValid( enemy ) and self.IsSeeEnemy then
                    local enemyBearingToMe = self:enemyBearingToMeAbs()
                    local myNavArea = self:GetCurrentNavArea()
                    local canDoNewPath = data.minNewPathTime < CurTime()
                    local reallyCloseToEnemy = self.DistToEnemy < 350

                    -- drop our weap because fists will serve us better!
                    if self.DistToEnemy < 500 and wep and self:IsRangedWeapon( wep ) then
                        local blockFisticuffs = wepIsReallyGood or self:inSeriousDanger()
                        local canDoFisticuffss = self.DistToEnemy < fisticuffsDist or ( data.quitTime < CurTime() and ( math.random( 0, 100 ) < 25 ) ) or reallyLowHealth
                        local fistiCuffs = canDoFisticuffss and not blockFisticuffs
                        if fistiCuffs and self.HasFists then
                            if self:EnemyIsLethalInMelee( enemy ) and not data.wasStalk then
                                self:TaskFail( "movement_duelenemy_near" )
                                self:StartTask2( "movement_stalkenemy", { distMul = 0.01, forcedOrbitDist = self.DistToEnemy * 2 }, "i wanted to punch them, but ill back up instead" )

                            else
                                -- put weap on back
                                self:DropWeapon( false )
                                -- do this after dropweapon so we can set it a bit bigger!
                                self.terminator_NextWeaponPickup = CurTime() + math.Rand( 1.5, 3 )

                            end
                        end
                    end

                    local finishedOrInvalid = ( Result == true or not self:primaryPathIsValid() or not terminator_Extras.PosCanSeeComplex( self:EyePos(), enemy:EyePos(), self ) )
                    local needsToPathNow = enemyBearingToMe < 20 and not self:primaryPathIsValid() and self:IsReallyAngry()

                    canDoNewPath = canDoNewPath and ( finishedOrInvalid or reallyCloseToEnemy )
                    canDoNewPath = canDoNewPath or needsToPathNow
                    local wepIsUseful = wep and wepIsOk

                    -- ranged weap
                    if not waterFight and canDoNewPath and ( wepIsUseful or canCover ) and self:IsRangedWeapon( wep ) and IsValid( myNavArea ) then
                        local adjAreas = myNavArea:GetAdjacentAreas()
                        table.Shuffle( adjAreas )

                        local enemysShootPos = self:EntShootPos( enemy )
                        local successfulPath

                        local distAddedByKiller = self:DistAddedByKillerEnemy( enemy )

                        local tooClose = maxDuelDist / 4
                        tooClose = tooClose + distAddedByKiller

                        local tooFar = maxDuelDist + distAddedByKiller
                        local shootPosOffset = self.ViewOffset
                        local trFilter = { self, enemy }
                        local trMask = MASK_SOLID

                        -- pick an adjacent area
                        for _, area in ipairs( adjAreas ) do
                            if not area then continue end
                            coroutine_yield()
                            if area == enemyNavArea then continue end -- dont go to the enemy's area!

                            local areasCenter = area:GetCenter()
                            local howCloseWellGetToEnemy = util.DistanceToLine( myPos, areasCenter, enemysShootPos )
                            if howCloseWellGetToEnemy < tooClose then continue end -- dont go there if we'll get too close to the enemy

                            local visible
                            local potVisiblePos
                            if area:GetSizeX() + area:GetSizeY() > 200 then
                                for _ = 1, 10 do
                                    potVisiblePos = area:GetRandomPoint()
                                    visible, trace = terminator_Extras.PosCanSeeComplex( potVisiblePos + shootPosOffset, enemysShootPos, trFilter, trMask )
                                    if visible then break end

                                end
                            else
                                potVisiblePos = areasCenter
                                visible = terminator_Extras.PosCanSeeComplex( potVisiblePos + shootPosOffset, enemysShootPos, trFilter, trMask )

                            end
                            if not visible then continue end -- dont go behind corners!
                            local pathPos = potVisiblePos

                            local newsDistToEnemy = pathPos:DistToSqr( enemysShootPos )
                            if not canCover and SqrDistGreaterThan( newsDistToEnemy, tooFar ) then continue end
                            if SqrDistLessThan( newsDistToEnemy, tooClose ) then continue end

                            --debugoverlay.Cross( pathPos, 5, 5, color_white, true )

                            local footCanSee = terminator_Extras.PosCanSeeComplex( pathPos + plus15Z, enemysShootPos, trFilter, trMask )
                            if canCover and footCanSee then
                                --debugoverlay.Line( pathPos + plus15Z, enemysShootPos, 1, Color( 255, 0, 0 ), true )
                                continue
                            --elseif canCover then
                                --debugoverlay.Line( pathPos + plus15Z, enemysShootPos, 1, color_white, true )

                            end
                            if not canCover and not footCanSee then continue end -- stand in the open!

                            self:SetupPathShell( pathPos )
                            if not self:primaryPathIsValid() then break end
                            successfulPath = true
                            local add = self.DistToEnemy / ( self.DuelEnemyDist * 0.25 )
                            data.minNewPathTime = CurTime() + add
                            break

                        end
                        if not successfulPath then
                            if canCover then
                                data.failedToTakeCover = data.failedToTakeCover + 1

                            end
                            goto SkipRemainingCriteria

                        end
                        if successfulPath then
                            data.failedToTakeCover = math.max( 0, data.failedToTakeCover - 1 )

                        end
                    --melee
                    elseif canDoNewPath or waterFight then
                        data.minNewPathTime = CurTime() + 0.05

                        local enemVel = enemy:GetVelocity()
                        local enemSpeed = enemVel:Length()
                        enemVel.z = enemVel.z * 0.15
                        local velProduct = math.Clamp( enemVel:Length() * 1.4, 0, self.DistToEnemy * 0.8 )
                        local offset = enemVel:GetNormalized() * velProduct

                        -- determine where player CAN go
                        -- dont build path to somewhere behind walls
                        local mymins,mymaxs = self:GetCollisionBounds()
                        mymins = Vector( mymins.x, mymins.y, mymins.z )
                        mymaxs = Vector( mymaxs.x, mymaxs.y, mymaxs.z )
                        mymins = mymins * 0.5
                        mymaxs = mymaxs * 0.5

                        local pathHull = {}
                        pathHull.start = enemyPos
                        pathHull.endpos = enemyPos + offset
                        pathHull.mask = MASK_SOLID_BRUSHONLY
                        pathHull.mins = mymins
                        pathHull.maxs = mymaxs

                        local whereToInterceptTr = util.TraceHull( pathHull )

                        local range = self:GetWeaponRange()
                        local zDist = math.abs( myPos.z - enemyPos.z )
                        -- enemy is above us!
                        local highUp = zDist > range
                        -- closerToWeapon is more lenient, so bot gets weapons more often
                        local closerToWeapon = distToWeapSqr^2 < self.DistToEnemy^2
                        local weaponToMeLessThanWeaponToEnemy = distToWeapSqr < wepDistToEnemySqr
                        local badDist = ( closerToWeapon and weaponToMeLessThanWeaponToEnemy and self.DistToEnemy > getWepDist and not reallyLowHealth ) or highUp
                        local unholster = math.random( 1, 100 ) < 15 and self.DistToEnemy > getWepDist and self:IsHolsteredWeap( potentialWep )

                        local quitEat = 10
                        if enemyBearingToMe < 30 then -- i stop running sooner when they lookin at me
                            quitEat = -4
                        end
                        local quitTime = data.quitTime + quitEat
                        local tooAngryToQuit = enemy.isTerminatorHunterKiller or self:IsReallyAngry()

                        -- i got close! im not giving up.
                        if self.DistToEnemy < 75 and terminator_Extras.PosCanSeeComplex( self:GetShootPos(), self:EntShootPos( enemy ), self ) then
                            data.quitTime = CurTime() + 10

                        end

                        -- enemy isn't moving, don't quit!
                        if enemy:GetVelocity():Length2DSqr() < 1600 then
                            data.quitTime = data.quitTime + 0.5

                        end

                        local bored = quitTime <= CurTime()
                        local wepIsGoodIdea = unholster or badDist or bored or ( reallyLowHealth and self:inSeriousDanger() )

                        if wepIsGoodIdea and canWep and self:getTheWeapon( "movement_duelenemy_near", potentialWep, "movement_handler" ) then
                            return

                        -- super close to enemy, use gotopossimple
                        elseif reallyCloseToEnemy and ( not IsValid( self.LastShootBlocker ) or self.LastShootBlocker == enemy ) and enemyPos then
                            if self:primaryPathIsValid() then
                                self:InvalidatePath( "im close enough to go to enemy's pos simple" )

                            end
                            local maxOffsetFromEnem = range / 2 + onDamagedMarcher
                            local lostHealth = self:getLostHealth()
                            local fearful = ( ( enemy.Health and enemy:Health() > 500 ) or self:EnemyIsLethalInMelee( enemy ) or self:Health() < self:GetMaxHealth() * 0.5 )
                            local gotoPos
                            local angy = self:IsAngry()
                            -- try and go behind
                            if angy and onDamagedMarcher > 1 and enemSpeed <= 100 and fearful then
                                local flat = terminator_Extras.dirToPos( myPos, enemyPos )
                                flat.z = 0
                                flat:Normalize()
                                gotoPos = enemyPos + VectorRand() * onDamagedMarcher + flat * maxOffsetFromEnem

                            -- if we're mad and enemy is not moving, go for the head
                            elseif angy and self.DistToEnemy < 200 and enemSpeed <= 50 then
                                gotoPos = self:EntShootPos( enemy )

                            -- we mad and they're moving, predict where they will go, and surprise them
                            elseif angy then
                                gotoPos = whereToInterceptTr.HitPos

                            -- if we lost a bit of health, back up a bit and strafe to the side
                            elseif lostHealth > 5 then
                                local flat = self:GetAimVector()
                                flat.z = 0
                                flat:Normalize()
                                gotoPos = enemyPos + -flat * maxOffsetFromEnem
                                gotoPos = gotoPos + VectorRand() * onDamagedMarcher

                            -- default, just run up to enemy
                            else
                                gotoPos = enemyPos

                            end

                            --debugoverlay.Cross( gotoPos, 10, 1, Color( 255,255,0 ) )
                            --print( self, duelType )

                            data.myTbl.GotoPosSimple( self, data.myTbl, gotoPos, 10 )
                            if self.DistToEnemy < 100 then
                                self:crouchToGetCloserTo( self:EntShootPos( enemy ) )

                            end

                        -- far from enemy, build real melee paths
                        elseif not bored or tooAngryToQuit then
                            local pathPos = whereToInterceptTr.HitPos

                            --debugoverlay.Cross( pathPos, 10, 1, Color( 255,255,0 ) )
                            local interceptResult = terminator_Extras.getNearestPosOnNav( pathPos )
                            local reachable = self:areaIsReachable( interceptResult.area )
                            if not reachable then return end

                            local timeAdd = math.Clamp( velProduct / 200, 0.1, 1 )

                            data.minNewPathTime = CurTime() + timeAdd
                            --print( timeAdd )
                            if not self:nextNewPathIsGood() then return end

                            self:SetupPathShell( interceptResult.pos )
                            if self:primaryPathIsValid() then goto SkipRemainingCriteria end
                            data.Unreachable = true

                        -- the bot isnt just gonna follow you around like a lobotimised lemming
                        else
                            self.duelQuitCount = data.duelQuitCount + 1
                            self:TaskFail( "movement_duelenemy_near" )
                            self:StartTask2( "movement_watch", { tooCloseDist = 150 }, "they're just running" )

                        end
                    end

                    ::SkipRemainingCriteria::
                    if data.Unreachable and data.NextRandPathAtt < CurTime() then
                        if IsValid( myNavArea ) then
                            data.NextRandPathAtt = CurTime() + math.random( 1, 2 )
                            self:SetupPathShell( myNavArea:GetRandomPoint() )

                        else
                            self:TaskFail( "movement_duelenemy_near" )
                            self:StartTask2( "movement_handler", nil, "FAIL" )

                        end
                    end
                end
            end,
            ShouldRun = function( self, data )
                local killerrr = IsValid( self:GetEnemy() ) and self:GetEnemy().isTerminatorHunterKiller
                local isRandomOrIsMelee = ( CurTime() + self:GetCreationID() ) % 10 > 8 or self:IsMeleeWeapon()
                local randomOrMeleeOrDamaged = isRandomOrIsMelee or self:getLostHealth() > 3 or killerrr -- if player is engaging us, dont walk
                return randomOrMeleeOrDamaged and self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        -- simple wander
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

                if not IsValid( myNavArea ) then
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
                    local dropToArea = area2:ComputeAdjacentConnectionHeightChange( area1 )
                    local score = area2:GetCenter():DistToSqr( scoreData.startPos ) * math.Rand( 0.8, 1.4 )
                    if scoreData.self.walkedAreas[area2:GetID()] then
                        return 1
                    end
                    if not area2:IsPotentiallyVisible( scoreData.startArea ) then
                        score = score * 2
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
                    self:SetupPathShell( wanderPos )

                    if not self:primaryPathIsValid() then
                        data.InvalidateAfterwards = true
                        return
                    end
                else
                    data.InvalidateAfterwards = true
                    return
                end
            end,
            BehaveUpdateMotion = function( self, data )
                local result = self:ControlPath2( not self.IsSeeEnemy )

                local canWep, potentialWep = self:canGetWeapon()
                yieldIfWeCan()

                if data.InvalidateAfterwards then
                    self:TaskFail( "movement_inertia" )
                    yieldIfWeCan( "wait" )

                    self:StartTask2( "movement_biginertia", nil, "i couldnt find somewhere to wander" )
                    return

                elseif canWep and self:getTheWeapon( "movement_inertia", potentialWep, "movement_inertia" ) then
                    return

                elseif self:interceptIfWeCan( "movement_inertia", data ) then
                    return

                elseif self:beatupVehicleIfWeCan( "movement_inertia" ) then
                    return

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
                elseif ( data.Want or 0 ) <= 0 then -- no want, end the inertia
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_biginertia", { Want = 20 }, "im bored of small wandering" )

                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        -- complex wander, preserves areas already explored, makes bot cross entire map pretty much
        ["movement_biginertia"] = {
            OnStart = function( self, data )
                -- wait!
                self:YieldUntilNextNewPath()

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

                if not IsValid( myNavArea ) then
                    self:TaskFail( "movement_biginertia" )
                    self:StartTask2( "movement_wait", nil, "i dont know where i am" )
                    return
                end

                local foundSomewhereNotBeen = nil
                local anotherHuntersPos = self:GetOtherHuntersProbableEntrance()

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
                if anotherHuntersPos then
                    scoreData.doSpreadOut = true
                    scoreData.spreadOutAvoidAreas = {}
                    local areasFound = navmesh.Find( anotherHuntersPos, 1500, 100, 100 )

                    for _, currArea in ipairs( areasFound ) do
                        scoreData.spreadOutAvoidAreas[currArea:GetID()] = true

                    end
                end

                local scoreFunction = function( scoreData, area1, area2 ) -- this is the function that determines the score of a navarea
                    local dropToArea = area2:ComputeAdjacentConnectionHeightChange( area1 )
                    local area2sCenter = area2:GetCenter()
                    local score = area2sCenter:DistToSqr( scoreData.startPos ) * math.Rand( 0.8, 1.4 )

                    if dropToArea > self.loco:GetJumpHeight() then
                        return 0

                    end
                    local area2sId = area2:GetID()

                    if scoreData.beenAreas[area2sId] then -- avoid already been areas
                        score = score * 0.0001
                    else
                        foundSomewhereNotBeen = true
                    end
                    -- dont group up!
                    if scoreData.doSpreadOut and scoreData.spreadOutAvoidAreas[area2sId] then
                        score = score * 0.001
                    end
                    -- go forward
                    if math.abs( terminator_Extras.BearingToPos( scoreData.startPos, scoreData.forward, area2sCenter, scoreData.forward ) ) < 22.5 then
                        score = score^1.5
                    end
                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = score * 0.001
                    end
                    if math.abs( dropToArea ) > 100 then
                        score = score * 0.001
                    end

                    --debugoverlay.Text( area2sCenter, tostring( math.Round( score ) ), 8, false )

                    return score

                end

                wanderPos = self:findValidNavResult( scoreData, self:GetPos(), math.random( 5000, 6000 ), scoreFunction )

                if foundSomewhereNotBeen == nil then
                    data.beenAreas = nil
                    local fails = data.fails or 0
                    if self.IsSeeEnemy then
                        self:EnemyAcquired( "movement_biginertia" )

                    elseif not self:IsMeleeWeapon( self:GetWeapon() ) and self:GetWeaponRange() > 2000 then
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_perch", nil, "i ran out of places, and i have a real weapon" )

                    elseif fails < 10 then
                        self:TaskFail( "movement_biginertia" )
                        yieldIfWeCan( "wait" )

                        self:StartTask2( "movement_biginertia", { fails = fails + 1 }, "i ran out of unreached spots, going back" )

                    else
                        self.overrideVeryStuck = true
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_handler", nil, "my biginertia ended up in a death spiral" )

                    end

                elseif wanderPos then
                    self:SetupPathShell( wanderPos )

                    if not self:primaryPathIsValid() then
                        self:TaskFail( "movement_biginertia" )
                        self:StartTask2( "movement_wait", nil, "i couldnt make a path" )
                        if self:AreaIsOrphan( myNavArea, true ) then -- uh oh
                            self.overrideVeryStuck = true

                        end
                        self.bigInertiaPreserveBeenAreas = data.beenAreas

                    end
                else
                    self:TaskFail( "movement_biginertia" )
                    self:StartTask2( "movement_search", nil, "i couldnt find somewhere to wander to" ) -- just do something!
                    self.bigInertiaPreserveBeenAreas = data.beenAreas

                end
            end,
            BehaveUpdateMotion = function( self, data )
                -- gives up on self.bigInertiaPreserveBeenAreas if we know for a fact that the enemy has moved

                local want = data.Want or 0
                local canWep, potentialWep = self:canGetWeapon()

                local result = self:ControlPath2( not self.IsSeeEnemy )
                if canWep and self:getTheWeapon( "movement_biginertia", potentialWep, "movement_biginertia" ) then
                    self.bigInertiaPreserveBeenAreas = data.beenAreas
                    return

                elseif self:interceptIfWeCan( "movement_biginertia", data ) then
                    self.bigInertiaPreserveBeenAreas = nil

                elseif self:beatupVehicleIfWeCan( "movement_biginertia" ) then
                    return

                elseif self.IsSeeEnemy then
                    self:EnemyAcquired( "movement_biginertia" )
                    self.bigInertiaPreserveBeenAreas = nil

                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_biginertia" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, " i heard something" )
                    if self.lastHeardSoundHint and self.lastHeardSoundHint.valuable then
                        self.bigInertiaPreserveBeenAreas = nil

                    end
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
                        local chanceNeeded = 15
                        if wepRange == math.huge or SqrDistGreaterThan( wepRange, 2500 ) then
                            chanceNeeded = 85

                        end
                        if self:WeaponIsPlacable() then
                            self:StartTask2( "movement_placeweapon", nil, "i want to place my wep" )
                            return

                        elseif table.Count( data.beenAreas ) > self.RunSpeed * 3 and math.random( 0, 100 ) < chanceNeeded then
                            self:StartTask2( "movement_perch", nil, "i wandered a long time, ill wait here" )
                            self.bigInertiaPreserveBeenAreas = nil

                        else
                            self:StartTask2( "movement_biginertia", { Want = want, dir = terminator_Extras.dirToPos( data.PathStart, self:GetPos() ), beenAreas = data.beenAreas }, "i still want to wander" )
                            self.bigInertiaPreserveBeenAreas = data.beenAreas

                        end
                    elseif not self.Unstucking and result == false and not self:primaryPathIsValid() then
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
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        -- enemy dependant, stand totally still and shoot them
        ["movement_camp"] = {
            OnStart = function( self, data )
                local enemy = self:GetEnemy()
                data.neverSeenEnemy = true

                -- static enemy pos
                data.startingEnemyPos = self:GetLastEnemyPosition( enemy ) or self.EnemyLastPos

                if not self.isUnstucking then
                    self:InvalidatePath( "camping, killing old path" )

                end

                self.campingFailures = self.campingFailures or 0

                data.campingStaringTolerance = math.Clamp( 50 + -( self.campingFailures * 2 ), 10, 50 ) -- increases if the player gets wise to our camping
                data.maxNoSeeing = data.maxNoSeeing or self:campingTolerance()
                data.tooCloseDist = data.tooCloseDist or 750
                data.campingCounter = 0
                data.lookinRightAtMeCount = 0
                data.notSeeCount = 0
                data.notSeeToLookAround = 0
                data.campingTarget = math.random( 40, 90 )
                data.targetModulo = data.campingTarget

                -- where we look at
                data.campingStarePos = self.EnemyLastPos

                if IsValid( enemy ) and self:enemyBearingToMeAbs() < 15 then
                    -- we aint foolin nobody!
                    data.startedAsSeen = true

                end

                self.totalCampingCount = self.totalCampingCount or 0

                if self:Health() < ( self:GetMaxHealth() * 0.9 ) or data.startedAsSeen then
                    data.campingTarget = data.campingTarget * 0.15

                end

                local notGonnaBeSurprised = enemy and ( enemy.isTerminatorHunterKiller or self:EnemyIsLethalInMelee( enemy ) )
                if notGonnaBeSurprised then
                    self.PreventShooting = nil

                else
                    self.PreventShooting = true -- this IS a SNIPING behaviour, not a "fire everything we have" behaviour!

                end
                data.ItShotMe = function( self )
                    return self:getLostHealth() > 10 or self:inSeriousDanger()

                end
                data.StartedShotAt = data.ItShotMe( self )
 
            end,
            BehaveUpdateMotion = function( self, data )
                local enemy = self:GetEnemy()
                local tooDangerousToApproach = self:EnemyIsLethalInMelee( enemy )
                local enemyBearingToMeAbs = math.huge
                local enemStandingStill = nil
                local standingSortaStillAndBored = nil
                local veryBored = nil
                local internalStaringTolerance = data.campingStaringTolerance
                local isFists = self:IsFists()
                if isFists then
                    internalStaringTolerance = math.Clamp( internalStaringTolerance, 0, 5 )

                end

                if IsValid( enemy ) then
                    data.campingStarePos = self.EnemyLastPos

                    local velLengSqr = enemy:GetVelocity():Length2DSqr()
                    enemyBearingToMeAbs = self:enemyBearingToMeAbs()
                    enemStandingStill = velLengSqr < 15^2

                    local walkSpeed = 0
                    if enemy.GetWalkSpeed then walkSpeed = enemy:GetWalkSpeed() end

                    standingSortaStillAndBored = velLengSqr <= walkSpeed and self.totalCampingCount > 500
                    -- get it over with already!
                    veryBored = self.totalCampingCount > 1000

                end

                self.blockReallyStuckAccumulate = CurTime() + 5

                if self.IsSeeEnemy then
                    data.neverSeenEnemy = nil

                    -- oh sh-
                    if not data.StartedShotAt and data.ItShotMe( self ) then
                        self:TaskComplete( "movement_camp" )
                        self:StartTask2( "movement_stalkenemy", { perchWhenHidden = true }, "it shot me" )
                        self.PreventShooting = nil
                        return

                    end

                    data.wasEnemy = true
                    data.notSeeCount = 0
                    data.notSeeToLookAround = 0
                    self.totalCampingCount = self.totalCampingCount + 3
                    if enemyBearingToMeAbs > 20 or standingSortaStillAndBored or veryBored or data.startedAsSeen then
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
                    elseif enemyBearingToMeAbs < 10 then
                        if enemy and enemy.isTerminatorHunterKiller then
                            -- nopenope
                            data.lookinRightAtMeCount = data.lookinRightAtMeCount + 10
                            data.campingCounter = data.campingCounter + -20

                        else
                            -- they see us!
                            data.lookinRightAtMeCount = data.lookinRightAtMeCount + 1
                            data.campingCounter = data.campingCounter + -2

                        end
                        self.PreventShooting = nil

                    else
                        -- don't reveal our pos!
                        data.campingCounter = 0

                    end
                else
                    local myShootPos = self:GetShootPos()

                    if not data.campingStarePos or ( data.notSeeCount > data.notSeeToLookAround ) then
                        local didOne
                        for _ = 1, 5 do
                            local offset = VectorRand()
                            offset.z = math.Clamp( offset.z, -0.1, 0.1 )
                            offset:Normalize()
                            offset = offset * 500
                            local offsetted = myShootPos + offset
                            if terminator_Extras.PosCanSeeComplex( myShootPos, offsetted, self ) then
                                --debugoverlay.Line( myShootPos, offsetted, 10, color_white, true )
                                data.campingStarePos = offsetted
                                didOne = true
                                break

                            end
                        end
                        if not didOne then
                            data.notSeeToLookAround = data.notSeeToLookAround + math.random( 10, 20 )

                        else
                            local prod = terminator_Extras.dirToPos( myShootPos, self.EnemyLastPos ):Dot( terminator_Extras.dirToPos( myShootPos, data.campingStarePos ) )
                            if prod > 0.75 then -- look for longer if the enemy was this direction
                                data.notSeeToLookAround = data.notSeeToLookAround + math.random( 30, 70 )

                            elseif prod > 0.55 then
                                data.notSeeToLookAround = data.notSeeToLookAround + math.random( 10, 30 )

                            else
                                data.notSeeToLookAround = data.notSeeToLookAround + math.random( 5, 10 )

                            end
                        end
                    end
                    if data.campingStarePos then
                        self:shootAt( data.campingStarePos, true )

                    end
                    self.totalCampingCount = self.totalCampingCount + 1
                    if data.wasEnemy then
                        if data.killedEnemy then -- no more enemy, cause i killed them!
                            data.wasEnemy = nil

                        elseif enemy and enemy.isTerminatorHunterKiller then
                            -- dont let them run away!
                            data.notSeeCount = data.notSeeCount + 15

                        else
                            -- get bored faster
                            data.notSeeCount = data.notSeeCount + 8

                        end
                    elseif self:interceptIfWeCan( nil, data ) then
                        data.notSeeCount = data.notSeeCount + 10

                    else
                        data.notSeeCount = data.notSeeCount + 1

                    end

                    if isFists then
                        data.campingCounter = data.campingCounter + -0.05

                    end
                end

                local enemyMovedReallyFar = nil

                if data.startingEnemyPos then
                    enemyMovedReallyFar = SqrDistGreaterThan( data.startingEnemyPos:DistToSqr( self.EnemyLastPos ), 1000 )

                end

                local tooCloseDist = data.tooCloseDist + self:DistAddedByKillerEnemy( enemy )

                if self.IsSeeEnemy and self.DistToEnemy < tooCloseDist then
                    self:TaskComplete( "movement_camp" )
                    if tooDangerousToApproach then
                        self:StartTask2( "movement_stalkenemy", nil, "they got too close, and they scary!" )

                    else
                        self:StartTask2( "movement_flankenemy", nil, "they got too close to me" )

                    end
                    self.PreventShooting = nil

                -- where'd you go...
                elseif enemyMovedReallyFar or ( data.neverSeenEnemy and not self.IsSeeEnemy and data.notSeeCount > data.maxNoSeeing ) then
                    local term_DontPerchAgain = self.term_DontPerchAgain or 0

                    if term_DontPerchAgain > CurTime() then -- we already did a perch with tight criteria
                        self:Anger( 30 )
                        self.term_DontPerchAgain = nil
                        self:TaskComplete( "movement_camp" )
                        self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPos, searchWant = 20, searchRadius = 1000 }, "i lost sight of them, and i was already perching hard" )

                    else -- start a new perching where we pick a pos with tighter criteria
                        --print( data.notSeeCount, data.maxNoSeeing, enemyMovedReallyFar, data.neverSeenEnemy, not self.IsSeeEnemy )
                        self.term_DontPerchAgain = CurTime() + 10
                        self:TaskComplete( "movement_camp" )
                        self:StartTask2( "movement_perch", { requiredTarget = self.EnemyLastPosOffsetted, earlyQuitIfSeen = true, distanceWeight = 0.1 }, "i lost sight of them" )

                    end

                    self.PreventShooting = nil

                elseif ( not self.IsSeeEnemy and data.notSeeCount > ( data.maxNoSeeing / 8 ) ) or data.lookinRightAtMeCount > 150 then
                    self:TaskComplete( "movement_camp" )
                    self:StartTask2( "movement_perch", { requiredTarget = self.EnemyLastPosOffsetted, earlyQuitIfSeen = true, distanceWeight = 1 }, "i saw them before, and lost sight of them" )

                -- exit if we took damage, or if we haven't seen an enemy 
                elseif ( not self.IsSeeEnemy and ( self:getLostHealth() > 1 and ( data.wasEnemy or data.neverSeenEnemy ) ) ) or data.campingCounter < -internalStaringTolerance then

                    self.campingFailures = self.campingFailures + 1

                    self:TaskComplete( "movement_camp" )
                    self:StartTask2( "movement_stalkenemy", { perchWhenHidden = true }, "im bored" )
                    self.PreventShooting = nil

                end
            end,
            OnKillEnemy = function( self, data )
                data.campingCounter = data.campingCounter + 25
                data.killedEnemy = true

            end,
            OnInstantKillEnemy = function( self, data ) -- my new favourite spot
                data.campingCounter = data.campingCounter + 1000
                data.killedEnemy = true

            end,
            ShouldCrouch = function( self )
                local enemy = self:GetEnemy()
                if not IsValid( enemy ) then return true end
                return terminator_Extras.PosCanSeeComplex( self:GetCrouchingShootPos(), self:EntShootPos( enemy ), self )
            end,
        },

        -- find 2 functions
            -- wep.termPlace_ScoringFunc -- takes navarea and returns value, higher value for better placement
            -- wep.termPlace_PlacingFunc -- returns pos that terminator should aim at before primary attacking

        -- optional variables
            -- wep.Range, bot only checks areas that are closer to it than this.
            -- wep.termPlace_MaxAreaSize, won't pick areas with a getsize x or y bigger than this.
            -- wep.termPlace_PlacingRange, for the placing half, not area choosing, this is the range from bot's shootpos, to where the weapon is placed on a surface

        ["movement_placeweapon"] = {
            OnStart = function( self, data )
                local wep = self:GetWeapon()
                local range = wep.Range or 2500
                data.potentialPlaceables = navmesh.Find( self:GetPos(), range, 100, 100 )
                data.scoredPlaceables = {}
                data.scoredAreas = {}
                data.hazardousAreas = self.hazardousAreas
                data.oldDistToBestPos = math.huge
                self:InvalidatePath( "placing wep, remove old path!" )
            end,
            BehaveUpdateMotion = function( self, data )
                local wep = self:GetWeapon()
                local armed = self:IsFists()

                local arePlaceableVecsToProcess = #data.potentialPlaceables >= 1
                local foundTheBestOne = isvector( data.bestPos )

                local unstucking = self.isUnstucking and not armed
                local notPlacing = not ( isfunction( wep.termPlace_ScoringFunc ) and isfunction( wep.termPlace_PlacingFunc ) )

                local canWep, potentialWep = self:canGetWeapon()
                if canWep and not self:primaryPathIsValid() and self:getTheWeapon( "movement_placeweapon", potentialWep, "movement_placeweapon" ) then
                    return

                elseif ( notPlacing and not unstucking ) or data.failed then
                    self:TaskFail( "movement_placeweapon" )
                    self:StartTask2( "movement_handler", nil, "i placed it!" )

                elseif self:getLostHealth() > 10 or self:inSeriousDanger() then
                    self:TaskComplete( "movement_placeweapon" )
                    self:StartTask2( "movement_handler", nil, "something hurt me!" )

                elseif self.IsSeeEnemy and self.DistToEnemy < 1500 then
                    self:EnemyAcquired( "movement_placeweapon" )

                elseif self:interceptIfWeCan( "movement_placeweapon", data ) then
                    return

                elseif self:validSoundHint() then
                    self:TaskComplete( "movement_placeweapon" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )

                elseif arePlaceableVecsToProcess then
                    local maxSize = wep.termPlace_MaxAreaSize or 200
                    local scoringFunc = wep.termPlace_ScoringFunc
                    if not data.nearestVolatileIds then
                        data.nearestVolatileIds = {}
                        data.nextVolatileUpdate = CurTime() + 0.25

                    end

                    if self.awarenessDamaging and data.nextVolatileUpdate < CurTime() then
                        local damagingAreas = self:DamagingAreas()
                        for _, volatileArea in ipairs( damagingAreas ) do
                            data.nearestVolatileIds[volatileArea:GetID()] = true

                        end
                    end
                    for _ = 1, 20 do
                        if #data.potentialPlaceables == 0 then break end
                        local toPlaceArea = table.remove( data.potentialPlaceables, 1 )
                        if not IsValid( toPlaceArea ) then continue end

                        local areasId = toPlaceArea:GetID()
                        if data.hazardousAreas[areasId] then continue end
                        if data.nearestVolatileIds[areasId] then continue end
                        if self.failedPlacingAreas[areasId] then continue end
                        if self.unreachableAreas[areasId] then continue end

                        if math.max( toPlaceArea:GetSizeX(), toPlaceArea:GetSizeY() ) > maxSize then continue end

                        local checkPositions = getUsefulPositions( toPlaceArea )

                        for _, checkPos in ipairs( checkPositions ) do
                            -- floor the pos
                            checkPos = checkPos + vectorUp * 5
                            local dat = {
                                start = checkPos,
                                endpos = checkPos + negativeFiveHundredZ,
                                mask = MASK_SOLID
                            }
                            local trace = util.TraceLine( dat )
                            local flooredPos = trace.HitPos

                            -- get final checkpos 
                            checkPos = flooredPos + plus25Z
                            -- ask wep for score
                            local scoreOfPos = scoringFunc( wep, self, checkPos )

                            data.scoredPlaceables[ scoreOfPos ] = checkPos
                            data.scoredAreas[ scoreOfPos ] = toPlaceArea

                        end
                    end
                elseif not foundTheBestOne then
                    if not data.scoredPlaceables then
                        self:TaskComplete( "movement_placeweapon" )
                        self:StartTask2( "movement_handler", nil, "nowhere to place stuff" )

                    else
                        data.bestPosScore = table.maxn( data.scoredPlaceables )
                        data.bestPos = data.scoredPlaceables[ data.bestPosScore ]
                        data.bestArea = data.scoredAreas[ data.bestPosScore ]

                        data.scoredPlaceables = nil
                        --debugoverlay.Text( data.bestPos, "a" .. data.bestPosScore, 10, false )

                    end

                -- get to the pos
                else
                    local myShootPos = self:GetShootPos()
                    local oldDist = data.oldDistToBestPos
                    local newDist = myShootPos:Distance( data.bestPos )
                    data.oldDistToBestPos = newDist

                    local progressMade = oldDist - newDist

                    local placingDist = wep.termPlace_PlacingRange or 45
                    local canSeePos, trResult = terminator_Extras.PosCanSeeComplex( myShootPos, data.bestPos, self )
                    local doPlace = progressMade < 4 and canSeePos and trResult.HitPos:DistToSqr( myShootPos ) < placingDist^2

                    -- at the pos
                    if doPlace then
                        if data.giveUpTime and data.giveUpTime < CurTime() then
                            data.failed = true
                            return

                        end
                        self:crouchToGetCloserTo( data.bestPos )
                        local placingAimSpot = wep:termPlace_PlacingFunc( self )
                        self:shootAt( placingAimSpot, false )

                    -- not there yet!
                    else
                        if self:primaryPathInvalidOrOutdated( data.bestPos ) then
                            self:SetupPathShell( data.bestPos )

                        end
                        local result = self:ControlPath2( not self.IsSeeEnemy )

                        if result == true then
                            data.placing = true

                        elseif result == false then
                            self:TaskFail( "movement_placeweapon" )
                            self:StartTask2( "movement_placeweapon", nil, "i couldnt path to the placing spot, try again please!" )
                            self.failedPlacingAreas[ data.bestArea:GetID() ] = true

                        else
                            data.giveUpTime = CurTime() + 1

                        end
                    end
                end
            end,
            ShouldRun = function( self, data )
                return self:canDoRun() and not SqrDistLessThan( self:GetPos():DistToSqr( self:GetPath():GetEnd() ), 200 )

            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()

            end,
        },
        ["movement_perch"] = {
            OnStart = function( self, data )
                data.perchRadius = data.perchRadius or 8000
                data.perchRadius = math.Clamp( data.perchRadius, 0, 8000 )
                data.distanceWeight = data.distanceWeight or 1
                data.potentialPerchables = navmesh.Find( self:GetPos(), data.perchRadius, self.loco:GetMaxJumpHeight(), self.loco:GetMaxJumpHeight() )
                data.nextPerchSort = CurTime() + 2
                data.lastPerchSortedPos = nil
                data.nextPath = CurTime() + 1

                data.scoredPerchables = {}
                data.nookOverrideDirections = {
                    -- cardinal directions with a bias downwards
                    -- Vector( 0.7, 0, -0.3 ),
                    -- Vector( -0.7, 0, -0.3 ),
                    -- Vector( 0, 0.7, -0.3 ),
                    -- Vector( 0, -0.7, -0.3 ),

                    -- 45 degree directions with a bias downwards
                    Vector( -0.35, 0.35, -0.15 ),
                    Vector( -0.35, -0.35, -0.15 ),
                    Vector( 0.35, 0.35, -0.15 ),
                    Vector( 0.35, -0.35, -0.15 ),

                }

            end,
            BehaveUpdateMotion = function( self, data )
                if self.IsSeeEnemy and IsValid( self:GetEnemy() ) and self:GetEnemy().isTerminatorHunterKiller then
                    self.PreventShooting = nil

                end

                local myPos = self:GetPos()
                local canWep, potentialWep = self:canGetWeapon()

                local enemysLastPos = self.EnemyLastPos
                local requiredTarget = data.requiredTarget
                local preferredPos = requiredTarget or enemysLastPos

                if data.bestPosSoFar and ( CurTime() % 10 ) < 5 then
                    self:shootAt( data.bestPosSoFar, true )

                else
                    self:shootAt( preferredPos, true )

                end

                if canWep and self:getTheWeapon( "movement_perch", potentialWep, "movement_perch" ) then
                    return

                elseif data.requiredTarget and self:interceptIfWeCan( "movement_perch", data ) then
                    return

                elseif self.IsSeeEnemy and IsValid( self:GetEnemy() ) and not ( requiredTarget and self.EnemyLastPos:Distance( requiredTarget ) < data.perchRadius / 2 and self.DistToEnemy > self.DuelEnemyDist ) then
                    self:EnemyAcquired( "movement_perch" )

                elseif self:validSoundHint() and not data.requiredTarget then
                    self:TaskComplete( "movement_perch" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint }, "i heard something" )

                elseif #data.potentialPerchables >= 1 then
                    for _ = 1, 2 do
                        if #data.potentialPerchables == 0 then break end
                        local perchableArea = table.remove( data.potentialPerchables, 1 )
                        if not IsValid( perchableArea ) then continue end
                        local checkPositions = getUsefulPositions( perchableArea )

                        if preferredPos and #checkPositions > 1 then
                            local bestDist = math.huge
                            local bestPos
                            for _, checkPos in ipairs( checkPositions ) do
                                local dist = checkPos:DistToSqr( preferredPos )
                                if dist < bestDist then
                                    bestPos = checkPos

                                end
                            end
                            if bestPos then
                                --debugoverlay.Cross( bestPos, 10, 20, color_white, true )
                                checkPositions = { bestPos }

                            end
                        end

                        for _, checkPos in ipairs( checkPositions ) do
                            yieldIfWeCan()
                            checkPos = checkPos + plus25Z
                            local dat = {
                                start = checkPos,
                                endpos = checkPos + negativeFiveHundredZ,
                                mask = MASK_SOLID
                            }

                            local trace = util.TraceLine( dat )
                            local flooredPos = trace.HitPos
                            checkPos = flooredPos + plus25Z

                            local nookScore = 1
                            local distance = checkPos:Distance( myPos ) * data.distanceWeight
                            local canSeeTargetMul = 1

                            if requiredTarget then
                                local _, canSeeTr = terminator_Extras.PosCanSeeComplex( checkPos, requiredTarget, self )
                                local hitNearby = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( requiredTarget ), 300 )
                                local hitAlmost = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( requiredTarget ), 50 )
                                if hitAlmost then -- probably hit it
                                    canSeeTargetMul = 200

                                elseif hitNearby then -- hit nearby it
                                    canSeeTargetMul = 8

                                else
                                    canSeeTargetMul = 0.01

                                end
                                --debugoverlay.Line( checkPos, requiredTarget, 10, color_white, true )

                            else
                                nookScore = terminator_Extras.GetNookScore( checkPos, 6000, data.nookOverrideDirections )

                            end
                            local zOffset = checkPos.z - myPos.z

                            local score = ( ( distance * 0.01 ) + zOffset * 4 ) / nookScore
                            score = score * canSeeTargetMul

                            data.scoredPerchables[ score ] = checkPos

                        end

                        local oldPathThink = data.oldPathThink or 0
                        if CurTime() == oldPathThink then continue end
                        data.oldPathThink = CurTime()

                        local bestPosScore = table.maxn( data.scoredPerchables )
                        if not bestPosScore then continue end

                        local bestPos = data.scoredPerchables[ bestPosScore ]
                        if not bestPos then continue end

                        data.bestPosSoFar = bestPos
                        local earlyQuit = data.earlyQuitIfSeen and self.IsSeeEnemy
                        yieldIfWeCan()

                        if data.lastPerchSortedPos ~= bestPos and data.nextPerchSort < CurTime() then
                            data.lastPerchSortedPos = bestPos
                            data.nextPerchSort = CurTime() + 5
                            local centers = {}
                            local distToSqrInternal = distToSqr
                            for _, area in ipairs( data.potentialPerchables ) do
                                if IsValid( area ) then
                                    centers[area] = area:GetCenter()

                                else
                                    return 

                                end
                            end
                            table.sort( data.potentialPerchables, function( a, b ) -- sort ents by distance to me 
                                local ADist = distToSqrInternal( centers[a], bestPos )
                                local BDist = distToSqrInternal( centers[b], bestPos )
                                return ADist < BDist

                            end )
                        end

                        if self:GetRangeTo( bestPos ) > 75 then
                            local nextPath = data.nextPath or 0

                            if nextPath < CurTime() and self:primaryPathInvalidOrOutdated( bestPos ) then
                                data.nextPath = CurTime() + 1
                                self:SetupPathShell( bestPos )

                            elseif self:PathIsValid() then
                                self:ControlPath2()

                            end
                        elseif self:IsOnGround() and ( earlyQuit or table.Count( data.scoredPerchables ) > #data.potentialPerchables * 0.15 ) then
                            local myShoot = self:GetShootPos()
                            local nookScore = terminator_Extras.GetNookScore( myShoot, 6000, data.nookOverrideDirections )

                            if requiredTarget then
                                local _, canSeeTr = terminator_Extras.PosCanSeeComplex( myShoot, requiredTarget, self )
                                local hitNearby = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( requiredTarget ), 150 )
                                if hitNearby and ( earlyQuit or nookScore >= 3.25 ) then
                                    data.potentialPerchables = {}
                                    return

                                end
                            end
                            if nookScore >= 2.5 then
                                data.potentialPerchables = {}
                                return

                            end
                        end
                    end
                elseif not data.bestPos then
                    data.bestPosScore = table.maxn( data.scoredPerchables )
                    data.bestPos = data.scoredPerchables[ data.bestPosScore ]

                    if data.requiredTarget and data.bestPos then
                        local _, canSeeTr = terminator_Extras.PosCanSeeComplex( data.bestPos, data.requiredTarget, self )
                        local canSee = SqrDistLessThan( canSeeTr.HitPos:DistToSqr( data.requiredTarget ), 200 )
                        local targetsNav = terminator_Extras.getNearestNav( data.requiredTarget )
                        if not canSee and IsValid( targetsNav ) then
                            local areas = { targetsNav }
                            table.Add( areas, targetsNav:GetAdjacentAreas() )
                            for _, area in ipairs( areas ) do
                                if area:IsVisible( data.bestPos ) then
                                    canSee = true
                                    break

                                end
                            end

                        end
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
                    if myPos:Distance( data.bestPos ) < 200 then
                        self.overrideCrouch = CurTime() + 0.5

                    end
                    if self:primaryPathInvalidOrOutdated( data.bestPos ) then
                        self:SetupPathShell( data.bestPos )
                        self.forcedShouldWalk = CurTime() + 1

                    end
                    local result = self:ControlPath2( not self.IsSeeEnemy )
                    if result == true or SqrDistLessThan( myPos:DistToSqr( data.bestPos ), 50 ) then
                        self:TaskComplete( "movement_perch" )
                        self:StartTask2( "movement_camp", nil, "i got to my camping spot" )

                    end
                end
            end,
            ShouldRun = function( self, data )
                local closeDist = self.RunSpeed * 0.75
                local closeToTheEnd = SqrDistLessThan( self:GetPos():DistToSqr( self:GetPath():GetEnd() ), closeDist )
                if closeToTheEnd then return false end

                return self:canDoRun()

            end,
            ShouldWalk = function( self, data )
                local closeDist = self.RunSpeed * 0.75
                local closeToTheEnd = SqrDistLessThan( self:GetPos():DistToSqr( self:GetPath():GetEnd() ), closeDist )
                if closeToTheEnd then return true end

                return self:shouldDoWalk()

            end,
        },
        ["movement_intercept"] = { -- activates when alerted of enemy by our buddy
            OnStart = function( self, data )
                if not self.isUnstucking then
                    self:InvalidatePath( "intercepting enemy, killing old path" )
                end
                data.gaveItAChanceTime = CurTime() + 4
                data.time = CurTime() + math.Rand( 0.01, 0.2 )
            end,
            BehaveUpdateMotion = function( self, data )
                if data.time and data.time > CurTime() then return end

                local lastInterceptPos              = self.lastInterceptPos
                local lastInterceptDir              = self.lastInterceptDir or vec_zero
                local lastInterceptDist2            = data.lastInterceptDistance2 or 0

                local nextPath = data.nextPath or 0
                if lastInterceptPos and nextPath < CurTime() then
                    data.nextPath = CurTime() + 0.4
                    local lastInterceptPosOffsetted = lastInterceptPos + Vector( 0, 0, 20 )

                    local predictedRelativeEnd = ( lastInterceptDir * math.random( 2500, 3500 ) )
                    local predictedTraceStart = lastInterceptPosOffsetted + ( lastInterceptDir * 100 )
                    local predictionTr = util.QuickTrace( predictedTraceStart, predictedRelativeEnd, nil )
                    -- in wall
                    if predictionTr.StartSolid or predictionTr.Entity:IsPlayer() then goto terminatorInterceptNewPathFail end
                    local predictedPos = predictionTr.HitPos

                    --debugoverlay.Line( predictedTraceStart, predictedPos, 20, Color( 255,255,255 ), true )
                    -- bring it down to the the ground
                    local floorTraceDat = {
                        start = predictedPos,
                        endpos = predictedPos + Vector( 0, 0, -2000 ),
                    }
                    local flooredTr = util.TraceLine( floorTraceDat )
                    local predictedPosOnSamePlane = flooredTr.HitPos.z > ( predictedPos.z - self.loco:GetMaxJumpHeight() )

                    -- limit silly behaviour where enemy is on a rooftop, and bots path to the streets below
                    -- don't remove entirely because the enemy could jump down there yknow 
                    if predictedPosOnSamePlane or ( flooredTr.Hit and math.random( 0, 100 ) < 25 ) then
                        predictedPos = flooredTr.HitPos

                    else
                        predictedPos = lastInterceptPosOffsetted

                    end

                    -- first proper check
                    if not self:primaryPathInvalidOrOutdated( predictedPos ) then goto terminatorInterceptNewPathFail end

                    local currDist2 = predictedPos:DistToSqr( lastInterceptPosOffsetted )
                    -- end here if this would place us closer to the enemy vs last time, we want to be far from the enemy if we can!
                    if SqrDistGreaterThan( lastInterceptDist2, currDist2 + 50 ) then goto terminatorInterceptNewPathFail end

                    self:InvalidatePath( "new intercept path time" )

                    local gotoResult = terminator_Extras.getNearestPosOnNav( predictedPos )
                    -- unreachable areas
                    local reachable = self:areaIsReachable( gotoResult.area )
                    if not reachable then
                        self.interceptPeekTowardsEnemy  = nil
                        self.lastInterceptTime          = nil
                        self.lastInterceptPos           = nil

                        data.Unreachable = true
                        return

                    end

                    local flankAroundPos = lastInterceptPosOffsetted
                    local flankBubble

                    local otherHuntersHalfwayPoint = self:GetOtherHuntersProbableEntrance()
                    -- BOX THEM IN BOX THEM IN
                    if otherHuntersHalfwayPoint then
                        flankAroundPos = otherHuntersHalfwayPoint
                        flankBubble = self:GetPos():Distance( otherHuntersHalfwayPoint ) * 0.7

                    end

                    local flankResult = terminator_Extras.getNearestPosOnNav( flankAroundPos )
                    yieldIfWeCan()

                    --debugoverlay.Cross( interceptResult.pos, 100, 5, color_white, true )

                    if IsValid( flankResult.area ) then
                        self:SetupFlankingPath( gotoResult.pos, flankResult.area, flankBubble )
                        yieldIfWeCan()
                        if self:primaryPathIsValid() then
                            data.lastInterceptDistance2 = currDist2

                        end
                    end

                    -- flank failed, normal path!
                    if not self:primaryPathIsValid() then
                        self:SetupPathShell( gotoResult.pos )
                        yieldIfWeCan()

                    end
                    if not self:primaryPathIsValid() then
                        data.Unreachable = true
                        self.interceptPeekTowardsEnemy  = nil
                        self.lastInterceptTime          = nil
                        self.lastInterceptPos           = nil
                        return

                    else
                        data.lastInterceptDistance2 = currDist2

                    end

                end
                ::terminatorInterceptNewPathFail::

                if not lastInterceptPos and not self:primaryPathIsValid() then
                    self:TaskFail( "movement_intercept" )
                    self:StartTask2( "movement_handler", nil, "nothing to intercept!" )
                    return

                end

                local myPos = self:GetPos()
                local path = self:GetPath()
                local pathIsMostlyDone = self:primaryPathIsValid( path ) and SqrDistLessThan( myPos:DistToSqr( path:GetEnd() ), self:MyPathLength( path ) / 2 )

                local result = self:ControlPath2( not self.IsSeeEnemy )
                local canWep, potentialWep = self:canGetWeapon()
                if self.PreventShooting and ( self:inSeriousDanger() or self:getLostHealth() > 1 or self:IsReallyAngry() ) then
                    self.PreventShooting = nil
                -- get WEAP
                elseif canWep and self:getTheWeapon( "movement_intercept", potentialWep, "movement_intercept" ) then
                    return
                elseif data.Unreachable then
                    --print( "unreach" )
                    self:TaskFail( "movement_intercept" )
                    self:GetTheBestWeapon()

                    local target = lastInterceptPos or self.EnemyLastPos
                    self:StartTask2( "movement_perch", { requiredTarget = target, earlyQuitIfSeen = true, perchRadius = self:GetRangeTo( target ) * 1.5, distanceWeight = 0.01 }, "i cant reach ya, time to snipe!" )

                elseif self.IsSeeEnemy and ( pathIsMostlyDone or self:inSeriousDanger() ) then
                    self:EnemyAcquired( "movement_intercept" )
                elseif pathIsMostlyDone and self:WeaponIsPlacable( self:GetWeapon() ) then
                    self:TaskComplete( "movement_intercept" )
                    self:StartTask2( "movement_placeweapon", nil, "i can place my wep and im almost at the intercept!" )
                elseif result then
                    self:TaskComplete( "movement_intercept" )
                    self:StartTask2( "movement_approachlastseen", { pos = self.lastInterceptPos }, "i got to the intercept" )
                end
            end,
            OnComplete = function( self, data )
            end,
            ShouldRun = function( self, data )
                return self:canDoRun()
            end,
            ShouldWalk = function( self, data )
                return self:shouldDoWalk()
            end,
        },
        ["inform_handler"] = {
            StartsOnInitialize = true,
            OnStart = function( self, data )
                data.Inform = function( enemy, pos, senderPos )
                    for _, ent in ipairs( self:GetNearbyAllies() ) do
                        if not IsValid( ent ) then continue end
                        ent:RunTask( "InformReceive", enemy, nil, pos, senderPos )

                    end
                end
            end,
            BehaveUpdatePriority = function( self, data, interval )
                local myTbl = data.myTbl
                local enemy = myTbl.GetEnemy( self )
                if not IsValid( enemy ) then return end
                if not myTbl.IsSeeEnemy then return end
                if data.EnemyPosInform and data.EnemyPosInform > CurTime() then return end

                local add
                if myTbl.isFodder then
                    add = math.Rand( 5, 10 )

                else
                    add = math.Rand( 2, 5 )

                end
                data.EnemyPosInform = CurTime() + add
                data.Inform( enemy, myTbl.EntShootPos( self, enemy ), self:GetPos() )

            end,
            InformReceive = function( self, data, enemy, _enemysTbl, pos, senderpos )
                if not senderpos or not IsValid( enemy ) then return end
                local myTbl = data.myTbl

                local realEnemy = myTbl.GetEnemy( self )

                if IsValid( realEnemy ) then
                    if realEnemy == enemy and myTbl.IsSeeEnemy then return end -- we are already attacking this guy! dont wast perf!

                    local _, priorityOfCurr = myTbl.TERM_GetRelationship( self, myTbl, realEnemy )
                    local _, priorityOfNew = myTbl.TERM_GetRelationship( self, myTbl, enemy )
                    if priorityOfCurr > priorityOfNew then return end -- dont care about low priority enemies if we already fighting something decent

                end

                -- it made another terminator mad! it makes me mad!
                myTbl.MakeFeud( self, enemy )

                myTbl.EnemyLastPos = pos

                myTbl.interceptPeekTowardsEnemy  = myTbl.CanSeePosition( self, enemy, myTbl, enemyTbl ) and math.random( 1, 100 ) < 75
                myTbl.lastInterceptTime          = CurTime()
                myTbl.lastInterceptPos           = pos

                myTbl.RegisterForcedEnemyCheckPos( self, enemy )

                local enemVel = enemy:GetVelocity()
                local velLeng = enemVel:LengthSqr()

                -- they arent moving, just go the opposite side of them!
                if velLeng < 5^2 then
                    local enemDir = -terminator_Extras.dirToPos( enemy:GetPos(), senderpos )
                    myTbl.lastInterceptDir = enemDir

                -- they moving fast in one direction!
                elseif velLeng > 50^2 then
                    local enemVelFlat = enemVel * Vector( 1, 1, 0 )
                    myTbl.lastInterceptDir = ( enemVelFlat ):GetNormalized()

                -- they are moving a bit, go left or right
                else
                    local enemDir = terminator_Extras.dirToPos( self:GetPos(), enemy:GetPos() )
                    local upOrDown = { 1, -1 }
                    myTbl.lastInterceptDir = enemDir:Cross( Vector( 0, 0, table.Random( upOrDown ) ) )

                end
            end,
        },
        ["playercontrol_handler"] = {
            StartsOnInitialize = true,
            StopControlByPlayer = function( self, data, ply )
                self:StartTask2( "enemy_handler", nil, "begin" )
                self:StartTask2( "movement_handler", nil, "begin" )
                self:StartTask2( "shooting_handler", nil, "begin" )
            end,
        },
    }
end
