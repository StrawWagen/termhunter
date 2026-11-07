-- Shared memory of where things happened, stored on navareas.
--
--  local term_Heat = terminator_Extras.term_Heat
--  term_Heat.RegisterLayer( "my_deaths", { perFaction = true } )
--  term_Heat.AddAround( "my_deaths", bot.isTerminatorHunterChummy, bot:GetPos(), 100, 1 )
--  ENT.HeatAvoidance = { my_deaths = 1 } -- bots path around it
--
-- Heat fades by itself, so it outlives the bots that made it, but not forever.
-- perFaction layers keep one heatmap per isTerminatorHunterChummy, everything else is shared by all.

terminator_Extras = terminator_Extras or {}
terminator_Extras.term_Heat = terminator_Extras.term_Heat or {}

local term_Heat = terminator_Extras.term_Heat
term_Heat.Layers = term_Heat.Layers or {}

local IsValid = IsValid
local CurTime = CurTime
local math_min = math.min
local math_Rand = math.Rand
local pairs = pairs
local ipairs = ipairs
local navMeta = FindMetaTable( "CNavArea" )
local GetID = navMeta.GetID

local THINK_INTERVAL = 3 -- decay functions are tuned around this
local GLOBAL_KEY = "global"

local debuggingVar = CreateConVar( "terminator_heat_debug", 0, FCVAR_NONE, "Draw every heat layer's areas, needs developer 1.", 0, 1 )
local debugging = debuggingVar:GetBool()
cvars.AddChangeCallback( "terminator_heat_debug", function( _, _, new )
    debugging = tobool( new )

end, "updatedebugging" )

-- fades slowly while fresh, then faster the longer nothing's been added
function term_Heat.StaleDecay( heat, sinceLastAdd )
    local staleness = 1 + ( sinceLastAdd ^ 1.11 ) / 10
    return heat - math_Rand( 0.05, 0.1 ) * staleness

end

--[[
    cfg fields, all optional
    perFaction  - one heatmap per faction, instead of one everyone shares
    decay       - function( heat, sinceLastAdd ) returning the new heat, runs every 3 seconds. Defaults to term_Heat.StaleDecay
    cap         - max heat an area can hold
    hotSpot     - track a hot spot for GetHotSpot, costs a bit every think
    onThink     - function( state, factionKey ) called after each decay, state.hotSpot is ready by then
--]]
function term_Heat.RegisterLayer( name, cfg )
    local old = term_Heat.Layers[name]
    cfg.states = old and old.states or {} -- keep the heat across autorefresh
    term_Heat.Layers[name] = cfg

end

local function getState( layer, faction, create )
    local key = GLOBAL_KEY
    if layer.perFaction then
        if not isstring( faction ) then return end -- factionless bots have nobody to share with
        key = faction

    end
    local state = layer.states[key]
    if state or not create then return state end

    state = { heat = {}, lastAdd = {}, count = 0 }
    layer.states[key] = state
    return state

end

local function getLayer( name )
    local layer = term_Heat.Layers[name]
    if not layer then ErrorNoHaltWithStack( "terminator heat layer \"" .. tostring( name ) .. "\" was never registered" ) end
    return layer

end

local function addOne( state, cap, area, amount, cur )
    if not IsValid( area ) then return end
    local heat = state.heat
    local id = GetID( area )
    local old = heat[id]
    if not old then
        old = 0
        state.count = state.count + 1

    end
    heat[id] = math_min( old + amount, cap )
    state.lastAdd[id] = cur

end

-- adds amount to each area, so split it yourself if it should be spread out
function term_Heat.Add( name, faction, areas, amount )
    local layer = getLayer( name )
    if not layer then return end
    local state = getState( layer, faction, true )
    if not state then return end

    local cap = layer.cap or math.huge
    local cur = CurTime()
    for _, area in ipairs( areas ) do
        addOne( state, cap, area, amount, cur )

    end
end

-- Add for one area, without making a table
function term_Heat.AddToArea( name, faction, area, amount )
    local layer = getLayer( name )
    if not layer then return end
    local state = getState( layer, faction, true )
    if not state then return end

    addOne( state, layer.cap or math.huge, area, amount, CurTime() )

end

function term_Heat.AddAround( name, faction, pos, radius, amount, height )
    height = height or 64
    term_Heat.Add( name, faction, navmesh.Find( pos, radius, height, height ), amount )

end

