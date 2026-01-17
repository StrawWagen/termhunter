local entMeta = FindMetaTable( "Entity" )
local isstring = isstring
local string_find = string.find

--[[------------------------------------
    Name: NEXTBOT:RunTask
    Desc: Runs active tasks callbacks with given event.
    Arg1: string | event | Event of hook.
    Arg*: vararg | Arguments to callback. 
        NOTE: In callback, first argument is always bot entity, second argument is always task data, passed arguments from NEXTBOT:RunTask starts at third argument.
    Ret*: vararg | Callback return.
--]]------------------------------------

function ENT:RunTask( event, ... )
    local myTbl = entMeta.GetTable( self )
    local m_ActiveTasksNum = myTbl.m_ActiveTasksNum
    if not m_ActiveTasksNum then return end

    local hollowEvents = myTbl.m_HollowEventCache
    if hollowEvents and hollowEvents[event] then return end -- cached as hollow, no callbacks in here, cache is reset after some time, or when a new task is started below

    local m_TaskList = myTbl.m_TaskList
    local passedTasks = {}

    local wasCallback
    local k = 1
    while true do
        local currTask = m_ActiveTasksNum[k]
        if not currTask then break end -- no more tasks

        local task = currTask[1]

        if passedTasks[task] then -- already passed this task
            k = k + 1

            continue
        end
        passedTasks[task] = true

        local taskReal = m_TaskList[task]
        if not taskReal then continue end

        local callback = taskReal[event]

        if callback then
            wasCallback = true
            -- always yields every 2 'k'
            local data = currTask[2] -- task data
            local beforeCalledCount = #m_ActiveTasksNum
            local args = { callback( self, data, ... ) }

            if args[1] ~= nil then -- something was returned
                if args[2] == nil then -- only one argument returned
                    return args[1]

                else
                    return unpack( args )

                end
            end

            if #m_ActiveTasksNum == beforeCalledCount then continue end -- no tasks were added/removed, dont need to retrace
            while k > 0 do -- tasks were added/removed, retrace to find the current task
                local cv = m_ActiveTasksNum[k]
                if cv == currTask then break end

                k = k - 1

            end
        end

        k = k + 1

    end

    if not wasCallback then
        if not hollowEvents then
            hollowEvents = {}
            myTbl.m_HollowEventCache = hollowEvents
            local cacheTime = 2.5
            if myTbl.IsFodder then
                cacheTime = 10 -- fodder bots are not important, so we can cache them longer

            end
            timer.Simple( cacheTime, function()
                myTbl.m_HollowEventCache = nil -- reset cache eventually

            end )
        end
        if not hollowEvents[event] then
            hollowEvents[event] = true

        end
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
            self:TaskFail( taskName, "KillAllTasksWith" )

        end
    end
end

local printTasksCvar = CreateConVar( "term_debugtasks", 0, FCVAR_NONE, "Debug terminator tasks? Also enables a task history dump on bot +use." )
local printTasks = printTasksCvar:GetBool()
cvars.AddChangeCallback( "term_debugtasks", function( _, _, newValue )
    printTasks = tobool( newValue )
    if not printTasks then
        permaPrint( "Term task debugging disabled." )

    else
        permaPrint( "Term task debugging enabled." )

    end
end, "TerminatorDebugTasks" )

--[[------------------------------------
    Name: NEXTBOT:HasTask
    Desc: Checks if a task with the given name is in the tasklist.
    Arg1: string | taskName | Task name.
    Ret1: bool | Does the task exist?
--]]------------------------------------
function ENT:HasTask( taskName )
    return self.m_TaskList[taskName] ~= nil

end

