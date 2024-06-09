local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local function yieldIfWeCan( reason )
    if not coroutine_running() then return end
    coroutine_yield( reason )

end

--[[------------------------------------
    Name: NEXTBOT:RunTask
    Desc: Runs active tasks callbacks with given event.
    Arg1: string | event | Event of hook.
    Arg*: vararg | Arguments to callback. NOTE: In callback, first argument is always bot entity, second argument is always task data, passed arguments from NEXTBOT:RunTask starts at third argument.
    Ret*: vararg | Callback return.
    EDITED to add a return end
--]]------------------------------------

function ENT:RunTask( event, ... )
    local m_ActiveTasksNum = self.m_ActiveTasksNum
    if not m_ActiveTasksNum then return end

    local m_TaskList = self.m_TaskList
    local PassedTasks = {}

    local k = 1
    while true do
        local v = m_ActiveTasksNum[k]
        if not v then break end

        local task,data = v[1],v[2]

        if PassedTasks[task] then
            k = k + 1

            continue
        end
        PassedTasks[task] = true

        local taskReal = m_TaskList[task]
        if not taskReal then continue end -- fix using smellllly continue
        local callback = taskReal[event]

        if callback then
            yieldIfWeCan()
            --local old = SysTime()
            local args = { callback( self, data, ... ) }

            --local cost = math.abs( old - SysTime() )
            --if cost > 0.5 then ErrorNoHaltWithStack( task .. "  " .. event .. "  " .. cost ) PrintTable( data ) end

            if args[1] ~= nil then
                if args[2] ~= nil then
                    return args[1]
                else
                    return unpack( args )
                end
            end

            while k > 0 do
                local cv = m_ActiveTasksNum[k]
                if cv == v then break end

                k = k-1
            end
        end

        k = k + 1

    end
end
