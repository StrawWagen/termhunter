function ENT:BehaveStart()
    self:SetupCollisionBounds()

end

local entMeta = FindMetaTable( "Entity" )
local locoMeta = FindMetaTable( "CLuaLocomotion" )
local physMeta = FindMetaTable( "PhysObj" )
local pathMeta = FindMetaTable( "PathFollower" )

local coroutine_yield = coroutine.yield
local coroutine_resume = coroutine.resume
local SysTime = SysTime
local IsValid = IsValid
local math = math
local pairs = pairs
local CurTime = CurTime

hook.Add( "Terminator_CoroutineCounterStarted", "relocalize_resume", function()
    coroutine_resume = coroutine.resume

end )

local aiDisabled = GetConVar( "ai_disabled" )
function ENT:DisabledThinking()
    return aiDisabled:GetBool()

end

local ignorePlayers = GetConVar( "ai_ignoreplayers" )
function ENT:IgnoringPlayers()
    return ignorePlayers:GetBool()

end

-- masks
local BOT_COROUTINE_RESULTS = {
    DONE = 1, -- this thread is done for now
    WAIT = 2, -- wait until next think
    PATHING = 4, -- let us get put in the pathing budget queue
    PATHING_DONTWAIT = 8, -- still a pathing yield, but dont count towards the budget, added for debugging
    DONE_CLEANUP = 16, -- end and teardown this thread

}
terminator_Extras.BOT_COROUTINE_RESULTS = BOT_COROUTINE_RESULTS

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

    threads.motionCor.cor = coroutine.create( function()
        coroutine_yield( BOT_COROUTINE_RESULTS.DONE_CLEANUP )

    end, self:GetClass() )

    -- just in case
    myTbl.debug_MotionCoroutineResets = ( myTbl.debug_MotionCoroutineResets or 0 ) + 1
    myTbl.debug_LastMotionCoroutineResetTime = CurTime()

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
    myTbl.m_FallSpeed = -myTbl.loco:GetVelocity().z

    myTbl.SetupGesturePosture( self )

    local threads = myTbl.BehaviourThreads
    if not threads then
        threads = {}
        myTbl.BehaviourThreads = threads

    end

    if disable then -- make sure we call the Think task callback even if we're disabled
        if not threads.disabledCor then
            threads.priorityCor = nil
            threads.motionCor = nil
            threads.playerControlCor = nil
            threads.disabledCor = {
                cor = coroutine.create( function( self, myTbl ) myTbl.DisabledBehaviourCoroutine( self, myTbl ) end, self:GetClass() ),

            }
        end
        return

    end

    myTbl.ProcessFootsteps( self, myTbl )
    myTbl.SetupEyeAngles( self, myTbl )
    myTbl.UpdatePhysicsObject( self )
    myTbl.HandlePathRemovedWhileOnladder( self )

    local ply = myTbl.GetControlPlayer( self )
    if IsValid( ply ) then -- being controlled, not _index optimizing this
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
            threads.priorityCor = nil
            threads.motionCor = nil
            threads.disabledCor = nil
            threads.playerControlCor = {
                cor = coroutine.create( function( self, myTbl ) myTbl.BehaviourPlayerControlCoroutine( self, myTbl ) end, self:GetClass() ),

            }
        end
        myTbl.m_ControlPlayerOldButtons = myTbl.m_ControlPlayerButtons

    else
        local updated
        if not threads.priorityCor then
            updated = true
            threads.priorityCor = {
                cor = coroutine.create( function( self, myTbl ) myTbl.BehaviourPriorityCoroutine( self, myTbl ) end, self:GetClass() ),

            }
        end
        if not threads.motionCor then
            updated = true
            threads.motionCor = {
                cor = coroutine.create( function( self, myTbl ) myTbl.BehaviourMotionCoroutine( self, myTbl ) end, self:GetClass() ),
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
        if updated then
            threads.disabledCor = nil
            threads.playerControlCor = nil

        end
    end
end


-- debuggers for finding yields that need TLC
local yieldDebugTotalCosts
local yieldDebugWorstCosts
local yieldDebugPathCosts
local yieldDebugLuaMemCosts
local debugging = false

do
    local function onToggleDebugging()
        if debugging then
            yieldDebugTotalCosts = {}
            yieldDebugWorstCosts = {}
            yieldDebugPathCosts = {}
            yieldDebugLuaMemCosts = {}

        else
            yieldDebugTotalCosts = nil
            yieldDebugWorstCosts = nil
            yieldDebugPathCosts = nil
            yieldDebugLuaMemCosts = nil

        end
    end

    CreateConVar( "term_debug_totaloverbudgetyields", "0", FCVAR_NONE, "Prints the yields that are collectively draining FPS" )
    cvars.AddChangeCallback( "term_debug_totaloverbudgetyields", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting overbudget yield finder.\nRun term_debug_totaloverbudgetyields 0 to see results" )

        else
            if not yieldDebugTotalCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local totalCostsCount = table.Count( yieldDebugTotalCosts )
            if totalCostsCount <= 0 then
                permaPrint( "No overbudget yields found." )
                return

            else
                local i = 0
                local max = 20
                local wasOverMax = false
                permaPrint( "Found " .. totalCostsCount .. " overbudget yields. Displaying the " .. math.min( totalCostsCount, max ) .. " worst results.\nAdd more yields BEFORE these lines:" )
                permaPrint( "Top " .. math.min( totalCostsCount, max ) .. " results:" )
                for currStack, value in SortedPairsByValue( yieldDebugTotalCosts, true ) do
                    i = i + 1
                    if i > max then
                        wasOverMax = true
                        break

                    end
                    permaPrint( "-------------------------" )
                    permaPrint( "Added costs: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )
                if wasOverMax then
                    local excludedCount = totalCostsCount - max
                    permaPrint( excludedCount .. " results excluded..." )
                    permaPrint( "-------------------------" )

                end
            end
            yieldDebugTotalCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker_totaloverbudgetyields" )

    CreateConVar( "term_debug_worstoverbudgetyields", "0", FCVAR_NONE, "Prints the yields spiking performance, causing tiny freezes" )
    cvars.AddChangeCallback( "term_debug_worstoverbudgetyields", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting worst overbudget yield finder.\nRun term_debug_worstoverbudgetyields 0 to see results" )

        else
            if not yieldDebugWorstCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local overbudgetFoundCount = table.Count( yieldDebugWorstCosts )
            if overbudgetFoundCount <= 0 then
                permaPrint( "No overbudget yields found." )
                return

            else
                local i = 0
                local max = 20
                local wasOverMax = false
                permaPrint( "Found " .. overbudgetFoundCount .. " worst overbudget yields. Displaying the " .. math.min( overbudgetFoundCount, max ) .. " worst results.\nAdd more yields BEFORE these lines:" )
                permaPrint( "Top " .. math.min( overbudgetFoundCount, max ) .. " results:" )
                for currStack, value in SortedPairsByValue( yieldDebugWorstCosts, true ) do
                    i = i + 1
                    if i > max then
                        wasOverMax = true
                        break

                    end
                    permaPrint( "-------------------------" )
                    permaPrint( "Worst cost: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )
                if wasOverMax then
                    local excludedCount = overbudgetFoundCount - max
                    permaPrint( excludedCount .. " results excluded..." )
                    permaPrint( "-------------------------" )

                end
            end
            yieldDebugWorstCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker_worstoverbudgetyields" )

    CreateConVar( "term_debug_pathbudget", "0", FCVAR_NONE, "Prints the total costs of every pathing yield" )
    cvars.AddChangeCallback( "term_debug_pathbudget", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting pathing yield cost tracker.\nRun term_debug_pathbudget 0 to see results" )

        else
            if not yieldDebugPathCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local yieldCostsCount = table.Count( yieldDebugPathCosts )
            if yieldCostsCount <= 0 then
                permaPrint( "No pathing yields found." )
                return

            else
                local i = 0
                local max = 20
                local wasOverMax = false
                permaPrint( "Found " .. yieldCostsCount .. " pathing yields.\nOptimize the code BEFORE these lines." )
                permaPrint( "Top " .. math.min( yieldCostsCount, max ) .. " results:" )
                for currStack, value in SortedPairsByValue( yieldDebugPathCosts, true ) do
                    i = i + 1
                    if i > max then
                        wasOverMax = true
                        break

                    end
                    permaPrint( "-------------------------" )
                    permaPrint( "Total cost: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )
                if wasOverMax then
                    local excludedCount = yieldCostsCount - max
                    permaPrint( excludedCount .. " results excluded..." )
                    permaPrint( "-------------------------" )

                end
            end
            yieldDebugPathCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker_pathbudget" )

    CreateConVar( "term_debug_luamem", "0", FCVAR_NONE, "Prints the yields taking up the most lua memory" )
    cvars.AddChangeCallback( "term_debug_luamem", function( _, _, newVal )
        debugging = tobool( newVal )
        if debugging then
            permaPrint( "Starting term luamem tracker.\nRun term_debug_luamem 0 to see results" )

        else
            if not yieldDebugLuaMemCosts then permaPrint( "ERR: File was autorefreshed." ) return end

            local yieldDebugLuaMemCostsCount = table.Count( yieldDebugLuaMemCosts )
            if yieldDebugLuaMemCostsCount <= 0 then
                permaPrint( "No yields found." )
                return

            else
                local i = 0
                local max = 20
                local wasOverMax = false
                permaPrint( "Found " .. yieldDebugLuaMemCostsCount .. " yields creating garbage.\nOptimize the code BEFORE these worst yields." )
                permaPrint( "Top " .. math.min( yieldDebugLuaMemCostsCount, max ) .. " results:" )
                for currStack, value in SortedPairsByValue( yieldDebugLuaMemCosts, true ) do
                    i = i + 1
                    if i > max then
                        wasOverMax = true
                        break

                    end
                    permaPrint( "-------------------------" )
                    permaPrint( "Total cost: " .. value .. "\n", currStack )

                end
                permaPrint( "-------------------------" )
                if wasOverMax then
                    local excludedCount = yieldDebugLuaMemCostsCount - max
                    permaPrint( excludedCount .. " results excluded..." )
                    permaPrint( "-------------------------" )

                end
            end
            yieldDebugLuaMemCosts = nil

        end
        onToggleDebugging()

    end, "maindebugthinker_luamem" )

end


local costThisTick = 0 -- total path yields used this tick
local probablyLagging = 60 -- shared path yield budget every bot gets. mitigates freezes from multiple bots pathing at once.
local budgetEveryoneGets = 2 -- but we let every bot get at least this many patch yields per think, otherwise they stand still forever.
local budgetAddIfNear = 2 -- if bot near enemy, gets this many more path yields 
local budgetAddIfNextTo = 5 -- next to, this many more
local lastTick = CurTime()
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
        local myPathingCostThisTick = 0
        local wasBusy
        local oldTimePathDebug
        local oldLuaMemDebug

        if debugging then
            oldLuaMemDebug = collectgarbage( "count" )

        end

        local done

        while thread and not done do
            local cost = SysTime() - oldTime
            local overbudget = cost > thresh
            local stackBefore
            if debugging or printTasks then
                stackBefore = debug.traceback( thread )

            end
            if overbudget then
                if debugging then
                    yieldDebugTotalCosts[stackBefore] = ( yieldDebugTotalCosts[stackBefore] or 0 ) + cost
                    yieldDebugWorstCosts[stackBefore] = math.max( yieldDebugWorstCosts[stackBefore] or 0, cost )

                end
                break

            end
            if printTasks then
                myTbl.lastYieldLocation = stackBefore

            end
            doneSomething = true
            wasBusy = true -- did we have at least 1 normal yield?

            if debugging then
                collectgarbage( "stop" )
                oldLuaMemDebug = collectgarbage( "count" )

            end
            local noErrors, result = coroutine_resume( thread, self, myTbl )

            local stackAfter
            if debugging then
                stackAfter = debug.traceback( thread )

            end

            if debugging then
                local newLuaMemDebug = collectgarbage( "count" )
                collectgarbage( "restart" )

                local luaMemUsed = newLuaMemDebug - oldLuaMemDebug
                yieldDebugLuaMemCosts[stackAfter] = ( yieldDebugLuaMemCosts[stackAfter] or 0 ) + luaMemUsed

                if result and ( result == BOT_COROUTINE_RESULTS.PATHING or result == BOT_COROUTINE_RESULTS.PATHING_DONTWAIT ) then
                    if not oldTimePathDebug then
                        oldTimePathDebug = SysTime()

                    else
                        yieldDebugPathCosts[stackAfter] = ( yieldDebugPathCosts[stackAfter] or 0 ) + ( SysTime() - oldTimePathDebug )
                        oldTimePathDebug = SysTime()

                    end
                else
                    oldTimePathDebug = nil

                end
            end

            if noErrors == false then -- something errored in there
                stackAfter = stackAfter or debug.traceback( thread )
                threads[index] = nil
                result = result or "unknown error"
                ErrorNoHalt( "TERM ERROR: " .. tostring( self ) .. " in " .. index .. "\n" .. result .. "\n" .. stackAfter .. "\n" )
                wasBusy = false
                break

            elseif result == BOT_COROUTINE_RESULTS.WAIT then -- all done this tick
                wasBusy = false
                break

            elseif result == BOT_COROUTINE_RESULTS.PATHING then -- pathing yield, count towards global budget
                local budgetIGet = budgetEveryoneGets
                if distToEnem < nextToDist then
                    budgetIGet = budgetIGet + budgetAddIfNextTo

                elseif distToEnem < nearDist then
                    budgetIGet = budgetIGet + budgetAddIfNear

                end
                if not dueling and myPathingCostThisTick >= budgetIGet and costThisTick > probablyLagging then -- hack to stop groups of bots from nuking session perf
                    break

                end
                myPathingCostThisTick = myPathingCostThisTick + 1
                costThisTick = costThisTick + 1
                wasBusy = false

            elseif result == BOT_COROUTINE_RESULTS.DONE then -- this thread is finished
                if whenBusy then -- final whenBusy call
                    whenBusy( self, myTbl, true )

                end
                if onDone then -- tell the thread we're done
                    onDone( self, myTbl )

                end
                wasBusy = false -- dont call whenBusy after onDone
                done = true
                break

            elseif result == BOT_COROUTINE_RESULTS.DONE_CLEANUP then -- this thread is finished, and we need to cleanup
                threads[index] = nil

                if whenBusy then -- final whenBusy call
                    whenBusy( self, myTbl, true )

                end
                if onDone then -- tell the thread we're done
                    onDone( self, myTbl )

                end
                wasBusy = false -- dont call whenBusy after onDone
                done = true
                break

            elseif isstring( result ) then -- invalid yield, needs to be BOT_COROUTINE_RESULTS
                stackAfter = stackAfter or debug.traceback( thread )
                ErrorNoHalt( "TERM ERROR: " .. tostring( self ) .. " for " .. index .. "\nUnknown yield result: " .. tostring( result ) .. "\n" .. stackAfter .. "\n" )

            end
        end
        if whenBusy and wasBusy then -- move us forward along our path and stuff
            whenBusy( self, myTbl )

        end
    end
    if doneSomething then
        entMeta.NextThink( self, CurTime() ) -- think fast if we have threads to process
        return true

    end
end

-- do enemy handling ( looking around, finding enemies, shooting ) asynced to the movement coroutine
function ENT:BehaviourPriorityCoroutine( myTbl )
    while true do
        -- update drowning, speaking, etc
        myTbl.TermThink( self, myTbl )
        coroutine_yield()

        -- stub, for your convenience!
        myTbl.AdditionalThink( self, myTbl )
        coroutine_yield()

        local nextBlockerCheck = myTbl.m_NextShootBlockerCheck or 0
        if nextBlockerCheck < CurTime() then
            if myTbl.IsFodder then
                myTbl.m_NextShootBlockerCheck = CurTime() + 0.5

            else
                myTbl.m_NextShootBlockerCheck = CurTime() + 0.1

            end
            -- do shootblocker checks
            myTbl.ShootblockerThink( self, myTbl )

        end

        -- Calling task callbacks
        myTbl.RunTask( self, "BehaveUpdatePriority" )
        myTbl.RunTask( self, "Think" )

        coroutine_yield( BOT_COROUTINE_RESULTS.DONE )

    end
end

-- do motion, anything super computationally expensive on this coroutine
function ENT:BehaviourMotionCoroutine( myTbl )
    while true do
        myTbl.term_cancelPathGen = nil -- set in tasks.lua when tasks end.

        myTbl.StuckCheck( self, myTbl ) -- check if we are intersecting stuff
        myTbl.WalkArea( self, myTbl ) -- mark nearby areas as walked, used for searching new unwalked areas

        -- Calling task callbacks
        myTbl.RunTask( self, "BehaveUpdateMotion" )

        coroutine_yield( BOT_COROUTINE_RESULTS.DONE )

    end
end

-- call stuff while controlled by players
function ENT:BehaviourPlayerControlCoroutine( myTbl )
    while true do
        -- update drowning, speaking, etc
        myTbl.TermThink( self, myTbl )
        myTbl.AdditionalThink( self, myTbl )
        myTbl.StuckCheck( self, myTbl ) -- check if we are intersecting stuff

        -- Calling task callbacks
        myTbl.RunTask( self, "PlayerControlUpdate", ply )
        myTbl.RunTask( self, "Think" )

        coroutine_yield( BOT_COROUTINE_RESULTS.DONE )

    end
end

-- make sure Think callback is always called
function ENT:DisabledBehaviourCoroutine( myTbl )
    while true do
        myTbl.RunTask( self, "Think" )
        myTbl.AdditionalThink( self, myTbl )

        coroutine_yield( BOT_COROUTINE_RESULTS.DONE )

    end
end
