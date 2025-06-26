function ENT:BehaveStart()
    self:SetupCollisionBounds()

end

local entMeta = FindMetaTable( "Entity" )

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime
local IsValid = IsValid
local math = math
local pairs = pairs
local CurTime = CurTime

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

local costThisTick = 0
local lastTick = CurTime()
local probablyLagging = 60 -- shared path yield budget every bot gets. mitigates freezes from multiple bots pathing at once.
local budgetEveryoneGets = 1 -- but we let every bot get at least this many patch yields per think, otherwise they stand still forever.
local budgetAddIfNear = 2 -- if bot near enemy, gets this many more path yields 
local budetAddIfNextTo = 5 -- next to, this many more
local nearDist = 3000
local nextToDist = 550
if game.IsDedicated() then
    budgetEveryoneGets = 2

end

-- process the threads every tick if we can
function ENT:Think()

    local cur = CurTime()

    -- why go through so much effort properly waterfall down this table?
    -- BECAUSE ~10X PERF GAINS!
    -- always pass this beautiful table, else reckon the fps-draining scourge of the _index call....
    local myTbl = entMeta.GetTable( self )

    local threads = myTbl.BehaviourThreads
    if not threads then
        entMeta.NextThink( self, cur + 0.02 )
        return true

    end

    if lastTick ~= cur then
        costThisTick = 0
        lastTick = cur

    end

    local dueling
    local distToEnem = myTbl.DistToEnemy

    local enem = myTbl.GetEnemy( self )
    local thresh = myTbl.CoroutineThresh
    if myTbl.IsFodder and not IsValid( enem ) then
        thresh = thresh / 2

    elseif myTbl.ThreshMulIfDueling then
        local distFullBoost = math.max( myTbl.DuelEnemyDist, 500 )
        local distHalfBoost = math.max( myTbl.DuelEnemyDist * 3, 1500 )
        if distToEnem <= distFullBoost and myTbl.IsPlyNoIndex( enem ) then
            thresh = thresh * myTbl.ThreshMulIfDueling
            dueling = true

        elseif distToEnem <= distHalfBoost then
            thresh = thresh * myTbl.ThreshMulIfClose

        end
    end

    local doneSomething
    for index, thread in pairs( threads ) do
        local oldTime = SysTime()
        local myCostThisTick = 0

        while SysTime() - oldTime < thresh do
            doneSomething = true
            local noErrors, result = coroutine_resume( thread, self, myTbl )
            if noErrors == false then
                threads[index] = nil
                local stack = debug.traceback( thread )
                ErrorNoHalt( "TERM ERROR: " .. tostring( self ) .. "\n", result .. "\n", stack )
                break

            elseif result == "wait" then
                break

            elseif result == "pathing" then
                local budgetIGet = budgetEveryoneGets
                if distToEnem < nextToDist then
                    budgetIGet = budgetIGet + budetAddIfNextTo

                elseif distToEnem < nearDist then
                    budgetIGet = budgetIGet + budgetAddIfNear

                end
                if not dueling and myCostThisTick >= budgetIGet and costThisTick > probablyLagging then -- hack to stop groups of bots from nuking session perf
                    break

                end
                myCostThisTick = myCostThisTick + 1
                costThisTick = costThisTick + 1

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
