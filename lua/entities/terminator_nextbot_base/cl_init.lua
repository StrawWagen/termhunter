include("shared.lua")

local entMeta = FindMetaTable("Entity")

--[[------------------------------------
	NEXTBOT:Initialize
	Initialize our bot
--]]------------------------------------
function ENT:Initialize()
	local myTbl = entMeta.GetTable( self )
	myTbl.SetupSpecialActions( self, myTbl )

	myTbl.m_TaskList = {}
	myTbl.m_ActiveTasks = {}
	myTbl.m_ActiveTasksID = {}

	myTbl.SetupTaskList( self, myTbl.m_TaskList )
	myTbl.SetupTasks( self )
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
