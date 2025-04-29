function ENT:BehaveStart()
    self:SetupCollisionBounds()

    self:SetupTaskList( self.m_TaskList )
    self:SetupTasks()

end

local entMeta = FindMetaTable( "Entity" )

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime
local IsValid = IsValid
local math = math
local pairs = pairs

function ENT:BehaveUpdate( interval )
    local myTbl = entMeta.GetTable( self )
    myTbl.BehaveInterval = interval

    if myTbl.m_Physguned then
        myTbl.loco:SetVelocity( vector_origin )
    end

    local disable = myTbl.DisableBehaviour( self, myTbl )

    if not disable then
        local crouch = myTbl.ShouldCrouch( self, myTbl )
        if crouch ~= myTbl.IsCrouching( self ) and ( not crouch or myTbl.CanStandUp( self, myTbl ) ) then
            myTbl.SwitchCrouch( self, crouch )

        end
    end

    myTbl.SetupSpeed( self )
    myTbl.SetupMotionType( self, myTbl )
    myTbl.ProcessFootsteps( self )
    myTbl.ChildrenCleanupHack( self, myTbl ) -- for some reason bots slowly accumulate themself in their _children table?????
    myTbl.m_FallSpeed = -myTbl.loco:GetVelocity().z

    if not disable then
        myTbl.SetupEyeAngles( self )
        myTbl.UpdatePhysicsObject( self )
        myTbl.HandlePathRemovedWhileOnladder( self )

        local ply = self:GetControlPlayer()
        if IsValid( ply ) then -- not optimizing this
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
                threads.priorityCor = coroutine.create( function( self, myTbl ) myTbl.BehaviourPriorityCoroutine( self, myTbl ) end )

            end
            if not threads.motionCor then
                threads.motionCor = coroutine.create( function( self, myTbl ) myTbl.BehaviourMotionCoroutine( self, myTbl ) end )

            end
        end
    end

    myTbl.SetupGesturePosture( self )

end

-- process the threads every tick if we can
function ENT:Think()
    local myTbl = entMeta.GetTable( self )

    local threads = myTbl.BehaviourThreads
    if not threads then
        entMeta.NextThink( self, CurTime() + 0.02 )
        return true

    end

    local enem = myTbl.GetEnemy( self )
    local thresh = myTbl.CoroutineThresh
    if myTbl.IsFodder and not IsValid( enem ) then
        thresh = thresh / 2

    elseif myTbl.ThreshMulIfDueling then
        local distToEnem = myTbl.DistToEnemy
        local distFullBoost = math.max( myTbl.DuelEnemyDist, 500 )
        local distHalfBoost = math.max( myTbl.DuelEnemyDist * 3, 1500 )
        if distToEnem <= distFullBoost and myTbl.IsPlyNoIndex( enem ) then
            thresh = thresh * myTbl.ThreshMulIfDueling

        elseif distToEnem <= distHalfBoost then
            thresh = thresh * myTbl.ThreshMulIfClose

        end
    end

    local doneSomething
    for index, thread in pairs( threads ) do
        local oldTime = SysTime()

        while SysTime() - oldTime < thresh do
            doneSomething = true
            local noErrors, result = coroutine_resume( thread, self, myTbl )
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
        entMeta.NextThink( self, CurTime() )
        return true

    else
        myTbl.BehaviourThreads = nil

    end
end

-- do enemy handling ( looking around, finding enemies, shooting ) asynced to the movement coroutine
function ENT:BehaviourPriorityCoroutine( myTbl )
    -- do shoot blocking thinking
    myTbl.TermThink( self, myTbl )
    myTbl.BehaviourThink( self, myTbl )

    -- Calling task callbacks
    myTbl.RunTask( self, "BehaveUpdatePriority" )

    coroutine_yield( "done" )

end

-- do motion, anything super computationally expensive on this coroutine
function ENT:BehaviourMotionCoroutine( myTbl )
    myTbl.StuckCheck( self, myTbl ) -- check if we are intersecting stuff
    myTbl.WalkArea( self, myTbl ) -- mark nearby areas as walked, used for searching new unwalked areas

    -- Calling task callbacks
    myTbl.RunTask( self, "BehaveUpdateMotion" )

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