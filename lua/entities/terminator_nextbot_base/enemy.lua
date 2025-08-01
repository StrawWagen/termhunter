local INT_MIN = -2147483648
local DEF_RELATIONSHIP_PRIORITY = INT_MIN

--[[------------------------------------
	Name: NEXTBOT:SetEnemy
	Desc: Sets active enemy of bot.
	Arg1: Entity | enemy | Enemy to set.
	Ret1: 
--]]------------------------------------
function ENT:SetEnemy(enemy)
	self.m_Enemy = enemy
end

--[[------------------------------------
	Name: NEXTBOT:GetEnemy
	Desc: Returns active enemy of bot.
	Arg1: 
	Ret1: Entity | Enemy
--]]------------------------------------
function ENT:GetEnemy()
	return self.m_Enemy or NULL
end

--[[------------------------------------
	Name: NEXTBOT:SetClassRelationship
	Desc: Sets how bot feels towards entities with that class.
	Arg1: string | class | Entities classname
	Arg2: number | d | Disposition. See D_* Enums
	Arg3: (optional) number | priority | How strong relationship is.
	Ret1: 
--]]------------------------------------
function ENT:SetClassRelationship(class,d,priority)
	self.m_ClassRelationships[class] = {d,priority or DEF_RELATIONSHIP_PRIORITY}
end

--[[------------------------------------
	Name: NEXTBOT:Term_SetEntityRelationship
	Desc: Sets how bot feels towards entity.
	Arg1: Entity | ent | Entity to apply relationship
	Arg2: number | d | Disposition. See D_* Enums
	Arg3: (optional) number | priority | How strong relationship is.
	Ret1: 
--]]------------------------------------
function ENT:Term_SetEntityRelationship(ent,d,priority)
	if not self.m_EntityRelationships then return end
	self.m_EntityRelationships[ent] = {d,priority or DEF_RELATIONSHIP_PRIORITY}
end

--[[------------------------------------
	Name: NEXTBOT:GetRelationship
	Desc: Returns how bot feels about this entity.
	Arg1: Entity | ent | Entity to get disposition from.
	Ret1: number | Priority disposition. See D_* Enums.
	Ret2: number | Priority of disposition.
--]]------------------------------------
function ENT:GetRelationship(ent)
	local d,priority
	
	local entr = self.m_EntityRelationships[ent]
	if entr and (!priority or entr[2]>priority) then
		d,priority = entr[1],entr[2]
	end
	
	local classr = self.m_ClassRelationships[ent:GetClass()]
	if classr and (!priority or classr[2]>priority) then
		d,priority = classr[1],classr[2]
	end
	
	return d or D_NU,priority or DEF_RELATIONSHIP_PRIORITY
end

--[[------------------------------------
	Name: NEXTBOT:UpdateEnemyMemory
	Desc: Updates bot's memory of this enemy.
	Arg1: Entity | enemy | Enemy to update.
	Arg2: Vector | pos | Position where bot see enemy.
	Ret1: 
--]]------------------------------------
function ENT:UpdateEnemyMemory(enemy,pos)
	self.m_EnemiesMemory[enemy] = self.m_EnemiesMemory[enemy] or {}
	self.m_EnemiesMemory[enemy].lastupdate = CurTime()
	self.m_EnemiesMemory[enemy].pos = pos
end

--[[------------------------------------
	Name: NEXTBOT:ClearEnemyMemory
	Desc: Clears bot memory of this enemy.
	Arg1: (optional) Entity | enemy | Enemy to clear memory of. If unset, will be used NEXTBOT:GetEnemy 
	Ret1: 
--]]------------------------------------
function ENT:ClearEnemyMemory(enemy)
	enemy = enemy or self:GetEnemy()
	self.m_EnemiesMemory[enemy] = nil
	
	if self:GetEnemy()==enemy then
		self:SetEnemy(NULL)
	end
end

--[[------------------------------------
	Name: NEXTBOT:FindEnemies
	Desc: Finds all enemies that can be seen from bot position and updates memory.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:FindEnemies()
	local ShouldBeEnemy = self.ShouldBeEnemy
	local CanSeePosition = self.CanSeePosition
	local UpdateEnemyMemory = self.UpdateEnemyMemory
	local EntShootPos = self.EntShootPos

	for k,v in ents.Iterator() do
		if v==self or !ShouldBeEnemy(self,v) or !CanSeePosition(self,v) then continue end
		
		UpdateEnemyMemory(self,v,EntShootPos(self,v))
	end
end

--[[------------------------------------
	Name: NEXTBOT:GetKnownEnemies
	Desc: Returns all entities that in bot's enemy memory.
	Arg1: 
	Ret1: table | Enemies table
--]]------------------------------------
function ENT:GetKnownEnemies()
	local t = {}
	
	for k,v in pairs(self.m_EnemiesMemory) do
		if IsValid(k) and self:ShouldBeEnemy(k) then
			table.insert(t,k)
		end
	end
	
	return t
end

--[[------------------------------------
	Name: NEXTBOT:GetLastEnemyPosition
	Desc: Returns last updated position of enemy.
	Arg1: Entity | enemy | Enemy to get position.
	Ret1: Vector | Last known position. Returns nil if enemy is not in bot memory.
--]]------------------------------------
function ENT:GetLastEnemyPosition(enemy)
	return self.m_EnemiesMemory[enemy] and self.m_EnemiesMemory[enemy].pos
end

--[[------------------------------------
	Name: NEXTBOT:HaveEnemy
	Desc: Returns if bot have enemy.
	Arg1: 
	Ret1: bool | Bot have enemy or not.
--]]------------------------------------
function ENT:HaveEnemy()
	local enemy = self:GetEnemy()
	return IsValid(enemy) and self:ShouldBeEnemy(enemy)
end

--[[------------------------------------
	Name: NEXTBOT:ForgetOldEnemies
	Desc: (INTERNAL) Clears bot memory from enemies that not valid, not updating very long time or not should be enemy.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:ForgetOldEnemies()
	for k,v in pairs(self.m_EnemiesMemory) do
		if !IsValid(k) or CurTime()-v.lastupdate>=self.ForgetEnemyTime or !self:ShouldBeEnemy(k) then
			self:ClearEnemyMemory(k)
		end
	end
end