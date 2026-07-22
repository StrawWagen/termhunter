AddCSLuaFile()

SWEP.PrintName = "Terminator Fists"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Innate weapon that the terminator hunter will use"

SWEP.Range    = 80
SWEP.Weight = 0
SWEP.HitMask = MASK_SOLID

SWEP.DamageMin = 40
SWEP.DamageMax = 50
SWEP.DamageType = DMG_CLUB

-- added to the owner's FistDamageMul, so a strength 4 owner hits props for 5x, not 4x
SWEP.PropDamageBonusMul = 1
SWEP.NPCDamageBonusMul = 1

local className = "weapon_terminatorfists_term"
if CLIENT then
    language.Add( className, SWEP.PrintName )
    killicon.Add( className, "vgui/hud/killicon/" .. className .. ".png", color_white )

end

local entMeta = FindMetaTable( "Entity" )
local vecMeta = FindMetaTable( "Vector" )
local distToSqr = vecMeta.DistToSqr

SWEP.SwingSound = Sound( "WeaponFrag.Throw" )
SWEP.HitSound = Sound( "Flesh.ImpactHard" )
SWEP.PoundSound = Sound( "npc/zombie/zombie_pound_door.wav" )
SWEP.ShoveSound = Sound( "npc/antlion_guard/shove1.wav" )
SWEP.ViewPunchMul = 1

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
        filter = function( ent )
            if ent == target then return true end
            return false

        end,
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

local slidingDoors = {
    ["func_movelinear"] = true,
    ["func_door"] = true,

}

function SWEP:HandleDoor( door, strength )
    if CLIENT or not IsValid( door ) then return end
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
    if isSlidingDoor and IsValid( doorsObj ) then
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

                if ( HitCount % 3 ) == 0 then
                    if owner.Use2 then
                        owner:Use2( door )

                    else
                        door:Use( self, self )

                    end
                end

                if isProperDoor then
                    terminator_Extras.OpenDoorQuicklyAwayFrom( door, self )

                end
            end

            if doorsLocked and isProperDoor then
                terminator_Extras.EmitSparksFromDoorHandle( door )
                LockBustSound( door )

            end
        end
    end
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
    local oldTime = self.doFistsTime or 0
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

function SWEP:PlayHitSound( owner, pitchShift )
    self:EmitSound( self.HitSound, 75, 100 + pitchShift )
    self:EmitSound( "physics/flesh/flesh_strider_impact_bullet1.wav", 80, math.random( 130, 160 ) + pitchShift, 1, CHAN_STATIC )

end

function SWEP:PlaySwingSound( owner, pitchShift )
    self:EmitSound( self.SwingSound, 75, 100 + pitchShift )
    self:EmitSound( "weapons/slam/throw.wav", 80, 80 + pitchShift )

end

local MEMORY_BREAKABLE = 4

