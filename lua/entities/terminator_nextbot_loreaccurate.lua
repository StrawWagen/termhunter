AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Lore Accurate Terminator"
list.Set( "NPC", "terminator_nextbot_loreaccurate", {
    Name = ENT.PrintName,
    Class = "terminator_nextbot_loreaccurate",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },
    AdminOnly = true,
} )

ENT.AdminOnly = true

if CLIENT then
    language.Add( "terminator_nextbot_loreaccurate", ENT.PrintName )
    return

end

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh * 1.25 -- boss, think a bit faster than normal

ENT.WalkSpeed = 130
ENT.MoveSpeed = 275
ENT.RunSpeed = 350
ENT.AccelerationSpeed = 2000
ENT.JumpHeight = 70 * 2
ENT.FistDamageMul = 10 -- over double of the overcharged


ENT.TakesFallDamage = false
ENT.DeathDropHeight = 4000

ENT.SpawnHealth = 50000
ENT.ExtraSpawnHealthPerPlayer = 2500

ENT.AlwaysAngry = true
ENT.MimicPlayer = true -- make fist stance use player stance mimicking

ENT.Term_FootstepTiming = "perfect"
ENT.PerfectFootsteps_FeetBones = { "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot" }

local low_health = 0.1 -- 10% health

function ENT:canDoRun()
    if self:Health() < self:GetMaxHealth() * low_health then
        return BaseClass.canDoRun( self ) -- run if low health

    end
    return false

end

function ENT:HandleFlinching()
    if self:Health() < self:GetMaxHealth() * low_health then
        return BaseClass.HandleFlinching( self ) -- flinch if low health

    end
    return false -- no flinching

end

function ENT:IsAngry()
    return true

end

function ENT:IsReallyAngry()
    return true -- always angry

end

function ENT:EnemyIsLethalInMelee()
    return -- no fear

end

function ENT:inSeriousDanger()
    return false -- no fear

end

function ENT:EnemyIsUnkillable()
    return false

end


ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_PERFECT