local entMeta = FindMetaTable( "Entity" )
local string_find = string.find
local coroutine_yield = coroutine.yield
local coroutine_running = coroutine.running
local function yieldIfWeCan( reason )
    if not coroutine_running() then return end
    coroutine_yield( reason )

end

debugPrintTasks = GetConVar( "terminator_debug_tasks" ) -- global convar for debugging tasks, prints task names in console when they start/stop

--[[------------------------------------
    Name: NEXTBOT:RunTask
    Desc: Runs active tasks callbacks with given event.
    Arg1: string | event | Event of hook.
    Arg*: vararg | Arguments to callback. NOTE: In callback, first argument is always bot entity, second argument is always task data, passed arguments from NEXTBOT:RunTask starts at third argument.
    Ret*: vararg | Callback return.
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
        if not currTask then break end -- no more tasks

        local task,data = currTask[1],currTask[2]

        if passedTasks[task] then -- already passed this task
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

            if args[1] ~= nil then -- 
                if args[2] ~= nil then
                    return args[1]

                else
                    return unpack( args )

                end
            end

            while k > 0 do
                local cv = m_ActiveTasksNum[k]
                if cv == currTask then break end

                k = k - 1
            end
        end

        k = k + 1

    end
end


--[[------------------------------------
    Name: NEXTBOT:KillAllTasksWith
    Desc: Kills all tasks with given string in their name.
    Arg1: string | withStr | String to search in task names.
    Ret1:
--]]------------------------------------
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
    Desc: Starts a task with given name and data.
    Arg1: string | task | Task name.
    Arg2: table | data | Task data.
    Arg3: string | reason | Reason for starting task, used for debugging.
--]]------------------------------------
function ENT:StartTask( task, data, reason )
    if self:IsTaskActive( task ) then return end
    yieldIfWeCan()

    data = data or {}
    data.taskStartTime = CurTime()
    data.myTbl = self:GetTable()

    self.m_ActiveTasks[task] = data

    local m_ActiveTasksNum = self.m_ActiveTasksNum
    if not m_ActiveTasksNum then
        m_ActiveTasksNum = {}
        self.m_ActiveTasksNum = m_ActiveTasksNum
    end
    m_ActiveTasksNum[ #m_ActiveTasksNum + 1 ] = { task, data }

    self:RunCurrentTask( task, "OnStart" )

    if not reason then -- This is an essential debugging tool, Use it.
        ErrorNoHaltWithStack( "NEXTBOT:StartTask called without reason! Task: " .. task .. "\n" )

    end

    -- additional debugging tool
    if not debugPrintTasks:GetBool() then return end

    print( self:GetCreationID(), task, self:GetEnemy(), reason ) --global

    self.taskHistory = self.taskHistory or {}

    table.insert( self.taskHistory, SysTime() .. " " .. task .. " " .. reason )

end


--[[------------------------------------
    Name: NEXTBOT:DoCustomTasks
    Desc: stub for entities based on this.
        Passes terminator tasks, so you can add new functionality/ai and just copy over the base reallystuck handler, enemy handler, etc
    Arg1: table | defaultTasks | Base terminator tasks
    Ret1: table | defaultTasks | 
--]]------------------------------------
function ENT:DoCustomTasks( _defaultTasks )
end

--[[
--DoCustomTasks example!
--keep all the default tasks, and add a custom movement task
function ENT:DoCustomTasks( defaultTasks )
    self.TaskList = {
        -- the important ones
        -- keep enemy handler, manages current enemy, finds new enemies, etc
        ["enemy_handler"] = defaultTasks["enemy_handler"],
        -- keep shooting handler, aiming
        ["shooting_handler"] = defaultTasks["shooting_handler"],
        -- keep awareness handler, keeps track of props nearby to the bot
        ["awareness_handler"] = defaultTasks["awareness_handler"],
        -- keep really stuck handler, fixes bots in task loops by restarting all movement tasks, and forcing bot to walk to a nearby navarea
        ["reallystuck_handler"] = defaultTasks["reallystuck_handler"],

        -- these ones are less important
        -- keep inform handler, used for informing other bots about current enemy
        ["inform_handler"] = defaultTasks["inform_handler"],
        -- handles player controlling
        ["playercontrol_handler"] = defaultTasks["playercontrol_handler"],
        -- generic movement task, makes bot wait a second then starts movement_handler
        ["movement_wait"] = defaultTasks["movement_wait"],

        -- custom movement starter
        ["movement_handler"] = {
            StartsOnInitialize = true, -- makes this task start on spawn
            OnStart = function( self, data )
                -- when this tasks starts
                -- maybe start movement_mycustomtask?
            end,
        },

        -- the actual CUSTOM TASK!
        ["movement_mycustomtask"] = {
            OnStart = function( self, data )
                -- when this tasks starts
            end,
            BehaveUpdateMotion = function( self, data )
                -- do something in the motion coroutine
            end,
            OnEnd = function( self, data )
                -- when this task ends
                -- maybe go back to movement_handler?
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
