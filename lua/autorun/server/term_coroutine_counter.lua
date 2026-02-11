-- credit redox for the method

local function startCounter()
    TrackedCoroutines = TrackedCoroutines or setmetatable( {}, { __mode = "k" } )
    TrackedCoroutineClasses = TrackedCoroutineClasses or setmetatable( {}, { __mode = "k" } )
    TrackedCoroutinesLastResumes = TrackedCoroutinesLastResumes or setmetatable( {}, { __mode = "k" } )

    local nextPrint = 0
    local SysTime = SysTime

    coroutine_create_ = coroutine_create_ or coroutine.create
    function coroutine.create( f, ... )
        local co = coroutine_create_( f, ... )
        TrackedCoroutines[co] = debug.traceback()
        local potenitalClass = select( 1, ... )
        if isstring( potenitalClass ) then
            TrackedCoroutineClasses[co] = potenitalClass

        end

        hook.Run( "termDebug_CoroutineCreated", co )

        if nextPrint < CurTime() then
            nextPrint = CurTime() + 5
            local count = 0
            for _, _ in pairs( TrackedCoroutines ) do
                count = count + 1

            end
        end
        return co

    end

    coroutine_resume_ = coroutine_resume_ or coroutine.resume
    function coroutine.resume( co, ... )
        TrackedCoroutinesLastResumes[co] = SysTime()
        return coroutine_resume_( co, ... )

    end

    hook.Run( "Terminator_CoroutineCounterStarted" )

end

local function count()
    collectgarbage( "collect" )
    collectgarbage( "stop" )
    local cur = SysTime()

    local coroutineDatas = setmetatable( {}, { __mode = "k" } )
    for co, tb in pairs( TrackedCoroutines ) do
        local lastResume = TrackedCoroutinesLastResumes[co] or 0
        local sinceResumed = math.Round( cur - lastResume, 4 )
        local class = TrackedCoroutineClasses[co] or "unknown_class"
        local coData = setmetatable( { co = co, tb = tb, lastResume = lastResume, sinceResumed = sinceResumed, class = class }, { __mode = "k" } )
        table.insert( coroutineDatas, coData )

    end

    local printed
    local coCount = 0
    local staleCoCount = 0
    for _, coData in SortedPairsByMemberValue( coroutineDatas, "sinceResumed" ) do
        coCount = coCount + 1
        local co = coData.co
        print( "last resumed " .. coData.sinceResumed .. " seconds ago:\n", coData.class, co, coData.tb )
        if coData.sinceResumed > 25 then
            if luagc and not printed then
                local references = luagc.GetReferences( co )
                PrintTable( references )
                printed = true

            end
            staleCoCount = staleCoCount + 1

        end
    end

    collectgarbage( "restart" )

    print( "live coroutines:", coCount )
    print( "of which, " .. staleCoCount .. " are stale")

end

local done -- autorefresh should reset this

concommand.Add( "term_countcoroutines", function()
    if not done then
        done = true
        startCounter()
        print("Started tracking coroutines.")
        if luagc then
            print( "holylib found, using luagc... this can cause crashes!" )

        end
    else
        count()

    end
end )
