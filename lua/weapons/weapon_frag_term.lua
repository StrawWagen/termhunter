AddCSLuaFile()

if CLIENT then
    killicon.AddFont( "weapon_frag_term", "HL2MPTypeDeath", "1", Color( 255, 80, 0 ) )
end

SWEP.Base = "weapon_crowbar_term"
SWEP.PrintName = "#HL2_Frag"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Should only be used internally by term nextbots!"

SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/weapons/w_stunbaton.mdl"
SWEP.Weight = terminator_Extras.GoodWeight + -2

terminator_Extras.SetupAnalogWeight( SWEP )

SWEP.PickupSound = "Grenade.ImpactSoft"
SWEP.Range = 1800
SWEP.MeleeWeaponDistance = SWEP.Range
SWEP.HoldType = "melee"
SWEP.SpawningOffset = 50
SWEP.worksWithoutSightline = true
SWEP.PreOverrideClass = "weapon_frag"
SWEP.MinForceMul = 1

function SWEP:CanPrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return false end
    if IsValid( self:GetOwner() ) and self:GetOwner():IsControlledByPlayer() then return true end
    if not terminator_Extras.PosCanSeeComplex( self:GetOwner():GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end

    return true

end

function SWEP:SwingSpawn( spawnPos )
    local new = ents.Create( "npc_grenade_frag" )
    new:Fire( "SetTimer", 5 )
    new:SetAngles( AngleRand() )
    new:SetPos( spawnPos )
    new:SetOwner( self:GetOwner() )
    new:Spawn()
    new.isTerminatorHunterGrenade = true
    new.blockReturnAsWeap = true

    return new

end

function SWEP:ThrowForce()
    local owner = self:GetOwner()
    local enemy = owner:GetEnemy()
    if not IsValid( enemy ) then return 15000 end
    local myShootPos = owner:GetShootPos()
    local dist = myShootPos:Distance( owner:EntShootPos( enemy ) )
    local force = dist * 6
    force = math.Clamp( force, 1000, 25000 )
    --print( dist, force, "a" )
    return force

end

function SWEP:terminatorAimingFunc()
    local owner = self:GetOwner()
    local enemy = owner:GetEnemy()
    local myShootPos = owner:GetShootPos()
    local enemShootPos = owner:EntShootPos( enemy )

    -- sanity check
    local weCanJustSeeThem, weCanJustSeeThemResult = terminator_Extras.PosCanSee( myShootPos, enemShootPos )
    if weCanJustSeeThem then
        return enemy:GetPos() -- aim for the feet

    end

    if weCanJustSeeThemResult.HitPos:DistToSqr( enemShootPos ) > 1400^2 then
        owner:ClearEnemyMemory( enemy )
        return

    end

    local nextReturn = self.nextTerminatorAimingFuncResultCache or 0
    local cached = self.cachedTerminatorAimingFuncResult

    if ( nextReturn > CurTime() ) and cached then return cached end

    self.nextTerminatorAimingFuncResultCache = CurTime() + 0.15

    local dir = terminator_Extras.dirToPos( myShootPos, enemShootPos )
    local dist = owner.DistToEnemy
    local results = {}

    local max = 50

    for ourCount = 1, max do
        local randMult = ourCount / ( max * 2 )
        local aimdir = dir + ( VectorRand() * randMult )
        aimdir:Normalize()

        local pos = myShootPos + aimdir * dist
        local _, trace = owner:ClearOrBreakable( myShootPos, pos )
        local hitPos = trace.HitPos
        --debugoverlay.Line( myShootPos, hitPos, 0.5, color_white, true )

        local score = hitPos:DistToSqr( enemShootPos )

        if not terminator_Extras.PosCanSee( hitPos, enemShootPos ) then continue end
        if score < 20^2 then return enemShootPos end

        results[score] = hitPos

    end

    local keys = table.GetKeys( results )
    local smallestKey = math.huge
    for _, key in ipairs( keys ) do
        smallestKey = math.min( key, smallestKey )

    end

    local result = results[ smallestKey ]
    self.cachedTerminatorAimingFuncResult = result

    return result

end

function SWEP:ThrowStartSound( owner )
    owner:EmitSound( "weapons/slam/throw.wav", 90, 150 )

end

function SWEP:SwingingSound( projectile )
    projectile:EmitSound( "weapons/slam/throw.wav", 90, 80 )
    projectile:EmitSound( "weapons/grenade/tick1.wav", 70, 100 )

end

hook.Add( "EntityTakeDamage", "STRAW_terminatorHunter_grenadeCorrectTheAttacker", function( target, damage )
    local inflic = damage:GetInflictor()
    if not IsValid( inflic ) then return end
    if not inflic.isTerminatorHunterGrenade then return end
    if damage:GetDamageType() == DMG_BLAST then return end
    for _ = 1, 4 do
        target:EmitSound( "npc/antlion/shell_impact" .. math.random( 1, 4 ) .. ".wav", 90, math.random( 40, 80 ), 1, CHAN_STATIC )
    end
    if not IsValid( inflic:GetOwner() ) then return end
    damage:SetAttacker( inflic:GetOwner() )
    damage:ScaleDamage( 1.25 )
    damage:SetDamage( math.Clamp( damage:GetDamage(), 0, 200 ) )

    inflic:GetPhysicsObject():SetVelocity( vector_origin )

    inflic.isTerminatorHunterGrenade = nil

end )
