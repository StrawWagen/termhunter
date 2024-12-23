function ENT:BehaveStart()
    self:SetupCollisionBounds()

    self:SetupTaskList( self.m_TaskList )
    self:SetupTasks()

end

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
        if crouch ~= myTbl.IsCrouching( self ) and ( not crouch or myTbl.CanStandUp( self ) ) then
            myTbl.SwitchCrouch( self, crouch )

        end
    end

    self:SetupSpeed()
    self:SetupMotionType()
    self:ProcessFootsteps()
    self:ChildrenCleanupHack( myTbl ) -- for some reason bots slowly accumulate themself in their _children table?????
    myTbl.m_FallSpeed = -myTbl.loco:GetVelocity().z

    if not disable then
        self:SetupEyeAngles()
        self:UpdatePhysicsObject()
        self:ForgetOldEnemies()
        self:HandlePathRemovedWhileOnladder()

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

            myTbl.m_ControlPlayerOldButtons = myTbl.m_ControlPlayerButtons
        else
            -- Calling behaviour with coroutine type
            local threads = myTbl.BehaviourThreads
            if not threads then
                threads = {}
                myTbl.BehaviourThreads = threads

            end

            if not threads.priorityCor then
                threads.priorityCor = coroutine.create( function( self ) self:BehaviourPriorityCoroutine() end )

            end
            if not threads.motionCor then
                threads.motionCor = coroutine.create( function( self ) self:BehaviourMotionCoroutine() end )

            end
        end
    end

    self:SetupGesturePosture()

end

-- process the threads every tick if we can
function ENT:Think()
    self:TermThink()
    local threads = self.BehaviourThreads
    if not threads then return end

    local thresh = self.CoroutineThresh
    if self.IsFodder and not IsValid( self:GetEnemy() ) then
        thresh = thresh / 2

    end

    local doneSomething
    for index, thread in pairs( threads ) do
        local oldTime = SysTime()

        while SysTime() - oldTime < thresh do
            doneSomething = true
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
    if doneSomething then
        self:NextThink( CurTime() )
        return true

    end
end

-- do enemy handling ( looking around, finding enemies, shooting ) asynced to the movement coroutine
function ENT:BehaviourPriorityCoroutine()
    -- do shoot blocking thinking
    self:BehaviourThink()

    -- Calling task callbacks
    self:RunTask( "BehaveUpdatePriority" )

    coroutine_yield( "done" )

end

-- do motion, anything super computationally expensive on this coroutine
function ENT:BehaviourMotionCoroutine()
    self:StuckCheck()
    self:walkArea()

    -- Calling task callbacks
    self:RunTask( "BehaveUpdateMotion" )

    coroutine_yield( "done" )

end

-- wtf is this bug?????
function ENT:ChildrenCleanupHack( myTbl )
    local nextCleanup = myTbl.term_NextChildrenCleanup or 0
    if nextCleanup > CurTime() then return end
    myTbl.term_NextChildrenCleanup = CurTime() + 5

    local _children = myTbl._children
    if not _children then return end
    -- there were 87544!!!! copies of itself in _children when i left it spawned for 12+ minutes?!?!?!
    -- one added every tick!
    -- no wonder it was lagging so much....
    -- SetParent is used 6 times in this repo and it's all related to weapons!
    -- if you have any insight into this bug, please let me know.

    local newTbl = {}

    for _, child in pairs( _children ) do
        if child ~= self then
            newTbl[#newTbl + 1] = child

        end
    end

    myTbl._children = newTbl

end