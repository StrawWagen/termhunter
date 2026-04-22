-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

ENT.DefaultWeapon = "weapon_rpg"

ENT.DefaultSidearms = {
    "weapon_frag",
}

ENT.Base = "terminator_nextbot_csoldier"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Combine Rocketeer"
ENT.Spawnable = false -- dont show up in entity spawn category

if GetConVar( "developer" ):GetBool() then -- todo, MAKE THESE SPAWNABLE
    list.Set( "NPC", "terminator_nextbot_crocketeer", {
        Name = "Combine Rocketeer",
        Class = "terminator_nextbot_crocketeer",
        Category = "Terminator Nextbot",
        Weapons = { ENT.DefaultWeapon },
    } )
end

if CLIENT then
    language.Add( "terminator_nextbot_crocketeer", ENT.PrintName )
    return

end

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 4
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 5 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 3 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = false

ENT.JumpHeight = 45
ENT.SpawnHealth = 70
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_VERY_GOOD
ENT.WalkSpeed = 55
ENT.MoveSpeed = 120
ENT.RunSpeed = 175

ENT.isTerminatorHunterChummy = "combine"
ENT.DuelEnemyDist = 1200

ENT.Models = {
    "models/player/combine_soldier_prisonguard.mdl",
}
ENT.ModelSkin = 1