function term_Heat.Get( name, faction, area )
    local layer = getLayer( name )
    if not layer then return 0 end
    local state = getState( layer, faction )
    if not state then return 0 end
    return state.heat[GetID( area )] or 0

end

-- heat of the hottest of these areas, eg along a path, and that area
function term_Heat.GetMaxAlong( name, faction, areas )
    local layer = getLayer( name )
    if not layer then return 0 end
    local state = getState( layer, faction )
    if not state then return 0 end

    local heat = state.heat
    local hottest = 0
    local hottestArea
    for _, area in ipairs( areas ) do
        if not IsValid( area ) then continue end
        local areasHeat = heat[GetID( area )]
        if areasHeat and areasHeat > hottest then
            hottest = areasHeat
            hottestArea = area

        end
    end
    return hottest, hottestArea

end

-- area id -> heat, live, don't write to it
-- nil when there's no heat at all
function term_Heat.GetHeatTable( name, faction )
    local layer = getLayer( name )
    if not layer then return end
    local state = getState( layer, faction )
    if not state then return end
    return state.heat

end

-- one of the hottest areas, with some randomness, so not everyone piles onto the same one
-- updated every 3 seconds, needs hotSpot = true on the layer
function term_Heat.GetHotSpot( name, faction )
    local layer = getLayer( name )
    if not layer then return end
    if not layer.hotSpot then ErrorNoHaltWithStack( "terminator heat layer \"" .. name .. "\" doesn't track a hot spot" ) return end
    local state = getState( layer, faction )
    if not state then return end
    return state.hotSpot, state.hotSpotHeat

end

local function decayState( layer, state, cur )
    local decay = layer.decay or term_Heat.StaleDecay
    local trackHotSpot = layer.hotSpot
    local heat = state.heat
    local lastAdd = state.lastAdd

    local bestId
    local bestScore = 0
    for id, oldHeat in pairs( heat ) do
        local newHeat = decay( oldHeat, cur - lastAdd[id] )
        if newHeat <= 0 then
            heat[id] = nil
            lastAdd[id] = nil
            state.count = state.count - 1

        else
            heat[id] = newHeat
            if trackHotSpot then
                local score = newHeat * math_Rand( 0.75, 1.25 )
                if score > bestScore then
                    bestId = id
                    bestScore = score

                end
            end
        end
    end

    if not trackHotSpot then return end
    state.hotSpot = bestId and navmesh.GetNavAreaByID( bestId )
    state.hotSpotHeat = bestId and heat[bestId] or 0

end

local textOffset = Vector( 0, 0, 20 )

-- hotter areas draw redder, relative to the hottest in the same heatmap
local function debugDraw( name, key, state )
    local maxHeat = 0
    for _, heat in pairs( state.heat ) do
        if heat > maxHeat then maxHeat = heat end

    end
    if maxHeat <= 0 then return end

    for id, heat in pairs( state.heat ) do
        local area = navmesh.GetNavAreaByID( id )
        if not IsValid( area ) then continue end

        local fade = 255 - math.Round( ( heat / maxHeat ) * 255 )
        local color = Color( 255, fade, fade )
        for corner = 0, 3 do
            debugoverlay.Line( area:GetCorner( corner ), area:GetCorner( ( corner + 1 ) % 4 ), THINK_INTERVAL, color, true )

        end
        debugoverlay.Text( area:GetCenter() + textOffset, name .. " " .. key .. " " .. math.Round( heat, 2 ), THINK_INTERVAL, false )

    end

    local hotSpot = state.hotSpot
    if IsValid( hotSpot ) then
        debugoverlay.Cross( hotSpot:GetCenter(), 40, THINK_INTERVAL, color_white, true )

    end
end

local function think()
    local cur = CurTime()
    for name, layer in pairs( term_Heat.Layers ) do
        local states = layer.states
        for key, state in pairs( states ) do
            if state.count <= 0 then
                states[key] = nil
                continue

            end
            decayState( layer, state, cur )

            if debugging then
                debugDraw( name, key, state )

            end

            local onThink = layer.onThink
            if onThink then
                ProtectedCall( function() onThink( state, key ) end )

            end
        end
    end
end

timer.Create( "terminator_heat_think", THINK_INTERVAL, 0, think )

hook.Add( "PostCleanupMap", "terminator_heat_clear", function()
    for _, layer in pairs( term_Heat.Layers ) do
        layer.states = {}

    end
end )
