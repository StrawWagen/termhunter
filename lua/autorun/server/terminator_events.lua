AddCSLuaFile( "autorun/client/terminator_cl_events.lua" )

util.AddNetworkString( "terminator_event_setupclientvars" )
util.AddNetworkString( "terminator_event_askforallcvars" )

local debuggingVar = CreateConVar( "terminator_event_debug", 0, FCVAR_REPLICATED, "Debug the terminator event system", 0, 1 )
local debugging = debuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_event_debug", function( _, _, new )
    debugging = tobool( new )

end, "updatedebugging" )

local function debugPrint( ... )
    if not debugging then return end
    permaPrint( ... )

end

local enabledVar = CreateConVar( "terminator_event_enabled", 1, FCVAR_ARCHIVE, "Enable/disable all dynamic terminator events?", 0, 1 )
local chanceBoostVar = CreateConVar( "terminator_event_globalchanceboost", 0, FCVAR_ARCHIVE, "Boosts the chance of ALL events happening.", -100, 100 )

local chanceVarNamePrefix = "terminator_eventchance_"

terminator_Extras = terminator_Extras or {}
local terminator_Extras = terminator_Extras
terminator_Extras.activeEvents = terminator_Extras.activeEvents or {}
terminator_Extras.events = {}

terminator_Extras.activeEventThinkInterval = 0.1

local hour = 3600
terminator_Extras.defaultSpawnTimeoutTime = hour / 2


local CurTime = CurTime

local activePly

local function theActivePlyIs( ply )
    activePly = ply

end

local function getActivePly()
    if IsValid( activePly ) then
        return activePly

    else
        return Entity( 1 )

    end
end

local function aPlyIsLoaded()
    local firstPly = getActivePly()
    if not IsValid( firstPly ) then return end
    if not firstPly:IsPlayer() then return end
    if not firstPly.GetShootPos then return end

    return true

end

local function getDedication( varName )
    if not aPlyIsLoaded() then return 0 end
    return getActivePly():GetInfoNum( varName, 0 ) or 0

end

local fallback = -111112 -- nobody will ever crack this
local function makeSureTheyGotDedi( ply, varName )
    local dedi = ply:GetInfoNum( varName, fallback )
    if dedi == fallback then
        debugPrint( "asking for ply to setup var", ply, varName )
        SetGlobal2Bool( varName, true ) -- these cant be spoofed, right??
        timer.Simple( 0.1, function()
            if not IsValid( ply ) then return end
            net.Start( "terminator_event_setupclientvars" )
                net.WriteString( varName )
            net.Send( ply )
        end )
        return false

    else
        return true

    end
end

net.Receive( "terminator_event_askforallcvars", function( _, ply )
    local cur = CurTime()
    local nextRecieve = ply.termEvents_NextAskForAllCvars or 0
    if nextRecieve > cur then return end

    ply.termEvents_NextAskForAllCvars = cur + 2.5

    local time = 0
    for _, event in pairs( terminator_Extras.events ) do
        if not event.dedicationInfoNum then continue end
        timer.Simple( time, function()
            if not IsValid( ply ) then return end
            makeSureTheyGotDedi( ply, event.dedicationInfoNum )
            time = time + 0.01

        end )
    end
end )


