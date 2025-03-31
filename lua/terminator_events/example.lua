
local newEvent = {
    defaultPercentChancePerMin = 0.01,

    doesDedicationProgression = true,
    navmeshEvent = true,
    variants = {
        {
            variantName = "chancePaparazziMeeting",
            getIsReadyFunc = nil,
            minDedication = 0,
            overrideChance = 25, -- chance to override other events
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius",
                    deleteAfterMeet = true,
                    timeout = true, -- if bot has no enemy for this long, despawns em, true means it sets to the default, 30 min

                }
            },
            thinkInterval = nil, -- makes it default to terminator_Extras.activeEventThinkInterval
            concludeOnMeet = true,
        },
        {
            variantName = "smallScoutedPaparazzi",
            getIsReadyFunc = nil,
            minDedication = 2,
            overrideChance = 25,
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadius",
                    scout = true, -- halts the spawning until this guy sees an enemy
                    timeout = true,

                },
                {
                    class = "terminator_nextbot_fakeply",
                    spawnAlgo = "steppedRandomRadiusNearby",
                    repeats = 2

                },
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
        {
            variantName = "largeScoutedPaparazzi",
            getIsReadyFunc = nil,
            minDedication = 4,
            overrideChance = 25,
            unspawnedStuff = {
                {
                    class = "terminator_nextbot_jerminator",
                    spawnAlgo = "steppedRandomRadius",
                    scout = true,
                    timeout = true,

                },
                {
                    class = "terminator_nextbot_jerminator",
                    spawnAlgo = "steppedRandomRadiusNearby",
                    repeats = 10

                },
            },
            thinkInterval = nil,
            concludeOnMeet = true,
        },
    },
}

terminator_Extras.RegisterEvent( newEvent, "paparazzi_sighting" )