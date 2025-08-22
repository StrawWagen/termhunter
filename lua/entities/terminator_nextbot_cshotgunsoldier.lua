-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

ENT.DefaultWeapon = {
    "weapon_shotgun"
}

ENT.DefaultSidearms = {
    "weapon_frag",
}

ENT.Base = "terminator_nextbot_csoldier"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Shotgun Soldier"
ENT.Spawnable = false -- dont show up in entity spawn category

if GetConVar( "developer" ):GetBool() then -- todo, MAKE THESE SPAWNABLE
    list.Set( "NPC", "terminator_nextbot_cshotgunsoldier", {
        Name = "Shotgun Soldier",
        Class = "terminator_nextbot_cshotgunsoldier",
        Category = "Terminator Nextbot",
        Weapons = ENT.DefaultWeapon,
    } )
end

ENT.PlayerColorVec = Vector( 1, 0, 0 ) -- used for player color

if CLIENT then
    language.Add( "terminator_nextbot_cshotgunsoldier", ENT.PrintName )
    return

end

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 8
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = false

ENT.JumpHeight = 50
ENT.SpawnHealth = 80
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_GOOD
ENT.WalkSpeed = 75
ENT.MoveSpeed = 125
ENT.RunSpeed = 250

ENT.isTerminatorHunterChummy = "combine"
ENT.DuelEnemyDist = 750

ENT.Models = {
    "models/player/combine_soldier.mdl",
}
ENT.ModelSkin = 1