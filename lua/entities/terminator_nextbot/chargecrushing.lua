
local entMeta = FindMetaTable( "Entity" )

-- running into anything much shorter or lighter hurts it, see CanChargeCrush
ENT.ChargeCrushes = nil
ENT.ChargeCrushDmgPerSpeed = nil -- default of 0.1, 1000 speed does 100 damage
ENT.ChargeCrushDmgMinSpeed = nil -- nil uses MoveSpeed
ENT.ChargeCrushSound = nil -- plays on every crush, nil uses the fists' flesh hit

-- A bit shorter than us, and under half our mass.
function ENT:CanChargeCrush( myTbl, ent, myHeight )
    if ent:OBBMaxs().z - ent:OBBMins().z > myHeight * 0.9 then return false end

    local obj = ent:GetPhysicsObject()
    return IsValid( obj ) and obj:GetMass() < myTbl.MyPhysicsMass * 0.5

end

local chargeCrushInterval = 0.1
local chargeCrushRehitTime = 0.15
local chargeCrushForceMul = 100
local chargeCrushMiddleFrac = 0.25 -- of our half width, anything this close to center gets trampled forward

local chargeSlamSpeedDrop = 0.4 -- under this fraction of last check's speed, we stopped dead
local chargeSlamReach = 16
local chargeSlamCooldown = 1

local hitSound = Sound( "Flesh.ImpactHard" )
local poundSound = Sound( "npc/zombie/zombie_pound_door.wav" )
local shoveSound = Sound( "npc/antlion_guard/shove1.wav" )

local function chargeSlam( self, myTbl, dir, speed )
    local cur = CurTime()
    if ( myTbl.term_NextChargeSlam or 0 ) > cur then return end

    local scale = entMeta.GetModelScale( self )
    local bounds = myTbl.CollisionBounds
    local mins = bounds[1] * scale
    local maxs = bounds[2] * scale
    mins.z = mins.z + myTbl.loco:GetStepHeight()
    local myPos = entMeta.GetPos( self )

    local tr = util.TraceHull( {
        start = myPos,
        endpos = myPos + dir * chargeSlamReach,
        mins = mins,
        maxs = maxs,
        mask = self:GetSolidMask(),
        collisiongroup = entMeta.GetCollisionGroup( self ),
        filter = self,
    } )
    if not tr.Hit then return end -- nothing there, we just braked

    -- slowed down plowing through something we crushed, that's not a slam
    local crushedUntil = myTbl.term_ChargeCrushedUntil
    if crushedUntil and ( crushedUntil[tr.Entity] or 0 ) > cur then return end

    myTbl.term_NextChargeSlam = cur + chargeSlamCooldown

    local lvl = math.Clamp( 75 + speed * 0.02, 75, 100 )
    local pitchShift = terminator_Extras.asNumber( self, myTbl, myTbl.term_SoundPitchShift )

    local surface = util.GetSurfaceData( tr.SurfaceProps or 0 )
    local impactSound = surface and surface.impactHardSound
    if impactSound and impactSound ~= "" then
        self:EmitSound( impactSound, lvl, 90 + pitchShift, 1, CHAN_STATIC )

    end
    self:EmitSound( "physics/body/body_medium_impact_hard" .. math.random( 1, 6 ) .. ".wav", lvl, math.random( 70, 80 ) + pitchShift, 1, CHAN_STATIC )
    self:EmitSound( poundSound, lvl, math.random( 85, 95 ) + pitchShift, 1, CHAN_STATIC )
    util.ScreenShake( myPos, speed * 0.01, 20, 0.3, math.Clamp( speed * 2, 500, 2000 ) )

end

