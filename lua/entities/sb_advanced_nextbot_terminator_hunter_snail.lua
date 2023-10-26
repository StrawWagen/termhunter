AddCSLuaFile()

ENT.Base = "sb_advanced_nextbot_terminator_hunter"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"
list.Set( "NPC", "sb_advanced_nextbot_terminator_hunter_snail", {
    Name = "Terminator",
    Class = "sb_advanced_nextbot_terminator_hunter_snail",
    Category = "SB Advanced Nextbots",
    Weapons = { "weapon_terminatorfists_sb_anb" },
} )

if CLIENT then
    language.Add( "sb_advanced_nextbot_terminator_hunter_snail", ENT.PrintName )
    return
end

ENT.WalkSpeed = 75
ENT.MoveSpeed = 200
ENT.RunSpeed = 360
ENT.AccelerationSpeed = 1500
ENT.JumpHeight = 70 * 2.5
ENT.FistDamageMul = 1

ENT.duelEnemyTimeoutMul = 5