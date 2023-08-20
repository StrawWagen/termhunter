AddCSLuaFile()

if CLIENT then
    killicon.AddFont( "weapon_crowbar_sb_anb", "HL2MPTypeDeath", "1", Color( 255, 80, 0 ) )
end

SWEP.PrintName = "#HL2_Crowbar"
SWEP.Spawnable = false
SWEP.Author = "Shadow Bonnie (RUS)"
SWEP.Purpose = "Should only be used internally by advanced nextbots!"

SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.Weight = 6

SWEP.Primary = {
    Ammo = "None",
    ClipSize = 1,
    DefaultClip = 1,
}

SWEP.Secondary = {
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

Terminator_SetupAnalogWeight( SWEP )

SWEP.PickupSound = "weapons/crowbar/crowbar_impact2.wav"
SWEP.Range = 2200
SWEP.MeleeWeaponDistance = SWEP.Range
SWEP.HoldType = "melee"
SWEP.SpawningOffset = 50
SWEP.ThrowForce = 28000
SWEP.ClassToRespawnAs = "weapon_crowbar"

function SWEP:Initialize()
    self:SetHoldType( self.HoldType )
    self:SetNextPrimaryFire( CurTime() + 1 )

    if CLIENT then self:SetNoDraw( true ) end
end

function SWEP:GetProjectileOffset()
    local owner = self:GetOwner()
    local aimVec = owner:GetAimVector()
    return owner:GetShootPos() + aimVec * self.SpawningOffset, aimVec

end

function SWEP:CanPrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return false end

    local owner = self:GetOwner()
    if not util.PosCanSeeComplex( owner:GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end

    if not owner.NothingOrBreakableBetweenEnemy then return end

    local enemy = self:GetOwner():GetEnemy()
    if not IsValid( enemy ) then return true end

    local dot = enemy:GetVelocity():GetNormalized():Dot( self:GetOwner():GetVelocity():GetNormalized() )
    local whoCares = enemy:IsNPC() or ( self.getLostHealth and self:getLostHealth() > 10 ) or owner.DistToEnemy < 200
    if not whoCares and math.abs( dot ) > 0.25 then return end

    return true

end

function SWEP:CanSecondaryAttack()
    return false
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    self:Swing()
    self:SetLastShootTime()
end

function SWEP:SecondaryAttack()
    if not self:CanSecondaryAttack() then return end
end

function SWEP:SwingSpawn( spawnPos )
    local new = ents.Create( "prop_physics" )
    new:SetModel( "models/weapons/w_crowbar.mdl" )
    new:SetAngles( AngleRand() )
    new:SetPos( spawnPos )
    new:SetOwner( self:GetOwner() )
    new.isTerminatorHunterCrowbar = true
    new:Spawn()

    return new

end

function SWEP:ThrowStartSound( owner )
    owner:EmitSound( "weapons/slam/throw.wav", 90, 150 )

end

function SWEP:SwingingSound( projectile )
    projectile:EmitSound( "weapons/slam/throw.wav", 100, 80 )
    projectile:EmitSound( "weapons/crowbar/crowbar_impact1.wav", 75, 100 )

end

function SWEP:Swing()
    if not SERVER then return end

    local owner = self:GetOwner()
    self:SetColor( Color( 255, 255, 255, 0 ) )
    SafeRemoveEntityDelayed( self, 0.3 )
    self:SetNextPrimaryFire( CurTime() + 10 )

    self:ThrowStartSound( owner )

    timer.Simple( 0.2, function()
        if not IsValid( self ) then return end
        local newPos, aimVec = self:GetProjectileOffset()

        local thrownFake = self:SwingSpawn( newPos )

        local obj = thrownFake:GetPhysicsObject()
        local force = 0

        if isnumber( self.ThrowForce ) then
            force = self.ThrowForce

        elseif isfunction( self.ThrowForce ) then
            force = self:ThrowForce()

        end

        if not owner.ReallyStrong then
            force = force / 5

        end

        if force > 15000 then
            self:DoFlyingSound( thrownFake, aimVec )

        end

        obj:ApplyForceCenter( aimVec * force )
        obj:SetAngleVelocity( aimVec * force )

        self:SwingingSound( thrownFake )

        local ClassToRespawnAs = self.ClassToRespawnAs

        timer.Simple( 3, function()
            if not IsValid( thrownFake ) then return end
            if thrownFake.blockReturnAsWeap then return end
            local returnWeap = ents.Create( ClassToRespawnAs )
            returnWeap:SetAngles( thrownFake:GetAngles() )
            returnWeap:SetPos( thrownFake:GetPos() )
            returnWeap:Spawn()

            timer.Simple( 60 * 5, function()
                if not IsValid( returnWeap ) or IsValid( returnWeap:GetParent() ) or IsValid( returnWeap:GetOwner() ) then return end
                SafeRemoveEntity( returnWeap )

            end )
            SafeRemoveEntity( thrownFake )

        end )
    end )
end

hook.Add( "EntityTakeDamage", "STRAW_terminatorHunter_crowbarCorrectTheAttacker", function( target, damage )
    local inflic = damage:GetInflictor()
    if not IsValid( inflic ) then return end
    if not inflic.isTerminatorHunterCrowbar then return end
    for _ = 1, 2 do
        target:EmitSound( "weapons/crowbar/crowbar_impact" .. math.random( 1, 2 ) .. ".wav", 80, math.random( 60,100 ), 0.75, CHAN_STATIC )
    end
    for _ = 1, 4 do
        target:EmitSound( "npc/antlion/shell_impact" .. math.random( 1, 4 ) .. ".wav", 90, math.random( 40, 80 ), 1, CHAN_STATIC )
    end
    if not IsValid( inflic:GetOwner() ) then return end
    damage:SetAttacker( inflic:GetOwner() )
    damage:ScaleDamage( 1.5 )
    damage:SetDamage( math.Clamp( damage:GetDamage(), 0, 200 ) )

    if math.random( 0, 100 ) > 85 and target:IsPlayer() and damage:GetDamage() >= target:GetMaxHealth() then
        local force = ( VectorRand() + vector_up ) * 25000000 -- SPIN!
        damage:SetDamageForce( force )
        damage:SetDamagePosition( target:GetPos() )

    end
end )

function SWEP:Equip()
    self:SetNextPrimaryFire( CurTime() + 1 )
    self:GetOwner():EmitSound( self.PickupSound, 80, 120, 0.6 )

end

local airSoundPath = "ambient/levels/canals/windmill_wind_loop1.wav"

function SWEP:DoFlyingSound( thrown, direction )
    local filterAll = RecipientFilter()
    filterAll:AddAllPlayers()

    local airSound = CreateSound( thrown, airSoundPath, filterAll )
    airSound:SetSoundLevel( 90 )
    airSound:PlayEx( 1, 150 )
    local timerName = "terminator_thrown_manage_sound_" .. thrown:GetCreationID()

    thrown:CallOnRemove( "terminator_stopwhooshsound", function() thrown:StopSound( airSoundPath ) end )

    local StopAirSound = function()
        timer.Remove( timerName )
        if not IsValid( thrown ) then return end
        thrown:StopSound( airSoundPath )
    end

    timer.Create( timerName, 0, 0, function()
        if not IsValid( thrown ) then StopAirSound() return end
        if not airSound:IsPlaying() then StopAirSound() return end
        local vel = thrown:GetVelocity():Length()
        local pitch = vel / 10
        local volume = vel / 1500
        if pitch < 10 then StopAirSound() return end
        airSound:ChangePitch( pitch )
        airSound:ChangeVolume( volume )

    end )
end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
end

function SWEP:Reload()
end

function SWEP:CanBePickedUpByNPCs()
    return true
end


function SWEP:GetNPCBulletSpread(prof)
    return 1
end

function SWEP:GetNPCBurstSettings()
    return 1,1,0
end

function SWEP:GetNPCRestTimes()
    return 0.5,1
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end