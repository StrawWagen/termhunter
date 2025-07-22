-- Lua analogs to engine weapons
local EngineAnalogs = {
	weapon_ar2 = "weapon_ar2_term",
	weapon_smg1 = "weapon_smg1_term",
	weapon_pistol = "weapon_pistol_term",
	weapon_357 = "weapon_357_term",
	weapon_crossbow = "weapon_crossbow_term",
	weapon_rpg = "weapon_rpg_term",
	weapon_shotgun = "weapon_shotgun_term",
	weapon_crowbar = "weapon_crowbar_term",
	weapon_stunstick = "weapon_stunstick_term",
}

local EngineAnalogsReverse = {}
for k,v in pairs(EngineAnalogs) do EngineAnalogsReverse[v] = k end

--[[------------------------------------
	Name: NEXTBOT:ReloadWeaponData
	Desc: (INTERNAL) Reloads weapon data like burst and reload settings.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:ReloadWeaponData()
	self.m_WeaponData = {
		Primary = {
			BurstBullets = -1,
			BurstBullet = 0,
			NextShootTime = 0,
		},
		Secondary = {
			NextShootTime = 0,
		},
		NextReloadTime = 0,
	}
end

--[[------------------------------------
	Name: NEXTBOT:CanWeaponPrimaryAttack
	Desc: Returns can bot do primary attack or not.
	Arg1: 
	Ret1: bool | Can do primary attack
--]]------------------------------------
function ENT:CanWeaponPrimaryAttack()
	if !self:HasWeapon() or CurTime()<self.m_WeaponData.Primary.NextShootTime then return false end
	
	local wep = self:GetActiveLuaWeapon()
	if CurTime()<wep:GetNextPrimaryFire() then return false end

	return true
end

--[[------------------------------------
	Name: NEXTBOT:WeaponPrimaryAttack
	Desc: Does primary attack from bot's active weapon. This also uses burst data from weapon.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:WeaponPrimaryAttack()
	if !self:CanWeaponPrimaryAttack() then return end
	
	local wep = self:GetActiveLuaWeapon()
	local data = self.m_WeaponData.Primary
	
	ProtectedCall(function() wep:NPCShoot_Primary(self:GetShootPos(),self:GetAimVector()) end)
	self:DoRangeGesture()
	
	if self:ShouldWeaponAttackUseBurst(wep) then
		local bmin,bmax,frate = wep:GetNPCBurstSettings()
		local rmin,rmax = wep:GetNPCRestTimes()
		
		if data.BurstBullets==-1 then
			data.BurstBullets = math.random(bmin,bmax)
		end
		
		data.BurstBullet = data.BurstBullet+1
		
		if data.BurstBullet>=data.BurstBullets then
			data.BurstBullets = -1
			data.BurstBullet = 0
			data.NextShootTime = math.max(CurTime()+math.Rand(rmin,rmax),data.NextShootTime)
		else
			data.NextShootTime = math.max(CurTime()+frate,data.NextShootTime)
		end
	else
		local bmin,bmax,frate = wep:GetNPCBurstSettings()
		data.NextShootTime = math.max(CurTime()+frate,data.NextShootTime)
	end
end

--[[------------------------------------
	Name: NEXTBOT:CanWeaponSecondaryAttack
	Desc: Returns can bot do secondary attack or not.
	Arg1: 
	Ret1: bool | Can do secondary attack
--]]------------------------------------
function ENT:CanWeaponSecondaryAttack()
	if !self:HasWeapon() or CurTime()<self.m_WeaponData.Secondary.NextShootTime then return false end
	
	local wep = self:GetActiveLuaWeapon()
	if CurTime()<wep:GetNextSecondaryFire() then return false end

	return true
end

--[[------------------------------------
	Name: NEXTBOT:WeaponSecondaryAttack
	Desc: Does secondary attack from bot's active weapon.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:WeaponSecondaryAttack()
	if !self:CanWeaponSecondaryAttack() then return end
	
	local wep = self:GetActiveLuaWeapon()
	
	ProtectedCall(function() wep:NPCShoot_Secondary(self:GetShootPos(),self:GetAimVector()) end)
	self:DoRangeGesture()
end

--[[------------------------------------
	Name: NEXTBOT:DoRangeGesture
	Desc: Make primary attack range animation.
	Arg1: 
	Ret1: number | Animation duration.
--]]------------------------------------
function ENT:DoRangeGesture()
	local act = self:TranslateActivity(ACT_MP_ATTACK_STAND_PRIMARYFIRE)
	local seq = self:SelectWeightedSequence(act)
	
	self:DoGesture(act)
	
	return self:SequenceDuration(seq)
end

--[[------------------------------------
	Name: NEXTBOT:DoReloadGesture
	Desc: Make reload animation.
	Arg1: 
	Ret1: number | Animation duration.
--]]------------------------------------
function ENT:DoReloadGesture()
	local act = self:TranslateActivity(ACT_MP_RELOAD_STAND)
	local seq = self:SelectWeightedSequence(act)
	
	self:DoGesture(act)
	
	return self:SequenceDuration(seq)
end

--[[------------------------------------
	Name: NEXTBOT:WeaponReload
	Desc: Reloads active weapon and do reload animation. Does nothing if we reloading already or if weapon clip is full.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:WeaponReload()
	if !self:HasWeapon() then return end
	
	local wep = self:GetActiveLuaWeapon()
	if wep:Clip1()>=wep:GetMaxClip1() then return end
	if CurTime()<self.m_WeaponData.NextReloadTime then return end
	
	wep:SetClip1(wep:GetMaxClip1())
	
	local time = CurTime()+self:DoReloadGesture()
	
	self.m_WeaponData.Primary.NextShootTime = math.max(time,self.m_WeaponData.Primary.NextShootTime)
	self.m_WeaponData.Secondary.NextShootTime = math.max(time,self.m_WeaponData.Secondary.NextShootTime)
	self.m_WeaponData.NextReloadTime = time
end

--[[------------------------------------
	Name: NEXTBOT:SetCurrentWeaponProficiency
	Desc: Sets how skilled bot with weapons. See WEAPON_PROFICIENCY_ Enums.
	Arg1: number | prof | Weapon proficiency
	Ret1: 
--]]------------------------------------
function ENT:SetCurrentWeaponProficiency(prof)
	self.m_WeaponProficiency = prof
end

--[[------------------------------------
	Name: NEXTBOT:GetCurrentWeaponProficiency
	Desc: Returns how skilled bot with weapons. See WEAPON_PROFICIENCY_ Enums.
	Arg1: 
	Ret1: number | Weapon proficiency
--]]------------------------------------
function ENT:GetCurrentWeaponProficiency()
	return self.m_WeaponProficiency or WEAPON_PROFICIENCY_GOOD
end

--[[------------------------------------
	Name: NEXTBOT:OnWeaponEquip
	Desc: Called when bot equips weapon.
	Arg1: Entity | wep | Equiped weapon. It will be not lua analog.
	Ret1: 
--]]------------------------------------
function ENT:OnWeaponEquip(wep)
	self:RunTask("OnWeaponEquip",wep)
end

--[[------------------------------------
	Name: NEXTBOT:OnWeaponDrop
	Desc: Called when bot drops weapon.
	Arg1: Entity | wep | Dropped weapon. It will be not lua analog.
	Ret1: 
--]]------------------------------------
function ENT:OnWeaponDrop(wep)
	self:RunTask("OnWeaponDrop",wep)
end

--[[------------------------------------
	Name: NEXTBOT:CanPickupWeapon
	Desc: Returns can we pickup this weapon.
	Arg1: Entity | wep | Entity to test. Not necessary Weapon entity.
	Ret1: bool | Can pickup or not.
--]]------------------------------------
function ENT:CanPickupWeapon(wep)
	return wep:IsWeapon() and IsValid(wep) and (wep:IsScripted() and wep.CanBePickedUpByNPCs and wep:CanBePickedUpByNPCs() or EngineAnalogs[wep:GetClass()]) and !IsValid(wep:GetOwner()) or false
end

--[[------------------------------------
	Name: NEXTBOT:CanDropWeaponOnDie
	Desc: Decides can bot drop weapon on death. NOTE: Weapon also may not drop even with `true` if weapon's `SWEP:ShouldDropOnDie` returns `false`.
	Arg1: Weapon | wep | Current active weapon (this will be lua analog for engine weapon).
	Ret1: bool | Can drop.
--]]------------------------------------
function ENT:CanDropWeaponOnDie(wep)
	return !self:HasSpawnFlags(SF_NPC_NO_WEAPON_DROP)
end

--[[------------------------------------
	Name: NEXTBOT:ShouldWeaponAttackUseBurst
	Desc: Decides should bot shoot with bursts.
	Arg1: Weapon | wep | Current active weapon (this will be lua analog for engine weapon).
	Ret1: bool | Should use bursts.
--]]------------------------------------
function ENT:ShouldWeaponAttackUseBurst(wep)
	return !self:IsControlledByPlayer()
end

--[[------------------------------------
	Name: NEXTBOT:IsMeleeWeapon
	Desc: Returns true if weapon marked as for melee attacks (using CAP_* Enums).
	Arg1: (optional) Weapon | wep | Weapon to check (this should be lua analog for engine weapon). Without passing will be used active weapon.
	Ret1: bool | Weapon is melee weapon.
--]]------------------------------------
function ENT:IsMeleeWeapon(wep)
	wep = wep or self:GetActiveLuaWeapon()
	
	return IsValid(wep) and wep.GetCapabilities and bit.band(wep:GetCapabilities(),CAP_WEAPON_MELEE_ATTACK1)!=0 or false
end