--[[------------------------------------
    Name: NEXTBOT:StartTask
    Desc: Starts a task with given name and data.
    Arg1: string | task | Task name.
    Arg2: table | data | Task data.
    Arg3: string | reason | Reason for starting task, used for debugging, can also be passed as Arg2 if no data is needed.
--]]------------------------------------
function ENT:StartTask( task, data, reason )
    local myTbl = entMeta.GetTable( self )
    if myTbl.IsTaskActive( self, task ) then
        if printTasks then
            ErrorNoHaltWithStack( self, " tried to start already active task: ", task )

        end
        return

    end

    if isstring( data ) then -- if data is a string, it is the reason for starting the task
        reason = data
        data = nil

    end

    if not reason then -- This is an essential debugging tool, Use it.
        ErrorNoHaltWithStack( "NEXTBOT:StartTask with NO reason!" .. task )

    end

    data = data or {}
    data.taskStartTime = CurTime()
    data.myTaskName = task

    -- this might have been a mistake, really clutters the data table
    data.myTbl = myTbl -- store myTbl in data, so we can access it in task callbacks

    myTbl.m_ActiveTasks[task] = data

    local m_ActiveTasksNum = myTbl.m_ActiveTasksNum
    if not m_ActiveTasksNum then
        m_ActiveTasksNum = {}
        myTbl.m_ActiveTasksNum = m_ActiveTasksNum
    end
    m_ActiveTasksNum[ #m_ActiveTasksNum + 1 ] = { task, data }

    myTbl.m_HollowEventCache = nil -- reset hollow event cache

    if printTasks then
        permaPrint( self:GetCreationID(), task, self:GetEnemy(), reason ) -- print before calling OnStart, so they're in chronological order

    end

    myTbl.RunCurrentTask( self, task, "OnStart" )

    if not printTasks then return end
    if not string.find( task, "movement_" ) then return end -- only store history of movement tasks

    -- yes, memory leak, never activates under normal circumstances tho, only if term_debugtasks is 1
    myTbl.taskHistory = myTbl.taskHistory or {}

    table.insert( myTbl.taskHistory, SysTime() .. " " .. task .. " " .. reason )

end

-- dump task info on +use
-- only dump task history when the task debugger is true
function ENT:Use( user )
    if not printTasks then return end
    if not user:IsPlayer() then return end

    if ( self.nextCheatUse or 0 ) > CurTime() then return end
    self.nextCheatUse = CurTime() + 1

    local fourSpaces = "    "

    self.taskHistory = self.taskHistory or {}
    permaPrint( "taskhistory" )
    permaPrintTable( self.taskHistory )
    permaPrint( "activetasks", self )
    for taskName, _ in pairs( self.m_ActiveTasks ) do
        permaPrint( fourSpaces .. taskName )

    end
    permaPrint( "lastShootType", self.lastShootingType )
    permaPrint( "lastPathKillReason", self.lastPathInvalidateReason )
    permaPrint( "lastLadderLeaveReason", self.lastLadderLeaveStack )
    permaPrint( "lastYield", self.lastYieldLocation )

end

function ENT:StartTask2( ... ) -- TODO: remove, last addon that still uses this is supercop
    --ErrorNoHaltWithStack()
    self:StartTask( ... )

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
    ENT.MyClassTask
    Desc: Simple way to add class-specific behaviour to a bot.
    Fully compatible with baseclassing. ( the class tasks, of base classes, will also be added )
    NOT FOR ADDING MOVEMENT TASKS, USE DoCustomTasks INSTEAD. ( they're much more complex to get right )
--]]------------------------------------
ENT.MyClassTask = nil

-- see readme for a nearly full list of possible callbacks

-- handles adding class tasks
-- DO NOT OVERRIDE THIS ONE, OVERRIDE THE ENT.MyClassTask ABOVE INSTEAD
-- searches entire base class tree, setting up the ENT.MyClassTask of every class in the tree
-- DO NOT OVERRIDE THESE
function ENT:DoClassTasks( myTbl )
    local sentsToDo = myTbl.GetAllBaseClasses( self, myTbl )

    for _, sentTbl in ipairs( sentsToDo ) do
        local classTask = sentTbl.MyClassTask

        if not classTask then continue end
        if table.Count( classTask ) == 0 then continue end

        -- class tasks always start on initialize
        classTask.StartsOnInitialize = true

        local className = sentTbl.ClassName .. "_handler"
        self.TaskList[className] = classTask

    end
end

--[[------------------------------------
    Name: ENT:SetupTasks
    Desc: Sets up all tasks for the entity.
    add .StartsOnInitialize = true to task tbl to make it start on spawn.
    Override at your own risk.
    Ret1:
--]]------------------------------------
function ENT:SetupTasks( myTbl )
    myTbl.DoDefaultTasks( self ) -- terminator tasks, so everything can use the same enemy handler, shooting handler, etc

    myTbl.DoCustomTasks( self, myTbl.TaskList ) -- override terminator tasks, create a new brain
    myTbl.DoClassTasks( self, myTbl ) -- adds class-specific behaviour for every class in the baseclass tree

    local taskListStatic = myTbl.m_TaskList
    for k,v in pairs( myTbl.TaskList ) do
        taskListStatic[k] = v

    end

    for taskName, taskDat in pairs( self.TaskList ) do
        if printTasks and taskDat.StopsWhenPlayerControlled and string.StartsWith( taskName, "movement_" ) then
            print( "movement task, " .. taskName .. " initialized with unnecessary taskDat.StopsWhenPlayerControlled" )

        end
        if taskDat.StartsOnInitialize then
            self:StartTask( taskName, nil, "StartsOnInitialize" )

        end
    end
end

--[[------------------------------------
    Name: NEXTBOT:AddTask
    Desc: Add a task to the bot's task list, after setup.
    Arg1: string | taskName | Task name.
    Arg2: table  | taskDat | Task data.
    Ret1:
--]]------------------------------------
function ENT:AddTask( taskName, task )
    local myTbl = entMeta.GetTable( self )
    myTbl.TaskList[taskName] = task

    local taskListStatic = myTbl.m_TaskList
    taskListStatic[taskName] = task

    if task.StartsOnInitialize then
        self:StartTask( taskName, nil, "AddTask-StartsOnInitialize" )

    end
end