AddCSLuaFile()

if CLIENT then
    local function getVelocityDelta( ent, entTbl )
        local currPos = ent:WorldSpaceCenter()
        local currTime = CurTime()
        local oldPos = entTbl._OldVelocityPos
        local oldTime = entTbl._LastVelCheckTime
        entTbl._OldVelocityPos = currPos
        entTbl._LastVelCheckTime = currTime

        if not ( oldPos and oldTime ) then return end

        local deltaTime = math.abs( currTime - oldTime )

        local vel = currPos - oldPos
        vel = vel / deltaTime -- anchors vel to time, wont blow up when there's lag or anything

        return vel
    end

    killicon.AddFont( "weapon_crowbar_term", "HL2MPTypeDeath", "1", Color( 255, 80, 0 ) )

    local airSoundPath = "ambient/levels/canals/windmill_wind_loop1.wav"

    net.Receive( "terminator_crowbar_airrushingsound", function()
        local thrown = net.ReadEntity()
        if not IsValid( thrown ) then return end

        local airSound = CreateSound( thrown, airSoundPath )
        airSound:SetSoundLevel( 90 )
        airSound:PlayEx( 1, 150 )
        local timerName = "terminator_thrown_manage_sound_" .. thrown:GetCreationID()

        thrown:CallOnRemove( "terminator_stopwhooshsound", function() thrown:StopSound( airSoundPath ) end )

        local StopAirSound = function( fade )
            timer.Remove( timerName )
            if not IsValid( thrown ) then return end
            thrown:StopSound( airSoundPath, fade and 2 or nil )

            if not IsValid( thrown.tracer ) then return end
            SafeRemoveEntityDelayed( thrown.tracer, 0.2 )
        end

        local noVelFailures = 0

        timer.Create( timerName, 0, 0, function()
            if not IsValid( thrown ) then StopAirSound() return end
            if not airSound:IsPlaying() then StopAirSound() return end
            if thrown:IsDormant() then StopAirSound( true ) return end -- went out of PVS

            local velPosBased = getVelocityDelta( thrown, thrown:GetTable() )
            if not velPosBased then
                noVelFailures = noVelFailures + 1
                if noVelFailures > 5 then StopAirSound( true ) end
                return

            end

            velPosBased = velPosBased:Length()

            local pitch = velPosBased / 10
            local volume = velPosBased / 1500
            if pitch < 10 then
                noVelFailures = noVelFailures + 1
                if noVelFailures > 5 then StopAirSound( true ) end
                return

            end

            noVelFailures = 0
            airSound:ChangePitch( pitch )
            airSound:ChangeVolume( volume )

            if not IsValid( thrown.tracer ) then return end
            thrown.tracer:SetPos( thrown:GetPos() )

        end )
    end )
else
    util.AddNetworkString( "terminator_crowbar_airrushingsound" )

end

SWEP.PrintName = "#HL2_Crowbar"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Should only be used internally by term nextbots!"

SWEP.ViewModel = "models/weapons/c_crowbar.mdl"
SWEP.WorldModel = "models/weapons/w_crowbar.mdl"
SWEP.Weight = terminator_Extras.GoodWeight + -2

