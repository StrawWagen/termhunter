AddCSLuaFile()

if CLIENT then
    killicon.AddFont( "weapon_manhack_term", "HL2MPTypeDeath", "1", Color( 255, 255, 255 ) )
end

-- Base this off the existing frag implementation to reuse aiming, throwing, timing logic
SWEP.Base = "weapon_frag_term"
SWEP.PrintName = "#HL2_Manhack"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Internal: deploy a manhack at low speed"

SWEP.ViewModel = "models/weapons/c_stunstick.mdl"
SWEP.WorldModel = "models/manhack.mdl" -- manhack worldmodel so you can see it when holstered

SWEP.Weight = terminator_Extras.GoodWeight * 2
terminator_Extras.SetupAnalogWeight( SWEP )

-- Soft deploy sound
SWEP.PickupSound = "Grenade.ImpactSoft"

-- Keep same ranges for compatibility with existing AI logic
SWEP.Range = 1800
SWEP.MeleeWeaponDistance = SWEP.Range
SWEP.HoldType = "melee"
SWEP.SpawningOffset = 50
SWEP.worksWithoutSightline = true

-- Prevent crowbar return spawning logic in base chain
SWEP.PreOverrideClass = false
SWEP.MinForceMul = 1

-- Fallback to base's CanPrimaryAttack (in frag) for visibility logic

-- Spawn a manhack instead of grenade
function SWEP:SwingSpawn( spawnPos )
    local manhack = ents.Create( "npc_manhack" )
    if not IsValid( manhack ) then return end
    local thrower = self:GetOwner()
    manhack:SetPos( spawnPos )
    manhack:SetAngles( AngleRand() )
    manhack:SetOwner( thrower )
    timer.Simple( 0.5, function()
        if not IsValid(manhack) then return end
        manhack:SetOwner(nil)
    end )
    manhack:Spawn()
    manhack.blockReturnAsWeap = true
    if thrower.UpdateEnemyMemory then
        -- alert the owner to the location of the manhack's enemies
        local timerName = "terminator_manhack_alert_" .. manhack:GetCreationID()
        timer.Create( timerName, 1, 0, function()
            if not IsValid( manhack ) then
                timer.Remove( timerName )
                return

            end

            if not IsValid( thrower ) then
                timer.Remove( timerName )
                return

            end

            local enemy = manhack:GetEnemy()
            if IsValid( enemy ) and manhack:Visible( enemy ) then
                thrower:UpdateEnemyMemory( enemy, enemy:GetPos() )

            end
        end )
    end
    return manhack
end

-- Gentle deployment force (base frag weapon uses dynamic force calculation)
function SWEP:ThrowForce()
    return 12000
end

-- Use frag base aiming logic (sufficient for lob)

-- Keep throw start sound from base; optional change:
function SWEP:ThrowStartSound( owner )
    owner:EmitSound( "weapons/slam/throw.wav", 85, 170 )
end

function SWEP:SwingingSound( projectile )
    if not IsValid( projectile ) then return end
    projectile:EmitSound( "npc/scanner/scanner_siren1.wav", 80, 100 )
end

-- No grenade damage correction needed for manhack variant

function SWEP:DrawWorldModel()
    terminator_Extras.DrawInHand( self, Vector(0,0,-0), Angle(0,0,180) )
    self:DrawModel()
end