-- todo
-- intercepting
-- patrolling 

AddCSLuaFile()

ENT.DefaultWeapon = {
    "weapon_smg1",
    "weapon_pistol",
}

ENT.DefaultSidearms = {
    "weapon_frag",
}

ENT.Base = "terminator_nextbot_csoldier"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Metro-Police"
ENT.Spawnable = false -- dont show up in entity spawn category

if GetConVar( "developer" ):GetBool() then -- todo, MAKE THESE SPAWNABLE
    list.Set( "NPC", "terminator_nextbot_cmetro", {
        Name = "Metro-Police",
        Class = "terminator_nextbot_cmetro",
        Category = "Terminator Nextbot",
        Weapons = ENT.DefaultWeapon,
    } )
end

ENT.PlayerColorVec = Vector( 0, 0, 0 ) -- used for player color

if CLIENT then
    language.Add( "terminator_nextbot_cmetro", ENT.PrintName )
    return

end

ENT.CoroutineThresh = 0.00005
ENT.MaxPathingIterations = 2500
ENT.ThreshMulIfDueling = 3 -- CoroutineThresh is multiplied by this amount if we're closer than DuelEnemyDist
ENT.ThreshMulIfClose = 1.5 -- if we're closer than DuelEnemyDist * 2
ENT.IsFodder = false

ENT.JumpHeight = 25
ENT.SpawnHealth = 40
ENT.AimSpeed = 300
ENT.WalkSpeed = 75
ENT.MoveSpeed = 125
ENT.RunSpeed = 250

ENT.HasBrains = false

ENT.isTerminatorHunterChummy = "combine"
ENT.DuelEnemyDist = 750
ENT.ThrowingForceMul = 0.1

ENT.Models = {
    "models/player/police.mdl",
}
ENT.ModelSkin = 1