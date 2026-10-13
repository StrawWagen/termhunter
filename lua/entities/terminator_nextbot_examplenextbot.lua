AddCSLuaFile()

-- A plain human bot, start here if you're making your own.
-- Every ENT. variable here overrides one in terminator_nextbot/shared.lua, check there for the rest.

-- terminator_nextbot has intelligent AI but is not great at self-preservation
-- consider using terminator_nextbot_csoldier for a dumber, but more soldier-y AI 
ENT.Base = "terminator_nextbot"

DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Example Human"
ENT.Spawnable = true
ENT.SubCategory = "Other" -- .Category is inherited from terminator_nextbot

-- puts us in the spawnmenu's NPC tab
-- unlike list.Set, lets .Category and .SubCategory be inherited down the base class tree
terminator_Extras.RegisterNPC( "terminator_nextbot_examplenextbot", ENT, {
    -- one of these is picked when the spawnmenu's weapon is set to default
    Weapons = { "weapon_pistol", "weapon_smg1", "weapon_shotgun", "weapon_crowbar" },
} )

-- attacks/abilities that both the AI and players driving the bot can use, see the README
-- needs to be above the CLIENT return, the driving player's client reads it too
--[[
ENT.MySpecialActions = {
    ["Wave"] = {
        name = "Wave",
        inBind = IN_USE,
        drawHint = true,
        ratelimit = 2,
        svAction = function( driveController, driver, bot )
            bot:DoGesture( ACT_GMOD_GESTURE_WAVE )

        end,
    },
}
--]]

if CLIENT then return end

-- PERFORMANCE/SMARTS --
-- these are what keep hordes of bots from lagging the server

-- the big one, for bots spawned in hordes. Trades smarts for a LOT of performance
-- if true...
--   searches for new enemies, rechecks paths, and updates its awareness less often
--   spreads its work across more ticks, and thinks at half speed with no enemy
--   no fast shooting timer, so very high firerate guns fire slower
--   only lag compensated while it has a valid enemy
--   doesn't path around areas it was hurt in, or shoot explosive barrels near enemies
--   doesn't search for a new enemy the moment it kills one
ENT.IsFodder = true

-- ENT.IsStupid = true -- animal level smarts, zombies, headcrabs, etc
--   randomly swings at whatever's blocking it, instead of judging whether it's worth breaking
--   hates every npc it meets, (terminator nextbot hates everything that attacks IT, to quickly filter out enemies of no threat)

-- ENT.HasBrains = false -- or a number, % chance each bot spawns with brains
--   backs away from enemies smarter, breaking line of sight
--   when not IsFodder, remembers what hurt it, and shoots explosive barrels near enemies

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 20 -- processing time allowed per tick, see aicore.lua
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this when closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- and this when closer than DuelEnemyDist * 2
ENT.MaxPathingIterations = 2500 -- lower is cheaper, but long paths stop short, wherever got closest

-- WEAPONS --
ENT.DefaultWeapon = nil -- string or table, used when spawned by code, the spawnmenu's weapon takes priority
ENT.TERM_FISTS = "weapon_terminatorfists_term" -- innate melee weapon, bots will pull it out to try and bash through obstacles, false for none
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_POOR
ENT.AimSpeed = 300 -- degrees per second
ENT.ThrowingForceMul = 0.5 -- terminators are 1000, 0.5 and lower, and crowbar throwing is all but disabled
ENT.FistDamageMul = 0.1 -- damage mul for weapon_terminatorfists_term
-- ENT.DefaultSidearms = { "weapon_pistol", { "weapon_crowbar", "weapon_stunstick" } } -- holstered on spawn, a table inside picks one at random
-- ENT.CanHolsterWeapons = true -- false, no holstering, no sidearms
-- ENT.CanFindWeaponsOnTheGround = true -- false, only ever uses what it spawned with
-- ENT.DontDropPrimary = true -- keep the gun when switching to fists
-- ENT.DontShootThroughProps = true -- won't fire at enemies behind props
-- ENT.FistRangeMul = 1
-- ENT.FistForceMul = 1
-- ENT.FistDamageType = DMG_CLUB

-- HEALTH/DAMAGE --
ENT.SpawnHealth = 100
ENT.DoMetallicDamage = false -- terminator damage logic, bullet resistance, shock immunity, etc
-- ENT.HealthRegen = 1 -- health per HealthRegenInterval
-- ENT.HealthRegenInterval = 1
-- ENT.ExtraSpawnHealthPerPlayer = 50 -- for bosses, extra maxhealth for every player it targets after the first
-- ENT.term_DMG_ImmunityMask = bit.bor( DMG_NERVEGAS, DMG_POISON ) -- immune to these damage types, eg, wearing a gas mask
-- ENT.Term_BloodColor = BLOOD_COLOR_RED
-- ENT.FriendlyFireMul = 1 -- 0, allies can't hurt it
-- ENT.TakesFallDamage = true
-- ENT.HeightToStartTakingDamage = 70 * 3.5 -- the terminator's jump height
-- ENT.FallDamagePerHeight = 0.05
-- ENT.Term_DeathAnim = { act = ACT_GMOD_TAUNT_SALUTE, rate = 1 } -- same table as the GetDeathAnim callback

