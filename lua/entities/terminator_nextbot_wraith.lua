AddCSLuaFile()


ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Wraith"
ENT.Author = "Broadcloth0"
ENT.Spawnable = false

list.Set( "NPC", "terminator_nextbot_wraith", {
    Name = ENT.PrintName,
    Class = "terminator_nextbot_wraith",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },

} )

if CLIENT then
    language.Add( "terminator_nextbot_wraith", ENT.PrintName )
    return

end

ENT.FistDamageMul = 1.565
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_VERY_GOOD

ENT.SpawnHealth = terminator_Extras.healthDefault * 0.5

ENT.IsWraith = true -- enable wraith cloaking logic
ENT.NotSolidWhenCloaked = true -- if we're a wraith, we become non-solid when cloaked

function ENT:PlayHideFX()
    self:EmitSound( "ambient/levels/citadel/pod_open1.wav", 74, math.random( 115, 125 ) )
    self.FootstepClomping = false

end

function ENT:PlayUnhideFX()
    self:EmitSound( "ambient/levels/citadel/pod_close1.wav", 74, math.random( 115, 125 ) )
    self.FootstepClomping = true

end