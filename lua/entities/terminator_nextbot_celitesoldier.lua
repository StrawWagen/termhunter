-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

ENT.DefaultWeapon = {
    "weapon_ar2",
}

ENT.DefaultSidearms = {
    { "weapon_frag", "weapon_pistol" },
    "weapon_shotgun",
}

ENT.Base = "terminator_nextbot_csoldier"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Elite Combine Soldier"
ENT.Spawnable = false -- dont show up in entity spawn category

if GetConVar( "developer" ):GetBool() then -- todo, MAKE THESE SPAWNABLE
    list.Set( "NPC", "terminator_nextbot_celitesoldier", {
        Name = "Elite Combine Soldier",
        Class = "terminator_nextbot_celitesoldier",
        Category = "Terminator Nextbot",
        Weapons = ENT.DefaultWeapon,
    } )
end

ENT.PlayerColorVec = Vector( 1, 0, 0 ) -- used for player color

if CLIENT then
    language.Add( "terminator_nextbot_celitesoldier", ENT.PrintName )
    return

end

ENT.CoroutineThresh = 0.0002
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = false

ENT.JumpHeight = 55
ENT.SpawnHealth = 125
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_GOOD
ENT.WalkSpeed = 75
ENT.MoveSpeed = 115
ENT.RunSpeed = 225

ENT.isTerminatorHunterChummy = "combine"
ENT.DuelEnemyDist = 1250

ENT.Models = {
    "models/player/combine_super_soldier.mdl",
}