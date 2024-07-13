function ENT:BehaveStart()
    self:SetupCollisionBounds()

    self:SetupTaskList( self.m_TaskList )
    self:SetupTasks()

end

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime

function ENT:BehaveUpdate( interval )
    self.BehaveInterval = interval

    if self.m_Physguned then
        self.loco:SetVelocity( vector_origin )
    end

    self:StuckCheck()

    local disable = self:DisableBehaviour()

    if not disable then
        local crouch = self:ShouldCrouch()
        if crouch ~= self:IsCrouching() and ( crouch or self:CanStandUp() ) then
            self:SwitchCrouch( crouch )

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
            if not self.BehaviourThread then
                self.BehaviourThread = coroutine.create( function( self ) self:BehaviourCoroutine() end )

            end
            local thread = self.BehaviourThread
            if thread then
                local oldTime = SysTime()
                while math.abs( oldTime - SysTime() ) < 0.008 do
                    local noErrors, result = coroutine_resume( thread, self )
                    if noErrors == false then
                        self.BehaviourThread = nil
                        ErrorNoHaltWithStack( result )
                        break
                    elseif result == "wait" then
                        break

                    elseif result == "done" then
                        self.BehaviourThread = nil
                        break

                    end
                end
            end
        end
    end

    self:SetupGesturePosture()
end

function ENT:BehaviourCoroutine()
    -- Calling behaviour with think type
    self:BehaviourThink()

    coroutine_yield()

    -- Calling task callbacks
    self:RunTask( "BehaveUpdate", interval )

    coroutine_yield( "done" )

end