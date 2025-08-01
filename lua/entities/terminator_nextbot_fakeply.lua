AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Paparazzi"
ENT.Spawnable = false
list.Set( "NPC", "terminator_nextbot_fakeply", {
    Name = "Paparazzi",
    Class = "terminator_nextbot_fakeply",
    Category = "Terminator Nextbot",
    Weapons = {
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "gmod_camera",
        "weapon_pistol", -- HES GOT A GUN
    },
} )

if CLIENT then
    language.Add( "terminator_nextbot_fakeply", ENT.PrintName )
    return

end

ENT.DefaultWeapon = "gmod_camera"

ENT.CoroutineThresh = 0.000002
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- thresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = true

ENT.JumpHeight = 70
ENT.DefaultStepHeight = 18
ENT.StandingStepHeight = ENT.DefaultStepHeight * 1 -- used in crouch toggle in motionoverrides
ENT.CrouchingStepHeight = ENT.DefaultStepHeight * 0.9
ENT.StepHeight = ENT.StandingStepHeight
ENT.PathGoalToleranceFinal = 50
ENT.DoMetallicDamage = false
ENT.SpawnHealth = 100
ENT.AimSpeed = 300
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_POOR
ENT.WalkSpeed = 100
ENT.MoveSpeed = 200
ENT.RunSpeed = 400
ENT.AccelerationSpeed = 1500
ENT.DeathDropHeight = 400
ENT.InformRadius = 0

ENT.CanSwim = true
ENT.BreathesAir = true
ENT.ThrowingForceMul = 0.5

ENT.alwaysManiac = true

ENT.isTerminatorHunterChummy = "paparazzi"
ENT.MetallicMoveSounds = false
ENT.ReallyStrong = false
ENT.HasFists = false
ENT.FootstepClomping = false

-- a table is getting in here, maybe this fixes it?
local finalModels = {}
local models = player_manager.AllValidModels()
for _, model in pairs( models ) do
    if isstring( model ) then
        table.insert( finalModels, model )

    end
end

ENT.Models = finalModels

function ENT:GetAimVector()
    local dir = self:GetEyeAngles():Forward()

    if self:HasWeapon() then
        local deg = 0.01
        local active = self:GetActiveLuaWeapon()
        if isfunction( active.GetNPCBulletSpread ) then
            deg = active:GetNPCBulletSpread( self:GetCurrentWeaponProficiency() )
            deg = math.sin( math.rad( deg ) )
        end

        dir:Add(Vector(math.Rand(-deg,deg),math.Rand(-deg,deg),math.Rand(-deg,deg)))
    end

    return dir
end


-- randomize bodygroups and skins
function ENT:AdditionalInitialize()
    self:Appearance()

end

function ENT:Appearance()
    local model = self:GetModel()
    if not model then return end
    
    self:SetSkin( math.random( 0, self:SkinCount() - 1 ) )
    
    for i = 0, self:GetNumBodyGroups() - 1 do
        local count = self:GetBodygroupCount( i )
        if count <= 1 then continue end
 
        self:SetBodygroup( i, math.random( 0, count - 1 ) )

    end
end