function terminator_Extras.RegisterEvent( event, name )
    local variants = event.variants
    if not istable( variants ) then ErrorNoHaltWithStack( name .. ": Invalid .variants table" ) return end

    local defaultChance = event.defaultPercentChancePerMin
    if not isnumber( defaultChance ) then ErrorNoHaltWithStack( name .. ": Invalid .defaultPercentChancePerMin" ) return end

    -- above, validate event
    -- below, setup helpers and parse it

    local varName = chanceVarNamePrefix .. name

    event.eventChanceVar = CreateConVar( varName, -1, FCVAR_ARCHIVE, "% Chance for a \"" .. name .. "\" event to start every minute. -1 for default, " .. defaultChance, -1, 100 )
    local function doEventChance() -- handle the defaulting
        local eventChanceRaw = event.eventChanceVar:GetFloat()
        if eventChanceRaw <= -1 then
            eventChanceRaw = defaultChance

        end
        event.eventChance = eventChanceRaw
    end

    doEventChance() -- set it on creation
    cvars.AddChangeCallback( varName, function() doEventChance() end, "term_eventlocalvar" ) -- live updates

    event.eventName = name -- helper

    if event.doesDedicationProgression then
        event.dedicationInfoNum = "cl_termevent_" .. name .. "_dedication"

    end

    local initializeFunc = event.initializeFunc
    if initializeFunc then
        initializeFunc( event )

    end

    function event:OnStart()
        local onStartFunc = self.onStartFunc
        if isfunction( onStartFunc ) then
            ProtectedCall( function( eventProtected ) eventProtected.onStartFunc( eventProtected ) end, self )

        end
    end
    function event:OnStop( reason )
        debugPrint( "event stopped ", self.eventName, reason )
        local onStopFunc = self.onStopFunc
        if isfunction( onStopFunc ) then
            ProtectedCall( function( eventProtected ) eventProtected.onStopFunc( eventProtected ) end, self )

        end
    end

    local refreshed = istable( terminator_Extras.events[name] )
    terminator_Extras.events[name] = event
    if refreshed then
        permaPrint( "TERMevents: Refreshed " .. name )

    else
        permaPrint( "TERMevents: Initialized " .. name )

    end
end

function terminator_Extras.InitializeAllEvents()
    local spawnsetFiles = file.Find( "terminator_events/*.lua", "LUA" )
    for _, name in ipairs( spawnsetFiles ) do
        ProtectedCall( function( nameProtected ) include( "terminator_events/" .. nameProtected ) end, name )

    end
end

terminator_Extras.InitializeAllEvents()


local aiDisabledVar = GetConVar( "ai_disabled" )
local freebies = {}

local thinkInterval = 60
local eventRollTimerName = "terminator_eventroll"

local function startEventRollTimer()
    timer.Create( eventRollTimerName, thinkInterval, 0, function()
        terminator_Extras.eventRollThink()

    end )
end

startEventRollTimer()

function terminator_Extras.eventRollThink()
    if not enabledVar:GetBool() then return end
    if not aPlyIsLoaded() then return end

    local haveNav = navmesh.GetNavAreaCount() > 0
    local activeEvents = terminator_Extras.activeEvents
    local chanceBoost = chanceBoostVar:GetFloat()

    local pickedEventName
    local pickedVariant
    local pickedVariantInd
    local aiDisabled = aiDisabledVar:GetBool()

    for name, event in pairs( terminator_Extras.events ) do
        if aiDisabled and not event.worksWhenAIDisabled then continue end
        if event.navmeshEvent and not haveNav then debugPrint( name, " no nav" ) continue end
        if aiDisabled and not event.ignoreAiDisabled then continue end
        if activeEvents[name] then debugPrint( name, " already active" ) continue end

        local rand = math.Rand( 0, 100 )
        local chance = event.eventChance + chanceBoost
        if not freebies[name] and rand > chance then debugPrint( chance, rand, name, " fail random " ) continue end
        freebies[name] = nil

        local dedication
        if event.dedicationInfoNum then
            local theyGot = makeSureTheyGotDedi( getActivePly(), event.dedicationInfoNum )
            if not theyGot then
                debugPrint( "waiting for firstply to setup infonum", event.dedicationInfoNum )
                freebies[name] = true
                thinkInterval = 5
                timer.Adjust( eventRollTimerName, thinkInterval )
                continue

            end

            dedication = getDedication( event.dedicationInfoNum )

        end

        for variantInd, variant in ipairs( event.variants ) do
            if variant.getIsReadyFunc and not event.getIsReadyFunc( event ) then debugPrint( name, " fail getIsReady" ) continue end
            if dedication then
                if variant.minDedication and dedication < variant.minDedication then
                    --debugPrint( name, " too early" )
                    continue

                end
                if variant.maxDedication and dedication > variant.maxDedication then
                    --debugPrint( name, " too late" )
                    continue

                end
            end
            if not pickedVariantInd then
                pickedVariant = variant
                pickedEventName = name
                pickedVariantInd = variantInd

            elseif variant.overrideChance and math.Rand( 0, 100 ) < variant.overrideChance then
                pickedVariant = variant
                pickedEventName = name
                pickedVariantInd = variantInd

            end
        end

        if pickedVariantInd then break end

    end

    if thinkInterval ~= 30 then
        thinkInterval = 30
        timer.Adjust( thinkInterval, thinkInterval )

    end

    if not pickedVariantInd then return end

    debugPrint( pickedEventName, " PICKED ", pickedVariant.variantName )
    terminator_Extras.startEvent( pickedEventName, pickedVariantInd )

