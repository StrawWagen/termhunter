AddCSLuaFile()

ENT.Base = "sb_advanced_nextbot_terminator_hunter"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"
list.Set( "NPC", "sb_advanced_nextbot_terminator_hunter_slower", {
    Name = "Terminator Hard",
    Class = "sb_advanced_nextbot_terminator_hunter_slower",
    Category = "SB Advanced Nextbots",
    Weapons = { "weapon_terminatorfists_sb_anb" },
} )

if CLIENT then
    language.Add( "sb_advanced_nextbot_terminator_hunter_slower", ENT.PrintName )
    return
end

ENT.WalkSpeed = 130
ENT.MoveSpeed = 250
ENT.RunSpeed = 400 -- normal speed
ENT.AccelerationSpeed = 2000
ENT.JumpHeight = 70 * 2.5
ENT.FistDamageMul = 1.5