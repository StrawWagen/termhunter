function ENT:BehaveStart()
    self:SetupCollisionBounds()

end

local entMeta = FindMetaTable( "Entity" )
local locoMeta = FindMetaTable( "CLuaLocomotion" )
local physMeta = FindMetaTable( "PhysObj" )
local pathMeta = FindMetaTable( "PathFollower" )

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local coroutine_create = coroutine.create
local SysTime = SysTime
local IsValid = IsValid
local math = math
local pairs = pairs
local CurTime = CurTime

local printTasks
if GetConVar( "term_debugtasks" ) then
    printTasks = GetConVar( "term_debugtasks" ):GetBool()

end
hook.Add( "InitPostEntity", "getprinttasks_behaviouroverrides", function()
    printTasks = GetConVar( "term_debugtasks" ):GetBool()

end )
cvars.AddChangeCallback( "term_debugtasks", function( _, _, newValue )
    printTasks = tobool( newValue )

end, "TerminatorDebugTasks_LastYield" )

-- demand path updates for 2 movement coroutine completions
-- otherwise bot would just mosey along with :Approaches, not actually checking if it should jump, or update the current path segment
function ENT:DemandPathUpdates( myTbl )
    myTbl.m_PathUpdatesDemanded = 2

end

-- used in StopMoving stuff
-- prevents bot from doing queued cheap updates
function ENT:RejectPathUpdates( myTbl )
    myTbl.m_PathUpdatesDemanded = 0

end

-- kill the motion coroutine
-- useful when teleporting bots a far distance, cause they could be in the middle of calculating some shorter setpos
function ENT:RestartMotionCoroutine( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )

    local threads = myTbl.BehaviourThreads
    if not threads then return end

    local motionCor = threads.motionCor
    if not motionCor then return end

    threads.motionCor.cor = coroutine_create( function()
        coroutine_yield( "done" )
    end )
end

local pathUpdateIntervalFodder = 0.1

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

    myTbl.SetupSpeed( self, myTbl )
    myTbl.SetupMotionType( self, myTbl )
    myTbl.ProcessFootsteps( self, myTbl )
    myTbl.m_FallSpeed = -myTbl.loco:GetVelocity().z

    if not disable then
        myTbl.SetupEyeAngles( self, myTbl )
        myTbl.UpdatePhysicsObject( self )
        myTbl.HandlePathRemovedWhileOnladder( self )

        local threads = myTbl.BehaviourThreads
        if not threads then
            threads = {}
            myTbl.BehaviourThreads = threads

        end

        local ply = myTbl.GetControlPlayer( self )
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

            if not threads.playerControlCor then
                threads.playerControlCor = {
                    cor = coroutine_create( function( self, myTbl ) myTbl.BehaviourPlayerControlCoroutine( self, myTbl ) end ),

                }
            end
            -- Calling task callbacks

            myTbl.m_ControlPlayerOldButtons = myTbl.m_ControlPlayerButtons
        else

            if not threads.priorityCor then
                threads.priorityCor = {
                    cor = coroutine_create( function( self, myTbl ) myTbl.BehaviourPriorityCoroutine( self, myTbl ) end ),

                }
            end
            if not threads.motionCor then
                threads.motionCor = {
                    cor = coroutine_create( function( self, myTbl ) myTbl.BehaviourMotionCoroutine( self, myTbl ) end ),
                    onDone = function( self, myTbl )
                        local demanded = myTbl.m_PathUpdatesDemanded
                        if demanded <= 0 then return end

                        myTbl.m_PathUpdatesDemanded = demanded - 1

                    end,
                    whenBusy = function( self, myTbl, lastOne ) -- horrible, terrible hacks to fix equally horrible terrible visual stuttering when low CoroutineThresh bots are pathing
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

                        local currSegment = pathMeta.GetCurrentGoal( path )
                        local currType = currSegment.type
                        local laddering = currType == 4 or currType == 5
                        if laddering then
                            myTbl.TermHandleLadder( self )
                            return

                        end

                        local loco = myTbl.loco

                        -- was setting bot's angle to their angle before the path:Update, but that was breaking prediction/velocity somehow
                        -- this as it turns out, is the correct way to stop it from turning towards the path
                        local oldYawRate = locoMeta.GetMaxYawRate( loco )
                        locoMeta.SetMaxYawRate( loco, 0 )

                        pathMeta.Update( path, self )

                        locoMeta.SetMaxYawRate( loco, oldYawRate )

                        local phys = entMeta.GetPhysicsObject( self )
                        if IsValid( phys ) then
                            physMeta.SetAngles( phys, angle_zero )

                        end
                    end
                }
            end
        end
    end

    myTbl.SetupGesturePosture( self )

end


-- debuggers for finding yields that need TLC
local yieldDebugTotalCosts
local yieldDebugWorstCosts
local debugging = false

