
local function giveCamera( arazzi )
    arazzi:Give( "gmod_camera" )

end

local newEvent = {
    -- chance for this to happen, rolled every minute
    defaultPercentChancePerMin = 0.05,
    -- each player who says the keyword this session adds chanceIncrease % to the chance
    secret = {
        keyword = "im famous",
        chanceIncrease = 1,
    },

    -- does this event progress through a "dedication" cvar?
    doesDedicationProgression = true,
    -- does this event need a map with a navmesh
    navmeshEvent = true,
    -- can this event start while ai_disabled is on?
    -- worksWhenAIDisabled = true,

    -- called once, when the event is registered
    -- initializeFunc = function( event ) end,
    -- called on the active copy of the event, when it starts/stops
    -- onStartFunc = function( event ) end,
    -- onStopFunc = function( event ) end,

    -- each time the event starts, it picks and runs ONE of these variants
    -- first eligible variant gets picked, later ones can steal the pick via overrideChance
    variants = {
        -- variant 1, 1 paparazzi, will despawn after seeing player
        {
            variantName = "chancePaparazziMeeting",
            getIsReadyFunc = nil, -- function( event ), return false to skip this variant
            minDedication = 0, -- this variant is always eligible
            -- maxDedication = 10, -- ineligible once the player has completed 10 'paparazzi_sighting' events
            overrideChance = 25, -- does nothing on the first variant, it's never stealing
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius", -- will try to spawn this AS FAR as possible from all players
                    -- preSpawnedFunc = function( ent, toSpawn ) end, -- before ent:Spawn()
                    onSpawnedFunc = giveCamera,
                    deleteAfterMeet = true, -- deletes the bot after .IsSeeEnemy is true, then not true for a while
                    timeout = true, -- if bot has no enemy for this long, despawns em, true means it sets to the default, 30 min

                }
            },
            thinkInterval = nil, -- makes it default to terminator_Extras.activeEventThinkInterval
            concludeOnMeet = true, -- this is what actually makes the event increase a dedication cvar, if one of the bots see a player
        },
        {
            variantName = "smallScoutedPaparazzi",
            getIsReadyFunc = nil,
            minDedication = 2, -- eligible after the player completes 2 'paparazzi_sighting' events
            overrideChance = 25, -- % chance to steal the pick from the variant above
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius",
                    onSpawnedFunc = giveCamera,
                    scout = true, -- halts the spawning until this guy sees an enemy
                    timeout = true,

                },
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadiusNearby", -- spawns it far from players, but within at least 4000 units of them
                    onSpawnedFunc = giveCamera,
                    repeats = 2, -- X count of this will exist in the unspawnedStuff list, so 2 will spawn, 3 including the above scout

                },
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
        {
            variantName = "largeScoutedPaparazzi",
            getIsReadyFunc = nil,
            minDedication = 4, -- eligible after 4 completed 'paparazzi_sighting' events
            overrideChance = 25,
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius",
                    onSpawnedFunc = giveCamera,
                    scout = true,
                    timeout = true,

                },
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadiusNearby",
                    onSpawnedFunc = giveCamera,
                    repeats = 10, -- 11 total will spawn including the scout

                },
                -- {
                --     class = "terminator_nextbot_fakeply",
                --     spawnAlgo = "teammateSpawn", -- spawns near a random bot this event already spawned
                --     onSpawnedFunc = giveCamera,
                --
                -- },
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
    },
}

terminator_Extras.RegisterEvent( newEvent, "paparazzi_sighting" )

-- hooks, these run for every event, so filter by event.eventName
--[[

-- runs for every event, every roll, before its chance is rolled
-- return false to stop the event from starting
hook.Add( "terminator_event_canstart", "example_paparazzi_canstart", function( event )
    if event.eventName ~= "paparazzi_sighting" then return end
    if #player.GetHumans() == 0 then return false end

end )

-- the event is starting, this runs once per variant it could pick
-- return false to make that variant ineligible
hook.Add( "terminator_event_canstartvariant", "example_paparazzi_canstartvariant", function( event, variant, variantInd )
    if event.eventName ~= "paparazzi_sighting" then return end
    if variant.variantName == "largeScoutedPaparazzi" and player.GetCount() < 2 then return false end

end )

hook.Add( "terminator_event_started", "example_paparazzi_started", function( event )
    if event.eventName ~= "paparazzi_sighting" then return end
    print( "paparazzi started, variant", event.variants[event.activeVariantInd].variantName )

end )

-- edit spawnPos in place to move the spawn, reassigning it does nothing
hook.Add( "terminator_event_prespawn", "example_paparazzi_prespawn", function( event, ent, toSpawn, spawnPos )
    if event.eventName ~= "paparazzi_sighting" then return end
    spawnPos.z = spawnPos.z + 10

end )

hook.Add( "terminator_event_spawned", "example_paparazzi_spawned", function( event, ent, toSpawn )
    if event.eventName ~= "paparazzi_sighting" then return end
    ent:Give( "weapon_crowbar" )

end )

-- first time each player gets involved
hook.Add( "terminator_event_playerjoined", "example_paparazzi_playerjoined", function( event, ply, ent )
    if event.eventName ~= "paparazzi_sighting" then return end
    ply:ChatPrint( "You feel watched..." )

end )

-- first time each bot sees a player
hook.Add( "terminator_event_met", "example_paparazzi_met", function( event, ent, ply )
    if event.eventName ~= "paparazzi_sighting" then return end
    ent:EmitSound( "npc/scanner/scanner_photo1.wav" )

end )

-- deleteAfterMeet bot is about to be removed, return false to keep it forever
hook.Add( "terminator_event_forgotten", "example_paparazzi_forgotten", function( event, ent )
    if event.eventName ~= "paparazzi_sighting" then return end
    if ent:Health() < ent:GetMaxHealth() then return false end -- someone hurt it, it holds a grudge

end )

-- bot never met anyone and is about to time out, return false to restart its timer
hook.Add( "terminator_event_timeout", "example_paparazzi_timeout", function( event, ent )
    if event.eventName ~= "paparazzi_sighting" then return end
    if event.scout == ent then return false end

end )

-- runs before dedication is upgraded, only when a concludeOnMeet variant met a player
hook.Add( "terminator_event_concluded", "example_paparazzi_concluded", function( event )
    if event.eventName ~= "paparazzi_sighting" then return end
    for ply in pairs( event.participatingPlayers ) do
        if not IsValid( ply ) then continue end
        ply:ChatPrint( "You got papped." )

    end
end )

-- reason is "done", "concluded", or "mapcleanup"
hook.Add( "terminator_event_stopped", "example_paparazzi_stopped", function( event, reason )
    if event.eventName ~= "paparazzi_sighting" then return end
    print( "paparazzi stopped", reason )

end )

--]]