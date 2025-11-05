AddCSLuaFile()

SWEP.PrintName = "Terminator Fists"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Innate weapon that the terminator hunter will use"

SWEP.Range    = 80
SWEP.Weight = 0
SWEP.HitMask = MASK_SOLID

local className = "weapon_terminatorfists_term"
if CLIENT then
    language.Add( className, SWEP.PrintName )
    killicon.Add( className, "vgui/hud/killicon/" .. className .. ".png", color_white )

end

local SwingSound = Sound( "WeaponFrag.Throw" )
local HitSound = Sound( "Flesh.ImpactHard" )

SWEP.Primary = {
    Automatic = true,
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

SWEP.Secondary = {
    Ammo = "None",
    ClipSize = -1,
    DefaultClip = -1,
}

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
    if surfaceProps then
        local surfaceData = util.GetSurfaceData( surfaceProps )
        if surfaceData and surfaceData.breakSound and surfaceData.breakSound ~= "" then
            breakSound = surfaceData.breakSound

        end
    end
    target:EmitSound( breakSound, 100, math.random( 80, 90 ) + target.bustedDoorHp / 100 )

    if target.bustedDoorHp <= 0 then
        SafeRemoveEntity( target )
    end

end )
local lockOffset = Vector( 0, 42.6, -10 )

local slidingDoors = {
    ["func_movelinear"] = true,
    ["func_door"] = true,

}

function SWEP:HandleDoor( tr, strength )
    if CLIENT or not IsValid( tr.Entity ) then return end
    local door = tr.Entity
    if door.realDoor then
        door = door.realDoor

    end
    local owner = self:GetOwner()
    local class = door:GetClass()

    -- let nails do their thing
    if door.huntersglee_breakablenails then return end

    local doorsLocked = door:GetInternalVariable( "m_bLocked" ) == true

    if doorsLocked then
        terminator_Extras.lockedDoorAttempts = {}

    end

    local doorsObj = door:GetPhysicsObject()
    local isProperDoor = class == "prop_door_rotating"
    local isSlidingDoor = slidingDoors[class]
    local isBashableSlidDoor
    if isSlidingDoor then
        isBashableSlidDoor = doorsObj:GetVolume() < 48880 -- magic number! 10x mass of doors on terrortrain

    end
    if owner.markAsTermUsed then
        owner:markAsTermUsed( door )

    end

    if isSlidingDoor and doorsLocked then
        local lockHealth = door.terminator_lockHealth
        if not door.terminator_lockHealth then
            local initialHealth = 200
            if IsValid( doorsObj ) then
                initialHealth = math.max( initialHealth, doorsObj:GetVolume() / 1250 )

            end
            lockHealth = initialHealth
            door.terminator_lockMaxHealth = initialHealth

        end

        local lockDamage = 15 * strength

        lockHealth = lockHealth + -lockDamage

        if lockHealth <= 0 then
            lockHealth = nil
            door:Fire( "unlock", "", .01 )
            terminator_Extras.DoorHitSound( door )
            LockBustSound( door )

            util.ScreenShake( owner:GetPos(), 80, 10, 1, 1500 )

            for _ = 1, 20 do
                ModelBoundSparks( door )

            end

        else
            terminator_Extras.DoorHitSound( door )
            if lockHealth < door.terminator_lockMaxHealth * 0.45 then
                ModelBoundSparks( door )
                util.ScreenShake( owner:GetPos(), 10, 10, 0.5, 600 )
                local pitch = math.random( 175, 200 ) + math.Clamp( -lockHealth, -100, 0 )
                door:EmitSound( "physics/metal/metal_box_break1.wav", 90, pitch, 1, CHAN_STATIC )

            end
        end

        door.terminator_lockHealth = lockHealth

    elseif class == "func_door_rotating" or isProperDoor or isBashableSlidDoor then
        local HitCount = door.term_PunchedCount or 0
        door.term_PunchedCount = HitCount + strength

        if terminator_Extras.CanBashDoor( door ) == false then
            terminator_Extras.DoorHitSound( door )

        else
            if HitCount > 4 then
                terminator_Extras.BreakSound( door )

            end
            if HitCount > 2 then
                terminator_Extras.StrainSound( door )

            end

            if HitCount >= 5 then
                local debris = terminator_Extras.DehingeDoor( self, door )
                if not IsValid( debris ) then return end
                if not owner.markAsTermUsed then return end
                owner:markAsTermUsed( debris )

            elseif HitCount < 5 then
                terminator_Extras.DoorHitSound( door )
                terminator_Extras.StrainSound( door )

                if ( HitCount % 3 ) == 4 then
                    if owner.Use2 then
                        self:Use2( door )

                    else
                        door:Use( self, self )

                    end
                end

                if isProperDoor then
                    self:SoftBashProperDoor( door, owner )

                end
            end

            if doorsLocked and isProperDoor then
                SparkEffect( door:GetPos() + -lockOffset )
                LockBustSound( door )

            end
        end
    end
end