function SWEP:DealDamage()
    if not SERVER then return end

    local owner = self:GetOwner()
    local ownersShoot = owner:GetShootPos()
    local aimVec = owner:GetAimVector()
    local strength = owner.FistDamageMul or 1
    local rangeMul = owner.FistRangeMul or 1

    local sizeMul = 1 + ( strength / 8 )
    local range = self.Range * rangeMul

    local tr = util.TraceLine( {
        start = ownersShoot,
        endpos = ownersShoot + aimVec * range,
        filter = owner,
        mask = bit.bor( self.HitMask ),
    } )

    local firstTirDist = tr.Fraction * range
    local hitEnts

    -- traceLine hit, use that
    if IsValid( tr.Entity ) then
        hitEnts = { tr.Entity }

    -- traceLine did not hit, find things to hit with ents.FindAlongRay
    else
        local startPos = ownersShoot
        local smallerDist = math.min( firstTirDist, range * 0.75 )

        if sizeMul > 25 then -- sanity clamp
            local _, myMaxs = owner:GetCollisionBounds()
            sizeMul = math.min( sizeMul, myMaxs.z )

        end

        local maxs = Vector( 10, 10, 8 ) * sizeMul
        local mins = -maxs
        mins.z = mins.z * 1.5

        if owner:GetModelScale() > terminator_Extras.MDLSCALE_LARGE then
            local _, ownersMaxs = owner:BoundsAdjusted( 0.75 )
            if ownersMaxs.z > maxs.z then -- big owner, hit guys at our toes too
                maxs.z = ownersMaxs.z
                startPos = owner:WorldSpaceCenter()

            end
        end

        local endPos = startPos + aimVec * smallerDist

        hitEnts = ents.FindAlongRay( startPos, endPos, mins, maxs )

    end

    local startingDamage = math.random( self.DamageMin, self.DamageMax )
    local totalDamage = startingDamage

    if #hitEnts > 1 then
        local centers = {}
        for _, ent in ipairs( hitEnts ) do
            centers[ent] = entMeta.WorldSpaceCenter( ent )

        end

        table.sort( hitEnts, function( a, b ) -- sort ents by distance to me
            local ADist = distToSqr( centers[a], ownersShoot )
            local BDist = distToSqr( centers[b], ownersShoot )
            return ADist < BDist

        end )
    end

    local hitSomething
    local hitAlready = {}
    local playedPoundSound
    local playedShoveSound

    for _, hitEnt in ipairs( hitEnts ) do
        if totalDamage < startingDamage * 0.05 then break end
        if hitEnt == owner then continue end -- stop hitting yourself
        if not hitEnt:IsSolid() then continue end -- dont hit non-solid stuff

        local hitEntsOwner = hitEnt:GetOwner()
        local hitEntsParent = hitEnt:GetParent()
        if IsValid( hitEntsOwner ) and IsValid( hitEntsParent ) and hitEntsOwner == hitEntsParent then continue end -- just in case

        local vehicle = hitEnt.GetVehicle and hitEnt:GetVehicle() or nil
        if IsValid( vehicle ) then
            if hitAlready[vehicle] then continue end -- dont hit the same vehicle twice
            hitEnt = vehicle -- vehicle protects driver

        end

        local class = hitEnt:GetClass()
        local IsGlass = class == "func_breakable_surf"
        if IsGlass then
            hitEnt:Fire( "Shatter", tr.HitPos )

        else
            local obj = hitEnt:GetPhysicsObject()
            local isSignificant = hitEnt:IsNPC() or hitEnt:IsNextBot() or hitEnt:IsPlayer()
            -- teamkilling is funny but also stupid
            local friendly = isSignificant and hitEnt.isTerminatorHunterChummy == owner.isTerminatorHunterChummy and owner:Disposition( hitEnt ) ~= D_HT

            local dmgMul = strength

            if friendly then
                dmgMul = 0.1
                hitEnt.overrideMiniStuck = true

            -- break props really fast
            elseif not isSignificant then
                if not IsValid( obj ) then
                    dmgMul = 0.05

                else
                    dmgMul = dmgMul + self.PropDamageBonusMul

                end

            elseif hitEnt:Health() <= 0 then
                -- dont hit dead stuff
                dmgMul = 0

            -- break not player stuff fast
            elseif not hitEnt:IsPlayer() then
                dmgMul = dmgMul + self.NPCDamageBonusMul

            end

            if dmgMul == 0 then continue end -- dont waste perf

            if dmgMul >= strength * 0.5 then
                hitSomething = true

            end

            hitAlready[hitEnt] = true

            -- damage dealt this time
            local damageThisTime = totalDamage * dmgMul

            -- march down total damage a bit, dont just do all the damage to everything
            totalDamage = totalDamage - math.max( damageThisTime * 0.1, 5 )

            local dmginfo = DamageInfo()

            local attacker = owner
            if not IsValid( attacker ) then attacker = self end
            dmginfo:SetAttacker( attacker )

            dmginfo:SetInflictor( self )
            dmginfo:SetDamage( damageThisTime )
            dmginfo:SetDamageType( owner.FistDamageType or self.DamageType )
            dmginfo:SetDamagePosition( tr.HitPos )

            local forceMul = owner.FistForceMul or 1

            if isSignificant then -- HIGH FORCE for npc ragdolls
                dmginfo:SetDamageForce( aimVec * 6998 * 3 * forceMul )

            else -- LOW force for props
                dmginfo:SetDamageForce( aimVec * 50 * forceMul )

            end

            SuppressHostEvents( NULL ) -- Let the breakable gibs spawn in multiplayer on client
            hitEnt:TakeDamageInfo( dmginfo )
            SuppressHostEvents( owner )

            if hitEnt:IsPlayer() then
                local punchSize = damageThisTime * self.ViewPunchMul
                hitEnt:ViewPunch( Angle( -punchSize * 0.5, damageThisTime * math.Rand( -0.1, 0.1 ), damageThisTime * math.Rand( -0.05, 0.05 ) ) )

            end

            if owner.PostHitObject then
                owner:PostHitObject( hitEnt, damageThisTime )

            end

            if owner:IsOnFire() then
                hitEnt:Ignite( damageThisTime / 20 )

            end

            if not playedPoundSound and ( damageThisTime > 100 or string.find( class, "prop" ) ) then
                playedPoundSound = true
                local lvl = 75 + damageThisTime * 0.1
                local pitch = math.Clamp( 120 + -( damageThisTime * 0.25 ), 85, 120 )
                hitEnt:EmitSound( self.PoundSound, lvl, pitch, 1, CHAN_STATIC )
                util.ScreenShake( self:GetPos(), damageThisTime * 0.1, 20, 0.15, math.Clamp( damageThisTime * 5, 0, 2000 ) )

            end
            if not playedShoveSound and damageThisTime > 200 then
                playedShoveSound = true
                local lvl = math.Clamp( 80 + damageThisTime * 0.1, 80, 150 )
                local pitch = math.Clamp( 120 + -( damageThisTime * 0.35 ), 85, 120 )
                hitEnt:EmitSound( self.ShoveSound, lvl, pitch, 1, CHAN_STATIC )
                util.ScreenShake( self:GetPos(), damageThisTime * 0.005, 2, 3, math.Clamp( damageThisTime * 5, 0, 2000 ) )

                if owner.Use2 and math.random( 1, 100 ) < 5 then -- really heavy hitters will eventually open USE doors
                    owner:Use2( hitEnt )

                end
            end

            if not isSignificant then
                hitEnt:ForcePlayerDrop()
                local oldHealth = hitEnt:Health()
                local _, entMemoryKey = owner.getMemoryOfObject and owner:getMemoryOfObject( owner:GetTable(), hitEnt )

                timer.Simple( 0.1, function()
                    if not IsValid( self ) then return end
                    -- small things dont take the damage's force when in water????
                    if IsValid( hitEnt ) and hitEnt:GetVelocity():LengthSqr() < 25 ^ 2 and IsValid( obj ) then
                        obj:ApplyForceCenter( aimVec * 9998 )

                    end

                    if owner.memorizeEntAs and ( not IsValid( hitEnt ) or ( oldHealth > 0 and hitEnt:Health() <= 0 ) ) then
                        owner:memorizeEntAs( entMemoryKey, MEMORY_BREAKABLE )

                    end
                end )

                if IsValid( obj ) then
                    local punchForce = aimVec * math.Clamp( obj:GetMass() / 500, 0.25, 1 ) * 100000
                    obj:ApplyForceOffset( punchForce, tr.HitPos )

                end
            end
        end
        self:HandleDoor( hitEnt, strength )

    end

    local pitchShift = owner.term_SoundPitchShift or 0
    if hitSomething then
        self:PlayHitSound( owner, pitchShift )
        util.ScreenShake( owner:GetPos(), 10, 10, 0.1, 400 )
        util.ScreenShake( owner:GetPos(), 1, 10, 0.5, 750 )

    else
        self:PlaySwingSound( owner, pitchShift )

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

    -- TODO investigate holdtype
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