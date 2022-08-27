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


function SWEP:HandleDoor(slashtrace)
	if CLIENT or not IsValid(slashtrace.Entity) then return end

	if slashtrace.Entity:GetClass() == "func_door_rotating" or slashtrace.Entity:GetClass() == "prop_door_rotating" then
		slashtrace.Entity:EmitSound("ambient/materials/door_hit1.wav", 100, math.random(80, 120))

		local newname = "TFABash" .. self:EntIndex()
		self.PreBashName = self:GetName()
		self:SetName(newname)

		slashtrace.Entity:SetKeyValue("Speed", "500")
		slashtrace.Entity:SetKeyValue("Open Direction", "Both directions")
		slashtrace.Entity:SetKeyValue("opendir", "0")
		slashtrace.Entity:Fire("unlock", "", .01)
		slashtrace.Entity:Fire("openawayfrom", newname, .01)

		timer.Simple(0.02, function()
			if not IsValid(self) or self:GetName() ~= newname then return end

			self:SetName(self.PreBashName)
		end)

		timer.Simple(0.3, function()
			if IsValid(slashtrace.Entity) then
				slashtrace.Entity:SetKeyValue("Speed", "100")
			end
		end)
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
		mask = MASK_SHOT_HULL
	} )

	if ( !IsValid( tr.Entity ) ) then
		tr = util.TraceHull( {
			start = self.Owner:GetShootPos(),
			endpos = self.Owner:GetShootPos() + self.Owner:GetAimVector() * self.Range,
			filter = self.Owner,
			mins = Vector( -10, -10, -8 ),
			maxs = Vector( 10, 10, 8 ),
			mask = MASK_SHOT_HULL
		} )
	end

	local hit = false
	local scale = phys_pushscale:GetFloat() * 3

	if SERVER and IsValid( tr.Entity ) then
		if tr.Entity:IsNPC() or tr.Entity:IsPlayer() or tr.Entity:Health() > 0 then
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