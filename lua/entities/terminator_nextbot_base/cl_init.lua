include("shared.lua")

local entMeta = FindMetaTable("Entity")

--[[------------------------------------
	NEXTBOT:Initialize
	Initialize our bot
--]]------------------------------------
function ENT:Initialize()
	self.m_TaskList = {}
	self.m_ActiveTasks = {}
	self.m_ActiveTasksID = {}

	self:SetupTaskList(self.m_TaskList)
	self:SetupTasks()
end

--[[------------------------------------
	NEXTBOT:Draw
	Draw bot, more optimized than base nextbot DrawModel
--]]------------------------------------
function ENT:Draw()
	entMeta.DrawModel( self )
end

-- Handles Player Control methods
include("cl_playercontrol.lua")
include("drive.lua")

-- Handle Tasks methods
include("tasks.lua")
