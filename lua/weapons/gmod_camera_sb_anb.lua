
SWEP.WorldModel = Model( "models/MaxOfS2D/camera.mdl" )

SWEP.Primary.ClipSize        = 1
SWEP.Primary.DefaultClip    = -1
SWEP.Primary.Automatic        = false
SWEP.Primary.Ammo            = "none"

SWEP.Secondary.ClipSize        = -1
SWEP.Secondary.DefaultClip    = -1
SWEP.Secondary.Automatic    = true
SWEP.Secondary.Ammo            = "none"


SWEP.PrintName    = "#GMOD_Camera"

SWEP.Weight     = 0
SWEP.Slot        = 5
SWEP.SlotPos    = 1

SWEP.DrawAmmo        = false
SWEP.DrawCrosshair    = false
SWEP.Spawnable        = false

SWEP.ShootSound = Sound( "NPC_CScanner.TakePhoto" )
SWEP.terminator_IgnoreWeaponUtility = true

Terminator_SetupAnalogWeight( SWEP )

--
-- Initialize Stuff
--
function SWEP:Initialize()

    self:SetHoldType( "camera" )

end

--
-- Reload resets the FOV and Roll
--
function SWEP:Reload()
end

--
-- PrimaryAttack - make a screenshot
--
function SWEP:PrimaryAttack()

    self:DoShootEffect()
end

--
-- Deploy - Allow lastinv
--
function SWEP:Deploy()

    return true

end

--
-- The effect when a weapon is fired successfully
--
function SWEP:DoShootEffect()

    local owner = self:GetOwner()

    self:EmitSound( self.ShootSound )
    self:SendWeaponAnim( ACT_VM_PRIMARYATTACK )
    owner:SetAnimation( PLAYER_ATTACK1 )

    --
    -- Note that the flash effect is only
    -- shown to other players!
    --

    local vPos = owner:GetShootPos()
    local vForward = owner:GetAimVector()

    local fireGlow = ents.Create( "env_sprite" ) -- bright flash
    fireGlow:SetKeyValue( "model", "sprites/glow04_noz.vmt" )
    fireGlow:SetKeyValue( "rendercolor", "140 140 140" )
    fireGlow:SetKeyValue( "scale", "1" )

    fireGlow:SetPos( vPos + ( vForward * 50 ) )
    SafeRemoveEntityDelayed( fireGlow, 0.05 )
    fireGlow:Spawn()
    fireGlow:Activate()

end

function SWEP:Equip()
end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
end

function SWEP:CanBePickedUpByNPCs()
    return true
end


function SWEP:GetNPCBulletSpread(prof)
    return 0
end

function SWEP:GetNPCBurstSettings()
    return 1,1,0.001
end

function SWEP:GetNPCRestTimes()
    return 2,4
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end