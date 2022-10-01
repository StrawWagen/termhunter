AddCSLuaFile()

if SERVER then
	util.AddNetworkString("weapon_terminatorfists_sb_anb")
else
    language.Add("weapon_terminatorfists_sb_anb","Terminator's Fists")
	killicon.AddFont("weapon_terminatorfists_sb_anb","HL2MPTypeDeath","",Color(255,80,0))
end

SWEP.PrintName = "Terminator Fists"
SWEP.Spawnable = false
SWEP.Author = "StrawWagen"
SWEP.Purpose = "Innate weapon that the terminator hunter will use"

SWEP.Range	= 80
SWEP.Weight = 1

local SwingSound = Sound( "WeaponFrag.Throw" )
local HitSound = Sound( "Flesh.ImpactHard" )

SWEP.Primary = {
	Ammo = "None",
	ClipSize = -1,
	DefaultClip = -1,
}

SWEP.Secondary = {
	Ammo = "None",
	ClipSize = -1,
	DefaultClip = -1,
}

local function DoorHitSound( ent )
	ent:EmitSound("ambient/materials/door_hit1.wav", 100, math.random(80, 120))
end
local function BreakSound( ent )
	local Snd = "physics/wood/wood_furniture_break" .. tostring(math.random(1, 2)) .. ".wav"
	ent:EmitSound(Snd, 110, math.random(80, 90))
end

function SWEP:MakeDoor( ent )
	local vel = self:GetForward() * 4800
	pos = ent:GetPos()
	ang = ent:GetAngles()
	mdl = ent:GetModel()
	ski = ent:GetSkin()
	ent:SetNotSolid(true)
	ent:SetNoDraw(true)
	prop = ents.Create("prop_physics")
	prop:SetPos(pos)
	prop:SetAngles(ang)
	prop:SetModel(mdl)
	prop:SetSkin(ski or 0)
	prop:Spawn()
	prop:SetVelocity( vel )
	prop:GetPhysicsObject():ApplyForceOffset( vel, self:GetPos() )
	prop:SetPhysicsAttacker( self )
	DoorHitSound( prop )
	BreakSound( prop )
	print( "door" )
end

function SWEP:HandleDoor( tr )
	if CLIENT or not IsValid(tr.Entity) then return end
	local ent = tr.Entity
	if ent:GetClass() == "func_door_rotating" or ent:GetClass() == "prop_door_rotating" then
		local HitCount = ent.PunchedCount or 0
		ent.PunchedCount = HitCount + 1 

		if HitCount > 6 then
			BreakSound( ent )
		end
		if HitCount >= 8 then
			self:MakeDoor( ent )
		elseif HitCount < 8 then
			DoorHitSound( ent )

			local newname = "TFABash" .. self:EntIndex()
			self.PreBashName = self:GetName()
			self:SetName(newname)

			if ent.bashCount == nil or not isnumber( ent.bashCount ) then 
				ent.bashCount = 0 
			end 

			ent.bashCount = ent.bashCount + 1

			if ( ent.bashCount % 3 ) == 2 then
				ent:Use( self.Owner, self.Owner )
			end

			ent:SetKeyValue("Speed", "500")
			ent:SetKeyValue("opendir", 0)
			ent:Fire("unlock", "", .01)
			ent:Fire("openawayfrom", newname, .01)

			timer.Simple(0.02, function()
				if not IsValid(self) or self:GetName() ~= newname then return end

				self:SetName(self.PreBashName)
			end)

			timer.Simple(0.3, function()
				if IsValid(ent) then
					ent:SetKeyValue("Speed", "100")
				end
			end)
		end
	end
end


function SWEP:Initialize()
	self:SetHoldType("fist")
	
	if CLIENT then self:SetNoDraw(true) end
end

function SWEP:CanPrimaryAttack()
	return CurTime() > self:GetNextPrimaryFire()
end

function SWEP:CanSecondaryAttack()
	return false
