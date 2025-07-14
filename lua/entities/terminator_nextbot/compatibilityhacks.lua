AddCSLuaFile()

-- hacky fixes for comaptibility with other common addons

local entMeta = FindMetaTable( "Entity" )

-- had some weapon base problems that made this necessary iirc
function ENT:Classify()
    return CLASS_NONE

end

-- VJ BASE, connects with weapons.lua

if SERVER then
    ENT.WeaponSpread = 0.05

    function ENT:VJ_GetDifficultyValue( int )
        return int
    end

    function ENT:fakeVjBaseWeaponFiring( wep ) -- copied code from vj base github, hope it doesnt change in future and break
        timer.Simple( wep.NPC_TimeUntilFire, function()
            if IsValid( wep ) and IsValid( self ) and IsValid( self:GetOwner() ) and CurTime() > wep.NPC_NextPrimaryFireT then
                wep:PrimaryAttack()
                if wep.NPC_NextPrimaryFire == false then return end -- Support for animation events
                wep.NPC_NextPrimaryFireT = CurTime() + wep.NPC_NextPrimaryFire
                for _, tv in ipairs( wep.NPC_TimeUntilFireExtraTimers ) do
                    timer.Simple( tv, function()
                        if not IsValid( wep ) or not IsValid( self ) or wep:NPCAbleToShoot() ~= true then return end
                        wep:PrimaryAttack()

                    end )
                end
            end
        end )
    end

    function ENT:CheckRelationship( otherEnt )
        return self:GetRelationship( otherEnt )

    end

    -- zbase
    function ENT:ZBaseUpdateRelationships()
        return

    end

end

--see SetupEntityRelationship in enemyoverrides.lua for more vj base stuff

-- drg base
-- drg assumes that all nextbots are drg nextbots, stupid

if SERVER then
    function ENT:DrG_SetRelationship( ent, _ )
        self:Term_SetEntityRelationship( ent, D_HT )

    end

end

-- approximate player/npc funcs!

function ENT:GetTarget()
    return self:GetEnemy()

end

function ENT:DrawViewModel()
end

function ENT:SetEyeAngles()
end

function ENT:GetViewModel()
    if not IsValid( self ) or CLIENT then return NULL end
    return self:GetWeapon() or NULL

end

function ENT:Alive()
    return entMeta.Health( self ) > 0

end

function ENT:LagCompensation()
end

function ENT:UniqueID()
    return entMeta.GetCreationID( self )

end

function ENT:GetViewPunchAngles()
    return angle_zero

end

function ENT:KeyPressed( KEY )
    if not SERVER then return end

    local localizedVel = self.loco:GetVelocity()
    localizedVel:Rotate( -self:GetAngles() )

    if KEY == IN_ATTACK or KEY == IN_ATTACK2 or KEY == IN_BULLRUSH then
        return self.terminator_FiringIsAllowed

    elseif KEY == IN_JUMP then
        return not self:IsOnGround()

    elseif KEY == IN_DUCK then
        return self:ShouldCrouch()

    elseif KEY == IN_FORWARD then
        return localizedVel.x > 10

    elseif KEY == IN_BACK then
        return localizedVel.x < -10

    elseif KEY == IN_MOVELEFT then
        return localizedVel.y > 10

    elseif KEY == IN_MOVERIGHT then
        return localizedVel.y < 10

    elseif KEY == IN_RELOAD then
        local wep = self:GetWeapon()
        if wep:GetMaxClip1() > 0 then
            if wep:Clip1() <= 0 then
                return true

            end
        else
            return math.random( 1, 100 ) < 25

        end

    elseif KEY == IN_SPEED then
        return self:canDoRun() and localizedVel:LengthSqr() >= ( self.MoveSpeed + 50 ) ^ 2

    elseif KEY == IN_WALK then
        return self:shouldDoWalk()

    elseif KEY == IN_USE then
        return

    end
end

function ENT:KeyDown( KEY )
    if not SERVER then return end
    return self:KeyPressed( KEY )

end

local defaultColor = Vector( 1, 1, 1 )

