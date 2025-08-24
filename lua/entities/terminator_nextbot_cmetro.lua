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

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 15
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

ENT.term_LoseEnemySound = {
    "npc/metropolice/vo/nocontact.wav",
    "npc/metropolice/hiding02.wav",
    "npc/metropolice/hiding03.wav",
    "npc/combine_soldier/vo/stayalert.wav",
    "npc/metropolice/vo/suspectlocationunknown.wav",
}
ENT.term_FindEnemySound = {
    "npc/metropolice/vo/acquiringonvisual.wav",
    "npc/metropolice/vo/holdit.wav",
    "npc/metropolice/vo/preparingtojudge10-107.wav",
    "npc/metropolice/vo/prepareforjudgement.wav",
    "npc/metropolice/vo/holditrightthere.wav",
    "npc/metropolice/vo/dontmove.wav",
}
ENT.term_DamagedSound = {
    "npc/metropolice/vo/help.wav",
    "npc/metropolice/pain1.wav",
    "npc/metropolice/pain2.wav",
    "npc/metropolice/pain3.wav",
    "npc/metropolice/knockout2.wav", 

}
ENT.term_DieSound = {
    "npc/metropolice/die1.wav",
    "npc/metropolice/die2.wav",
    "npc/metropolice/die3.wav",
    "npc/metropolice/die4.wav"
}
ENT.term_KilledEnemySound = {
    "npc/metropolice/vo/condemnedzone.wav",
    "npc/metropolice/vo/finalverdictadministered.wav",
    "npc/metropolice/vo/externaljurisdiction.wav",
    "npc/metropolice/vo/sociocide.wav",
    "npc/metropolice/vo/suspectisbleeding.wav",
}

ENT.IdleLoopingSounds = {}
ENT.AngryLoopingSounds = {}

ENT.Term_FootstepSoundWalking = {
    {
        path = "NPC_MetroPolice.FootstepRight",
    },
    {
        path = "NPC_MetroPolice.FootstepLeft",
    },
}
ENT.Term_FootstepSound = { -- running sounds
    {
        path = "NPC_MetroPolice.RunFootstepLeft",
    },
    {
        path = "NPC_MetroPolice.RunFootstepRight",
    },
}
