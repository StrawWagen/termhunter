AddCSLuaFile()

if SERVER then
    util.AddNetworkString( "weapon_terminatorfists_sb_anb" )
else
    language.Add( "weapon_terminatorfists_sb_anb", "Terminator's Fists" )
    killicon.AddFont( "weapon_terminatorfists_sb_anb", "HL2MPTypeDeath", "", Color( 255, 80, 0 ) )
end

SWEP.PrintName = "Terminator Fists"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Innate weapon that the terminator hunter will use"

SWEP.Range    = 80
SWEP.Weight = 0
SWEP.HitMask = MASK_SOLID

local SwingSound = Sound( "WeaponFrag.Throw" )
local HitSound = Sound( "Flesh.ImpactHard" )

SWEP.Primary = {
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

SWEP.Secondary = {
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

local function DoorHitSound( ent )
    ent:EmitSound( "ambient/materials/door_hit1.wav", 100, math.random( 80, 120 ) )

end
local function BreakSound( ent )
    local Snd = "physics/wood/wood_furniture_break" .. tostring( math.random( 1, 2 ) ) .. ".wav"
    ent:EmitSound( Snd, 110, math.random( 80, 90 ) )

end
local function StrainSound( ent )
    local Snd = "physics/wood/wood_strain" .. tostring( math.random( 2, 4 ) ) .. ".wav"
    ent:EmitSound( Snd, 80, math.random( 60, 70 ) )

end

local function LockBustSound( ent )
    ent:EmitSound( "doors/vent_open1.wav", 100, 80, 1, CHAN_STATIC )
    ent:EmitSound( "physics/metal/metal_solid_strain3.wav", 100, 200, 1, CHAN_STATIC )

end

local function SparkEffect( SparkPos )
    timer.Simple( 0, function() -- wow wouldnt it be cool if effects worked on the first tick personally i think that would be really cool
        local Sparks = EffectData()
        Sparks:SetOrigin( SparkPos )
        Sparks:SetMagnitude( 2 )
        Sparks:SetScale( 1 )
        Sparks:SetRadius( 6 )
        util.Effect( "Sparks", Sparks )

    end )

end

local function ModelBoundSparks( ent )
    local randpos = ent:WorldSpaceCenter() + VectorRand() * ent:GetModelRadius()
    randpos = ent:NearestPoint( randpos )

    -- move them a bit in from the exact edges of the model
    randpos = ent:WorldToLocal( randpos )
    randpos = randpos * 0.8
    randpos = ent:LocalToWorld( randpos )

    SparkEffect( randpos )

end

-- code from the sanic nextbot, the greatest nexbot
local function detachAreaPortals( self, door )

    local doorName = door:GetName()
    if doorName == "" then return end

    for _, portal in ipairs( ents.FindByClass( "func_areaportal" ) ) do
        local portalTarget = portal:GetInternalVariable( "m_target" )
        if portalTarget == doorName then

            portal:Input( "Open", self, door )

            portal:SetSaveValue( "m_target", "" )
        end
    end
end

function SWEP:MakeDoor( ent )
    local vel = self:GetForward() * 4800
    pos = ent:GetPos()
    ang = ent:GetAngles()
    mdl = ent:GetModel()
    ski = ent:GetSkin()

    detachAreaPortals( self:GetOwner(), ent )

    local getRidOf = { ent }
    table.Add( getRidOf, ent:GetChildren() )
    for _, toRid in pairs( getRidOf ) do
        toRid:SetNotSolid( true )
        toRid:SetNoDraw( true )
    end
    prop = ents.Create( "prop_physics" )
    prop:SetPos( pos )
    prop:SetAngles( ang )
    prop:SetModel( mdl )
    prop:SetSkin( ski or 0 )
    prop:Spawn()
    prop:SetVelocity( vel )
    prop:GetPhysicsObject():ApplyForceOffset( vel, self:GetPos() )
    prop:SetPhysicsAttacker( self )
    DoorHitSound( prop )
    BreakSound( prop )

    prop.isBustedDoor = true
    prop.bustedDoorHp = 400

end

hook.Add( "EntityTakeDamage", "term_busteddoorbreak", function( target, damage )
    if not target.isBustedDoor then return end
    local doorDamaged = damage:GetDamage()
    target.bustedDoorHp = target.bustedDoorHp + -doorDamaged

    local breakSound = "Breakable.MatWood"
    local modelRad = target:GetModelRadius()

    local trInfo = {
        start = target:GetPos() + vector_up * modelRad * 2,
        endpos = target:GetPos() + -vector_up * modelRad * 2,
        ignoreworld = true,
        filter = function( ent ) if ent == target then return true end return false end,
    }
    local result = util.TraceLine( trInfo )

    local surfaceProps = result.SurfaceProps
    local surfaceData = util.GetSurfaceData( surfaceProps )
    if surfaceData.breakSound and surfaceData.breakSound ~= "" then
        breakSound = surfaceData.breakSound

    end
    target:EmitSound( breakSound, 100, math.random( 80, 90 ) + target.bustedDoorHp / 100 )

    if target.bustedDoorHp <= 0 then
        SafeRemoveEntity( target )
    end

end )
local lockOffset = Vector( 0, 42.6, -10 )

function SWEP:HandleDoor( tr )
    if CLIENT or not IsValid( tr.Entity ) then return end
    local door = tr.Entity
    if door.realDoor then
        door = door.realDoor

    end
    local owner = self:GetOwner()
    local class = door:GetClass()

    -- let nails do their thing
    if door.huntersglee_breakablenails then return end

    if class == "func_door_rotating" or class == "prop_door_rotating" then
        local HitCount = door.PunchedCount or 0
        door.PunchedCount = HitCount + 1

        if terminator_Extras.CanBashDoor( door ) == false then
            DoorHitSound( door )
        else
            if HitCount > 4 then
                BreakSound( door )
            end
            if HitCount > 2 then
                StrainSound( door )
            end

            if HitCount >= 5 then
                self:MakeDoor( door )
            elseif HitCount < 5 then
                DoorHitSound( door )
                StrainSound( door )

                local newname = "TFABash" .. self:EntIndex()
                self.PreBashName = self:GetName()
                self:SetName( newname )

                if ( HitCount % 3 ) == 4 then
                    if owner.Use2 then
                        self:Use2( door )
                    else
                        door:Use( self, self )
                    end
                end

                if not door.defaultsGrabbed then
                    door.defaultsGrabbed = true
                    local values = door:GetKeyValues()
                    door.oldBashSpeed = values["speed"]
                    door.oldOpenDir = values["opendir"]
                end

                door:SetKeyValue( "speed", "500" )
                door:SetKeyValue( "opendir", 0 )
                door:Fire( "unlock", "", .01 )
                door:Fire( "openawayfrom", newname, .01 )

                timer.Simple( 0.02, function()
                    if not IsValid( basher ) or basher:GetName() ~= newname then return end

                    basher:SetName( basher.PreBashName )
                end )

                timer.Simple( 0.3, function()
                    if not IsValid( door ) then return end
                    if door.oldBashSpeed then
                        door:SetKeyValue( "speed", door.oldBashSpeed )
                    end
                    if door.oldOpenDir then
                        door:SetKeyValue( "opendir", door.oldOpenDir )
                    end
                end )
            end

            if door:GetInternalVariable( "m_bLocked" ) == true then
                SparkEffect( door:GetPos() + -lockOffset )
                LockBustSound( door )

            end
        end
    elseif class == "func_door" and door:GetInternalVariable( "m_bLocked" ) == true then
        local lockHealth = door.terminator_lockHealth
        if not door.terminator_lockHealth then
            local initialHealth = 200
            local doorsObj = door:GetPhysicsObject()
            if doorsObj and doorsObj:IsValid() then
                initialHealth = math.max( initialHealth, doorsObj:GetVolume() / 1250 )

            end
            lockHealth = initialHealth
            door.terminator_lockMaxHealth = initialHealth

        end

        local lockDamage = 15

        lockHealth = lockHealth + -lockDamage

        if lockHealth <= 0 then
            lockHealth = nil
            door:Fire( "unlock", "", .01 )
            DoorHitSound( door )
            LockBustSound( door )

            util.ScreenShake( owner:GetPos(), 80, 10, 1, 1500 )

            for _ = 1, 20 do
                ModelBoundSparks( door )

            end

        else
            DoorHitSound( door )
            if lockHealth < door.terminator_lockMaxHealth * 0.45 then
                ModelBoundSparks( door )
                util.ScreenShake( owner:GetPos(), 10, 10, 0.5, 600 )
                local pitch = math.random( 175, 200 ) + math.Clamp( -lockHealth, -100, 0 )
                door:EmitSound( "physics/metal/metal_box_break1.wav", 90, pitch, 1, CHAN_STATIC )

            end
        end

        door.terminator_lockHealth = lockHealth

    end
end

function SWEP:ResetHoldTypeCountdown()
    if not SERVER then return end
    local owner = self:GetOwner()
    if not IsValid( owner ) then return end
    local time = 15

    if owner:IsAngry() then
        time = 30

    end
    if owner:IsReallyAngry() then
        time = 120

    end
    local oldTime = self.doFistsTime
    self.doFistsTime = math.max( CurTime(), oldTime ) + time

end

function SWEP:HoldTypeThink()
    local owner = self:GetOwner()
    if not IsValid( owner ) then return end
    local enemy = owner:GetEnemy()
    local holdType = "fist"
    local doFistsTime = self.doFistsTime

    if owner.MimicPlayer then
        holdType = "normal"

    else
        self:SetHoldType( "fist" )
        return false

    end

    local path = owner:GetPath()

    if doFistsTime > CurTime() then
        holdType = "fist"

    elseif owner:IsReallyAngry() then
        holdType = "fist"

    elseif IsValid( enemy ) and enemy.isTerminatorHunterKiller then
        holdType = "fist"
        doFistsTime = math.max( doFistsTime, CurTime() + 10 )

    elseif IsValid( enemy ) and self.DistToEnemy and self.DistToEnemy < self.Range * 4 then
        holdType = "fist"

    elseif owner:getLostHealth() > 0.01 then
        holdType = "fist"
        doFistsTime = math.max( doFistsTime, CurTime() + 10 )

    elseif IsValid( enemy ) and path and path:GetEnd() and path:GetEnd():DistToSqr( enemy:GetPos() ) < 1000^2 and path:GetLength() < 1000 then
        holdType = "fist"
        doFistsTime = math.max( doFistsTime, CurTime() + 3 )

    end

    self.doFistsTime = doFistsTime
    local oldHoldType = self.oldHoldType

    if not oldHoldType or oldHoldType ~= holdType then
        self:SetHoldType( holdType )
        self.oldHoldType = holdType

    end
end

function SWEP:Initialize()
    self:SetHoldType( "normal" )

    if CLIENT then
        self:SetNoDraw( true )

    else
        self.doFistsTime = 0
        self.oldHoldType = nil

    end
end

function SWEP:CanPrimaryAttack()
    return CurTime() > self:GetNextPrimaryFire()
end

function SWEP:CanSecondaryAttack()
    return false
end

function SWEP:PrimaryAttack()
    if not self:CanPrimaryAttack() then return end

    self:ResetHoldTypeCountdown()
    self:DealDamage()

    self:SetClip1( self:Clip1() - 1 )
    self:SetNextPrimaryFire( CurTime() + 0.4 )
    self:SetLastShootTime()
end

function SWEP:DealDamage()

    local owner = self:GetOwner()

    local tr = util.TraceLine( {
        start = owner:GetShootPos(),
        endpos = owner:GetShootPos() + owner:GetAimVector() * self.Range,
        filter = owner,
        mask = bit.bor( self.HitMask ),
    } )

    if not IsValid( tr.Entity ) then
        tr = util.TraceHull( {
            start = owner:GetShootPos(),
            endpos = owner:GetShootPos() + owner:GetAimVector() * self.Range,
            filter = owner,
            mins = Vector( -10, -10, -8 ),
            maxs = Vector( 10, 10, 8 ),
            mask = bit.bor( self.HitMask ),
        } )
    end

    local scale = 3
    local hitEnt = tr.Entity

    if SERVER and IsValid( hitEnt ) then
        local Class = hitEnt:GetClass()
        local IsGlass = Class == "func_breakable_surf"
        -- teamkilling is funny but also stupid
        local friendly = hitEnt:IsNPC() and Class == self:GetOwner():GetClass() and self:GetOwner():Disposition( hitEnt ) ~= D_HT
        if IsGlass then
            hitEnt:Fire( "Shatter", tr.HitPos )
        else
            local _, entMemoryKey = owner.getMemoryOfObject and self:GetOwner():getMemoryOfObject( hitEnt )

            local dmgMul = owner.FistDamageMul
            if friendly then
                dmgMul = 0.05
                hitEnt.overrideMiniStuck = true

            end

            -- break not plauer stuff fast
            if not hitEnt:IsPlayer() then
                dmgMul = dmgMul + 1

            end
            local oldHealth = hitEnt:Health()

            local damageToDeal = math.random( 40, 50 ) * dmgMul
            local dmginfo = DamageInfo()

            local attacker = owner
            if not IsValid( attacker ) then attacker = self end
            dmginfo:SetAttacker( attacker )

            dmginfo:SetInflictor( self )
            dmginfo:SetDamage( damageToDeal )
            dmginfo:SetDamageType( DMG_CLUB )

            if hitEnt:IsPlayer() or hitEnt:IsNextBot() or hitEnt:IsNPC() then
                dmginfo:SetDamageForce( owner:GetAimVector() * 6998 * scale )

            end

            SuppressHostEvents( NULL ) -- Let the breakable gibs spawn in multiplayer on client
            hitEnt:TakeDamageInfo( dmginfo )
            SuppressHostEvents( owner )

            hit = true

            local MEMORY_BREAKABLE = 4

            timer.Simple( 0.1, function()
                if not IsValid( self ) then return end
                -- small things dont take the damage's force when in water????
                if IsValid( hitEnt ) and hitEnt:GetVelocity():LengthSqr() < 25 ^ 2 and IsValid( hitEnt:GetPhysicsObject() ) then
                    hitEnt:GetPhysicsObject():ApplyForceCenter( owner:GetAimVector() * 9998 )

                end

                if not IsValid( hitEnt ) or ( IsValid( hitEnt ) and oldHealth > 0 and hitEnt:Health() <= 0 ) then
                    self:GetOwner():memorizeEntAs( entMemoryKey, MEMORY_BREAKABLE )

                end
            end )


        end
        self:HandleDoor( tr )
    end
    if SERVER then
        if IsValid( hitEnt ) then
            self:EmitSound( HitSound )
            self:EmitSound( "physics/flesh/flesh_strider_impact_bullet1.wav", 80, math.random( 130, 160 ), 1, CHAN_STATIC )
            local phys = hitEnt:GetPhysicsObject()
            local punchForce = owner:GetAimVector()
            if IsValid( phys ) then
                punchForce = punchForce * math.Clamp( phys:GetMass() / 500, 0.25, 1 )
                punchForce = punchForce * 100000
                phys:ApplyForceOffset( punchForce, tr.HitPos )

            end
        else
            self:EmitSound( SwingSound )
            self:EmitSound( "weapons/slam/throw.wav", 80, 80 )
        end
    end
    if tr.Hit then
        util.ScreenShake( owner:GetPos(), 10, 10, 0.1, 400 )
        util.ScreenShake( owner:GetPos(), 1, 10, 0.5, 750 )
    end
end

function SWEP:SecondaryAttack()
    if not self:CanSecondaryAttack() then return end
end

function SWEP:DoMuzzleFlash()
end

function SWEP:Equip()
    if self:GetOwner():IsPlayer() and GetConVar( "sv_cheats" ):GetInt() ~= 1 then SafeRemoveEntity( self ) return end

    if not SERVER then return end

    local timerName = "terminator_fists_manageholdtype_" .. self:GetCreationID()

    timer.Create( timerName, 0.1, 0, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        if not IsValid( self:GetOwner() ) then timer.Remove( timerName ) return end
        if self:HoldTypeThink() == false then timer.Remove( timerName ) return end

    end )

end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
    SafeRemoveEntity( self )
end

function SWEP:Reload()
end

function SWEP:CanBePickedUpByNPCs()
    return true
end

function SWEP:GetNPCBulletSpread( prof )
    local spread = { 0,0,0,0,0 }
    return spread[ prof + 1 ]
end

function SWEP:ShouldWeaponAttackUseBurst()
    return true
end

function SWEP:GetNPCBurstSettings()
    return 1,4,0.05
end

function SWEP:GetNPCRestTimes()
    return 0.2, 0.4
end

function SWEP:GetCapabilities()
    return CAP_INNATE_MELEE_ATTACK1
end

function SWEP:DrawWorldModel()
end