AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Hard"
terminator_Extras.RegisterNPC( "terminator_nextbot_slower", ENT, {
    Weapons = { "weapon_terminatorfists_term" },
} )

if CLIENT then return end

ENT.WalkSpeed = 130
ENT.MoveSpeed = 250
ENT.RunSpeed = 400 -- normal speed
ENT.AccelerationSpeed = 2000
ENT.JumpHeight = 70 * 2.5
ENT.FistDamageMul = 1.5
ENT.ThrowingForceMul = 5


ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_VERY_GOOD