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