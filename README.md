# termhunter
Experimental Nextbot + Base.  
Allows for very complicated custom behaviour.  
For basing NPCs off this, it doesn't support custom animations that well, it expects player animations by default, but there is limited support for custom animations(see below for more info).

Best for creating code-driven AI agents that relentlessly pursue their enemies, crouching, jumping, climbing ladders, attacking obstacles.  
Supports optimized custom weights on pathfinding, good if you want a bot to avoid a dangerous area, avoid an obvious entrance to a room, etc.  
Limited but functional support for custom, non-player shaped enemies, would not recommend working with this base if you've just finished a custom non-player model and want it to attack you.  


See [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=2944078031) page for more info.
Check [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies)
    (NPCs with a fully custom brain)
And [Jerma985 Nextbot](https://github.com/StrawWagen/the_jerminator)
    (Flat reskins with no real custom behaviour)

This project is a highly modified, optimized version of [this nextbot base](https://github.com/ShadowBonnieRUS/GMOD-SB_Advanced_Nextbots_Base)


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

Following patcher, Creates connections between navareas.
This should always be enabled, no navmesh is perfect.
terminator_followpatcher_enable 0/1 "Patches the navmesh as players wander the map, Leads to terminators feeling smarter, following you through windows. Only runs with at least 1 bot spawned."
terminator_followpatcher_maxplayers -1/inf "Max amount of plys to process at a time, the system always prioritizes players being actively chased. -1 for default"
terminator_followpatcher_debug 0/1 "Debug the following patcher."

Areapatcher
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
You can also play animation layers (gestures) over the bot's current animation using `bot:DoGesture( act, speed, wait )`:
- `act` - Activity enum (ACT_*) or sequence name string
- `speed` - Playback rate (default 1.0, lower = slower)
- `wait` - If true, blocks bot behavior/movement until gesture finishes

You'll see examples of this in the MySpecialActions section below.


## ENT.MyClassTask System

Simple way to add entity-class-specific behaviour to your custom nextbot based on termhunter.  
Fully compatible with baseclassing - tasks from all base classes in the inheritance tree will also be added automatically.  

**Important:** This is NOT for adding movement tasks. Use `ENT:DoCustomTasks` instead for complex movement behavior.

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
        -- Great if you want a bot to assume a position before it attacks
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
        -- Called when self.ReallyHeavy bots fall far and deal damage to stuff they landed on, or landed next to. 
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
    
    
    -- ALLY/TEAM CALLBACKS --
    -- OnBlockingAlly = function( self, data, ally, sinceStarted )
        -- Called when this bot is blocking an ally's path, simple checks cause this so it isn't exhaustive
    -- end,
    
    -- OnBlockedByAlly = function( self, data, blocker, sinceStarted )
        -- Called when this bot is blocked by an ally
    -- end,
}
```

**Note:** All callbacks receive `data` as the second parameter - this is the task's data table where you can store state between calls.  
All class tasks automatically start on initialization.


## ENT.MySpecialActions System

Special actions allow bots to perform custom actions when specific inputs are triggered, with full support for player control and AI logic. Actions defined in derived classes override actions with the same name from base classes.

### Usage

Trigger actions from code using:
```lua
self:TakeAction( "actionName" )
```

You can also check if an action can be taken:
```lua
if self:CanTakeAction( "actionName" ) then
    self:TakeAction( "actionName" )
end
```

### Example: Dance Action

```lua
ENT.MySpecialActions = {
    ["Dance"] = {
        inBind = IN_USE, -- IN_ Input for players driving this bot to trigger this action
        drawHint = true, -- Show hint to player when driving bot
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
    ["UseItem"] = {
        name = "Use",
        svAction = function( drive, driver, bot )
            -- Base implementation
        end,
    },
}

-- In derived class - this completely replaces the base "UseItem" action
ENT.MySpecialActions = {
    ["UseItem"] = {
        name = "Advanced Use",
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


## now you might be thinking..

"That's great, but i want to add a custom brain to my npc!"

Well, the support is there.
See the [Nextbot Zambies](https://github.com/StrawWagen/nextbot_zambies) repo
And the `terminator_nextbot_csoldier` NPCs inside this base

But I can't make that process easy for you.
Adding custom behaviour is extremely tough, fraught with pitfalls and lag.

If you want to try anyway, your best bet is to reverse engineer those examples.

### And make sure you take special note of how...
1. They use `ENT:DoCustomTasks` to reuse base tasks, WITHOUT copying any code.
2. They manage paths, (or avoid managing, with self:GotoPosSimple)
3. They return the brain back to the generic `movement_handler` task for simpler logic flow
    (I didn't do this enough for the terminator brain, big mistake!)
4. They all fully utilize `ENT:StartTask( taskName, taskData or nil, taskStartReason )`
    (start reasons exist for easy debugging of logic flow with `term_debugtasks 1`, thanks [l4d2 ai design doc](https://steamcdn-a.akamaihd.net/apps/valve/2009/ai_systems_of_l4d_mike_booth.pdf))
5. All the movement tasks start with `movement_`, because ai logic in the code expects moving tasks to start with it.
6. They waterfall down data.myTbl for optimisation (ask around about _index optimsation for more info)
7. They sometimes use `BehaveUpdatePriority` callbacks to bail path calculations and not just stand there when someones shooting them!
8. They use the fickle `ENT:findValidNavResult` function to find navareas, to path to, in wandering routines, and more!
9. they call `coroutine.yield()`... seemingly everywhere, but not too much?
    (The placement of coroutine_yields is usually honed with the `term_debug_worstoverbudgetyields` and `term_debug_totaloverbudgetyields` commands)

*But most importantly...*
### have fun!
