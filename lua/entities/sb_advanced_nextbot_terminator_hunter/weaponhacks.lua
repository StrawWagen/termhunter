-- HACKS!
terminator_WeaponHacks = {
    m9k_davy_crockett = function( self )
        if MMM_M9k_IsBaseInstalled then return end
        self.terminator_NeedsEnemy = true
        self:SetNextPrimaryFire( CurTime() + 5 )
        self.PrimaryAttack = function()
            if self:CanPrimaryAttack() and self.FireDelay <= CurTime() and not self.Owner:KeyPressed(IN_SPEED) then
            if IsValid( self.Owner ) then -- change is here
                if GetConVar("DavyCrockettAllowed") == nil or (GetConVar("DavyCrockettAllowed"):GetBool()) then
                    self:FireRocket()
                    self.Weapon:EmitSound("RPGF.single")
                    self.Weapon:TakePrimaryAmmo(1)
                    self.Weapon:SendWeaponAnim( ACT_VM_PRIMARYATTACK )
                    self.Owner:SetAnimation( PLAYER_ATTACK1 )
                    self.Owner:MuzzleFlash()
                    self.Weapon:SetNextPrimaryFire(CurTime()+1/(self.Primary.RPM/60))
                else
                    self.Owner:PrintMessage( HUD_PRINTCENTER, "Nukes are not allowed on this server." )
                end
            end
            self:CheckWeaponsAndAmmo()
            end
        end
    end,
    m9k_orbital_strike = function( self )
        if MMM_M9k_IsBaseInstalled then return end
        self.terminator_NeedsEnemy = true
        self.PrimaryAttack = function()
            self.PoorBastard = false
            if not IsFirstTimePredicted() then return end
            if self:CanPrimaryAttack() and IsValid( self.Owner ) and self.NextShoot <= CurTime() and !self.Owner:KeyDown(IN_SPEED) and !self.Owner:KeyDown(IN_RELOAD) then
                local mark = self.Owner:GetEyeTrace()
                if mark.HitSky then 
                    self.Owner:EmitSound("player/suit_denydevice.wav")
                end

                local skytrace = {}
                skytrace.start = mark.HitPos
                skytrace.endpos = mark.HitPos + Vector(0,0,65000)
                skycheck = util.TraceLine(skytrace)
                if skycheck.HitSky then
                    if SERVER then
                        local Sky = skycheck.HitPos - Vector(0,0,10)
                        local Ground = mark.HitPos
                        Satellite = ents.Create("m9k_oribital_cannon")
                        Satellite.Ground = Ground
                        Satellite.Sky = Sky
                        Satellite.Owner = self.Owner
                        Satellite:SetPos(Sky) //was sky but for testing, its this
                        Satellite:Spawn()
                    end
                    if SERVER then self.Owner:EmitSound(self.Primary.Sound) end
                    self.Weapon:TakePrimaryAmmo(1)
                    self.Weapon:SetNextPrimaryFire(CurTime()+15)
                    self.NextShoot = CurTime() + 15
                    self:CheckWeaponsAndAmmo()
                    self:Reload()
                elseif mark.Entity:IsPlayer() or mark.Entity:IsNPC() then
                    self.PoorBastard = true
                    thetarget = mark.Entity
                    skytrace2 = {}
                    skytrace2.start = thetarget:GetPos()
                    skytrace2.endpos = thetarget:GetPos() + Vector(0,0,65000)
                    skytrace2.filter = thetarget
                    skycheck2 = util.TraceLine(skytrace2)
                    if skycheck2.HitSky then //someone's gonna be in big trouble
                        sky2 = skycheck2.HitPos - Vector(0,0,10)
                        if SERVER then
                            Satellite = ents.Create("m9k_oribital_cannon")
                            --Satellite.Ground = Ground
                            Satellite.PoorBastard = true
                            Satellite.Target = thetarget
                            Satellite.Sky = sky2
                            Satellite.Owner = self.Owner
                            Satellite:SetPos(sky2)
                            Satellite:Spawn()
                        end
                        self.Owner:EmitSound(self.Primary.Sound)
                        self.Weapon:TakePrimaryAmmo(1)
                        self.Weapon:SetNextPrimaryFire(CurTime()+15)
                        self.NextShoot = CurTime() + 15
                        self:CheckWeaponsAndAmmo()
                        self:Reload()
                    else
                        self.Owner:EmitSound("player/suit_denydevice.wav")
                    end
                else
                    self.Owner:EmitSound("player/suit_denydevice.wav")
                end
            end
        end
    end,
    bobs_nade_base = function( self )
        if MMM_M9k_IsBaseInstalled then return end
        self.terminator_NeedsEnemy = true
        self.PrimaryAttack = function()
            if not IsValid( self.Owner ) then return end
            if self:CanPrimaryAttack() then
                self.Weapon:SendWeaponAnim(ACT_VM_PULLPIN)

                self.Weapon:SetNextPrimaryFire(CurTime()+1/(self.Primary.RPM/60))	
                timer.Simple( 0.6, function() if SERVER then if not IsValid(self) then return end 
                    if IsValid(self.Owner) then 
                        if (self:AllIsWell()) then 
                            self:Throw() 
                        end 
                    end
                end end )
            end
        end
        self.AllIsWell = function( self )

            if IsValid( self.Owner ) and self.Weapon != nil then
                if self.Weapon:GetClass() == self.Gun and self.Owner:Alive() then
                    return true
                    else return false
                end
                else return false
            end

        end
    end,
    bobs_gun_base = function( self )
        if not MMM_M9k_IsBaseInstalled then
            -- WHY DO YOU MAKE ME DO THIS?!?!?!
            self:SetClip1( self:GetMaxClip1() )
            self:SetClip2( self:GetMaxClip2() )

        else
            self.Equip = function( self )
                if not IsValid(self.Owner) then return end

                --[[if not self.Owner:IsPlayer() then -- NPCs cannot have M9kR Weapons! Also prevents invalid spawning
                    self:Remove()
        
                    return
                end--]]

                if self.EquipHooked then
                    self:EquipHooked()
                end
            end
        end
    end,
    meteors_melee_base = function( self )
        self.IsMeleeWeapon = true
        self.Equip = function( self )
            if not IsValid(self.Owner) then return end

            --[[if not self.Owner:IsPlayer() then -- NPCs cannot have M9kR Weapons! Also prevents invalid spawning
                self:Remove()

                return
            end]]--

            if self.EquipHooked then
                self:EquipHooked()
            end
        end
    end,
    mg_base = function( self )
        if game.SinglePlayer() and not terminator_Extras.MWCOMPAT_HasDoneSingleplayerWarn then
            terminator_Extras.MWCOMPAT_HasDoneSingleplayerWarn = true
            local msg = "Terminator Nextbot: MW base support is limited/broken in singleplayer. Change session type to \"local multiplayer\" or one of the two \"peer to peer\" types."
            PrintMessage( HUD_PRINTCENTER, msg )
            PrintMessage( HUD_PRINTTALK, msg )
            PrintMessage( HUD_PRINTTALK, msg )
            PrintMessage( HUD_PRINTTALK, msg )
            ErrorNoHaltWithStack( msg )

        end

        self.PlayerGesture = function( self, slot, anim )

            if (CLIENT && IsFirstTimePredicted()) then 
                self:GetOwner():AnimRestartGesture(slot, anim, true)
            end

            if SERVER then
                if self:GetOwner():IsPlayer() then  -- added this
                    net.Start("mgbase_tpanim", true)
                    net.WriteUInt(slot, 2)
                    net.WriteInt(anim, 12)
                    net.WriteEntity(self:GetOwner())
                    if (game.SinglePlayer()) then
                        net.Send(self:GetOwner())
                    else
                        net.SendOmit(self:GetOwner())
                    end
                else
                    self:RestartGesture( anim, true, true ) -- to enable this

                end
            end
        end
        self.CanAttack = function( self )
            return true

        end
        self.FireTracer = function( self )
        end
    end
}

-- get stuff in nested 
function ENT:DoWeaponHacks( wep )
    local wepClass = wep:GetClass()
    local wepsTable = weapons.Get( wepClass )
    local max = 100 -- dont let anything funny happen!
    local doneCount = 0

    while wepsTable and doneCount < max do
        doneCount = doneCount + 1

        local hack = terminator_WeaponHacks[ wepsTable.ClassName ]
        if hack then
            hack( wep )

        end

        if not wepsTable.Base or wepsTable.Base == wepsTable.ClassName then break end
        wepsTable = weapons.Get( wepsTable.Base )

    end
end