-- credit redox for the method

local function startCounter()
    TrackedCoroutines = TrackedCoroutines or setmetatable({}, { __mode = "k" })
    TrackedCoroutineClasses = TrackedCoroutineClasses or setmetatable({}, { __mode = "k" })
    TrackedCoroutinesLastResumes = TrackedCoroutinesLastResumes or setmetatable({}, { __mode = "k" })

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
    -- call later:
    collectgarbage("collect")
    local cur = SysTime()

    local coroutineDatas = {}
    for co, tb in pairs(TrackedCoroutines) do
        local lastResume = TrackedCoroutinesLastResumes[co] or 0
        local sinceResumed = math.Round( cur - lastResume, 4 )
        local class = TrackedCoroutineClasses[co] or "unknown_class"
        table.insert(coroutineDatas, { co = co, tb = tb, lastResume = lastResume, sinceResumed = sinceResumed, class = class })

    end

    local coCount = 0
    for _, coData in SortedPairsByMemberValue( coroutineDatas, "sinceResumed" ) do
        coCount = coCount + 1
        print("last resumed " .. coData.sinceResumed .. " seconds ago:\n", coData.class, coData.co, coData.tb)

    end

    print("live coroutines:", coCount)

end

local done -- autorefresh should reset this

concommand.Add( "term_countcoroutines", function()
    if not done then
        done = true
        startCounter()
        print("Started tracking coroutines.")

    else
        count()

    end
end )