-- credit redox for the method

local function startCounter()
    TrackedCoroutines = TrackedCoroutines or setmetatable({}, { __mode = "k" })
    TrackedCoroutineKillReasons = TrackedCoroutineKillReasons or setmetatable({}, { __mode = "k" })

    local nextPrint = 0

    coroutine_create_ = coroutine_create_ or coroutine.create
    function coroutine.create( f, ... )
        local co = coroutine_create_( f, ... )
        TrackedCoroutines[co] = debug.traceback()

        if nextPrint < CurTime() then
            nextPrint = CurTime() + 5
            local count = 0
            for _, _ in pairs( TrackedCoroutines ) do
                count = count + 1

            end
        end
        return co

    end
end
local function count()
    -- call later:
    collectgarbage("collect")

    local coCount = 0
    for co, tb in pairs(TrackedCoroutines) do
        coCount = coCount + 1
        print("still alive:", co, tb)

    end

    print("live coroutines:", coCount)

end

concommand.Add( "term_countcoroutines", function()
    if not TrackedCoroutines then
        startCounter()
        print("Started tracking coroutines.")

    else
        count()

    end
end )