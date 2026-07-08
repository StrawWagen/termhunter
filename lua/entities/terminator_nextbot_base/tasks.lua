
--[[------------------------------------
	Name: NEXTBOT:SetupTaskList
	Desc: Used to setup bot's list of tasks.
	Arg1: table | list | List of tasks add new tasks to.
	Ret1: 
--]]------------------------------------
function ENT:SetupTaskList( list )
end

--[[------------------------------------
	Name: NEXTBOT:SetupTasks
	Desc: Used to start behaviour tasks on spawn
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:SetupTasks()
end

-- If a task callback returned a value ( non-nil first return ), pass it back up.
-- Shared by RunCurrentTask, mirrors the same logic in RunTask.
local function unpackTaskReturn( args )
	if args[1] == nil then return end
	if args[2] == nil then return args[1] end
	return unpack( args )

end

-- Removes a task from both the lookup table and the ordered list.
local function removeActiveTask( self, task )
	self.m_ActiveTasks[task] = nil

	local m_ActiveTasksNum = self.m_ActiveTasksNum
	for i = 1, #m_ActiveTasksNum do
		if m_ActiveTasksNum[i][1] == task then
			table.remove( m_ActiveTasksNum, i )
			break

		end
	end
end

-- Shared body of TaskComplete/TaskFail: run the end event ( OnComplete or OnFail ),
-- then OnEnd, then delete the task. Callbacks run while the task is still active.
local function endTask( self, task, endEvent )
	if !self:IsTaskActive( task ) then return end

	self:RunCurrentTask( task, endEvent )
	self:RunCurrentTask( task, "OnEnd" )

	removeActiveTask( self, task )

end

--[[------------------------------------
	Name: NEXTBOT:RunCurrentTask
	Desc: Runs one given task callback with given event.
	Arg1: any | task | Task name.
	Arg2: string | event | Event of hook.
	Arg*: vararg | Arguments to callback. NOTE: In callback, first argument is always bot entity, second argument is always task data, passed arguments from NEXTBOT:RunTask starts at third argument.
	Ret*: vararg | Callback return.
--]]------------------------------------
function ENT:RunCurrentTask( task, event, ... )
	if !self:IsTaskActive( task ) then return end

	local data = self.m_ActiveTasks[task]

	local dt = self.m_TaskList[task]
	if !dt or !dt[event] then return end

	return unpackTaskReturn( { dt[event]( self, data, ... ) } )

end

--[[------------------------------------
	Name: NEXTBOT:TaskComplete
	Desc: Calls 'OnComplete' and 'OnEnd' task callbacks and deletes task. Does nothing if given task not started.
	Arg1: any | task | Task name.
	Ret1: 
--]]------------------------------------
function ENT:TaskComplete( task )
	endTask( self, task, "OnComplete" )

end

--[[------------------------------------
	Name: NEXTBOT:TaskFail
	Desc: Calls 'OnFail' and 'OnEnd' task callbacks and deletes task. Does nothing if given task is not started.
	Arg1: any | task | Task name.
	Ret1: 
--]]------------------------------------
function ENT:TaskFail( task )
	endTask( self, task, "OnFail" )

end

--[[------------------------------------
	Name: NEXTBOT:IsTaskActive
	Desc: Returns whenever given task exists or not.
	Arg1: any | task | Task name.
	Ret1: bool | Returns true if task exists, false otherwise.
--]]------------------------------------
function ENT:IsTaskActive( task )
	return self.m_ActiveTasks[task] and true or false

end
