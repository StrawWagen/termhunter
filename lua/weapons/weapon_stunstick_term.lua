AddCSLuaFile()

if CLIENT then
    killicon.AddFont( "weapon_stunstick_term", "HL2MPTypeDeath", "1", Color( 255, 80, 0 ) )
end

SWEP.Base = "weapon_crowbar_term"
SWEP.PrintName = "#HL2_StunBaton"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Should only be used internally by term nextbots!"

SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.Weight = terminator_Extras.GoodWeight + -2

terminator_Extras.SetupAnalogWeight( SWEP )

SWEP.PickupSound = "weapons/stunstick/spark3.wav"
SWEP.Range = 1800
SWEP.MeleeWeaponDistance = SWEP.Range
SWEP.HoldType = "melee"
SWEP.SpawningOffset = 50
SWEP.ThrowForce = 25000
SWEP.PreOverrideClass = "weapon_stunstick"

function SWEP:SwingSpawn( spawnPos )
    local new = ents.Create( "prop_physics" )
    new:SetModel( "models/weapons/w_stunbaton.mdl" )
    new:SetAngles( AngleRand() )
    new:SetPos( spawnPos )
    new:SetOwner( self:GetOwner() )
    new:Spawn()
    new.isTerminatorHunterStunstick = true

    return new

end

function SWEP:ThrowStartSound( owner )
    owner:EmitSound( "weapons/slam/throw.wav", 90, 150 )

end

function SWEP:SwingingSound( projectile )
    projectile:EmitSound( "weapons/slam/throw.wav", 90, 80 )
    projectile:EmitSound( "weapons/stunstick/stunstick_swing2.wav", 70, 100 )

end

hook.Add( "EntityTakeDamage", "STRAW_terminatorHunter_stunstickShockDamage", function( target, damage )
    local inflic = damage:GetInflictor()
    if not IsValid( inflic ) then return end
    if not inflic.isTerminatorHunterStunstick then return end

    inflic:EmitSound( "weapons/stunstick/stunstick_fleshhit2.wav" )
    local attacker = IsValid( inflic:GetOwner() ) and inflic:GetOwner() or inflic
    damage:SetAttacker( attacker )
    damage:SetDamageType( DMG_SHOCK )
    damage:ScaleDamage( 10 )
    damage:SetDamage( math.Clamp( damage:GetDamage(), 0, 200 ) )

end )

