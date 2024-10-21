AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"
list.Set( "NPC", "terminator_nextbot_snail", {
    Name = "Terminator",
    Class = "terminator_nextbot_snail",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },
} )

if CLIENT then
    language.Add( "terminator_nextbot_snail", ENT.PrintName )
    return
end

ENT.WalkSpeed = 75
ENT.MoveSpeed = 200
ENT.RunSpeed = 360
ENT.AccelerationSpeed = 1500
ENT.JumpHeight = 70 * 2.5
ENT.FistDamageMul = 1
ENT.ThrowingForceMul = 1
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_GOOD

ENT.duelEnemyTimeoutMul = 5