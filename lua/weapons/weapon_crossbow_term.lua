AddCSLuaFile()

if CLIENT then
    killicon.AddFont( "weapon_crossbow_term","HL2MPTypeDeath","1",Color( 255, 80, 0 ) )
end

SWEP.PrintName = "#HL2_Crossbow"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Should only be used internally by term nextbots!"

SWEP.ViewModel = "models/weapons/c_crossbow.mdl"
SWEP.WorldModel = "models/weapons/w_crossbow.mdl"
SWEP.Weight = terminator_Extras.GoodWeight + -1

SWEP.Primary = {
    Ammo = "XBowBolt",
    ClipSize = 1,
    DefaultClip = 1,
}

SWEP.Secondary = {
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

terminator_Extras.SetupAnalogWeight( SWEP )

function SWEP:Initialize()
    self:SetHoldType( "crossbow" )

end

function SWEP:CanPrimaryAttack()

    local owner = self:GetOwner()
    if owner:IsControlledByPlayer() then return true end
    if not terminator_Extras.PosCanSeeComplex( owner:GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end

    if not owner.NothingOrBreakableBetweenEnemy then return end

    return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0
end

function SWEP:CanSecondaryAttack()
    return false
end

local BOLT_AIR_VELOCITY      = 3500
local BOLT_WATER_VELOCITY    = 1500

function SWEP:PrimaryAttack()
    if !self:CanPrimaryAttack() then return end

    self:FireBolt()
    self:SetLastShootTime()
end

function SWEP:SecondaryAttack()
    if !self:CanSecondaryAttack() then return end
end

function SWEP:GetProjectileOffset()
    local owner = self:GetOwner()
    local aimVec = owner:GetAimVector()
    return owner:GetShootPos() + aimVec * 80, aimVec

end

function SWEP:FireBolt()
    if self:Clip1()<=0 then return end
    
    local owner = self:GetOwner()
    local sourceOffsetted, dir = self:GetProjectileOffset() -- stop hitting yourself!
    
    local bolt = self:CreateBolt(sourceOffsetted,dir:Angle(),GetConVarNumber("sk_plr_dmg_crossbow"),owner)
    
    if owner:WaterLevel()==3 then
        bolt:SetVelocity(dir*BOLT_WATER_VELOCITY)
    else
        bolt:SetVelocity(dir*BOLT_AIR_VELOCITY)
    end
    
    self:SetClip1(self:Clip1()-1)
    
    self:GetOwner():EmitSound(Sound("Weapon_Crossbow.Single"))
    
    self:SetNextPrimaryFire(CurTime()+2)
    self:SetNextSecondaryFire(CurTime()+2)
    
    self:DoLoadEffect()
end

function SWEP:CreateBolt(pos,ang,damage,owner)
    local bolt = ents.Create("crossbow_bolt")
    bolt:SetPos(pos)
    bolt:SetAngles(ang)
    bolt:Spawn()
    bolt:SetOwner(owner)
    bolt:SetSaveValue("m_hOwnerEntity",owner)
    bolt:EmitSound(Sound("Weapon_Crossbow.BoltFly"))

    local hookName = "term_crossbowbolt_damage_" .. tostring( bolt:GetCreationID() )

    hook.Add( "EntityTakeDamage", hookName, function( ent,dmg )
        if not IsValid( bolt ) then
            hook.Remove( "EntityTakeDamage", hookName )
            return

        end
        local inflictor = dmg:GetInflictor()
        if inflictor != bolt then return end

        dmg:SetDamage( damage )

    end )
    bolt:CallOnRemove( "term_crossbowbolt_removedamageoverride", function()
        hook.Remove( "EntityTakeDamage", hookName )

    end )

    return bolt
end

function SWEP:DoLoadEffect()
    local ef = EffectData()
    ef:SetAttachment(1)
    ef:SetEntity(self)
    
    local filter = RecipientFilter()
    filter:AddPAS(ef:GetOrigin())
    util.Effect("CrossbowLoad",ef,false,filter)
end

function SWEP:Equip()
end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
end

function SWEP:Reload()
    self:GetOwner():EmitSound(Sound("Weapon_Pistol.NPC_Reload"))
    self:SetClip1(self.Primary.ClipSize)
end

function SWEP:CanBePickedUpByNPCs()
    return true
end

function SWEP:GetNPCBulletSpread(prof)
    local spread = {5,4,3,2,1}
    return spread[prof+1]
end

function SWEP:GetNPCBurstSettings()
    return 1,1,0
end

function SWEP:GetNPCRestTimes()
    return 1,2
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end