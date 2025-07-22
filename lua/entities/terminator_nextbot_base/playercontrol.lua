
local entMeta = FindMetaTable("Entity")
local plyMeta = FindMetaTable("Player")
local IsValid = IsValid

local function GetControlledBot(ply)
	local bot = ply:GetDrivingEntity()
	
	if IsValid(bot) and bot.TerminatorNextBot then
		return bot
	end
end

--[[------------------------------------
	Name: NEXTBOT:IsControlledByPlayer
	Desc: Returns true if bot currently controlled by player.
	Arg1: 
	Ret1: bool | Is bot controlled by player or not
--]]------------------------------------
function ENT:IsControlledByPlayer( myTbl )
	myTbl = myTbl or entMeta.GetTable( self )
	local ply = myTbl.GetControlPlayer( self )
	if !IsValid( ply ) then return false end

	if plyMeta.GetDrivingEntity( ply ) != self then
		self:StopControlByPlayer()
		return false

	end

	return true
end

--[[------------------------------------
	Name: NEXTBOT:StartControlByPlayer
	Desc: Starts bot control by player.
	Arg1: Player | ply | Who will control bot
	Ret1: 
--]]------------------------------------
function ENT:StartControlByPlayer(ply)
	self:SetControlPlayer(ply)
	self.m_ControlPlayerOldButtons = 0
	self.m_ControlPlayerButtons = 0
	self:ReloadWeaponData()

	self.PreventShooting = nil

	self:RunTask( "StartControlByPlayer", ply )

	-- kill all movement tasks
	self:KillAllTasksWith( "movement" )
end

--[[------------------------------------
	Name: NEXTBOT:StopControlByPlayer
	Desc: Stops bot control by player.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:StopControlByPlayer()
	local ply = self:GetControlPlayer()
	self:SetControlPlayer(NULL)
	
	self:RunTask("StopControlByPlayer",ply)
end

--[[------------------------------------
	Name: NEXTBOT:ControlPlayerKeyDown
	Desc: Returns true if key of player who controls bot is downed.
	Arg1: number | key | Key. See IN_ Enums
	Ret1: bool | Key is downed
--]]------------------------------------
function ENT:ControlPlayerKeyDown(key)
	return bit.band(self.m_ControlPlayerButtons,key)==key
end

--[[------------------------------------
	Name: NEXTBOT:ControlPlayerKeyPressed
	Desc: Returns true if player who controls bot has pressed given key at this bot behaviour tick.
	Arg1: number | key | Key. See IN_ Enums
	Ret1: bool | Key is pressed
--]]------------------------------------
function ENT:ControlPlayerKeyPressed(key)
	return self:ControlPlayerKeyDown(key) and bit.band(self.m_ControlPlayerOldButtons,key)!=key
end

-- Weapon drop
hook.Add("PlayerButtonDown","TerminatorNextBotControl",function(ply,btn)
	local bot = GetControlledBot(ply)
	
	if bot then
		if btn==KEY_G then
			bot:DropWeapon()
		end
	end
end)
