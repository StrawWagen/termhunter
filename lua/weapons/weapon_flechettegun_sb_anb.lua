-- Variables that are used on both client and server

SWEP.Instructions    = "Shoot a prop to attach a Manhack.\nRight click to attach a rollermine."

SWEP.Spawnable            = true
SWEP.AdminOnly            = true
SWEP.UseHands            = true

SWEP.ViewModel            = "models/weapons/c_pistol.mdl"
SWEP.WorldModel            = "models/weapons/w_pistol.mdl"

SWEP.Primary.ClipSize        = 1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic        = false
SWEP.Primary.Ammo            = "none"

SWEP.Secondary.ClipSize        = -1
SWEP.Secondary.DefaultClip    = -1
SWEP.Secondary.Automatic    = false
SWEP.Secondary.Ammo            = "none"

SWEP.Weight             = 100
SWEP.AutoSwitchTo        = false
SWEP.AutoSwitchFrom        = false

SWEP.PrintName            = "#GMOD_ManhackGun"
SWEP.Slot                = 3
SWEP.SlotPos            = 1
SWEP.DrawAmmo            = false
SWEP.DrawCrosshair        = true
SWEP.UseHands            = true

Terminator_SetupAnalogWeight( SWEP )

if ( !IsMounted( "ep2" ) ) then return end

AddCSLuaFile()

SWEP.PrintName = "#GMOD_FlechetteGun"
SWEP.Author = "garry"
SWEP.Purpose = "Shoot flechettes with primary attack."

SWEP.Slot = 1
SWEP.SlotPos = 2

SWEP.Spawnable = false

SWEP.ViewModel = Model( "models/weapons/c_smg1.mdl" )
SWEP.WorldModel = Model( "models/weapons/w_smg1.mdl" )
SWEP.ViewModelFOV = 54
SWEP.UseHands = true

SWEP.Primary.ClipSize = 1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = true
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.DrawAmmo = false
SWEP.AdminOnly = true

game.AddParticles( "particles/hunter_flechette.pcf" )
game.AddParticles( "particles/hunter_projectile.pcf" )

function SWEP:Initialize()

    self:SetHoldType( "smg" )

end

function SWEP:Reload()
end

function SWEP:PrimaryAttack()

    if ( CLIENT ) then return end

    self:SetNextPrimaryFire( CurTime() + 0.1 )

    self:EmitSound( "NPC_Hunter.FlechetteShoot" )
    self:ShootEffects( self )

    SuppressHostEvents( NULL ) -- Do not suppress the flechette effects

    local ent = ents.Create( "hunter_flechette" )
    if ( !IsValid( ent ) ) then return end

    local owner = self:GetOwner()

    local Forward = owner:GetAimVector()

    ent:SetPos( owner:GetShootPos() + Forward * 32 )
    ent:SetAngles( owner:EyeAngles() )
    ent:SetOwner( owner )
    ent:Spawn()
    ent:Activate()

    ent:SetVelocity( Forward * 2000 )

end

function SWEP:SecondaryAttack()

    -- TODO: Reimplement the old rollermine secondary attack?

end

function SWEP:ShouldDropOnDie()

    return false

end

function SWEP:GetNPCRestTimes()

    -- Handles the time between bursts
    -- Min rest time in seconds, max rest time in seconds

    return 0.3, 0.6

end

function SWEP:GetNPCBurstSettings()

    -- Handles the burst settings
    -- Minimum amount of shots, maximum amount of shots, and the delay between each shot
    -- The amount of shots can end up lower than specificed

    return 10, 20, 0.05

end

function SWEP:GetNPCBulletSpread( _ )

    -- Handles the bullet spread based on the given proficiency
    -- return value is in degrees

    return 1

end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end