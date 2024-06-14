AddCSLuaFile()

SWEP.Base = "weapon_frag_term"
SWEP.PrintName = "#HL2_Slam"
SWEP.Spawnable = true
SWEP.Author = "straw wagen"
SWEP.Purpose = "Should only be used internally by advanced nextbots!"

SWEP.WorldModel = "models/weapons/w_slam.mdl"
SWEP.Weight = terminator_Extras.GoodWeight

terminator_Extras.SetupAnalogWeight( SWEP )

SWEP.PickupSound = "physics/metal/weapon_impact_soft3.wav"
SWEP.Range = 2000
SWEP.HoldType = "slam"
SWEP.SpawningOffset = 25
SWEP.worksWithoutSightline = true
SWEP.PreOverrideClass = "weapon_slam"

terminator_Extras.SetupAnalogWeight( SWEP )


function SWEP:CanPrimaryAttack()
    if self:GetNextPrimaryFire() > CurTime() then return false end

    local owner = self:GetOwner()
    local holdType = self.HoldType
    if holdType == "slam" and owner.IsSeeEnemy then
        self.HoldType = "melee"
        self:SetHoldType( self.HoldType )
        self:SetNextPrimaryFire( CurTime() + 0.75 )
        return false

    elseif holdType == "melee" and not owner.IsSeeEnemy then
        self.HoldType = "slam"
        self:SetHoldType( self.HoldType )
        self:SetNextPrimaryFire( CurTime() + 0.75 )
        return false

    end

    return true

end

function SWEP:SwingSpawn()
    -- let swing system handle vel
    local satchel = self:ThrowSatchel( 0 )
    satchel.blockReturnAsWeap = true

    return satchel

end

function SWEP:Reload()
end

local whiteNoAlpha = Color( 255, 255, 255, 0 )

SWEP.termPlace_PlacingRange = 85