-- ENT.ChargeCrushes, anything we run into that CanChargeCrush takes DMG_CRUSH, allies too.
-- Damage is our speed * ChargeCrushDmgPerSpeed, nothing below ChargeCrushDmgMinSpeed, nothing while crouched.
-- Stopping dead against something while charging slams into it.
function ENT:ChargeCrushThink( myTbl )
    if not myTbl.ChargeCrushes then return end

    local cur = CurTime()
    if ( myTbl.term_NextChargeCrush or 0 ) > cur then return end
    myTbl.term_NextChargeCrush = cur + chargeCrushInterval

    if myTbl.IsCrouching( self ) then
        myTbl.term_ChargeCrushLastSpeed = 0
        return

    end

    local vel = myTbl.loco:GetVelocity()
    vel.z = 0
    local speed = vel:Length()
    local minSpeed = myTbl.ChargeCrushDmgMinSpeed or myTbl.MoveSpeed

    -- LastDir is only written when we're over minSpeed, so it's fresh whenever lastSpeed is too
    local lastSpeed = myTbl.term_ChargeCrushLastSpeed or 0
    myTbl.term_ChargeCrushLastSpeed = speed
    if lastSpeed >= minSpeed and speed < lastSpeed * chargeSlamSpeedDrop then
        chargeSlam( self, myTbl, myTbl.term_ChargeCrushLastDir, lastSpeed )

    end

    if speed < minSpeed then return end

    -- the hull CanStandAtPos traces, the OBB is smaller on scaled bots
    local scale = entMeta.GetModelScale( self )
    local bounds = myTbl.CollisionBounds
    local mins = bounds[1] * scale
    local maxs = bounds[2] * scale
    local myHeight = maxs.z - mins.z
    local dir = vel / speed
    myTbl.term_ChargeCrushLastDir = dir
    local right = Vector( dir.y, -dir.x, 0 )
    local middleWidth = maxs.x * chargeCrushMiddleFrac
    local myPos = entMeta.GetPos( self )
    local reach = myPos + vel * chargeCrushInterval -- as far as we'll get before the next check

    local crushedUntil = myTbl.term_ChargeCrushedUntil
    if not crushedUntil then
        -- weak keys, crushed things that get removed don't stay in here forever
        crushedUntil = setmetatable( {}, { __mode = "k" } )
        myTbl.term_ChargeCrushedUntil = crushedUntil

    end

    local myCenter = entMeta.WorldSpaceCenter( self )
    local wallCheck = { start = myCenter, mask = MASK_SOLID_BRUSHONLY }

    -- the engine's own collision rules, groups and ShouldCollide, only ever hitting the one we're checking
    local candidate
    local blockMins = Vector( mins )
    blockMins.z = blockMins.z + myTbl.loco:GetStepHeight() -- we'd step over it, it doesn't block us
    local blockCheck = {
        start = myPos,
        endpos = reach,
        mins = blockMins,
        maxs = maxs,
        mask = self:GetSolidMask(),
        collisiongroup = entMeta.GetCollisionGroup( self ),
        ignoreworld = true,
        filter = function( ent ) return ent == candidate end,
    }

    local perSpeed = myTbl.ChargeCrushDmgPerSpeed or 0.1

    local dmgAmount = speed * perSpeed
    local hitAny
    local hitProp
    -- FindAlongRay ignores the world, so this sees through walls until the wallCheck below
    for _, ent in ipairs( ents.FindAlongRay( myPos, reach, mins, maxs ) ) do
        if ent == self then continue end
        if ( crushedUntil[ent] or 0 ) > cur then continue end
        if not ent:IsSolid() then continue end
        if IsValid( ent:GetParent() ) then continue end -- held things, our own weapon
        if not myTbl.CanChargeCrush( self, myTbl, ent, myHeight ) then continue end

        candidate = ent
        if util.TraceHull( blockCheck ).Entity ~= ent then continue end

        wallCheck.endpos = ent:WorldSpaceCenter()
        if util.TraceLine( wallCheck ).Hit then continue end

        crushedUntil[ent] = cur + chargeCrushRehitTime
        hitAny = true
        if not ( ent:IsNPC() or ent:IsNextBot() or ent:IsPlayer() ) then
            hitProp = true

        end

        -- shove it off whichever side of our path it's on, dead ahead gets trampled forward
        local entCenter = ent:WorldSpaceCenter()
        local forceDir = dir
        local side = ( entCenter - myPos ):Dot( right )
        if side > middleWidth then
            forceDir = right

        elseif side < -middleWidth then
            forceDir = -right

        end

        local dmg = DamageInfo()
        dmg:SetAttacker( self )
        dmg:SetInflictor( self )
        dmg:SetDamageType( DMG_CRUSH )
        dmg:SetDamage( dmgAmount )
        dmg:SetDamageForce( forceDir * dmgAmount * chargeCrushForceMul )
        dmg:SetDamagePosition( entCenter )

        ent.term_TakingChargeCrush = true -- see PostTookDamage, skips FriendlyFireMul
        ent:TakeDamageInfo( dmg )
        if IsValid( ent ) then
            ent.term_TakingChargeCrush = nil

        end
    end

    if not hitAny then return end

    -- once per check, not per thing, or plowing through a crowd stacks up
    local pitchShift = terminator_Extras.asNumber( self, myTbl, myTbl.term_SoundPitchShift )
    local crushSound = myTbl.ChargeCrushSound
    if crushSound then
        self:EmitSound( crushSound, 80, 100 + pitchShift, 1, CHAN_STATIC )

    else
        self:EmitSound( hitSound, 75, 100 + pitchShift )
        self:EmitSound( "physics/flesh/flesh_strider_impact_bullet1.wav", 80, math.random( 130, 160 ) + pitchShift, 1, CHAN_STATIC )

    end

    if hitProp or dmgAmount > 100 then
        local lvl = 75 + dmgAmount * 0.1
        local pitch = math.Clamp( 120 + -( dmgAmount * 0.25 ), 85, 120 )
        self:EmitSound( poundSound, lvl, pitch, 1, CHAN_STATIC )

    end
    if dmgAmount > 200 then
        local lvl = math.Clamp( 80 + dmgAmount * 0.1, 80, 150 )
        local pitch = math.Clamp( 120 + -( dmgAmount * 0.35 ), 85, 120 )
        self:EmitSound( shoveSound, lvl, pitch, 1, CHAN_STATIC )

    end
    util.ScreenShake( myPos, dmgAmount * 0.1, 20, 0.15, math.Clamp( dmgAmount * 5, 0, 2000 ) )

end