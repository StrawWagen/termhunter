
local function giveCamera( arazzi )
    arazzi:Give( "gmod_camera" )

end

local newEvent = {
    -- chance for this to happen, rolled every minute
    defaultPercentChancePerMin = 0.05,

    -- does this event progress through a "dedication" cvar?
    doesDedicationProgression = true,
    -- does this event need a map with a navmesh
    navmeshEvent = true,
    variants = {
        -- event variants are checked in sequential order
        -- variant 1, 1 paparazzi, will despawn after seeing player
        {
            variantName = "chancePaparazziMeeting",
            getIsReadyFunc = nil,
            minDedication = 0, -- this event will always happen
            overrideChance = 25, -- chance to override other events
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius", -- will try to spawn this AS FAR as possible from all players
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
            minDedication = 2, -- this event will only happen after the player completes 2 other 'example' events
            overrideChance = 25, -- chance for this to override the above event, because it will get picked first
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
                    repeats = 2, -- X count of this will exist in the unspawnedStuff list, so 3 total will spawn including the scout

                },
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
        {
            variantName = "largeScoutedPaparazzi",
            getIsReadyFunc = nil,
            minDedication = 4, -- only after completing 4 other 'example' events
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
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
    },
}

terminator_Extras.RegisterEvent( newEvent, "paparazzi_sighting" )