local entMeta = FindMetaTable( "Entity" )
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


--[[------------------------------------
    Name: NEXTBOT:DoCustomTasks
    Desc: stub for entities based on this
    passes terminator tasks, so you can add new functionality/ai and just copy over the base reallystuckhandler, enemy finder, etc
    Arg1: table | defaultTasks | Base terminator tasks
    Ret1: table | defaultTasks | 
--]]------------------------------------
function ENT:DoCustomTasks( _defaultTasks )
end

--[[
DoCustomTasks example!, 
function ENT:DoCustomTasks( defaultTasks )
    self.TaskList = {
        ["shooting_handler"] = defaultTasks["shooting_handler"],
        ["awareness_handler"] = defaultTasks["awareness_handler"],
        ["enemy_handler"] = defaultTasks["enemy_handler"],
        ["inform_handler"] = defaultTasks["inform_handler"],
        ["reallystuck_handler"] = defaultTasks["reallystuck_handler"],
        ["movement_wait"] = defaultTasks["movement_wait"],
        ["playercontrol_handler"] = defaultTasks["playercontrol_handler"],
        ["movement_mycustomtask"] = {
            OnStart = function( self, data )
                -- start doing something
            end,
            OnEnd = function( self, data )
                -- stop doing something
            end,
            BehaveUpdateMotion = function( self, data )
                -- do something in the motion coroutine
            end,
        },
    }
end
--]]


--[[------------------------------------
    Name: NEXTBOT:SetupClassTask
    Desc: stub, Simple way to add class-specific task behaviour
    NOT FOR ADDING MOVEMENT CHANGES!!!
    this is just a simple background task for overriding death behaviour, etc
    see zambie god crab for example
    Arg1: table | task | raw task table
    Ret1:
--]]------------------------------------
function ENT:SetupClassTask( _myTbl, _myClassTask ) -- _ just here to make the linter happy
end

ENT.HasClassTask = false -- set this to true if you're using SetupClassTask

--[[
SetupClassTask example!,
function ENT:SetupClassTask( myClassTask )
    myClassTask.EnemyFound = function( self, data )
        -- do something on enemy found
    end
    myClassTask.EnemyLost = function( self, data )
        -- do something else on enemy lost
    end
    myClassTask.OnKilled = function( self, data )
        -- do something on death
    end
    return myClassTask

end
--]]

-- handles adding class task, donot touch!
function ENT:DoClassTask( myTbl )
    if not myTbl.HasClassTask then return end
    local classTask = {}
    myTbl.SetupClassTask( self, myTbl, classTask )

    if table.Count( classTask ) == 0 then
        return
    end

    classTask.StartsOnInitialize = true

    local className = entMeta.GetClass( self ) .. "_handler"
    self.TaskList[className] = classTask

end


--[[------------------------------------
    Name: ENT:SetupTasks
    Desc: Sets up all tasks for the entity.
    add .StartsOnInitialize = true to task tbl to make it start on spawn.
    Override at your own risk.
    Ret1:
--]]------------------------------------
function ENT:SetupTasks( myTbl )
    myTbl.DoDefaultTasks( self )

    myTbl.DoCustomTasks( self, myTbl.TaskList )
    myTbl.DoClassTask( self, myTbl )

    local taskListStatic = myTbl.m_TaskList
    for k,v in pairs( myTbl.TaskList ) do
        taskListStatic[k] = v

    end

    for taskName, taskDat in pairs( self.TaskList ) do
        if taskDat.StartsOnInitialize then
            self:StartTask( taskName )

        end
    end
end
