# termhunter
Experimental Nextbot + Base.  
Allows for very complicated custom behaviour.  
For basing NPCs off this, it doesn't support custom animations that well, it expects player animations by default, but there is limited support for other methods. ( see nextbot zambies below )

Best for creating code-driven AI agents that relentlessly pursue their enemies, crouching, jumping, attacking obstacles.  
Supports optimized custom weights on pathfinding, good if you want a bot to avoid a dangerous area, avoid an obvious entrance to a room, etc.  
Limited but functional support for custom, non-player shaped enemies, would not recommend working with this base if you've just finished a custom non-player model and want it to attack you.  


See [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2944078031) page for more info, check [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies) and [Jerma985 Nextbot](https://github.com/StrawWagen/the_jerminator) for examples of NPCs based off this  

This project is a highly modified, optimized version of [this nextbot base](https://github.com/ShadowBonnieRUS/GMOD-SB_Advanced_Nextbots_Base)

Convars
```

Behaviour
termhunter_health -1/99999999 "Override the terminator's health, -1 for default"
termhunter_fovoverride -1/180 "Override the terminator's FOV, -1 for default"
termhunter_modeloverride <any string> "Override the terminator nextbot's spawned-in model. Model needs to be rigged for player movement"
termhunter_doextremeunstucking 0/1 "Teleport terminators medium distances if they get really stuck?"
termhunter_dropuselessweapons 0/1 "Detect and drop useless weapons? Does not stop bot from dropping erroring weapons"

Bot debugging
term_debugpath 0/1 "Debug terminator paths? Requires sv_cheats to be 1"
term_debugtasks 0/1 "Debug terminator tasks? Also enables a task history dump on bot +use."
term_debug_totaloverbudgetyields <1 to start, 0 to stop.> "Prints the yields that are collectively draining FPS"
term_debug_worstoverbudgetyields <1 to start, 0 to stop.> "Prints the yields spiking performance, causing tiny freezes"

Infighting
terminator_block_random_infighting 0/1 "Block random infighting?"
terminator_block_infighting 0/1 "Disable ALL infighting, even non-random infighting?"

Weapon dropping
terminator_playerdropweapons 0/1 "Should players drop all their weapons when killed by terminators?"
terminator_playerdropweapons_droppedcount 1-inf "How many weapons to drop when terminators kill players, Default 6"

Event system
terminator_event_enabled 0/1 "Enable/disable all dynamic terminator events?"
terminator_event_globalchanceboost -100/100 "Boosts the chance of ALL events happening."
terminator_event_debug "Debug the terminator event system"

Following patcher, Creates connections, triggers areapatcher
terminator_followpatcher_enable 0/1 "Patches the navmesh as players wander the map, Leads to terminators feeling smarter, following you through windows. Only runs with at least 1 bot spawned."
terminator_followpatcher_maxplayers 0/1 "Max amount of plys to process at a time, the system always prioritizes players being actively chased. -1 for default"
terminator_followpatcher_debug 0/1 "Debug the following patcher."

Areapatcher
terminator_areapatching_enable 0/1 "Creates new areas if players, bots, end up off the navmesh. Only runs with at least 1 bot spawned."
terminator_areapatching_rate 0/1 "Max fraction of a second the area patcher can run at, -1 for default"
terminator_areapatching_debugging 0/1 "Enable areapatcher debug-prints/visualizers."
```

