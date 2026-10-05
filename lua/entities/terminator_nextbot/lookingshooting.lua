

function ENT:getBestPos( ent )
    if not IsValid( ent ) then return nil end
    local shootPos = self:GetShootPos()
    local obj = ent:GetPhysicsObject()
    local pos = ent:GetPos()
    if IsValid( obj ) and not obj:IsMotionEnabled() then
        pos = ent:NearestPoint( shootPos )
        -- put the nearest point a bit inside the entity
        pos = ent:WorldToLocal( pos )
        pos = pos * 0.6
        pos = ent:LocalToWorld( pos )

    elseif IsValid( obj ) then
        local center = obj:GetMassCenter()
        if center ~= vec_zero then
            pos = ent:LocalToWorld( center )

        end
    end


    --debugoverlay.Cross( pos, 5, 5 )

    if pos and ent:GetClass() ~= "func_breakable_surf" and terminator_Extras.PosCanSee( shootPos, pos ) then
        return pos

    end

    return pos

end

-- this is a stupid hack
-- fixes bot firing guns slow in multiplayer, without making bot think faster.
-- eg fixes m9k minigun firing at one tenth its actual fire rate
function ENT:CreateShootingTimer( myTbl )
    if myTbl.IsFodder then return end -- fodder npcs dont get this expensive timer
    local timerName = "terminator_fastshootingthink_" .. self:GetCreationID()
    timer.Create( timerName, 0.05, 0, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        if myTbl.terminator_FiringIsAllowed ~= true then return end

        myTbl.WeaponPrimaryAttack( self )

        if math.abs( myTbl.terminator_LastFiringIsAllowed - CurTime() ) > 0.25 then -- stops firing
            myTbl.terminator_FiringIsAllowed = nil

        end
    end )
end

-- DONT touch terminator_FiringIsAllowed and terminator_LastFiringIsAllowed
-- use shootAt to set them, anything else is a super hack
-- use blockShoot to make bot just look at the endPos
function ENT:shootAt( endPos, blockShoot, angTolerance )
    if not endPos then return end
    local myTbl = self:GetTable()
    myTbl.terminator_FiringIsAllowed = nil

    local endPosOffsetted = endPos
    local enemy = myTbl.GetEnemy( self )
    local wep = self:GetActiveWeapon()
    local validEnemy

    local dmgTracker = myTbl.Term_GetDamageTrackerOf( self, myTbl, wep )

    if IsValid( enemy ) then
        validEnemy = true
        if dmgTracker and not dmgTracker.noLeading then
            endPosOffsetted = endPosOffsetted + ( enemy:GetVelocity() * 0.08 )
            endPosOffsetted = endPosOffsetted - ( self:GetVelocity() * 0.08 )

        end
    end
    local attacked = nil
    local out = nil
    local myShoot = myTbl.GetShootPos( self )
    local dir = endPosOffsetted - myShoot

    dir:Normalize()

    myTbl.SetDesiredEyeAngles( self, dir:Angle() )

    angTolerance = angTolerance or 11.25
    if myTbl.IsMeleeWeapon( self ) then
        angTolerance = 60

    elseif dmgTracker and dmgTracker.isBurst then
        angTolerance = 4

    end

    local dot = math.Clamp( myTbl.GetAimVector( self, myTbl ):Dot( dir ), 0, 1 )
    local ang = math.deg( math.acos( dot ) )

    local lastFiringAllowed = myTbl.terminator_LastFiringIsAllowed or 0

    if not blockShoot and lastFiringAllowed < CurTime() then
        myTbl.RunTask( self, "OnMightStartAttacking" )

    end

    if ang <= angTolerance and not blockShoot then

        if dmgTracker then
            myTbl.TryAndUseWeaponRight( self, myTbl, wep, dmgTracker )

        end

        local wepRange = myTbl.GetWeaponRange( self, myTbl )

        local blockAttack = nil
        -- witness me hack for glee
        if validEnemy and enemy.AttackConfirmed then
            if not blockShoot and enemy:Health() > 0 and myTbl.DistToEnemy < wepRange * 1.25 then
                enemy.AttackConfirmed( enemy, self )

            end
            if not enemy.attackConfirmedBlock then
                attacked = true

            else
                blockAttack = true

            end
        end
        -- wep judging, drops weapons that don't do enough damage/aren't compatible with this npc
        if not attacked and not blockAttack and myTbl.DistToEnemy < wepRange * 1.25 then
            -- think is spammed a bit in singleplayer, don't over-judge
            local nextJudge = myTbl.term_NextJudge or 0
            if validEnemy and nextJudge < CurTime() then
                myTbl.term_NextJudge = CurTime() + 0.08
                myTbl.JudgeWeapon( self, myTbl, wep )
                myTbl.JudgeEnemy( self, enemy )

            end
            attacked = true

        end
    end

    if attacked then
        if myTbl.IsFodder then -- no shooting timer for fodder npcs
            myTbl.WeaponPrimaryAttack( self )

        else
            myTbl.terminator_LastFiringIsAllowed = CurTime()
            myTbl.terminator_FiringIsAllowed = true -- tell the ShootingTimer that it's shooting time

        end
    end

    if ang < 1 then
        out = true

    end
    return out, attacked

end

function ENT:isLookingAt( endpos, angTolerance )
    angTolerance = angTolerance or 11.25
    local myTbl = entMeta.GetTable( self )
    local myShoot = myTbl.GetShootPos( self )
    local dir = endpos - myShoot

    dir:Normalize()

    local dot = math.Clamp( myTbl.GetAimVector( self, myTbl ):Dot( dir ), 0, 1 )
    local ang = math.deg( math.acos( dot ) )

    if ang <= angTolerance then
        return true

    end
end

-- easy alias for shootAt, just looks at the endpos
function ENT:justLookAt( endpos )
    self:shootAt( endpos, true )

end