function SWEP:PrimaryAttack()
    self:SetLastShootTime()

    local owner = self:GetOwner()
    local ownersShoot = owner:GetShootPos()
    local eyeTr = owner:GetEyeTrace()
    local doPlant = eyeTr.Hit and ( eyeTr.HitPos:DistToSqr( ownersShoot ) < self.termPlace_PlacingRange^2 )
    local _, definitiveTr = terminator_Extras.PosCanSeeComplex( ownersShoot, ownersShoot + owner:GetAimVector() * self.termPlace_PlacingRange * 1.25, owner, MASK_SOLID )
    if doPlant and definitiveTr.Hit then
        local plantingAng = definitiveTr.HitNormal:Angle()
        plantingAng.x = plantingAng.x + 90

        local satchel = ents.Create( "npc_tripmine" )
        if not IsValid( satchel ) then return end
        satchel:SetAngles( plantingAng )
        satchel:SetPos( definitiveTr.HitPos + definitiveTr.HitNormal * 3 )

        satchel:SetSaveValue( "m_bIsAttached", true )
        satchel:SetSaveValue( "m_hThrower", owner )
        satchel:SetSaveValue( "m_hOwner", owner ) -- SetOwner but it still trips it 
        timer.Simple( 3, function()
            if not IsValid( satchel ) then return end
            satchel:SetSaveValue( "m_bIsLive", true )

        end )

        satchel:Spawn()

        satchel.usedByTerm = true -- hearing system ignores this
        satchel.terminator_Judger_WepClassToCredit = self:GetClass()
        owner:EmitSound( "Weapon_SLAM.TripMineMode" )

        self:SetColor( whiteNoAlpha )
        SafeRemoveEntityDelayed( self, 0.5 )
        self:SetNextPrimaryFire( CurTime() + 1 )
        return

    elseif IsValid( owner:GetEnemy() ) then
        if not terminator_Extras.PosCanSeeComplex( self:GetOwner():GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end
        self:Swing()

    else
        if not terminator_Extras.PosCanSeeComplex( self:GetOwner():GetShootPos(), self:GetProjectileOffset(), self, MASK_SOLID ) then return end
        self:ThrowSatchel( 400 )
        owner:EmitSound( "Weapon_SLAM.SatchelThrow" )

    end
    SafeRemoveEntityDelayed( self, 0.2 )
end


function SWEP:ThrowStartSound( owner )
    owner:EmitSound( "weapons/slam/throw.wav", 90, 150 )

end

function SWEP:SwingingSound( projectile )
    projectile:EmitSound( "weapons/slam/throw.wav", 90, 80 )

end

local function detonateSatchelsWithId( id )
    for _, satchel in ipairs( ents.FindByClass( "npc_satchel" ) ) do
        if satchel.term_throwerid == id then
            satchel:Fire( "Explode", "", 0.1 )

        end
    end
end

function SWEP:SecondaryAttack()
    local owner = self:GetOwner()
    local ownersId = owner:GetCreationID()
    owner:EmitSound( "Weapon_SLAM.SatchelDetonate" )
    detonateSatchelsWithId( ownersId )
    owner.term_Satchels = nil

end

function SWEP:ThrowSatchel( vel )
    local satchel = ents.Create( "npc_satchel" )
    if not IsValid( satchel ) then return end

    local owner = self:GetOwner()
    satchel:SetPos( self:GetProjectileOffset() )
    satchel:SetSaveValue( "m_bIsLive", true )
    satchel:SetSaveValue( "m_hThrower", owner )

    satchel:Spawn()

    local ownersId = owner:GetCreationID()

    owner.term_Satchels = owner.term_Satchels or {}
    table.insert( owner.term_Satchels, satchel )
    satchel.term_throwerid = ownersId

    local timerId = ownersId .. "_term_managethrownsatchels"
    timer.Remove( timerId )
    timer.Create( timerId, 0.25, 0, function()
        if not IsValid( owner ) then detonateSatchelsWithId( ownersId ) timer.Remove( timerId ) return end
        if owner:Health() <= 0 then detonateSatchelsWithId( ownersId ) timer.Remove( timerId ) return end
        if not owner.term_Satchels then timer.Remove( timerId ) return end

        if not owner.IsSeeEnemy then return end

        local enemy = owner:GetEnemy()
        if not IsValid( enemy ) then return end

        local enemysPos = owner:GetEnemy():GetPos()

        for _, currSatchel in ipairs( owner.term_Satchels ) do
            if IsValid( currSatchel ) and currSatchel:GetPos():DistToSqr( enemysPos ) < 125^2 then
                owner:EmitSound( "Weapon_SLAM.SatchelDetonate" )
                detonateSatchelsWithId( ownersId )
                owner.term_Satchels = nil
                timer.Remove( timerId )
                break

            end
        end
    end )

    if vel <= 0 then return satchel end

    timer.Simple( 0, function()
        if not IsValid( satchel ) then return end
        if not IsValid( satchel:GetPhysicsObject() ) then return end
        satchel:GetPhysicsObject():SetVelocity( owner:GetAimVector() * vel )

    end )

    return satchel

end

SWEP.termPlace_MaxAreaSize = 250

local nookDirections2dDirs = {
    Vector( 1, 0, 0 ),
    Vector( 0.5, 0.5, 0 ),
    Vector( 0, 1, 0 ),
    Vector( -0.5, 0.5, 0 ),
    Vector( -1, 0, 0 ),
    Vector( -0.5, -0.5, 0 ),
    Vector( 0, -1, 0 ),
    Vector( 0.5, -0.5, 0 ),
}

function SWEP:termPlace_ScoringFunc( owner, checkPos )
    local nookScore = terminator_Extras.GetNookScore( checkPos, 100, nookDirectionsScore )
    local score = nookScore
    score = score + math.Rand( -0.2, 0.2 )
    if checkPos:DistToSqr( owner:GetPos() ) < 350^ 2 then
        score = score + -1

    end
    --debugoverlay.Text( checkPos, tostring( score ), 5, false )
    return score

end

function SWEP:termPlace_PlacingFunc( owner )
    local _, hits = terminator_Extras.GetNookScore( owner:GetShootPos(), 500, nookDirections2dDirs )
    local shortestIndex = 1
    for fraction, tr in pairs( hits ) do
        local foundArea = navmesh.GetNavArea( tr.HitPos, 250 )
        if not foundArea then continue end
        if math.max( foundArea:GetSizeX(), foundArea:GetSizeY() ) > self.termPlace_MaxAreaSize then continue end

        -- find shortest tr
        if fraction <= shortestIndex then shortestIndex = fraction end

    end
    if shortestIndex >= 1 then return owner:GetPos() + owner:GetAimVector() * 100 end
    return hits[shortestIndex].HitPos

end