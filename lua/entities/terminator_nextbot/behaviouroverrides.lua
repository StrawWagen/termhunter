function ENT:BehaveStart()
    self:SetupCollisionBounds()

    self:SetupTaskList( self.m_TaskList )
    self:SetupTasks()

end

local math_abs = math.abs
local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime

function ENT:BehaveUpdate( interval )
    local myTbl = self:GetTable()
    myTbl.BehaveInterval = interval

    if myTbl.m_Physguned then
        myTbl.loco:SetVelocity( vector_origin )
    end

    local disable = myTbl.DisableBehaviour( self )

    if not disable then
        local crouch = myTbl.ShouldCrouch( self )
        if crouch ~= myTbl.IsCrouching( self ) and ( crouch or myTbl.CanStandUp( self ) ) then
            myTbl.SwitchCrouch( self, crouch )

        end
    end

    self:SetupSpeed()
    self:SetupMotionType()
    self:ProcessFootsteps()
    self.m_FallSpeed = -self.loco:GetVelocity().z

    if not disable then
        self:SetupEyeAngles()
        self:UpdatePhysicsObject()
        self:ForgetOldEnemies()

        local ply = self:GetControlPlayer()
        if IsValid( ply ) then
            -- Sending current weapon clips data

            if self:HasWeapon() then
                local wep = self:GetActiveWeapon()

                self:SetWeaponClip1( wep:Clip1() )
                self:SetWeaponClip2( wep:Clip2() )
                self:SetWeaponMaxClip1( wep:GetMaxClip1() )
                self:SetWeaponMaxClip2( wep:GetMaxClip2() )

            end

            -- Calling behavior think for player control
            self:BehaviourPlayerControlThink( ply )

            -- Calling task callbacks
            self:RunTask( "PlayerControlUpdate", interval, ply )

            self.m_ControlPlayerOldButtons = self.m_ControlPlayerButtons
        else
            -- Calling behaviour with coroutine type
            local threads = self.BehaviourThreads
            if not threads then
                threads = {}
                self.BehaviourThreads = threads

            end

            if not threads.priorityCor then
                threads.priorityCor = coroutine.create( function( self ) self:BehaviourPriorityCoroutine() end )

            end
            if not threads.motionCor then
                threads.motionCor = coroutine.create( function( self ) self:BehaviourMotionCoroutine() end )

            end

            local thresh = self.CoroutineThresh
            if self.IsFodder and not IsValid( self:GetEnemy() ) then
                thresh = thresh / 2

            end

            for index, thread in pairs( threads ) do
                local oldTime = SysTime()

                while math_abs( oldTime - SysTime() ) < thresh do
                    local noErrors, result = coroutine_resume( thread, self )
                    if noErrors == false then
                        threads[index] = nil
                        ErrorNoHaltWithStack( result )
                        break
                    elseif result == "wait" then
                        break

                    elseif result == "done" then
                        threads[index] = nil
                        break

                    end
                end
            end
        end
    end

    self:SetupGesturePosture()
end

-- do enemy handling ( looking around, finding enemies, shooting ) off the coroutine
function ENT:BehaviourPriorityCoroutine()
    -- do shoot blocking thinking
    self:BehaviourThink()

    self:RunTask( "BehaveUpdatePriority" )

    coroutine_yield( "done" )

end

-- do motion, anything super computationally expensive on the coroutine
function ENT:BehaviourMotionCoroutine()
    self:StuckCheck()

    -- Calling task callbacks
    self:RunTask( "BehaveUpdateMotion" )

    coroutine_yield( "done" )

end