function ENT:GetPlayerColor()
    return self.PlayerColorVec or defaultColor

end

function ENT:GetFOV()
    return self.Term_FOV

end

function ENT:SetFOV()
end

function ENT:SetAmmo()
end
function ENT:GetAmmoCount()
    return -1

end

function ENT:Armor()
    return 0

end
function ENT:GetMaxArmor()
    return 0

end

local cmd

local function createFakeCMD()
    cmd = {}
    cmd.GetMouseX = function() return 0 end
    cmd.GetMouseY = function() return 0 end
    cmd.GetButtons = function() return 0 end
    cmd.GetForwardMove = function() return 0 end
    cmd.GetSideMove = function() return 0 end
    cmd.GetUpMove = function() return 0 end
    cmd.GetViewAngles = function() return angle_zero end
    cmd.CommandNumber = function() return math.Round( CurTime() ) end
    cmd.TickCount = function() return engine.TickCount() end

end

function ENT:GetCurrentCommand()
    if not cmd then
        createFakeCMD()
    end
    return cmd

end

if SERVER then

    include( "weaponhacks.lua" )

    local medkitModels = {
        ["models/weapons/w_medkit.mdl"] = true,
        ["models/items/healthkit.mdl"] = true,

    }
    local medkitOffset = Angle( 0,0,-90 )
    hook.Add( "terminator_holstering_overrideangles", "fixthe_god_damn_MEDKITS!", function( model )
        if not medkitModels[model] then return end
        return medkitOffset

    end )

    function ENT:SendLua()
        return

    end

    function ENT:GetViewEntity()
        return self

    end

    function ENT:DoAnimationEvent()
    end

    function ENT:GetWeapons()
        local weps = {}
        local wep = self:GetWeapon()
        if IsValid( wep ) then
            table.insert( weps, wep )

        end
        local holsteredWeps = self:GetHolsteredWeapons()
        for _, holsteredWep in ipairs( holsteredWeps ) do
            if IsValid( holsteredWep ) then
                table.insert( weps, holsteredWep )

            end
        end
        return weps

    end

    function ENT:SelectWeapon()
    end

    function ENT:PrintMessage()
    end

    function ENT:SelectWeapon( wep )
        self:Give( wep )

    end

    function ENT:StripWeapon()
        if not IsValid( self:GetWeapon() ) then return end
        SafeRemoveEntityDelayed( self:DropWeapon( true ), 0 )

    end

    function ENT:GetEyeTrace()
        local start = self:GetShootPos()
        local endOffs = self:GetEyeAngles():Forward() * 32768
        local _, trResult = terminator_Extras.PosCanSeeComplex( start, start + endOffs, self )
        return trResult

    end

    function ENT:SwitchToDefaultWeapon()
        if not self.TERM_FISTS then return end
        self:DoFists()

    end

    function ENT:SetArmor()
    end

    function ENT:SetMaxArmor()
    end

    function ENT:GetNavType()
        return -1 --NAV_NONE

    end

    function ENT:GetIdealMoveSpeed()
        return self.loco:GetDesiredSpeed()

    end

    function ENT:SetLastPosition()
    end

    function ENT:SetSchedule()
    end

    function ENT:ClearSchedule()
    end

    function ENT:GetHeadDirection()
        local aimVec = self:GetAimVector()
        aimVec.z = 0
        aimVec:Normalize()
        return aimVec

    end

    function ENT:StopMoving()
    end

    function ENT:GetUserGroup()
        return "user"

    end

    function ENT:Crouching()
        return self:IsCrouching()

    end

    function ENT:M9K_GetShootPos()
        return self:GetShootPos()

    end

    function ENT:GetMoveVelocity()
        return self.loco:GetVelocity()

    end

    function ENT:HasEnemyMemory( potEnemy )
        return self.m_EnemiesMemory[potEnemy] ~= nil

    end

    function ENT:GetMovementActivity()
        return self:GetMotionType()

    end

else -- CLIENT
    function ENT:ShouldDrawLocalPlayer() -- for when you dont want to double-draw stuff
        return true

    end

end