do
    local function onToggleDebugging()
        if debugging then
            yieldDebugTotalCosts = {}
            yieldDebugWorstCosts = {}

        else
            yieldDebugTotalCosts = nil
            yieldDebugWorstCosts = nil

        end
    end

    CreateConVar( "term_debug_totaloverbudgetyields", "0", FCVAR_NONE, "Prints the yields that are collectively draining FPS" )
    cvars.AddChangeCallback( "term_debug_totaloverbudgetyields", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting overbudget yield finder.\nRun term_debug_totaloverbudgetyields 0 to see results" )

        else
            if not yieldDebugTotalCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local overbudgetFound = table.Count( yieldDebugTotalCosts )
            if overbudgetFound <= 0 then
                permaPrint( "No overbudget yields found." )
                return

            else
                local i = 0
                local max = 20
                permaPrint( "Found " .. overbudgetFound .. " overbudget yields. Displaying the " .. math.min( overbudgetFound, max ) .. " worst results.\nAdd more yields BEFORE these lines:" )
                for currStack, value in SortedPairsByValue( yieldDebugTotalCosts, true ) do
                    i = i + 1
                    if i > max then break end
                    permaPrint( "-------------------------" )
                    permaPrint( "Added costs: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )

            end
            yieldDebugTotalCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker" )

    CreateConVar( "term_debug_worstoverbudgetyields", "0", FCVAR_NONE, "Prints the yields spiking performance, causing tiny freezes" )
    cvars.AddChangeCallback( "term_debug_worstoverbudgetyields", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting worst overbudget yield finder.\nRun term_debug_worstoverbudgetyields 0 to see results" )

        else
            if not yieldDebugWorstCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local overbudgetFound = table.Count( yieldDebugWorstCosts )
            if overbudgetFound <= 0 then
                permaPrint( "No worst overbudget yields found." )
                return

            else
                local i = 0
                local max = 20
                permaPrint( "Found " .. overbudgetFound .. " worst overbudget yields. Displaying the " .. math.min( overbudgetFound, max ) .. " worst results.\nAdd more yields BEFORE these lines:" )
                for currStack, value in SortedPairsByValue( yieldDebugWorstCosts, true ) do
                    i = i + 1
                    if i > max then break end
                    permaPrint( "-------------------------" )
                    permaPrint( "Worst cost: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )

            end
            yieldDebugWorstCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker" )
end


local costThisTick = 0
local lastTick = CurTime()
local probablyLagging = 60 -- shared path yield budget every bot gets. mitigates freezes from multiple bots pathing at once.
local budgetEveryoneGets = 2 -- but we let every bot get at least this many patch yields per think, otherwise they stand still forever.
local budgetAddIfNear = 2 -- if bot near enemy, gets this many more path yields 
local budgetAddIfNextTo = 5 -- next to, this many more
local nearDist = 3000
local nextToDist = 650
if game.IsDedicated() then
    budgetEveryoneGets = 3

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
    if myTbl.IsFodder and not IsValid( enem ) then -- fodders without enemies think slower
        thresh = thresh / 2

    elseif myTbl.ThreshMulIfDueling then -- think fast when next to an enemy, even faster when next to player enemy
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

        while thread do
            local cost = SysTime() - oldTime
            local overbudget = cost > thresh
            if overbudget then
                if debugging then
                    local stack = debug.traceback( thread )
                    yieldDebugTotalCosts[stack] = ( yieldDebugTotalCosts[stack] or 0 ) + cost
                    yieldDebugWorstCosts[stack] = math.max( yieldDebugWorstCosts[stack] or 0, cost )

                end
                break

            end
            if printTasks then
                myTbl.lastYieldLocation = debug.traceback( thread )

            end
            doneSomething = true
            wasBusy = true -- did we have a normal yield?
            local noErrors, result = coroutine_resume( thread, self, myTbl )
            if noErrors == false then
                local stack = debug.traceback( thread )
                threads[index] = nil
                result = result or "unknown error"
                ErrorNoHalt( "TERM ERROR: " .. tostring( self ) .. "\n" .. result .. "\n" .. stack .. "\n" )
                wasBusy = false
                break

            elseif result == "wait" then
                wasBusy = false
                break

            elseif result == "pathing" then
                local budgetIGet = budgetEveryoneGets
                if distToEnem < nextToDist then
                    budgetIGet = budgetIGet + budgetAddIfNextTo

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
    -- update drowning, speaking, etc
    myTbl.TermThink( self, myTbl )

    coroutine_yield()

    -- do shootblocker checks
    myTbl.ShootblockerThink( self, myTbl )

    -- Calling task callbacks
    myTbl.RunTask( self, "BehaveUpdatePriority" )
    myTbl.RunTask( self, "Think" )

    coroutine_yield( "done" )

end

-- do motion, anything super computationally expensive on this coroutine
function ENT:BehaviourMotionCoroutine( myTbl )
    myTbl.term_cancelPathGen = nil -- set in tasks.lua when tasks end.

    myTbl.StuckCheck( self, myTbl ) -- check if we are intersecting stuff
    myTbl.WalkArea( self, myTbl ) -- mark nearby areas as walked, used for searching new unwalked areas

    -- Calling task callbacks
    myTbl.RunTask( self, "BehaveUpdateMotion" )

    coroutine_yield( "done" )

end

function ENT:BehaviourPlayerControlCoroutine( myTbl )

    -- update drowning, speaking, etc
    myTbl.TermThink( self, myTbl )
    myTbl.StuckCheck( self, myTbl ) -- check if we are intersecting stuff

    -- Calling task callbacks
    myTbl.RunTask( self, "PlayerControlUpdate", ply )
    myTbl.RunTask( self, "Think" )

    coroutine_yield( "done" )

end