-- MOVEMENT --
ENT.WalkSpeed = 100
ENT.MoveSpeed = 200
ENT.RunSpeed = 400
ENT.AccelerationSpeed = 1500
ENT.JumpHeight = 70 -- same as players
ENT.DefaultStepHeight = 18
ENT.StandingStepHeight = ENT.DefaultStepHeight -- terminators are * 1.5
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50 -- how close counts as reaching the end of a path
ENT.DeathDropHeight = 400 -- biggest drop the bot will path off of
ENT.CanSwim = true
ENT.BreathesAir = true -- drowns
-- ENT.CrouchSpeed = 120
-- ENT.DecelerationSpeed = 3000
-- ENT.CanCrouch = true
-- ENT.CanUseLadders = true
-- ENT.Term_Leaps = true -- leaps at enemies, and along paths
-- ENT.Term_LeapMinimizesHeight = true -- low leaps

-- SIZE --
-- ENT.TERM_MODELSCALE = function( self ) return math.Rand( 0.95, 1.05 ) end -- or a number, collision bounds scale with it
-- ENT.CollisionBounds = { Vector( -16, -16, 0 ), Vector( 16, 16, 72 ) }
-- ENT.CrouchCollisionBounds = { Vector( -16, -16, 0 ), Vector( 16, 16, 42 ) } -- defaults to CollisionBounds, 59% as tall
-- ENT.MyPhysicsMass = 85

-- SENSES/ENEMIES --
-- ENT.Term_FOV = 95 -- ignores the termhunter_fovoverride convar
-- ENT.MaxSeeEnemyDistance = 3000
-- ENT.DuelEnemyDist = 700 -- used for many things, but primarily, when we're closer to an enemy than this, stop pathing and start dueling
-- ENT.CanHearStuff = true
-- ENT.PrefersVehicleEnemies = true -- sticks to enemies in vehicles, good for bosses
-- ENT.CloseEnemyDistance = 175 -- ignores enemy priority when one's this close
-- ENT.CanUseStuff = true -- false, never :Use()s things, like doors and buttons

-- TEAMWORK --
ENT.isTerminatorHunterChummy = "examplenextbots" -- bots with the same string are allies
ENT.InformRadius = 0 -- how far it shares enemy info with allies
-- ENT.alwaysManiac = true -- fights its own allies too
-- ENT.neverManiac = true -- never randomly infights

-- SOUNDS/FEEL --
ENT.ReallyStrong = false -- terminator strength, throws crowbars 5x harder
ENT.ReallyHeavy = false -- heavy landings, goomba damage
ENT.MetallicMoveSounds = false
ENT.FootstepClomping = false -- second, heavier sound on every step
-- ENT.Term_FootstepShake = { amplitude = 1, frequency = 100, duration = 0.25, radius = 100 } -- a big guy
-- more footstep options, custom sounds, perfectly timed steps, etc, at the top of footsteps.lua

-- ENT.CanSpeak = true -- enables everything below, and self:Term_SpeakSound( path )
-- ENT.IdleLoopingSounds = { "player/breathe1.wav" }
-- ENT.AngryLoopingSounds = { "player/heartbeat1.wav" }
-- ENT.AlwaysPlayLooping = true -- keep looping while speaking
-- ENT.term_SoundPitchShift = 0 -- number, or function( self, myTbl ), footsteps follow it too
-- ENT.term_SoundLevelShift = 0

-- ANIMATIONS --
-- see the README's Overriding Animations
-- ENT.IdleActivity = ACT_HL2MP_IDLE
-- ENT.IdleActivityTranslations = { [ACT_MP_RUN] = ACT_HL2MP_RUN_PANICKED } -- runs like a scared civilian
-- ENT.term_AnimsWithIdealSpeed = true -- pick walk/run anims from the speed it wants, not the speed it's going

-- any playermodel
local finalModels = {}
for _, model in pairs( player_manager.AllValidModels() ) do
    if isstring( model ) then
        table.insert( finalModels, model )

    end
end
ENT.Models = finalModels
-- ENT.Models = false -- must be false, nil would inherit the base's models
-- ENT.Model = "models/player/kleiner.mdl"
-- ENT.ModelSkin = 0

-- every callback is listed in the README
ENT.MyClassTask = {
    -- randomize skin and bodygroups
    OnCreated = function( self, data )
        self:SetSkin( math.random( 0, self:SkinCount() - 1 ) )

        for i = 0, self:GetNumBodyGroups() - 1 do
            local count = self:GetBodygroupCount( i )
            if count <= 1 then continue end

            self:SetBodygroup( i, math.random( 0, count - 1 ) )

        end
    end,

    -- EnemyFound = function( self, data, newEnemy, secondsSinceLastEnemy )
    --     self:Term_SpeakSound( "vo/npc/male01/overhere01.wav" ) -- needs ENT.CanSpeak
    -- end,

    -- BehaveUpdatePriority = function( self, data )
    --     if not self.IsSeeEnemy then return end
    --     if self.DistToEnemy > 200 then return end
    --     if not self:CanTakeAction( "Wave" ) then return end
    --     self:TakeAction( "Wave" ) -- see MySpecialActions above
    -- end,

    -- OnDamaged = function( self, data, dmg )
    --     if dmg:GetDamage() < 5 then return true end -- shrug off small hits, true blocks the damage
    -- end,
}
