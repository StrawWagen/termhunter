
--[[------------------------------------
	NEXTBOT:BehaveStart
	Creating behaviour thread using NEXTBOT:BehaviourCoroutine. Also setups task list and default tasks.
--]]------------------------------------
function ENT:BehaveStart()
	self:SetupCollisionBounds()

	self:SetupTaskList(self.m_TaskList)
	self:SetupTasks()

	self.BehaviourThread = coroutine.create(function() self:BehaviourCoroutine() end)
end

--[[------------------------------------
	Name: NEXTBOT:BehaviourCoroutine
	Desc: Override this function to control bot using coroutine type.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:BehaviourCoroutine()
	while true do
		coroutine.yield()
	end
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesAdd
	Desc: Adds a capability to the bot.
	Arg1: number | cap | Capabilities to add. See CAP_ Enums
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesAdd(cap)
	self.m_Capabilities = bit.bor(self.m_Capabilities,cap)
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesClear
	Desc: Clears all capabilities of bot.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesClear()
	self.m_Capabilities = 0
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesGet
	Desc: Returns all capabilities including weapon capabilities.
	Arg1: 
	Ret1: number | Capabilities. See CAP_ Enums
--]]------------------------------------
function ENT:CapabilitiesGet()
	return bit.bor(self.m_Capabilities,self:HasWeapon() and self:GetActiveLuaWeapon():GetCapabilities() or 0)
end

--[[------------------------------------
	Name: NEXTBOT:CapabilitiesRemove
	Desc: Removes capability from bot.
	Arg1: number | cap | Capabilities to remove. See CAP_ Enums
	Ret1: 
--]]------------------------------------
function ENT:CapabilitiesRemove(cap)
	self.m_Capabilities = bit.bxor(bit.bor(self.m_Capabilities,cap),cap)
end