end

local vec3_origin		= vector_origin

function SWEP:PrimaryAttack()
	if not self:CanPrimaryAttack() then return end
	
	local owner = self:GetOwner()
	
	self:DealDamage()
	
	self:SetClip1(self:Clip1()-1)
	self:SetNextPrimaryFire(CurTime()+0.4)
	self:SetLastShootTime()
end

local phys_pushscale = GetConVar( "phys_pushscale" )

function SWEP:DealDamage()

	local anim = self:GetSequenceName(self:GetSequence())

	local tr = util.TraceLine( {
		start = self.Owner:GetShootPos(),
		endpos = self.Owner:GetShootPos() + self.Owner:GetAimVector() * self.Range,
		filter = self.Owner,
		mask = MASK_SOLID + CONTENTS_HITBOX,
	} )

	if ( !IsValid( tr.Entity ) ) then
		tr = util.TraceHull( {
			start = self.Owner:GetShootPos(),
			endpos = self.Owner:GetShootPos() + self.Owner:GetAimVector() * self.Range,
			filter = self.Owner,
			mins = Vector( -10, -10, -8 ),
			maxs = Vector( 10, 10, 8 ),
			mask = MASK_SOLID + CONTENTS_HITBOX,
		} )
	end

	local hit = false
	local scale = phys_pushscale:GetFloat() * 3

	if SERVER and IsValid( tr.Entity ) then
		local Class = tr.Entity:GetClass()
		local IsGlass = Class == "func_breakable_surf"
		if IsGlass then
			tr.Entity:Fire( "Shatter", tr.HitPos )
		elseif tr.Entity:IsNPC() or tr.Entity:IsPlayer() or tr.Entity:Health() > 0 then
			local dmginfo = DamageInfo()

			local attacker = self.Owner
			if ( !IsValid( attacker ) ) then attacker = self end
			dmginfo:SetAttacker( attacker )

			dmginfo:SetInflictor( self )
			dmginfo:SetDamage( math.random( 50, 60 ) )
			dmginfo:SetDamageForce( self.Owner:GetForward() * 9998 * scale ) 
				

			SuppressHostEvents( NULL ) -- Let the breakable gibs spawn in multiplayer on client
			tr.Entity:TakeDamageInfo( dmginfo )
			SuppressHostEvents( self.Owner )

			hit = true
		end
		self:HandleDoor( tr )
	end

	if ( IsValid( tr.Entity ) ) then
        self:EmitSound( HitSound )
        self:EmitSound( "physics/flesh/flesh_strider_impact_bullet1.wav", 80, math.random( 130, 160 ), 1, CHAN_STATIC )
		local phys = tr.Entity:GetPhysicsObject()
		if ( IsValid( phys ) ) then
			phys:ApplyForceOffset( self.Owner:GetForward() * 80 * phys:GetMass() * scale, tr.HitPos )
		end
    else
        self:EmitSound( SwingSound )
        self:EmitSound( "weapons/slam/throw.wav", 80, 80 )
    end
end

function SWEP:SecondaryAttack()
	if !self:CanSecondaryAttack() then return end
end

function SWEP:DoMuzzleFlash()
end

function SWEP:Equip()
end

function SWEP:OwnerChanged()
end

function SWEP:OnDrop()
end

function SWEP:Reload()
end

function SWEP:CanBePickedUpByNPCs()
	return true
end

function SWEP:GetNPCBulletSpread(prof)
	local spread = {0,0,0,0,0}
	return spread[prof+1]
end

function SWEP:ShouldWeaponAttackUseBurst( wep )
	return true
end

function SWEP:GetNPCBurstSettings()
    return 1,4,0.1
end

function SWEP:GetNPCRestTimes()
	return 0.4, 0.6
end

function SWEP:GetCapabilities()
	return CAP_INNATE_MELEE_ATTACK1
end

function SWEP:DrawWorldModel()
end