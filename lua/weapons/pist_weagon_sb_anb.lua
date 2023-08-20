//General Settings \\ 

if ( SERVER ) then

    AddCSLuaFile()

    SWEP.HoldType        = "pistol"

end

if ( CLIENT ) then

    SWEP.PrintName       = "Sexyness"
    SWEP.Author          = "2-bit"

    SWEP.Slot            = 1
    SWEP.SlotPos         = 1
    SWEP.iconletter      = "f"

end

SWEP.Base               = "weapon_base"

SWEP.Spawnable          = false
SWEP.AdminOnly = true

SWEP.ViewModel          = "models/weapons/v_pist_weagon.mdl"
SWEP.WorldModel         = "models/weapons/w_pist_weagon.mdl"
SWEP.ViewModelFlip      = true

SWEP.Weight             = 100
SWEP.AutoSwitchTo       = false
SWEP.AutoSwitchFrom     = false

SWEP.HoldType = "Pistol" // How the swep is hold Pistol smg greanade melee 

SWEP.FiresUnderwater = true // Does your swep fire under water ? 

SWEP.DrawCrosshair = true // Do you want it to have a crosshair ? 

SWEP.Category = "2-bit's sexy gun" // Make your own catogory for the swep 

SWEP.DrawAmmo = true // Does the ammo show up when you are using it ? True / False 

SWEP.ReloadSound = "sound/weapons/alyxgun/alyx_gun_reload.wav" // Reload sound, you can use the default ones, or you can use your one; Example; "sound/myswepreload.waw" 

SWEP.base = "weapon_base"

SWEP.CSMuzzleFlashes = true

//General settings\\

//PrimaryFire Settings\\ 
SWEP.Primary.Sound = "weapons/automag/deagle-1.wav"
SWEP.Primary.Damage = 99999999999 // How much damage the swep is doing 
SWEP.Primary.TakeAmmo = 1 // How much ammo does it take for each shot ? 
SWEP.Primary.ClipSize = 9999999 // The clipsize 
SWEP.Primary.Ammo = "Pistol" // ammmo type pistol/ smg1 
SWEP.Primary.DefaultClip = 9999999 // How much ammo does the swep come with `? 
SWEP.Primary.Spread = 0.25 // Does the bullets spread all over, if you want it fire exactly where you are aiming leave it 0.1 
SWEP.Primary.NumberofShots = 75 // How many bullets you are firing each shot. 
SWEP.Primary.Automatic = true // Is the swep automatic ? 
SWEP.Primary.Recoil = 0 // How much we should punch the view 
SWEP.Primary.Delay = 0.05 // How long time before you can fire again 
SWEP.Primary.Force = 1000000 // The force of the shot 

//SecondaryFire settings\\
SWEP.Secondary.Sound = "weapons/automag/deagle-1.wav"
SWEP.Secondary.Damage = 9999999 // How much damage the swep is doing 
SWEP.Secondary.TakeAmmo = 1 // How much ammo does it take for each shot ? 
SWEP.Secondary.ClipSize = 9999999 // The clipsize 
SWEP.Secondary.Ammo = "Pistol" // ammmo type pistol/ smg1 
SWEP.Secondary.DefaultClip = 9999999 // How much ammo does the swep come with `? 
SWEP.Secondary.Spread = 0.1 // Does the bullets spread all over, if you want it fire exactly where you are aiming leave it 0.1 
SWEP.Secondary.NumberofShots = 1 // How many bullets you are firing each shot. 
SWEP.Secondary.Automatic = true // Is the swep automatic ? 
SWEP.Secondary.Recoil = 0.0 // How much we should punch the view 
SWEP.Secondary.Delay = 0.05 // How long time before you can fire again 
SWEP.Secondary.Force = 1000000 // The force of the shot 

terminator_Extras.SetupAnalogWeight( SWEP )

//SWEP:Initialize\\ 
function SWEP:Initialize()
    if not self:GetOwner():IsNextBot() then SafeRemoveEntity( self ) return end
    self:SetHoldType( "pistol" )

    util.PrecacheSound( self.Primary.Sound )
    util.PrecacheSound( self.Secondary.Sound )

    if CLIENT then self:SetNoDraw( true ) end
end
//SWEP:Initialize\\

//SWEP:PrimaryFire\\ 
function SWEP:PrimaryAttack() 
    if not self:CanPrimaryAttack() then return end 
    local owner = self:GetOwner()
 
    local bullet = {} 
        bullet.Num = self.Primary.NumberofShots
        bullet.Src = owner:GetShootPos() 
        bullet.Dir = owner:GetAimVector() 
        bullet.Spread = Vector( self.Primary.Spread * 0.1 , self.Primary.Spread * 0.1, 0) 
        bullet.Tracer = 1
        bullet.Force = self.Primary.Force 
        bullet.Damage = self.Primary.Damage 
        bullet.AmmoType = self.Primary.Ammo 
 
    local rnda = self.Primary.Recoil * -1 
    local rndb = self.Primary.Recoil * math.random(-1, 1) 
 
    self:ShootEffects() 
 
    owner:FireBullets( bullet ) 
    self:EmitSound( Sound( self.Primary.Sound ), 120 )
    self:TakePrimaryAmmo( self.Primary.TakeAmmo ) 
 
    self:SetNextPrimaryFire( CurTime() + self.Primary.Delay )
    self:SetNextSecondaryFire( CurTime() + self.Primary.Delay )

end 
//SWEP:PrimaryFire\\

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
    return 1
end

function SWEP:GetNPCBurstSettings()
    return 1,1,0
end

function SWEP:GetNPCRestTimes()
    return 0.5,1
end

function SWEP:GetCapabilities()
    return CAP_WEAPON_RANGE_ATTACK1
end

function SWEP:DrawWorldModel()
end