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

    local nextYield = 10
    local m_TaskList = self.m_TaskList
    local passedTasks = {}

    local k = 1
    while true do
        local currTask = m_ActiveTasksNum[k]
        if not currTask then break end

        local task,data = currTask[1],currTask[2]

        if passedTasks[task] then
            k = k + 1

            continue
        end
        passedTasks[task] = true

        local taskReal = m_TaskList[task]

        if not taskReal then continue end
        local callback = taskReal[event]

        if callback then
            -- always yields every 2 'k'
            if k > nextYield then
                nextYield = k + 2
                yieldIfWeCan()

            end
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
                if cv == currTask then break end

                k = k-1
            end
        end

        k = k + 1

    end
end

local string_find = string.find

function ENT:KillAllTasksWith( withStr )
    local m_ActiveTasksNum = self.m_ActiveTasksNum
    if not m_ActiveTasksNum then return end

    for _, activeTaskDat in ipairs( m_ActiveTasksNum ) do
        if not activeTaskDat then break end

        local taskName = activeTaskDat[1]
        if string_find( taskName, withStr ) then
            self:TaskFail( taskName )

        end
    end
end

--[[------------------------------------
    Name: NEXTBOT:StartTask
    Desc: Starts new task with given data and calls 'OnStart' task callback. Does nothing if given task already started.
    Arg1: any | task | Task name.
    Arg2: (optional) table | data | Task data.
    Ret1: 
--]]------------------------------------
function ENT:StartTask( task, data )
    if self:IsTaskActive( task ) then return end

    data = data or {}
    data.myTbl = self:GetTable()
    self.m_ActiveTasks[task] = data

    local m_ActiveTasksNum = self.m_ActiveTasksNum
    if not m_ActiveTasksNum then
        m_ActiveTasksNum = {}
        self.m_ActiveTasksNum = m_ActiveTasksNum
    end
    m_ActiveTasksNum[ #m_ActiveTasksNum + 1 ] = { task, data }

    self:RunCurrentTask( task, "OnStart" )

end