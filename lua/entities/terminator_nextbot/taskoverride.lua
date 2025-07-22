local entMeta = FindMetaTable( "Entity" )
local isstring = isstring
local string_find = string.find
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

local debugPrintTasks = CreateConVar( "term_debugtasks", 0, FCVAR_NONE, "Debug terminator tasks? Also enables a task history dump on bot +use." )

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
    Arg3: string | reason | Reason for starting task, used for debugging.
--]]------------------------------------
function ENT:StartTask( task, data, reason )
    if self:IsTaskActive( task ) then return end
    yieldIfWeCan()

    if isstring( data ) then
        reason = data
        data = nil

    end

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
        ErrorNoHaltWithStack( "NEXTBOT:StartTask with NO reason!" .. task )

    end

    -- additional debugging tool
    if not debugPrintTasks:GetBool() then return end
    permaPrint( self:GetCreationID(), task, self:GetEnemy(), reason ) -- global

    if not string.find( task, "movement_" ) then return end -- only store history of movement tasks
    self.taskHistory = self.taskHistory or {}

    table.insert( self.taskHistory, SysTime() .. " " .. task .. " " .. reason )

end

-- dump task info on +use
-- only dump task history when the task debugger is true
function ENT:Use( user )
    if not user:IsPlayer() then return end
    if not debugPrintTasks:GetBool() then return end

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

end

function ENT:StartTask2( ... ) -- TODO: remove
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

--[[
--ENT.MyClassTask example!,
ENT.MyClassTask = {
    OnCreated = function( self )
        -- do something on creation, maybe set our color or a bodygroup?
    end,
    EnemyFound = function( self, data )
        -- do something on enemy found, maybe play a sound
    end,
    EnemyLost = function( self, data )
        -- do something else on enemy lost
    end,
    OnKilled = function( self, data )
        -- do something on death
    end,
}
--]]

-- handles adding class tasks
-- DO NOT OVERRIDE THIS ONE, OVERRIDE THE SetupClassTask ABOVE INSTEAD
-- searches entire base class tree, setting up the class task of every class in the tree
-- DO NOT OVERRIDE THESE
function ENT:DoClassTask( myTbl )
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
-- DO NOT OVERRIDE THESE, you can if you want, just adds spaghetti
function ENT:GetAllBaseClasses( myTbl )
    local fullTree = {}

    local reachedRoot = false
    local currClassName = myTbl.ClassName
    local currBaseSent = scripted_ents.GetStored( currClassName ).t
    local extent = 0
    while not reachedRoot do
        extent = extent + 1
        if extent > 100 then -- you never know
            break

        end
        if currBaseSent.Base == currClassName then
            reachedRoot = true
            break

        end

        fullTree[#fullTree + 1] = currBaseSent

        currClassName = currBaseSent.Base
        currBaseSent = scripted_ents.GetStored( currClassName ).t -- the next base class

    end

    return fullTree

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

    myTbl.DoCustomTasks( self, myTbl.TaskList )
    myTbl.DoClassTask( self, myTbl )

    local taskListStatic = myTbl.m_TaskList
    for k,v in pairs( myTbl.TaskList ) do
        taskListStatic[k] = v

    end

    for taskName, taskDat in pairs( self.TaskList ) do
        if taskDat.StartsOnInitialize then
            self:StartTask( taskName, nil, "StartsOnInitialize" )

        end
    end
end
