-- Variables that are used on both client and server

SWEP.Instructions    = "Shoot a prop to attach a Manhack.\nRight click to attach a rollermine."

SWEP.Spawnable            = false
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

--[[---------------------------------------------------------
    Reload does nothing
-----------------------------------------------------------]]
function SWEP:Reload()
end

--[[---------------------------------------------------------
    Think does nothing
-----------------------------------------------------------]]
function SWEP:Think()
end

--[[---------------------------------------------------------
    PrimaryAttack
-----------------------------------------------------------]]
function SWEP:PrimaryAttack()
    if ( CLIENT ) then return end

    local owner = self:GetOwner()

    local tr = util.QuickTrace( owner:GetShootPos(), owner:GetAimVector() * 15000, owner )
    --if ( tr.HitWorld ) then return end

    local effectdata = EffectData()
    effectdata:SetOrigin( tr.HitPos )
    effectdata:SetNormal( tr.HitNormal )
    effectdata:SetMagnitude( 8 )
    effectdata:SetScale( 1 )
    effectdata:SetRadius( 16 )
    util.Effect( "Sparks", effectdata )

    owner:EmitSound( "Metal.SawbladeStick" )

    self:ShootEffects( self )

    -- The rest is only done on the server

    -- Make a manhack
    local ent = ents.Create( "npc_manhack" )
    if ( !IsValid( ent ) ) then return end

    ent:SetPos( tr.HitPos + owner:GetAimVector() * -16 )
    ent:SetAngles( tr.HitNormal:Angle() )
    ent:Spawn()

    local weld = nil

    if ( tr.HitWorld ) then

        -- freeze it in place
        ent:GetPhysicsObject():EnableMotion( false )

    else

        -- Weld it to the object that we hit
        weld = constraint.Weld( tr.Entity, ent, tr.PhysicsBone, 0, 0 )

    end

end


--[[---------------------------------------------------------
    Name: ShouldDropOnDie
    Desc: Should this weapon be dropped when its owner dies?
-----------------------------------------------------------]]
function SWEP:ShouldDropOnDie()
    return false
end
//SWEP:PrimaryFire\\

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
    return 1
end

function SWEP:GetNPCBurstSettings()
    return 2,10,0.01
end

function SWEP:GetNPCRestTimes()
    return 0.5,1
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end