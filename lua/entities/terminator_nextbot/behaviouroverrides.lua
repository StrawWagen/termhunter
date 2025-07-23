function ENT:BehaveStart()
    self:SetupCollisionBounds()

end

local entMeta = FindMetaTable( "Entity" )
local locoMeta = FindMetaTable( "CLuaLocomotion" )
local pathMeta = FindMetaTable( "PathFollower" )

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime
local IsValid = IsValid
local math = math
local pairs = pairs
local CurTime = CurTime

local pathUpdateIntervalFodder = 0.1

function ENT:DemandPathUpdates( myTbl )
    myTbl.m_PathUpdatesDemanded = 2 -- demand path updates for 2 movement coroutine completions

end

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
    myTbl.ProcessFootsteps( self, myTbl )
    myTbl.m_FallSpeed = -myTbl.loco:GetVelocity().z

    if not disable then
        myTbl.SetupEyeAngles( self, myTbl )
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
                threads.priorityCor = {
                    cor = coroutine.create( function( self, myTbl ) myTbl.BehaviourPriorityCoroutine( self, myTbl ) end ),

                }
            end
            if not threads.motionCor then
                threads.motionCor = {
                    cor = coroutine.create( function( self, myTbl ) myTbl.BehaviourMotionCoroutine( self, myTbl ) end ),
                    onDone = function( self, myTbl )
                        local demanded = myTbl.m_PathUpdatesDemanded
                        if demanded <= 0 then return end

                        myTbl.m_PathUpdatesDemanded = demanded - 1

                    end,
                    whenBusy = function( self, myTbl, lastOne ) -- horrible, terrible hacks to fix equally horrible terrible stuttering when low CoroutineThresh bots are pathing
                        local demanded = myTbl.m_PathUpdatesDemanded
                        if demanded <= 0 then return end

                        if myTbl.IsFodder then -- ratelimit fodder path updates
                            local nextUpdate = myTbl.m_NextPathUpdate or 0
                            local cur = CurTime()
                            if nextUpdate > cur then return end

                            myTbl.m_NextPathUpdate = cur + pathUpdateIntervalFodder

                        end

                        local path = myTbl.GetPath( self )
                        if not path or not pathMeta.IsValid( path ) then return end

                        local loco = myTbl.loco

                        -- was setting bot's angle to their angle before the path:Update, but that was breaking prediction/velocity somehow
                        -- this as it turns out, is the correct way to stop it from turning towards the path
                        local oldYawRate = locoMeta.GetMaxYawRate( loco )
                        locoMeta.SetMaxYawRate( loco, 0 )

                        pathMeta.Update( path, self )

                        locoMeta.SetMaxYawRate( loco, oldYawRate )

                        local phys = entMeta.GetPhysicsObject( self )
                        if IsValid( phys ) then
                            phys:SetAngles( angle_zero )

                        end
                    end
                }
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
    for index, threadDat in pairs( threads ) do
        local thread = threadDat.cor
        local onDone = threadDat.onDone
        local whenBusy = threadDat.whenBusy
        local oldTime = SysTime()
        local myCostThisTick = 0
        local wasBusy

        while SysTime() - oldTime < thresh do
            doneSomething = true
            wasBusy = true
            local noErrors, result = coroutine_resume( thread, self, myTbl )
            if noErrors == false then
                threads[index] = nil
                local stack = debug.traceback( thread )
                ErrorNoHalt( "TERM ERROR: " .. tostring( self ) .. "\n", result .. "\n", stack )
                wasBusy = false
                break

            elseif result == "wait" then
                wasBusy = false
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
                wasBusy = false

            elseif result == "done" then
                threads[index] = nil
                if whenBusy then -- final whenBusy call
                    whenBusy( self, myTbl, true )

                end
                if onDone then -- tell the thread we're done
                    onDone( self, myTbl )

                end
                wasBusy = false -- dont call whenBusy after onDone
                break

            end
        end
        if whenBusy and wasBusy then
            whenBusy( self, myTbl )

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