end


function terminator_Extras.startEvent( eventName, pickedVariantInd )
    local eventCopy = table.Copy( terminator_Extras.events[eventName] )
    eventCopy.activeVariantInd = pickedVariantInd

    eventCopy.spawned = {}
    eventCopy.spawnedAlive = {}
    eventCopy.participatingPlayers = {}

    local oldCount = table.Count( terminator_Extras.activeEvents )
    terminator_Extras.activeEvents[eventName] = eventCopy

    debugPrint( eventName, "EVENT STARTING" )

    if oldCount > 0 then return end -- dont setup this hook if it's already running!
    hook.Add( "Think", "terminator_manageactiveevents", function()
        local returned = terminator_Extras.manageActiveEvents()
        if returned == false then
            hook.Remove( "Think", "terminator_manageactiveevents" )

        end
    end )
end

local function isOrphan( startArea, allAreas )
    local orphanCount = math.min( #allAreas, 150 )
    local open = { startArea }
    local openedIndex = {}
    local closedIndex = {}
    while #open > 0 and table.Count( closedIndex ) < orphanCount do
        local area = table.remove( open, 1 )
        for _, neighbor in ipairs( area:GetAdjacentAreas() ) do
            if openedIndex[neighbor] then continue end
            if closedIndex[neighbor] then continue end
            table.insert( open, neighbor )
            openedIndex[neighbor] = true

        end

        closedIndex[area] = true

    end
    if #open <= 0 then
        return true

    end
    return false

end

local spawnDist = 3000
local minSpawnDist = 1500

local function steppedRandomRadius( currToSpawn, plyCount, allAreas, maxRad )
    local maxCount = math.Clamp( 25 + -plyCount, 5, 25 )
    local currSpawnDist = spawnDist^2
    local currMaxSpawnDist
    if maxRad == math.huge then
        currMaxSpawnDist = maxRad

    else
        currMaxSpawnDist = ( maxRad + 4000 ) ^2

    end

    local spawnPos

    for _ = 1, maxCount do
        local randomArea = allAreas[math.random( 1, #allAreas )]
        if not IsValid( randomArea ) then
            debugPrint( "invalid area, skipping" )
            continue

        end
        if randomArea:IsUnderwater() and not currToSpawn.canSpawnUnderwater then maxCount = maxCount + 1 continue end

        local areasCenter = randomArea:GetCenter()
        local bad
        for _, ply in player.Iterator() do
            local distSqr = ply:GetShootPos():DistToSqr( areasCenter )
            if distSqr < currSpawnDist or distSqr > currMaxSpawnDist then
                bad = true
                break

            end
        end
        if bad then continue end
        if terminator_Extras.areaIsInterruptingSomeone( randomArea, areasCenter ) then continue end

        if isOrphan( randomArea, allAreas ) then continue end

        spawnPos = areasCenter

    end
    if not spawnPos then -- failed to find spot, let them spawn closer
        local newDist = spawnDist - ( maxCount * 25 )
        spawnDist = math.Clamp( newDist, minSpawnDist, maxRad )

    else
        local newDist = spawnDist + maxCount
        spawnDist = math.Clamp( newDist, minSpawnDist, maxRad )
        return spawnPos

    end
end

local function eventManage( event )
    local wait
    if event.scoutWaiting then
        local scout = event.scout
        if not IsValid( scout ) then -- THE SCOUT DIED WITHOUT SEEING ENEMY
            return "done"

        else
            wait = not scout.termEvent_HasMet

        end
    end

    local activeVariantInd = event.activeVariantInd
    local activeVariant = event.variants[activeVariantInd]

    local needsToSpawn = #activeVariant.unspawnedStuff >= 1 and not wait

    if needsToSpawn then
        local plyCount = player.GetCount()
        local allAreas = navmesh.GetAllNavAreas()

        local spawnPos
        local currToSpawn = activeVariant.unspawnedStuff[1]
        local algo = currToSpawn.spawnAlgo
        if algo == "steppedRandomRadius" then
            spawnPos = steppedRandomRadius( currToSpawn, plyCount, allAreas, math.huge )

        elseif algo == "steppedRandomRadiusNearby" then
            spawnPos = steppedRandomRadius( currToSpawn, plyCount, allAreas, 4000 )

        elseif algo == "teammateSpawn" then
            local teammate = event.spawnedAlive[math.random( 1, #event.spawnedAlive )]
            if IsValid( teammate ) and teammate.GetShootPos then
                local stepHeight = teammate.loco:GetStepHeight()
                local teammateAreas = navmesh.Find( teammate:GetPos(), math.random( 2000, 6000 ), stepHeight, stepHeight )
                spawnPos = steppedRandomRadius( currToSpawn, plyCount, teammateAreas, 6000 )

            else
                spawnPos = steppedRandomRadius( currToSpawn, plyCount, allAreas, 4000 )

            end
        end
        if spawnPos then
            local toSpawn = activeVariant.unspawnedStuff[1]
            if toSpawn.repeats and toSpawn.repeats >= 1 then
                toSpawn.repeats = toSpawn.repeats + -1
                toSpawn = table.Copy( toSpawn )

            else
                toSpawn = table.remove( activeVariant.unspawnedStuff, 1 )

            end

            local curr = ents.Create( toSpawn.class )
            if not IsValid( curr ) then return "SPAWNFAIL" end -- :(
            if debugging then
                local color = Color( 255, 255, 255 )
                debugoverlay.Line( getActivePly():GetShootPos() + getActivePly():GetAimVector() * 50, spawnPos, 5, color, true )
                debugoverlay.Box( spawnPos, Vector( -25, -25, 0 ), Vector( 25, 25, 0 ), 5, ColorAlpha( color, 50 ) )

            end

            if toSpawn.preSpawnedFunc then
                toSpawn.preSpawnedFunc( curr, toSpawn )

            end
            debugPrint( "EVENT spawned", curr )
            curr:SetPos( spawnPos )
            curr:Spawn()

            if toSpawn.onSpawnedFunc then
                toSpawn.onSpawnedFunc( curr, toSpawn )

            end

            table.insert( event.spawned, curr )

            if curr.GetShootPos then
                table.insert( event.spawnedAlive, curr )

                curr.termEvent_DeleteAfterMeet = toSpawn.deleteAfterMeet
                if toSpawn.scout then -- saves on perf, this npc holds up the spawning until it sees an enemy
                    event.scout = curr
                    event.scoutWaiting = true
                    curr.termEvent_Scout = true

                end
            end
            if toSpawn.timeout then
                if toSpawn.timeout == true then
                    toSpawn.timeout = terminator_Extras.defaultSpawnTimeoutTime

                end
                curr.termEvent_TimeoutTime = toSpawn.timeout
                curr.termEvent_TimeoutWhen = CurTime() + toSpawn.timeout

            end
            return "spawnedsomething"

        else
            return "wait"

        end
    else -- manage ALIVE
        for ind, curr in pairs( event.spawned ) do
            if not IsValid( curr ) then table.remove( event.spawned, ind ) continue end

            local enemy = curr.IsSeeEnemy and curr:GetEnemy() or nil
            if enemy and enemy:IsPlayer() then
                local isParticipating = event.participatingPlayers[enemy]
                if not isParticipating then
                    isParticipating = true
                    event.participatingPlayers[enemy] = isParticipating
                    makeSureTheyGotDedi( enemy, event.dedicationInfoNum ) -- get em ready!
                    if not IsValid( activePly ) then
                        theActivePlyIs( enemy )

                    end
                end
                curr.termEvent_HasMet = true
                curr.termEvent_MetRememberance = 200
                if curr.termEvent_TimeoutTime then
                    curr.termEvent_TimeoutWhen = CurTime() + curr.termEvent_TimeoutTime

                end
                if activeVariant.concludeOnMeet then
                    event.concluded = true

                end
            elseif curr.termEvent_HasMet then
                if curr.termEvent_DeleteAfterMeet and curr.termEvent_MetRememberance <= 0 then
                    SafeRemoveEntity( curr )

                else
                    curr.termEvent_MetRememberance = curr.termEvent_MetRememberance + -1

                end
            else
                local timeoutWhen = curr.termEvent_TimeoutWhen
                if timeoutWhen and timeoutWhen < CurTime() then
                    if terminator_Extras.posIsInterrupting( curr:WorldSpaceCenter(), false ) then
                        curr.termEvent_TimeoutWhen = CurTime() + curr.termEvent_TimeoutTime
                        debugPrint( curr, " timeout INTERRUPT!" )

                    else
                        debugPrint( curr, " TIMEOUT!" )
                        SafeRemoveEntity( spawned )

                    end
                end
            end
        end

        -- all done!
        if #event.spawned <= 0 then return "done" end

    end
end

function onConcluded( event )
    local participatorCount = table.Count( event.participatingPlayers )
    if event.dedicationInfoNum and participatorCount > 0 then
        local bestDedication = 0
        local bestDedicationPly
        local dedications = {}
        for ply, _ in pairs( event.participatingPlayers ) do
            if not IsValid( ply ) then continue end
            local theirDedication = ply:GetInfoNum( event.dedicationInfoNum, 0 )
            dedications[ply] = theirDedication

            if theirDedication > bestDedication then
                bestDedication = theirDedication
                bestDedicationPly = ply

            end
        end
        if not IsValid( bestDedicationPly ) then return end
        theActivePlyIs( bestDedicationPly )

        for ply, _ in pairs( event.participatingPlayers ) do -- this is kinda stupid, should base dedi off of the variant's dedi
            if not IsValid( ply ) then continue end

            -- catchup dedication faster for people lagging behind
            local newDedi = math.min( bestDedication + 1, dedications[ply] + 2 )

            ply:ConCommand( event.dedicationInfoNum .. " " .. newDedi )
            debugPrint( "upgraded dedi for", ply, dedications[ply] .. " to " .. newDedi )

        end
    end
end

function terminator_Extras.manageActiveEvents()
    local cur = CurTime()
    local managedCount = 0
    for eventType, event in pairs( terminator_Extras.activeEvents ) do
        managedCount = managedCount + 1
        local nextThink = event.nextThink or 0
        if nextThink > cur then continue end

        local interval = event.thinkInterval or terminator_Extras.activeEventThinkInterval

        local returned = eventManage( event )
        if returned == "done" then
            if event.concluded then
                onConcluded( event )
                event:OnStop( "concluded" )

            else
                event:OnStop( "done" )

            end
            terminator_Extras.activeEvents[eventType] = nil

        elseif returned == "wait" then
            event.nextThink = cur + ( interval * math.Rand( 10, 20 ) )

        else
            event.nextThink = cur + interval

        end
    end
    if managedCount <= 0 then
        return false

    end
end

hook.Add( "PreCleanupMap", "terminator_resetevents", function()
    local activeEvents = terminator_Extras.activeEvents
    for _, event in pairs( activeEvents ) do
        event:OnStop( "mapcleanup" )

    end

    terminator_Extras.activeEvents = {}
end )


local nextCheck = CurTime() + 120

hook.Add( "Think", "terminator_restartthedamntimer", function()
    local cur = CurTime()
    if nextCheck > cur then return end
    nextCheck = cur + 120

    if timer.Exists( eventRollTimerName ) then return end
    startEventRollTimer()

end )