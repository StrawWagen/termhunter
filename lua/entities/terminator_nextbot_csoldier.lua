AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Combine Soldier"
ENT.Spawnable = false -- dont show up in entity spawn category
list.Set( "NPC", "terminator_nextbot_csoldier", {
    Name = "Combine Soldier",
    Class = "terminator_nextbot_csoldier",
    Category = "Terminator Nextbot",
    Weapons = {
        "weapon_smg1",
        "weapon_ar2",
        "weapon_shotgun",
    },
} )

ENT.PlayerColorVec = Vector( 0.2, 0.2, 0.2 ) -- used for player color

if CLIENT then
    language.Add( "terminator_nextbot_csoldier", ENT.PrintName )
    return

end

ENT.CoroutineThresh = 0.001
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = true

ENT.JumpHeight = 65
ENT.DefaultStepHeight = 18
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1 -- used in crouch toggle in motionoverrides
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.DoMetallicDamage = false
ENT.SpawnHealth = 50
ENT.AimSpeed = 300
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_POOR
ENT.WalkSpeed = 50
ENT.MoveSpeed = 100
ENT.RunSpeed = 200
ENT.AccelerationSpeed = 1500
ENT.DeathDropHeight = 800
ENT.InformRadius = 0

ENT.CanHolsterWeapons = true

ENT.CanSwim = true
ENT.BreathesAir = true
ENT.ThrowingForceMul = 0.5

ENT.neverManiac = true

ENT.isTerminatorHunterChummy = "combine"
ENT.MetallicMoveSounds = false
ENT.ReallyStrong = false
ENT.HasFists = false
ENT.FootstepClomping = false

ENT.Models = {
    "models/player/combine_soldier.mdl",
}

ENT.DefaultSidearms = {
    "weapon_frag",
}

function ENT:DoCustomTasks( defaultTasks )
    self.TaskList = {
        ["enemy_handler"] = defaultTasks["enemy_handler"],
        ["shooting_handler"] = defaultTasks["shooting_handler"],
        ["awareness_handler"] = defaultTasks["awareness_handler"],
        ["reallystuck_handler"] = defaultTasks["reallystuck_handler"],

        ["inform_handler"] = defaultTasks["inform_handler"],
        ["movement_wait"] = defaultTasks["movement_wait"],
        ["playercontrol_handler"] = defaultTasks["playercontrol_handler"],

        -- custom movement starter
        ["movement_handler"] = {
            StartsOnInitialize = true, -- starts on spawn
            OnStart = function( self, data )
                -- when this tasks starts
                -- maybe start movement_mycustomtask?
            end,
        },

        -- the actual CUSTOM TASK!
        ["movement_mycustomtask"] = {
            OnStart = function( self, data )
                -- when this tasks starts
            end,
            BehaveUpdateMotion = function( self, data )
                -- do something in the motion coroutine
            end,
            OnEnd = function( self, data )
                -- when this task ends
                -- maybe go back to movement_handler?
            end,
        },
    }
end