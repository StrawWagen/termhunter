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
    },
} )

if CLIENT then
    language.Add( "terminator_nextbot_fakeply", ENT.PrintName )
    return

end

ENT.CoroutineThresh = 0.0005
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
ENT.DeathDropHeight = 200
ENT.InformRadius = 0

ENT.ThrowingForceMul = 0.5

ENT.alwaysManiac = true

ENT.isTerminatorHunterChummy = "paparazzi"
ENT.MetallicMoveSounds = false
ENT.ReallyStrong = false
ENT.HasFists = false

-- a table is getting in here, maybe this fixes it?
local finalModels = {}
local models = player_manager.AllValidModels()
for _, model in pairs( models ) do
    if isstring( model ) then
        table.insert( finalModels, model )

    end
end

ENT.Models = finalModels

-- copied the original function
function ENT:MakeFootstepSound(volume,surface)
    local foot = self.m_FootstepFoot
    self.m_FootstepFoot = !foot
    self.m_FootstepTime = CurTime()

    if !surface then
        local tr = util.TraceEntity({
            start = self:GetPos(),
            endpos = self:GetPos()-Vector(0,0,5),
            filter = self,
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
        },self)

        surface = tr.SurfaceProps
    end

    if !surface then return end

    local surface = util.GetSurfaceData(surface)
    if !surface then return end

    local sound = foot and surface.stepRightSound or surface.stepLeftSound

    if sound then
        local pos = self:GetPos()

        local filter = RecipientFilter()
        filter:AddPAS(pos)

        if !self:OnFootstep(pos,foot,sound,volume,filter) then
            self:EmitSound(sound,75,100,volume,CHAN_BODY)
        end
    end
end

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