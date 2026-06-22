# termhunter
Experimental Nextbot + Base.  
Allows for very complicated custom behaviour.  
For basing NPCs off this, it doesn't support custom animations that well, it expects player animations by default, but there is limited support for custom animations (see below for more info).

Best for creating code-driven AI agents that relentlessly pursue their enemies, crouching, jumping, climbing ladders, attacking obstacles.  
Supports optimized custom weights on pathfinding, good if you want a bot to avoid a dangerous area, avoid an obvious entrance to a room, etc.  
Includes a live navmesh generator that activates when bots are getting stuck, or their enemies are escaping into spots the default navmesh generator missed! (this can be disabled if say, you have authored navmeshes, see convars section!)  
Limited but functional support for custom, non-player shaped enemies, would not recommend working with this base if you've just finished a custom non-player model and want it to attack you.  


See [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2944078031) page for more info.
Check [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies)
    (NPCs with a fully custom brain)
And [Jerma985 Nextbot](https://github.com/StrawWagen/the_jerminator)
    (Flat reskins with no real custom behaviour)

This project is a highly modified, optimized version of [this nextbot base](https://github.com/ShadowBonnieRUS/GMOD-SB_Advanced_Nextbots_Base)  
The terminator model shipped with this, comes from [this fantastic addon!](https://steamcommunity.com/workshop/filedetails/?id=488823530)
(I only compressed some of the textures!)

## Convars
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

Perf debugging, finds laggy code running before the found yields.
term_debug_totaloverbudgetyields 0/1 "Prints the yields that are collectively draining FPS"
term_debug_worstoverbudgetyields 0/1 "Prints the yields spiking performance, causing tiny freezes"
term_debug_pathbudget 0/1 "Prints the total costs of every pathing yield"
term_debug_luamem 0/1 "Prints the yields taking up the most lua memory"

Infighting
terminator_block_random_infighting 0/1 "Block random infighting?"
terminator_block_infighting 0/1 "Disable ALL infighting, even non-random infighting?"

Weapon dropping
terminator_playerdropweapons 0/1 "Should players drop all their weapons when killed by terminators?"
terminator_playerdropweapons_droppedcount -1/inf "How many weapons to drop when terminators kill players, -1 for default (6)"
terminator_cleanupdroppedweps 0/1 "Cleanup weapons dropped by term bots after some time?"

Event system
terminator_event_enabled 0/1 "Enable/disable all dynamic terminator events?"
terminator_event_globalchanceboost -100/100 "Boosts the chance of ALL events happening."
terminator_event_debug 0/1 "Debug the terminator event system"
cl_termevent_resetallprogress "Requests the cvars for every event, then resets them all to 0"
cl_termevent_getallprogress "Requests the cvars for every event"

Following patcher, Only creates connections between navareas.
This should always be enabled, no navmesh is perfect.
terminator_followpatcher_enable 0/1 "Patches the navmesh as players wander the map, Leads to terminators feeling smarter, following you through windows. Only runs with at least 1 bot spawned."
terminator_followpatcher_maxplayers -1/inf "Max amount of plys to process at a time, the system always prioritizes players being actively chased. -1 for default"
terminator_followpatcher_debug 0/1 "Debug the following patcher."

Areapatcher, Creates navareas.
Disable this if you have manually curated navmeshes, it's slightly experimental.
terminator_areapatching_enable 0/1 "Creates new areas if players, bots, end up off the navmesh. Only runs with at least 1 bot spawned."
terminator_areapatching_rate -1/1 "Max fraction of a second the area patcher can run at, -1 for default"
terminator_areapatching_debugging 0/1 "Enable areapatcher debug-prints/visualizers."
```


## Overriding Animations

The terminator base expects player animations by default. To use custom animations (like zombie animations), override `ENT.IdleActivityTranslations`.

This table maps the bot's internal activities to custom [ACT enums](https://wiki.facepunch.com/gmod/Enums/ACT). The bot will automatically use these translations when playing animations for movement, attacks, reloading, etc.

```lua
local IdleActivity = ACT_HL2MP_IDLE_ZOMBIE
ENT.IdleActivity = IdleActivity
ENT.IdleActivityTranslations = {
    [ACT_MP_STAND_IDLE]                 = IdleActivity,
    [ACT_MP_WALK]                       = IdleActivity + 1,
    [ACT_MP_RUN]                        = IdleActivity + 2,
    [ACT_MP_CROUCH_IDLE]                = ACT_HL2MP_IDLE_CROUCH,
    [ACT_MP_CROUCHWALK]                 = ACT_HL2MP_WALK_CROUCH,
    [ACT_MP_ATTACK_STAND_PRIMARYFIRE]   = IdleActivity + 5,
    [ACT_MP_ATTACK_CROUCH_PRIMARYFIRE]  = IdleActivity + 5,
    [ACT_MP_RELOAD_STAND]               = IdleActivity + 6,
    [ACT_MP_RELOAD_CROUCH]              = IdleActivity + 7,
    [ACT_MP_JUMP]                       = ACT_HL2MP_JUMP_FIST,
    [ACT_MP_SWIM]                       = ACT_HL2MP_SWIM,
    [ACT_LAND]                          = ACT_LAND,
}
```

These entries can also be a function, eg 
```lua
ENT.IdleActivity = function( self ) 
    return ACT_HL2MP_IDLE_ZOMBIE
    
end
```

The above example gives the bot zombie animations. See [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies) for a complete implementation.

**Playing animations with DoGesture:**  
You can also play animation layers (gestures) over the bot's current animation using,

`bot:DoGesture( act, speed, wait )`:
- `act` - Activity enum (ACT_*) or sequence name string
- `speed` - Playback rate (default 1.0, lower = slower)
- `wait` - If true, blocks bot behavior/movement until gesture finishes

You'll see expanded examples of this in the MySpecialActions section below.


## ENT.MyClassTask System

Simple way to add entity-class behaviour to your custom nextbot based on termhunter.  
Interacts uniquely with baseclassing, every single class in the baseclass hierarchy gets their MyClassTask and callbacks created.

**Important:** This is NOT for adding advanced movement tasks.
Use `ENT:DoCustomTasks` instead for complex movement behavior. (more info below)

### Usage Example

```lua
ENT.MyClassTask = {
    -- CREATION/INITIALIZATION --
    -- OnPreCreated = function( self, data )
        -- Called before model is set, before basic initialization
    -- end,
    
    OnCreated = function( self, data )
        -- Called after basic initialization, after model set, before weapons
        -- Good for setting color, bodygroups, or initial state
    end,
    
    -- OnPostCreated = function( self, data )
        -- Called 1 tick after creation, after weapon/relationship setup
        -- Good for logic that needs everything else ready
    -- end,
    
    -- OnRemoved = function( self, data )
        -- Called when bot is removed
    -- end,
    
    
    -- ENEMY CALLBACKS --
    EnemyFound = function( self, data, newEnemy, secondsSinceLastEnemy )
        -- Called when bot first acquires an enemy
        -- newEnemy: The new enemy entity
        -- secondsSinceLastEnemy: Time since last enemy was lost
    end,
    
    -- EnemyChanged = function( self, data, newEnemy, oldEnemy )
        -- Called when bot switches to a different enemy
        -- newEnemy: The new enemy entity
        -- oldEnemy: The previous enemy entity
    -- end,
    
    EnemyLost = function( self, data, oldEnemy )
        -- Called when bot loses current enemy
        -- oldEnemy: The enemy that was lost
    end,
    
    
    -- THINK/BEHAVIOR CALLBACKS --
    Think = function( self, data )
        -- ALWAYS runs in a coroutine, whether AI or player controlled
        -- Good for constant checks and updates
    end,
    
    BehaveUpdateMotion = function( self, data )
        -- Runs inside the motion coroutine
        -- Best for performance-heavy operations like pathfinding
    end,
    
    BehaveUpdatePriority = function( self, data )
        -- Runs in the priority coroutine with enemy finding
        -- Good for things that MUST run at all times and aren't too expensive
    end,

    -- PlayerControlUpdate = function( self, data, ply )
        -- Runs in a coroutine while the bot is controlled by a player
    -- end,
    
    
    -- DAMAGE CALLBACKS --
    -- OnDamaged = function( self, data, dmg )
        -- Called when bot takes damage
        -- Return true to completely block the damage
    -- end,
    
    -- OnInjured = function( self, data, dmg )
        -- Called when bot is injured (from base nextbot)
    -- end,
    
    -- OnDrown = function( self, data )
        -- Called when bot is actively drowning
    -- end,
    
    -- PreventBecomeRagdollOnKilled = function( self, data, dmg )
        -- Return true to prevent ragdoll creation on death
        -- Return second value true to prevent bot removal
    -- end,

    
    -- DEATH CALLBACKS --
    OnKilled = function( self, data, attacker, inflictor, ragdoll )
        -- Called when bot dies
        -- attacker: Who killed the bot
        -- inflictor: Weapon/entity that killed the bot
        -- ragdoll: The ragdoll entity created (if any)
    end,
    
    -- OnKilledDmg = function( self, data, dmg )
        -- Called when bot dies, passes the actual CTakeDamageInfo
    -- end,
    
    -- GetDeathAnim = function( self, data, dmg )
        -- Return death animation data table
        -- Example table;
        -- return {
            -- act = ACT_GMOD_GESTURE_TAUNT_ZOMBIE,
            -- rate = 0.75,
            -- startFunc = function( self ) end -- optional
            -- finishFunc = function( self ) end -- optional
        --}
    -- end,
    
    -- OnStartDying = function( self, data, dmg )
        -- Called when death animation starts, if death animation is used
    -- end,
    
    
    -- WEAPON/ATTACKING CALLBACKS --
    -- OnWeaponEquip = function( self, data, wep )
        -- Called when bot equips any weapon.
    -- end,
    
    -- OnWeaponDrop = function( self, data, wep )
        -- Called when bot drops a weapon.
    -- end,
    
    -- GetWeapon = function( self, data )
        -- Called right before bot picks a weapon off the ground via default movement_getweapon task
        -- Never called if bot doesn't use the default movement_getweapon task
    -- end,
    
    -- OnAttack = function( self, data )
        -- Called when bot attacks/shoots
    -- end,

    -- OnMightStartAttacking = function( self, data )
        -- Repeatedly called when bot is in a state where it might soon attack
        -- Great if you want a bot to raise its weapon before it attacks, etc
    -- end
    
    -- OnKillEnemy = function( self, data, victim )
        -- Called when bot kills an enemy
    -- end,
    
    -- These two callbacks are exclusive, the bot either kills the enemy, or instant kills them

    -- OnInstantKillEnemy = function( self, data, victim )
        -- Called when bot one-shots an enemy
    -- end,
    
    
    -- PLAYER CONTROL CALLBACKS --
    -- StartControlByPlayer = function( self, data, ply )
        -- Called when a player starts controlling the bot
    -- end,
    
    -- StopControlByPlayer = function( self, data, ply )
        -- Called when a player stops controlling the bot  
    -- end,
    
    
    -- MOVEMENT/MOTION CALLBACKS --
    -- TranslateActivity = function( self, data, act )
        -- Return translated activity/animation to override default
        -- Good if you want the bot to say, use a different walking animation when not angry
    -- end,

    -- ShouldCrouch = function( self, data )
        -- Return true to make bot crouch
    -- end,
    
    -- ShouldRun = function( self, data )
        -- Return true to make bot run
    -- end,
    
    -- ShouldWalk = function( self, data )
        -- Return true to make bot walk
    -- end,

    -- AdditionalFootstep = function( self, data, footPos, foot, stepSound, volume, filter )
        -- return true to override default footstep logic
        -- NOTE: The footstep system is very well documented and dynamic
        -- fully consider and understand footsteps.lua before resorting to this
    -- end,

    -- OnJump = function( self, data, height )
        -- Called when bot jumps
    -- end,
    
    -- OnJumpToPos = function( self, data, pos, height )
        -- Called when bot jumps to a specific position via self:JumpToPos
    -- end,
    
    -- OnJumpOutOfWater = function( self, data, height )
        -- Called when bot attempts to jump out of the water
    -- end,
    
    -- OnLandOnGround = function( self, data, groundEnt, fallHeight )
        -- Called when bot lands after falling/jumping
    -- end,
    
    -- DealtGoobmaDamage = function( self, data, damage, fallHeight, dealt )
        -- Called when self.ReallyHeavy bots fall far,
        -- and dealt 'goomba' damage to stuff they landed on, or landed next to. 
    -- end,
    
    -- OnStuck = function( self, data )
        -- Called when bot is stuck intersecting another entity.
    -- end,
    
    -- OnUnStuck = function( self, data )
        -- Called when bot gets itself unstuck, no longer intersecting another entity.
    -- end,
    
    -- OnAnger = function( self, data )
        -- Called when bot becomes angry via self:Anger, or self:IsAngry checks
    -- end,
    
    -- OnReallyAnger = function( self, data )
        -- Called when bot becomes angry via self:ReallyAnger, or self:IsReallyAngry checks
        -- Bots will be really angry when low health, recently damaged
    -- end,
    
    -- OnPathFail = function( self, data, pathEndPos, failString )
        -- Called after a pathfinding attempt fails
        -- pathEndPos: The position the path was trying to reach
        -- failString: Description of why the path failed
    -- end,
    
    -- ModifyMovementSpeed = function( self, data, speed )
        -- Return modified desired movement speed 
    -- end,
    
    -- DisableBehaviour = function( self, data )
        -- Return true to disable bot behavior, same logic as ai_disabled
    -- end,

    -- OnFinishBuildingPath = function( self, data, path, endPos, wasGood )
        -- Called right after bots finish building their path
    -- end
    
    
    -- ALLY/TEAM CALLBACKS --
    -- OnBlockingAlly = function( self, data, ally, sinceStarted )
        -- Called when this bot is blocking an ally's path.
        -- This isn't exhaustive, expect false positives, false negatives
    -- end,
    
    -- OnBlockedByAlly = function( self, data, blocker, sinceStarted )
        -- Called when this bot is blocked by an ally
        -- Same as above, not exhaustive
    -- end,


    -- TASK CALLBACKS --
    -- These are best used in custom movement tasks, etc.
    -- Very useful when coding custom npc brains, not so useful for ClassTasks
    
    -- OnStart = function( self, data )
        -- Called when the task starts
        -- Unlike OnCreated, Which is called when the bot itself is :Initialized
    -- end,

    -- OnFail = function( self, data )
        -- Called when self:TaskFail( taskName ) is ran
    -- end,
    
    -- OnComplete = function( self, data )
        -- Called when self:TaskComplete( taskName ) is ran
    -- end,
    
    -- OnEnd = function( self, data )
        -- Called when either TaskComplete or TaskFail is ran
    -- end, 
}
```

**Notes:** 
1. All callbacks receive `data` as the second parameter - this is the task's data table where you can store state between calls.  
   Like storing variables on self, but for the task only.
2. Every class in the heirarchy has their classtask & callbacks created.
   
   Say you make your npc play... A laughing sound in OnDamaged, all npcs based off it will laugh.
   
   Even if those npcs have their own .MyClassTask, with their own OnDamaged callback playing a SCREAMING sound, they will still laugh! (and scream...)


## ENT.MySpecialActions System

The MySpecialActions system exists to be a standardized way for bots to define custom attacks. (& more!)

Say you want to script a ranged attack for your NPC, this was made as ***the*** spot for that to be built.

If you make it a Special Action, that means the playercontrol system *and* the AI controller can both seamlessly use the attack. 

### Example: Dance Action

```lua
ENT.MySpecialActions = {
    ["Dance"] = {
        inBind = IN_USE, -- IN_ Input for players driving this bot to trigger this action
        drawHint = true, -- Show hint to player when driving bot, lots of default, silent actions exist, like switching weapons, etc
        name = "Dance", -- Display name shown to player
        desc = "Makes the bot dance", -- unused for now
        ratelimit = 2, -- Minimum 2 seconds between uses
        
        svAction = function( driveController, driver, bot )
            bot:EmitSound( "vo/npc/male01/yeah02.wav" )

            -- Do the dance gesture, with a slower rate, and block movement while it happens
            bot:DoGesture( ACT_GMOD_TAUNT_DANCE, 0.75, true )
 
        end,
    },
}

```
### Triggering actions through code

```lua
self:TakeAction( "Dance" )
```

You can also check if an action can be taken (it might be on ratelimit?):
```lua
if self:CanTakeAction( "Dance" ) then
    self:TakeAction( "Dance" )
end
```

### Special Action Properties

**Required:**
- `.name` (string) - Display name of the action

**Optional:**
- `.desc` (string) - Description of the action (currently unused)
- `.inBind` (number) - `IN_*` bitflag for detecting player input (e.g., `IN_ZOOM`, `IN_USE`)
- `.commandName` (string) - Console command string (e.g., "+reload", "impulse 100")
  - If both `inBind` and `commandName` are defined, both must be pressed for the action to trigger
- `.drawHint` (bool or function) - Whether to show hint while driving
  - Can be a function that returns bool: `function( bot ) return bot.SomeCondition end`
- `.ratelimit` (number) - Minimum seconds between action uses
- `.uses` (number) - Maximum number of times action can be used (<=0 means unlimited)
- `.svAction` (function) - Server-side action logic: `function( driveController, driver, bot )`
- `.clAction` (function) - Client-side action logic: `function( driveController, driver, bot )`

### Action Override System

Actions in derived classes override base class actions with the same name:

```lua
-- In base class
ENT.MySpecialActions = {
    ["Dance"] = {
        name = "Dance",
        svAction = function( drive, driver, bot )
            -- Base implementation
        end,
    },
}

-- In derived class - this completely replaces the base "Dance" action
ENT.MySpecialActions = {
    ["Dance"] = {
        name = "Breakdance",
        ratelimit = 0.5,
        svAction = function( drive, driver, bot )
            -- New implementation
        end,
    },
}
```

## Mixing ENT.MySpecialActions and ENT.MyClassTask

Let's say you want your bot to walk up to people and dance?
How would you do that?

Well MyClassTask and MySpecialActions are basically designed to work together.

Here's an example!

```lua
-- Only dance if the bot is this close to the enemy!
ENT.DanceDistance = 500

-- Setup the Dance action!
ENT.MySpecialActions = {
    ["Dance"] = {
        inBind = IN_USE,
        drawHint = true,
        name = "Dance",
        desc = "Makes the bot dance",
        ratelimit = 2,
        
        svAction = function( driveController, driver, bot )
            bot:EmitSound( "vo/npc/male01/yeah02.wav" )
            bot:DoGesture( ACT_GMOD_TAUNT_DANCE, 0.75, true )
 
        end,
    },
}

-- Tell the AI how and when to call the Dance action!
ENT.MyClassTask = {
    -- Put this in the BehaveUpdatePriority callback
    -- Don't wanna put it in BehaveUpdateMotion.
    -- Would lead to the bot not dancing, if it's stuck thinking about a path and the enemy walks up to it! 
    BehaveUpdatePriority = function( self, data )
        local enemy = self:GetEnemy()
        if not IsValid( enemy ) then return end -- first, wait until there's a valid enemy

        -- self.IsSeeEnemy is a helper variable managed by the default enemy_handler
        -- it's false if theres any map geometry, static props between us and our enemy
        -- it's updated on a semi-regular basis, so can be out of date.
        -- but it's good enough for this and it would be a shame to start dancing with an enemy who can't see us yet!
        if not self.IsSeeEnemy then return end

        -- self.DistToEnemy is like self.IsSeeEnemy, except it's always the last distance to an enemy.
        if self.DistToEnemy > self.DanceDistance then return end

        -- check if the action is on cooldown!
        -- TakeAction also checks this, but it's just good practice to check before calling it
        if not self:CanTakeAction( "Dance" ) then return end

        self:TakeAction( "Dance" )

    end,
}
```

---

## Overridable Functions

**`ENT:AdditionalClientInitialize()`** — *client* — end of client realm :Initialize. Good for visual setup.
```lua
local mySpecialColor = Color( 255, 0, 0 )

function ENT:AdditionalClientInitialize()
    self:SetColor( mySpecialColor )

end
```

**`ENT:AdditionalInitialize( myTbl )`** — *server* — end of server realm :Initialize, weapons and relationships are already set up.
```lua
function ENT:AdditionalInitialize( myTbl )
    self.MyCustomState = true

end
```

**`ENT:Draw()`** — *client* — override to customise rendering. Default just draws the model.
```lua
local entMeta = FindMetaTable( "Entity" )

function ENT:Draw()
    entMeta.DrawModel( self ) -- saves an _index call vs self:DrawModel()

end
```

**`ENT:Think()`** — *client* — not defined by the base, freely override for per-frame effects.
```lua
function ENT:Think()
    -- particles, looping sounds, etc.

end
```

The following are deprecated — use `MyClassTask` callbacks instead:
- `ENT:AdditionalThink( myTbl )` → `Think`
- `ENT:AdditionalOnLandOnGround( ent, fallHeight )` → `OnLandOnGround`
- `ENT:AdditionalFootstep( ... )` → check the `ENT.` variables in `footsteps.lua` first, use the `AdditionalFootstep` callback if your usecase is too complex

---


### now you might be thinking..

"That's great, but i want to add a custom brain to my npc!"

Adding custom behaviour is extremely tough, fraught with pitfalls and lag.

If you go down this path,
you will make great use of...
## ENT:DoCustomTasks( defaultTasks )

The nextbot base provides many useful generic tasks that can be extracted, used in derived NPCs
This function exposes them, for you to build your own self.TaskList

### "enemy_handler"
Manages acquiring, finding, losing enemies.
    Manages these useful variables
    - `self.IsSeeEnemy` true if there is no map geometry between bot and it's enemy.
    - `self.NothingOrBreakableBetweenEnemy` true if there's either breakable props, or nothing at all between the bot and it's enemy.
    - `self.DistToEnemy` distance to current enemy, or distance to last enemy if no valid enemy
    - `self.EnemiesVehicle` current enemy's vehicle if they are a player and inside a valid vehicle
    - `self.LastEnemySpotTime` last CurTime() we had a valid line of sight to an enemy
    - `self.LastEnemyShootPos` the GetShootPos of the last enemy we saw
    - `self.EnemyLastMoveDir` the direction of movement of the last enemy we saw
    - `self.EnemyLastPos` the last position we saw any enemy at
    - `self.EnemyLastPosOffsetted` above, but offsetted 150u in the direction of EnemyLastMoveDir

### "shooting_handler"
Manages...
    - aiming. 
    - shooting at current enemy. 
    - dropping crappy weapons.
    - reloading weapons
    - looking around while pathing

### "awareness_handler"
Manages an essential local cache of nearby objects
    NPCs use this cache to...
    Find objects blocking their path (to beat them up)
    To find SLAMs, harmful traps to path around
    To find explosive barrels nearby their enemy, to shoot!
    To find nearby weapons...
    
    #### the exact cache name
    - `self.AwarenessCheckRange` radius of the cache (do not make this too big, will slow down bots A LOT)
    - `self.awarenessSubstantialStuff` all 'substantial' entities within this radius, ENT:caresAbout gates this table
    
    #### If the bot is not self.IsFodder and has self.HasBrains... these caches are kept
    - `self.awarenessDamaging` ents that match any class+model combos that have damaged the bot before
    - `self.awarenessVolatiles` explosive ents, can be any class+model combos that have done explosive damage to the bot
        (explosive barrels included by default)
    
    #### If the bot has self.TERM_FISTS set to any weapon classname
    - `self.awarenessBash` very breakable entities, locked doors aswell
    - `self.awarenessLockedDoors` locked doors, these generate NAV_MESH_BLOCKED_PROPDOOR flags,
        caused many pathfinding issues, so bots hate them with a passion

### "reallystuck_handler"
Background stuck checker.
    Always checking to see if the bot...
    - Hasn't moved location for some time.
    - Somehow ended up under a displacement.
    - Has self.overrideVeryStuck set to true.

    If any of these conditions are met, this sequence of events is started...
    1. A nearby navarea is selected
    2. All active bot tasks that begin with "movement_" are STOPPED
    3. The bot is then forced to move itself towards the nearby area
    4. movement_handler is then restarted
    If this fails, and the bot somehow didn't get to the area, it's then teleported.

### "inform_handler"
Manages sharing enemy position and relation with allies.
    - `self.InformRadius` defines the enemy information sharing distance

### "trancebreaking_handler"
Hacky fix to old terminator nextbot tasks often overthinking paths.
    If a bot is damaged, and has been thinking about a path for more than 4 seconds...
    1. All their movement tasks are stopped.
    2. if they have the generic task, "movement_backthehellup", it's started, otherwise "movement_handler" is started.

### "movement_handler"
***OVERRIDE THIS!!!***
    This is the "okay what do i do next" state of your bot, all other tasks should loop back to here

### "movement_wait"
Very simple task that waits for data.time, or 0.1-0.2 seconds

### "movement_waitforenemy"
Simple task that waits until the bot has a valid enemy, then starts movement_handler

### "movement_followtarget"
Simple task that follows `self.Target`, if it's valid.

### "movement_backthehellup"
An extremely useful task, makes the bot run away from it's current enemy.


## Implimenting DoCustomTasks

Small snippet from the `terminator_nextbot_csoldier` NPC

```lua
function ENT:DoCustomTasks( defaultTasks )
    self.TaskList = {
        ["enemy_handler"] = defaultTasks["enemy_handler"],
        ["shooting_handler"] = defaultTasks["shooting_handler"],
        ["awareness_handler"] = defaultTasks["awareness_handler"],
        ["reallystuck_handler"] = defaultTasks["reallystuck_handler"],

        ["inform_handler"] = defaultTasks["inform_handler"],
        ["movement_wait"] = defaultTasks["movement_wait"],
        ["movement_getweapon"] = defaultTasks["movement_getweapon"],
        ["movement_followtarget"] = defaultTasks["movement_followtarget"],
        ["movement_backthehellup"] = defaultTasks["movement_backthehellup"],

        ["soldier_meleeattack_handler"] = { -- simple task that triggers the bot's TermSoldier_Melee special action
    --- brain continues below
```
All the desired tasks are copied over into the bot's new self.TaskList, and the new brain continues below


## Examples and final custom brain thoughts

These other projects make great use of all terminator systems aswell.
See the [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies) repo
And the `terminator_nextbot_csoldier` NPCs inside this base

When you're reverse engineering the above examples
#### Make sure you take special note of how...
1. They use `ENT:DoCustomTasks` to reuse base tasks, WITHOUT copying any code.
2. They manage paths, (or avoid managing, with self:GotoPosSimple)
3. They return the brain back to the generic "movement_handler" task for simpler logic flow
    (I didn't do this enough for the terminator brain, big mistake!)
4. They all fully utilize `ENT:StartTask( taskName, taskData or nil, taskStartReason )`
    (start reasons exist for easy debugging of logic flow with `term_debugtasks 1`, thanks [l4d2 ai design doc](https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf))
5. All the movement tasks start with `movement_`, because ai logic in the code expects moving tasks to start with it.
6. They sometimes use `BehaveUpdatePriority` callbacks to bail path calculations and not just stand there when someones shooting them!
7. They use the fickle `ENT:findValidNavResult` function to find navareas, to path to, in wandering routines, and more!
8. they call `coroutine.yield()`... seemingly everywhere, but not too much?
    (The placement of coroutine_yields is usually honed with the `term_debug_worstoverbudgetyields` and `term_debug_totaloverbudgetyields` commands)

*But most importantly...*
### have fun!
