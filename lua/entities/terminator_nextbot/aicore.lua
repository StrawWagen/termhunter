
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
    PATHING_DONTWAIT = 8, -- still a pathing yield, but dont count towards the budget, added for debugging pathing yields
    DONE_CLEANUP = 16, -- end and teardown this thread

}
terminator_Extras.BOT_COROUTINE_RESULTS = BOT_COROUTINE_RESULTS

local printTasks
if GetConVar( "term_debugtasks" ) then
    printTasks = GetConVar( "term_debugtasks" ):GetBool()

end
hook.Add( "InitPostEntity", "getprinttasks_aicore", function()
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
local pathUpdateInterval = 0.025

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

                    local nextUpdate = myTbl.m_NextPathUpdate or 0
                    local cur = CurTime()
                    if nextUpdate > cur then return end

                    if myTbl.isFodder then
                        myTbl.m_NextPathUpdate = cur + pathUpdateIntervalFodder

                    else
                        myTbl.m_NextPathUpdate = cur + pathUpdateInterval

                    end

                    local path = myTbl.GetPath( self, myTbl )
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
-- every tracker feeds this one table, keyed by yield site
-- [key] = { total, worst, count, pathTotal, pathCount, mem, stack }
local yieldStats
local trackerOn = {} -- convar name -> bool, several can watch at once
local profiling = false -- any tracker, so the hot loop needs one check
local profilingMem = false -- the only tracker allowed to touch the collector
local yieldStatFor -- assigned below, called from ENT:Think

do
    local function refreshProfilingFlags()
        profiling = false
        for _, on in pairs( trackerOn ) do
            if on then
                profiling = true
                break

            end
        end

        profilingMem = trackerOn["term_debug_luamem"] or false

        if profiling then
            yieldStats = yieldStats or {} -- shared, so turning one tracker off doesnt wipe another

        else
            yieldStats = nil

        end
    end

    function yieldStatFor( thread )
        local here = debug.getinfo( thread, 2, "Sl" ) -- 1 is the C coroutine.yield, 2 is the lua that called it
        if not here then return end -- thread finished, no stack left to read

        local key = here.short_src .. ":" .. here.currentline
        local from = debug.getinfo( thread, 3, "Sl" )
        if from then -- keyed by caller too, so a shared helper doesnt collapse into one row
            key = key .. "  <- " .. from.short_src .. ":" .. from.currentline

        end

        local stat = yieldStats[key]
        if not stat then
            stat = {
                total = 0,
                worst = 0,
                count = 0,
                overTotal = 0, -- ms past thresh this site is responsible for, not time spent
                overCount = 0,
                overWorst = 0,
                pathTotal = 0,
                pathCount = 0,
                mem = 0,
                stack = debug.traceback( thread ), -- printed only, so once per site instead of once per resume

            }
            yieldStats[key] = stat

        end
        return stat

    end

    local reportMax = 20

    local function printYieldReport( heading, valueOf, describe )
        if not yieldStats then permaPrint( "ERR: File was autorefreshed." ) return end

        local rows = {}
        for _, stat in pairs( yieldStats ) do
            if valueOf( stat ) > 0 then
                rows[#rows + 1] = stat

            end
        end

        if #rows <= 0 then permaPrint( "No results found." ) return end

        table.sort( rows, function( a, b ) return valueOf( a ) > valueOf( b ) end )

        local shown = math.min( #rows, reportMax )
        permaPrint( "Found " .. #rows .. " yield sites. Showing the top " .. shown .. "." )
        permaPrint( heading )

        for i = 1, shown do
            local stat = rows[i]
            permaPrint( "-------------------------" )
            permaPrint( describe( stat ) .. "\n", stat.stack )

        end
        permaPrint( "-------------------------" )

        if #rows > reportMax then
            permaPrint( ( #rows - reportMax ) .. " results excluded..." )
            permaPrint( "-------------------------" )

        end
    end

    local function ms( seconds )
        return string.format( "%.3f ms", seconds * 1000 )

    end

    local function addTracker( convar, blurb, heading, valueOf, describe )
        CreateConVar( convar, "0", FCVAR_NONE, blurb )
        cvars.AddChangeCallback( convar, function( _, _, newVal )
            local on = tobool( newVal )
            trackerOn[convar] = on

            if on then
                refreshProfilingFlags()
                permaPrint( "Starting " .. convar .. ".\nRun " .. convar .. " 0 to see results" )

            else
                printYieldReport( heading, valueOf, describe )
                refreshProfilingFlags() -- drops yieldStats once the last tracker is off

            end
        end, "maindebugthinker_" .. convar )

    end

    addTracker(
        "term_debug_overbudgetyields",
        "Prints the yields whose work took a bot over its tick budget",
        "Ranked by how far past CoroutineThresh each site pushed a bot. ADD MORE YIELDS inside the work BEFORE these lines.",
        function( stat ) return stat.overTotal end,
        function( stat )
            return string.format( "overshoot %10s   times %7d   avg %10s   worst %10s   segment avg %10s", ms( stat.overTotal ), stat.overCount, ms( stat.overTotal / stat.overCount ), ms( stat.overWorst ), ms( stat.total / stat.count ) )

        end
    )

    addTracker(
        "term_debug_uselessyields",
        "Prints the yields firing constantly for almost no work",
        "Ranked by how often they fire. A huge count next to a tiny avg is a yield earning nothing, DELETE it or hoist it out of its loop.",
        function( stat ) return stat.count end,
        function( stat )
            return string.format( "count %7d   avg %10s   total %10s   worst %10s", stat.count, ms( stat.total / stat.count ), ms( stat.total ), ms( stat.worst ) )

        end
    )

    addTracker(
        "term_debug_worstyieldcosts",
        "Prints the yields spiking performance, causing tiny freezes",
        "Ranked by the single worst segment. These are the stutters.",
        function( stat ) return stat.worst end,
        function( stat )
            return string.format( "worst %10s   total %10s   count %7d", ms( stat.worst ), ms( stat.total ), stat.count )

        end
    )

    addTracker(
        "term_debug_pathbudget",
        "Prints the total costs of every pathing yield",
        "Ranked by time spent under pathing yields.",
        function( stat ) return stat.pathTotal end,
        function( stat )
            return string.format( "pathing %10s   yields %7d   avg %10s", ms( stat.pathTotal ), stat.pathCount, ms( stat.pathTotal / stat.pathCount ) )

        end
    )

    addTracker(
        "term_debug_luamem",
        "Prints the yields taking up the most lua memory",
        "Ranked by lua garbage created.",
        function( stat ) return stat.mem end,
        function( stat )
            return string.format( "garbage %9.1f KB   count %7d   avg %8.3f KB", stat.mem, stat.count, stat.mem / stat.count )

        end
    )

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

    myTbl.UpdatePhysicsObject( self, myTbl )

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
        local oldLuaMemDebug
        local profilerOverhead = 0

        local done

        while thread and not done do
            -- the budget is deliberately cumulative for the whole tick. profilerOverhead
            -- comes back off it so a bot runs the same code whether or not youre watching
            if ( SysTime() - oldTime ) - profilerOverhead > thresh then break end

            if printTasks and index ~= "disabledCor" then
                myTbl.lastYieldLocation = debug.traceback( thread )

            end
            doneSomething = true
            wasBusy = true -- did we have at least 1 normal yield?

            if profilingMem then
                collectgarbage( "stop" )
                oldLuaMemDebug = collectgarbage( "count" )

            end

            -- timed tight around the resume, so the profiler never charges itself
            local segmentStart = SysTime()
            local noErrors, result = coroutine_resume( thread, self, myTbl )
            local segmentCost = SysTime() - segmentStart

            if profiling then
                local overheadStart = SysTime()

                local luaMemUsed
                if profilingMem then
                    luaMemUsed = collectgarbage( "count" ) - oldLuaMemDebug
                    collectgarbage( "restart" )

                end

                -- overheadStart was taken right after the resume, so this is the tick total
                -- as of this segment ending, for free. profilerOverhead is still last
                -- iteration's, which is what we want, this segment hasnt added to it yet
                local overshoot = ( overheadStart - oldTime ) - profilerOverhead - thresh

                -- charged to the site it yielded AT, so a row reads as "the work ending here"
                local stat = yieldStatFor( thread )
                if stat then
                    stat.total = stat.total + segmentCost
                    stat.count = stat.count + 1
                    if segmentCost > stat.worst then
                        stat.worst = segmentCost

                    end
                    if overshoot > 0 then
                        -- how far past thresh this segment pushed us, not how long it was.
                        -- a cheap segment that merely happened to cross the line scores
                        -- near zero, which is what keeps landing spots off the report
                        if overshoot > segmentCost then -- cant be blamed for more than its own length
                            overshoot = segmentCost

                        end
                        stat.overTotal = stat.overTotal + overshoot
                        stat.overCount = stat.overCount + 1
                        if overshoot > stat.overWorst then
                            stat.overWorst = overshoot

                        end
                    end
                    if luaMemUsed then
                        stat.mem = stat.mem + luaMemUsed

                    end
                    if result == BOT_COROUTINE_RESULTS.PATHING or result == BOT_COROUTINE_RESULTS.PATHING_DONTWAIT then
                        stat.pathTotal = stat.pathTotal + segmentCost
                        stat.pathCount = stat.pathCount + 1

                    end
                end
                profilerOverhead = profilerOverhead + ( SysTime() - overheadStart )

            end

            if noErrors == false then -- something errored in there
                local stackAfter = debug.traceback( thread )
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
                local stackAfter = debug.traceback( thread )
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

        -- stub, for your convenience!
        myTbl.AdditionalThink( self, myTbl )

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

        coroutine_yield()

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

        coroutine_yield()

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
        myTbl.RunTask( self, "PlayerControlUpdate", myTbl.GetControlPlayer( self ) )
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