SWEP.Primary = {
    Automatic = true,
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

SWEP.Secondary = {
    Automatic = true,
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

terminator_Extras.SetupAnalogWeight( SWEP )

SWEP.PickupSound = "weapons/crowbar/crowbar_impact2.wav"
SWEP.Range = 2200
SWEP.MeleeWeaponDistance = SWEP.Range
SWEP.HoldType = "melee"
SWEP.SpawningOffset = 50
SWEP.ThrowForce = 28000
SWEP.PreOverrideClass = "weapon_crowbar"
SWEP.MinForceMul = 0

SWEP.SmackDamage = 25
SWEP.SmackSwingSound = "Weapon_Crowbar.Single"
SWEP.SmackHitSound = "Weapon_Crowbar.Melee_HitWorld"
SWEP.SmackDelay = 0.5

function SWEP:Initialize()
    self:SetHoldType( self.HoldType )
    self:SetNextPrimaryFire( CurTime() + 1 )

end

function SWEP:GetProjectileOffset()
    local owner = self:GetOwner()
    local aimVec = owner:GetAimVector()
    return owner:GetShootPos() + aimVec * self.SpawningOffset, aimVec

end

function SWEP:CanPrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return false end

    local owner = self:GetOwner()
    if owner:IsControlledByPlayer() then return true end

    if not owner.NothingOrBreakableBetweenEnemy then return end

    local enemy = self:GetOwner():GetEnemy()
    if not IsValid( enemy ) then return true end

    local dot = enemy:GetVelocity():GetNormalized():Dot( self:GetOwner():GetVelocity():GetNormalized() )
    local whoCares = enemy:IsNPC() or ( self.getLostHealth and self:getLostHealth() > 10 ) or owner.DistToEnemy < 200
    if not whoCares and math.abs( dot ) > 0.25 then return end

    return true

end

function SWEP:CanSecondaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return false end
    return true
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    local shouldThrow = terminator_Extras.PosCanSeeComplex( self:GetOwner():GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID )
    if shouldThrow then
        self:Swing()

    else
        self:Smack()

    end
end

function SWEP:SecondaryAttack()
    if not self:CanSecondaryAttack() then return end
    self:Smack()

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

local invisWhite = Color( 255, 255, 255, 0 )

function SWEP:Swing()
    if not SERVER then return end

    local wepsClass = self:GetClass()
    local owner = self:GetOwner()
    self:SetColor( invisWhite )
    SafeRemoveEntityDelayed( self, 0.3 )
    self:SetNextPrimaryFire( CurTime() + 10 )
    self:SetNextSecondaryFire( CurTime() + 10 )

    self:ThrowStartSound( owner )

    timer.Simple( 0.2, function()
        if not IsValid( self ) then return end
        local newPos, aimVec = self:GetProjectileOffset()

        local thrownFake = self:SwingSpawn( newPos )

        if not IsValid( thrownFake ) then return end
        thrownFake.terminator_Judger_WepClassToCredit = wepsClass

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
        if owner.ThrowingForceMul then
            local forceMul = math.Clamp( owner.ThrowingForceMul, self.MinForceMul, math.huge )
            force = force * forceMul

        end

        if force > 15000 then
            self:DoFlyingSound( thrownFake, aimVec, force )

        end

        if force > 150000 then
            obj:SetDragCoefficient( 0 )
            obj:SetMass( obj:GetMass() * 10 )

        end
        obj:ApplyForceCenter( aimVec * force )
        obj:SetAngleVelocityInstantaneous( aimVec * force * 10 )

        self:SwingingSound( thrownFake )

        local PreOverrideClass = self.PreOverrideClass

        timer.Simple( 3, function()
            if not IsValid( thrownFake ) then return end
            if thrownFake.blockReturnAsWeap then return end
            local returnWeap = ents.Create( PreOverrideClass )
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

local IsValid = IsValid

hook.Add( "EntityTakeDamage", "STRAW_terminatorHunter_crowbarCorrectTheAttacker", function( target, damage )
    local inflic = damage:GetInflictor()
    if not IsValid( inflic ) then return end
    if not IsValid( target ) then return end -- sharpness dealing damage to world
    if target == inflic then return end -- sharpness, again

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

function SWEP:DoFlyingSound( thrown, direction, force )
    local filterAll = RecipientFilter()
    filterAll:AddAllPlayers()

    if force > 200000 then -- SONIC BOOM
        util.ScreenShake( self:GetOwner():WorldSpaceCenter(), 5, 20, 0.2, 3000, true, filterAll )
        local owner = self:GetOwner()

        for _, ent in ipairs( ents.FindByClass( "player" ) ) do
            if not ent:IsPlayer() then continue end
            local dist = owner:GetPos():Distance( ent:GetPos() )

            if dist > 8000 then return end
            local distInverted = ( 8000 - dist ) + 4000

            timer.Simple( dist / 8000, function()
                if not IsValid( ent ) then return end
                if not owner or isnumber( owner ) then return end -- ??????????????????????????????????
                if not IsValid( owner ) then return end
                if not IsValid( thrown ) then return end

                local filterJustEnt = RecipientFilter()
                filterJustEnt:AddPlayer( ent )

                util.ScreenShake( owner:WorldSpaceCenter(), 40, 20, 0.2, 4000, true, filterJustEnt )
                util.ScreenShake( ent:WorldSpaceCenter(), 40, 20, 0.2, 3000, true, filterJustEnt )
                ent:EmitSound( "npc/sniper/sniper1.wav", 130, 80, distInverted / 8000, CHAN_STATIC, 0, 0, filterJustEnt )
                owner:EmitSound( "npc/sniper/echo1.wav", 100, 60, distInverted / 8000, CHAN_STATIC, 0, 0, filterJustEnt )

                net.Start( "terminator_crowbar_airrushingsound", true )
                    net.WriteEntity( thrown )
                net.Send( ent )

                if not thrown.isTerminatorHunterCrowbar then return end
                thrown:EmitSound( "weapons/crowbar/crowbar_impact" .. math.random( 1, 2 ) .. ".wav", 75, math.random( 40, 60 ), 0.75, CHAN_STATIC, nil, nil, filterJustEnt )

            end )
        end

        local tracer = ents.Create( "env_spritetrail" )
        tracer:SetKeyValue( "lifetime", "0.2" )
        tracer:SetKeyValue( "startwidth", "2" )
        tracer:SetKeyValue( "endwidth", "0" )
        tracer:SetKeyValue( "spritename", "trails/laser.vmt" )
        tracer:SetKeyValue( "rendermode", "5" )
        tracer:SetKeyValue( "rendercolor", "255 255 255" )
        tracer:SetPos( thrown:GetPos() )
        tracer:Spawn()
        tracer:Activate()

        thrown.tracer = tracer

    else -- below speed of sound, just play it normally
        net.Start( "terminator_crowbar_airrushingsound", true )
            net.WriteEntity( thrown )
        net.Send( filterAll )
    end
end

-- simple melee attack if there's no room to throw
function SWEP:Smack()
    if not SERVER then return end

    local owner = self:GetOwner()
    local _, aimVec = self:GetProjectileOffset()

    self:SetNextPrimaryFire( CurTime() + self.SmackDelay )
    self:SetNextSecondaryFire( CurTime() + self.SmackDelay )

    -- Play swing sound
    owner:EmitSound( self.SmackSwingSound, 75, math.random( 90, 110 ) )

    -- Shoot an invisible bullet like the default crowbar
    owner:FireBullets( {
        Num = 1,
        Src = owner:GetShootPos(),
        Dir = aimVec,
        Spread = vector_origin,
        Tracer = 0,
        Force = 1,
        Damage = self.SmackDamage,
        HullSize = 1,
        Distance = self.SpawningOffset,
        Callback = function( attacker, tr, dmginfo )
            if tr.Hit then
                owner:EmitSound( self.SmackHitSound, 100, math.random( 80, 100 ) )
            end
            dmginfo:SetDamageType( DMG_CLUB )
        end,
    } )
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
    return 0,0
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

if not CLIENT then return end

function SWEP:DrawWorldModel()
end