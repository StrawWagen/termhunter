AddCSLuaFile()

if SERVER then
    util.AddNetworkString("weapon_rpg_sb_anb.muzzleflash")
else
    killicon.AddFont("weapon_rpg_sb_anb_better","HL2MPTypeDeath","3",Color(255,80,0))
end

SWEP.PrintName = "#HL2_RPG"
SWEP.Spawnable = false
SWEP.Author = "Shadow Bonnie (RUS)"
SWEP.Purpose = "Should only be used internally by advanced nextbots!"

SWEP.ViewModel = "models/weapons/c_rpg.mdl"
SWEP.WorldModel = "models/weapons/w_rocket_launcher.mdl"
SWEP.Weight = 6

SWEP.Primary = {
    Ammo = "RPG_Round",
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
    self:SetHoldType("rpg")

    if CLIENT then self:SetNoDraw(true) end

end



function SWEP:GetProjectileOffset()
    local owner = self:GetOwner()
    local aimVec = owner:GetAimVector()
    return owner:GetShootPos() + aimVec * 100, aimVec

end

function SWEP:CanPrimaryAttack()
    local owner = self:GetOwner()
    if not terminator_Extras.PosCanSeeComplex( owner:GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end

    if not owner.NothingOrBreakableBetweenEnemy then return end

    return CurTime() >= self:GetNextPrimaryFire() and self:Clip1() > 0

end

function SWEP:CanSecondaryAttack()
    return false
end

function SWEP:PrimaryAttack()
    if !self:CanPrimaryAttack() then return end
    if IsValid(self.Missile) then return end

    local owner = self:GetOwner()

    self:SetNextPrimaryFire(CurTime()+0.5)

    local dir = owner:GetAimVector()

    local missile = self:CreateMissile(owner:GetShootPos(),owner)
    missile:SetSaveValue("m_hOwner",self:GetParent())
    missile:SetSaveValue("m_flGracePeriodEndsAt",CurTime()+0.2)
    missile:SetSaveValue("m_flDamage",GetConVarNumber("sk_plr_dmg_rpg"))

    self.Missile = missile

    self:GetOwner():EmitSound(Sound("Weapon_RPG.NPC_Single"))

    self:SetClip1(self:Clip1()-1)
    self:SetLastShootTime()
end

function SWEP:CreateMissile( pos, owner )

    local createPos, ang = self:GetProjectileOffset()
    ang = ang:Angle()

    local missile = ents.Create( "rpg_missile" )
    missile:SetPos( createPos )
    missile:SetAngles( ang )
    missile:SetOwner( owner )
    missile:Spawn()
    missile:AddEffects( EF_NOSHADOW )

    missile.doFastTurnExpires = CurTime() + 0.2
    missile.traceFilter = owner

    local timerName = "TermMissileAim_" .. missile:EntIndex()
    timer.Create( timerName, 0.1, 0, function()
        if not IsValid( missile ) then
            timer.Remove( timerName )
            return
        end
        local missileTargetPos = nil
        local ownerShootPos
        if owner and owner.GetEnemy and IsValid( owner:GetEnemy() ) then
            ownerShootPos = owner:GetShootPos()
            local enemyShootPos = owner:EntShootPos( owner:GetEnemy() )
            local traceData = {
                start = ownerShootPos,
                endpos = enemyShootPos,
                mask = MASK_BLOCKLOS,
                filter = missile.traceFilter,
            }
            local missilelasertrace = util.TraceLine( traceData )
            missileTargetPos = missilelasertrace.HitPos

            local ent = missilelasertrace.Entity

            if IsValid( ent ) and ent:GetParent() == owner then
                table.insert( missile.traceFilter, ent )

            end
        end

        if missileTargetPos then

            local missileTargetPos2 = missileTargetPos
            local missilePos = missile:GetPos()

            if not owner:GetEnemy().InVehicle or not owner:GetEnemy():InVehicle() then
                local dirToTarget = ( missileTargetPos - ownerShootPos ):GetNormalized()
                local myDistToTarget = ownerShootPos:Distance( missileTargetPos )
                local wayBehindTargetPos = missileTargetPos + dirToTarget * ( myDistToTarget + -150 )

                if missilePos:DistToSqr( wayBehindTargetPos ) < missilePos:DistToSqr( owner:GetShootPos() ) then
                    missileTargetPos2 = missilePos + Vector( 0, 0, -1000 )

                end

            end

            local oldDir = missile:GetForward()
            local newDir = ( missileTargetPos2 - missilePos ):GetNormalized()
            local oldMul = 0.85
            if missile.doFastTurnExpires > CurTime() then
                oldMul = 0.6
            end

            local dirAdded = ( oldDir * oldMul ) + ( newDir * 0.25 )
            dirAdded = dirAdded:GetNormalized()
            local aimAngle = ( dirAdded ):Angle()
            missile:SetAngles( aimAngle )
            local negativeCurrentVelocity = -missile:GetVelocity()
            missile:SetVelocity( negativeCurrentVelocity + ( dirAdded * 1500 ) )

        end
    end )

    return missile
end

function SWEP:DoMuzzleFlash()
    if SERVER then
        net.Start("weapon_rpg_sb_anb.muzzleflash",true)
            net.WriteEntity(self)
        net.SendPVS(self:GetPos())
    else
        local MUZZLEFLASH_RPG = 7

        local ef = EffectData()
        ef:SetEntity(self:GetParent())
        ef:SetAttachment(self:LookupAttachment("muzzle"))
        ef:SetScale(1)
        ef:SetFlags(MUZZLEFLASH_RPG)
        util.Effect("MuzzleFlash",ef,false)
    end
end

if CLIENT then
    net.Receive("weapon_rpg_sb_anb.muzzleflash",function(len)
        local ent = net.ReadEntity()

        if IsValid(ent) and ent.DoMuzzleFlash then
            ent:DoMuzzleFlash()
        end
    end)
end

function SWEP:SecondaryAttack()
    if !self:CanSecondaryAttack() then return end
end

function SWEP:Equip()
    --print( self:GetOwner() )
    if self:GetOwner():IsPlayer() then
        self:GetOwner():Give( "weapon_rpg" )
        SafeRemoveEntity( self )
        return
    end
end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
end

function SWEP:Reload()
    self:SetClip1( self.Primary.ClipSize )
end

function SWEP:CanBePickedUpByNPCs()
    return true
end

function SWEP:GetNPCBulletSpread(prof)
    return 0
end

function SWEP:GetNPCBurstSettings()
    return 1,1,1
end

function SWEP:GetNPCRestTimes()
    return 4,4
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end