function SWEP:SoftBashProperDoor( door, owner )
    local newname = "TFABash" .. self:EntIndex()
    self.term_PreBashName = self:GetName()
    self:SetName( newname )

    if not door.term_defaultsGrabbed then
        door.term_defaultsGrabbed = true
        local values = door:GetKeyValues()
        door.term_oldBashSpeed = values["speed"]
        door.term_oldOpenDir = values["opendir"]
        door.term_oldOpenDmg = values["dmg"]

    end

    door:SetKeyValue( "speed", "500" )
    door:SetKeyValue( "opendir", 0 )
    door:SetKeyValue( "dmg", 100 )
    door:Fire( "unlock", "", .01 )
    door:Fire( "openawayfrom", newname, .01 )

    timer.Simple( 0.02, function()
        if not IsValid( owner ) or owner:GetName() ~= newname then return end

        owner:SetName( owner.term_PreBashName )

    end )

    timer.Simple( 0.3, function()
        if not IsValid( door ) then return end
        if door.term_oldBashSpeed then
            door:SetKeyValue( "speed", door.term_oldBashSpeed )

        end
        if door.term_oldOpenDir then
            door:SetKeyValue( "opendir", door.term_oldOpenDir )

        end
        if door.term_oldOpenDmg then
            door:SetKeyValue( "dmg", door.term_oldOpenDmg )

        end
    end )
end

function SWEP:ResetHoldTypeCountdown()
    if not SERVER then return end
    local owner = self:GetOwner()
    if not IsValid( owner ) then return end
    if not owner.GetEnemy then return end
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
    if not owner.GetEnemy then return end
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

    elseif owner:IsReallyAngry() and not owner.AlwaysAngry then
        holdType = "fist"

    elseif IsValid( enemy ) and enemy.isTerminatorHunterKiller then
        holdType = "fist"
        doFistsTime = math.max( doFistsTime, CurTime() + 10 )

    elseif IsValid( enemy ) and owner.DistToEnemy and owner.DistToEnemy < self.Range * 4 then
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
    self:DrawShadow( false )

    if not SERVER then return end
    self.doFistsTime = 0
    self.oldHoldType = nil

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

local MEMORY_BREAKABLE = 4

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
        local friendly = hitEnt:IsNPC() and hitEnt.isTerminatorHunterChummy == owner.isTerminatorHunterChummy and owner:Disposition( hitEnt ) ~= D_HT

        local strength = owner.FistDamageMul or 1

        if IsGlass then
            hitEnt:Fire( "Shatter", tr.HitPos )
        else
            local dmgMul = strength
            if friendly then
                dmgMul = 0.05
                hitEnt.overrideMiniStuck = true

            end
            -- break not plauer stuff fast
            if not hitEnt:IsPlayer() then
                dmgMul = dmgMul + 1

            end

            local damageToDeal = math.random( 40, 50 ) * dmgMul
            local dmginfo = DamageInfo()

            local attacker = owner
            if not IsValid( attacker ) then attacker = self end
            dmginfo:SetAttacker( attacker )

            dmginfo:SetInflictor( self )
            dmginfo:SetDamage( damageToDeal )
            dmginfo:SetDamageType( DMG_CLUB )
            dmginfo:SetDamagePosition( tr.HitPos )

            if hitEnt:IsPlayer() or hitEnt:IsNextBot() or hitEnt:IsNPC() then
                dmginfo:SetDamageForce( owner:GetAimVector() * 6998 * scale )

            else
                dmginfo:SetDamageForce( owner:GetAimVector() * 100 )

            end

            SuppressHostEvents( NULL ) -- Let the breakable gibs spawn in multiplayer on client
            hitEnt:TakeDamageInfo( dmginfo )
            SuppressHostEvents( owner )

            if owner:IsOnFire() then
                hitEnt:Ignite( damageToDeal / 40 )

            end

            if owner.PostHitObject then
                owner:PostHitObject( hitEnt, damageToDeal )

            end

        end
        local isSignificant = hitEnt:IsNPC() or hitEnt:IsNextBot() or hitEnt:IsPlayer()

        if not isSignificant then
            hitEnt:ForcePlayerDrop()
            local oldHealth = hitEnt:Health()
            local _, entMemoryKey = owner.getMemoryOfObject and owner:getMemoryOfObject( owner:GetTable(), hitEnt )

            timer.Simple( 0.1, function()
                if not IsValid( self ) then return end
                -- small things dont take the damage's force when in water????
                if IsValid( hitEnt ) and hitEnt:GetVelocity():LengthSqr() < 25 ^ 2 and IsValid( hitEnt:GetPhysicsObject() ) then
                    hitEnt:GetPhysicsObject():ApplyForceCenter( owner:GetAimVector() * 9998 )

                end

                if owner.memorizeEntAs and not IsValid( hitEnt ) or ( IsValid( hitEnt ) and oldHealth > 0 and hitEnt:Health() <= 0 ) then
                    owner:memorizeEntAs( entMemoryKey, MEMORY_BREAKABLE )

                end
            end )
        end
        self:HandleDoor( tr, strength )
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