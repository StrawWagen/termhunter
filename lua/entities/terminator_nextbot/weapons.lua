-- Lua analogs to engine/unsupported weapons
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
    manhack_welder = "manhack_welder_term",
    weapon_flechettegun = "weapon_flechettegun_term",
    gmod_camera = "gmod_camera_term",
    weapon_frag = "weapon_frag_term",
    weapon_slam = "weapon_slam_term",

}

local crateClass = "item_item_crate"

local EngineAnalogsReverse = {}
for k,v in pairs( EngineAnalogs ) do EngineAnalogsReverse[v] = k end

termHunter_WeaponAnalogs = EngineAnalogs

local IsValid = IsValid
local entMeta = FindMetaTable( "Entity" )

--[[------------------------------------
    Name: NEXTBOT:Give
    Desc: Gives weapon to bot.
    Arg1: string | wepname | Class name of weapon.
    Ret1: Weapon | Weapon given to bot. Returns NULL if failed to give this weapon.
--]]------------------------------------
function ENT:Give( wepname )
    local wep = ents.Create( wepname )

    if not IsValid( wep ) then return end

    if not wep:IsScripted() and not EngineAnalogs[wepname] then
        SafeRemoveEntity( wep )

        return NULL

    end

    local oldWep = self:GetWeapon()
    if IsValid( oldWep ) then
        SafeRemoveEntity( oldWep )

    end

    wep:Spawn()
    wep:Activate()
    wep:SetPos( self:GetPos() )

    return self:SetupWeapon( wep )

end

function ENT:HateBuggyWeapon( wep, successful )
    if successful then return end
    terminator_Extras.OverrideWeaponWeight( wep:GetClass(), -100 )
    wep.terminatorCrappyWeapon = true
    print( "Terminator fired buggy weapon!\ndisgustang!!!!" )
    -- drop weap without holstering it
    self:DropWeapon( true )
    self:Anger( 10 )

    return true

end

--[[------------------------------------
    Name: NEXTBOT:GetActiveLuaWeapon
    Desc: Returns current weapon entity. If active weapon is engine weapon, returns lua analog.
    Arg1: 
    Ret1: Weapon | Active weapon.
--]]------------------------------------
function ENT:GetActiveLuaWeapon()
    return self.m_ActualWeapon or NULL

end

--[[------------------------------------
    Name: NEXTBOT:SetupWeapon
    Desc: Makes bot hold this weapon.
    Arg1: Weapon | wep | Weapon to hold.
    Ret1: Weapon | Parented weapon. If give weapon is engine weapon, then this will be lua analog. Returns nil if failed to setup.
--]]------------------------------------
function ENT:SetupWeapon( wep )

    if not IsValid( wep ) or wep == self:GetActiveWeapon() then return end

    local wepsClass = wep:GetClass()
    -- Cannot hold engine weapons
    if not wep:IsScripted() and not EngineAnalogs[ wepsClass ] then return end

    if self:IsHolsteredWeap( wep ) then
        self:UnHolsterWeap( wep )
        self:EmitSound( "common/wpn_hudoff.wav", 80, 100, 0.8, CHAN_STATIC )

    end

    -- Clear old weapon
    if self:HasWeapon() then
        self:DropWeapon( false )

    end

    self.terminator_NeedsAWeaponNow = nil
    local successful = ProtectedCall( function() self:OnWeaponEquip( wep ) end )
    self:HateBuggyWeapon( wep, successful )

    self:SetActiveWeapon( wep )

    -- Custom lua weapon analog for engine weapon, this need to have WEAPON metatable
    if EngineAnalogs[ wepsClass ] then
        local actwep = ents.Create( EngineAnalogs[ wepsClass ] )
        actwep:SetOwner( self )
        actwep:SetParent( wep )
        actwep:Spawn()
        actwep:Activate()

        actwep:SetLocalPos( vector_origin )
        actwep:SetLocalAngles( angle_zero )
        actwep:PhysicsDestroy()
        actwep:AddSolidFlags( FSOLID_NOT_SOLID )
        actwep:AddEffects( EF_BONEMERGE )
        actwep:SetTransmitWithParent( true )

        actwep:SetClip1( wep:Clip1() )
        actwep:SetClip2( wep:Clip2() )

        hook.Add( "Think", actwep, function( self )
            if not IsValid( wep ) then return end
            wep:SetClip1( self:Clip1() )
            wep:SetClip2( self:Clip2() )
        end )

        hook.Add( "EntityRemoved", actwep, function( self,ent )
            if ent == wep then self:Remove() end
        end )
        actwep:DeleteOnRemove( wep )

        self.m_ActualWeapon = actwep

    elseif wep.NPC_Initialize then
        wep:NPC_Initialize()
        self.m_ActualWeapon = wep

    else
        self.m_ActualWeapon = wep

    end

    -- do this before set hold type to work well with ANP base
    wep:SetOwner( self )

    local actwep = self:GetActiveLuaWeapon()
    actwep:SetWeaponHoldType( wep:GetHoldType() )

    self:ReloadWeaponData()

    -- Actually setup weapon. Very similar to engine code.

    wep:SetVelocity( vector_origin )
    wep:RemoveSolidFlags( FSOLID_TRIGGER )
    wep:RemoveEffects( EF_ITEM_BLINK )
    wep:PhysicsDestroy()

    wep:SetParent( self )
    wep:SetMoveType( MOVETYPE_NONE )
    wep:AddEffects( EF_BONEMERGE )
    wep:AddSolidFlags( FSOLID_NOT_SOLID )
    wep:SetLocalPos( vector_origin )
    wep:SetLocalAngles( angle_zero )

    wep:SetTransmitWithParent( true )

    self:DoWeaponHacks( wep )

    successful = ProtectedCall( function() actwep:OwnerChanged() end )
    self:HateBuggyWeapon( wep, successful )
    successful = ProtectedCall( function() actwep:Equip( self ) end )
    self:HateBuggyWeapon( wep, successful )
    successful = ProtectedCall( function() actwep:Deploy( self ) end )
    self:HateBuggyWeapon( wep, successful )

    -- 'equip' sound
    self:EmitSound( "Flesh.Strain", 80, 160, 0.8 )

    local oldFire = self.terminator_DontImmiediatelyFire or 0
    self.terminator_DontImmiediatelyFire = math.max( CurTime() + math.Rand( 0.75, 1.25 ), oldFire )
    self.terminator_FiringIsAllowed = nil
    self.terminator_LastFiringIsAllowed = 0
    self:NextWeapSearch( 0 )

    --[[
    -- debug for testing holstering
    timer.Simple( 0.5, function()
        if true then
            self:DropWeapon()

        end
    end )
    --]]

    return actwep

end

--[[------------------------------------
    Name: NEXTBOT:DropWeapon
    Desc: Drops current active weapon.
    Arg1: (optional) Vector | velocity | Sets velocity of weapon. Max speed is 400.
    Arg2: (optional) bool | justdrop | If true, just drop weapon from current hand position. Don't apply velocity and position.
    Ret1: Weapon | Dropped weapon. If active weapon is lua analog of engine weapon, then this will be engine weapon, not lua analog.
--]]------------------------------------
function ENT:DropWeapon( noHolster, droppingOverride )
    local wep
    local realWep = self:GetActiveWeapon()
    if IsValid( droppingOverride ) then
        local isGood = ( realWep == droppingOverride ) or self:IsHolsteredWeap( droppingOverride )
        if not isGood then return end
        wep = droppingOverride

    else
        wep = realWep

    end


    if not IsValid( wep ) then return end


    self:SetActiveWeapon( NULL )

    if wep:GetClass() == self.TERM_FISTS then
        SafeRemoveEntity( wep )
        return

    end

    local actwep = self:GetActiveLuaWeapon()
    local velocity = self:GetEyeAngles():Forward() * 10


    -- Unparenting weapon. Very similar to engine code.

    wep:SetParent()
    wep:RemoveEffects( EF_BONEMERGE )
    wep:RemoveSolidFlags( FSOLID_NOT_SOLID )
    wep:CollisionRulesChanged()

    wep:SetOwner( nil )
    wep.Owner = nil

    if self.m_ActualWeapon and self.m_ActualWeapon == wep then
        self.m_ActualWeapon = nil

    end

    wep:SetMoveType( MOVETYPE_FLYGRAVITY )

    local SF = wep:GetSolidFlags()
    if not wep:PhysicsInit( SOLID_VPHYSICS ) then
        wep:SetSolid( SOLID_BBOX )

    else
        wep:SetMoveType( MOVETYPE_VPHYSICS )
        wep:PhysWake()

    end
    wep:SetSolidFlags( bit.bor( SF, FSOLID_TRIGGER ) )

    wep:SetTransmitWithParent( false )

    if IsValid( actwep ) then
        local successful = ProtectedCall( function() actwep:OwnerChanged() end )
        self:HateBuggyWeapon( wep, successful )
        successful = ProtectedCall( function() actwep:OnDrop() end )
        self:HateBuggyWeapon( wep, successful )

        -- Restoring engine weapon from lua analog
        if wep ~= actwep then
            if actwep:Clip1() > 0 then
                if not IsValid( wep ) then return end
                wep:SetClip1( actwep:Clip1() )

            else
                timer.Simple( 0, function()
                    if not IsValid( wep ) then return end
                    wep:SetClip1( wep:GetMaxClip1() )

                end )

            end
            if actwep:Clip2() > 0 then
                if not IsValid( wep ) then return end
                wep:SetClip2( actwep:Clip2() )

            else
                timer.Simple( 0, function()
                    if not IsValid( wep ) then return end
                    wep:SetClip2( wep:GetMaxClip2() )

                end )
            end

            actwep:DontDeleteOnRemove( wep )
            actwep:Remove()

        end
    end

    local successful = ProtectedCall( function() self:OnWeaponDrop( wep ) end )
    self:HateBuggyWeapon( wep, successful )

    wep:SetPos( self:GetShootPos() )
    wep:SetAngles( self:GetEyeAngles() )

    local phys = wep:GetPhysicsObject()
    if IsValid( phys ) then
        phys:AddVelocity( velocity )
        phys:AddAngleVelocity( Vector( 200, 200, 200 ) )

    else
        wep:SetVelocity( velocity )

    end

    if self:CanHolsterWeap( wep ) and noHolster ~= true then -- holster wep if we can, and it's not crappy!
        self:HolsterWeap( wep )

    end

    self.terminator_NextWeaponPickup = CurTime() + math.Rand( 1, 2 )

    return wep
end

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

function ENT:AssumeWeaponNextShootTime()
    local wep = self:GetWeapon()
    local wepData = self.m_WeaponData

    if isnumber( wep.NPC_NextPrimaryFireT ) then -- vj BASE
        return wep.NPC_NextPrimaryFireT

    elseif wep and wepData.Primary.NextShootTime and wepData.Primary.NextShootTime ~= 0 then
        return wepData.Primary.NextShootTime

    elseif wep.GetNextPrimaryFire and not ( wep.terminator_FiredBefore and wep:GetNextPrimaryFire() == 0 ) then
        if wep.Primary.Automatic ~= true and wep.terminator_IsBurst then
            local nextFire = wep:GetNextPrimaryFire()
            if self:IsAngry() then
                nextFire = nextFire + math.Rand( 0.5, 1 )

            else
                nextFire = nextFire + math.Rand( 2, 4 )

            end
            return nextFire

        end
        return wep:GetNextPrimaryFire()

    end

    return wep.term_LastFire + 1

end

--[[------------------------------------
    Name: NEXTBOT:CanWeaponPrimaryAttack
    Desc: Returns can bot do primary attack or not.
    Arg1: 
    Ret1: bool | Can do primary attack
--]]------------------------------------
function ENT:CanWeaponPrimaryAttack()
    local dontImmiediatelyFire = self.terminator_DontImmiediatelyFire or 0
    if self:IsFists() then
        dontImmiediatelyFire = dontImmiediatelyFire - 0.1

    end
    if dontImmiediatelyFire > CurTime() and not ( self:IsReallyAngry() and self:Health() <= self:GetMaxHealth() * 0.25 )  then
        return false

    end

    local wep = self:GetActiveLuaWeapon() or self:GetActiveWeapon()
    if not IsValid( wep ) then return false end

    if self.IsReloadingWeapon then return false end

    if wep.terminator_NeedsEnemy and not IsValid( self:GetEnemy() ) then return false end

    if wep:GetMaxClip1() > 0 and wep:Clip1() <= 0 then return false end

    local canShoot = nil

    -- xpcall because we need to pass self
    local successful = ProtectedCall( function() -- no MORE ERRORS!
        local nextShoot = self:AssumeWeaponNextShootTime() or 0

        if not wep then canShoot = false return end
        if nextShoot > CurTime() then canShoot = false return end
        if wep.CanPrimaryAttack and not wep:CanPrimaryAttack() then canShoot = false return end

        canShoot = true

    end )
    self:HateBuggyWeapon( wep, successful )
    return canShoot

end

--[[------------------------------------
    Name: NEXTBOT:WeaponPrimaryAttack
    Desc: Does primary attack from bot's active weapon. This also uses burst data from weapon.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:WeaponPrimaryAttack()
    local wep = self:GetActiveLuaWeapon() or self:GetWeapon()
    if self:CanWeaponPrimaryAttack() ~= true then return end

    local data = self.m_WeaponData.Primary

    local isSetupProperly = isfunction( wep.GetNPCBurstSettings ) and isfunction( wep.GetNPCRestTimes )

    local successful = ProtectedCall( function() -- cant be too safe here

        if isSetupProperly then --SB base weapon probably

            local successfulShoot = ProtectedCall( function() wep:NPCShoot_Primary( self:GetShootPos(), self:GetAimVector() ) end )
            self:HateBuggyWeapon( wep, successfulShoot )

            if self:ShouldWeaponAttackUseBurst( wep ) then
                local bmin, bmax, frate = wep:GetNPCBurstSettings()
                local rmin, rmax = wep:GetNPCRestTimes()

                if data.BurstBullets == -1 then
                    data.BurstBullets = math.random( bmin, bmax )

                end

                data.BurstBullet = data.BurstBullet + 1

                if data.BurstBullet >= data.BurstBullets then
                    data.BurstBullets = -1
                    data.BurstBullet = 0
                    data.NextShootTime = math.max( CurTime() + math.Rand( rmin, rmax ), data.NextShootTime )

                else
                    data.NextShootTime = math.max( CurTime() + frate, data.NextShootTime )

                end
            else
                local _, _, frate = wep:GetNPCBurstSettings()
                data.NextShootTime = math.max( CurTime() + frate, data.NextShootTime )

            end

        elseif wep.NPCShoot_Primary then --some other kind of weapon
            --debugoverlay.Line( self:GetShootPos(), self:GetShootPos() + self:GetAimVector() * 100, 20  )
            if wep.NPC_TimeUntilFire then
                self:fakeVjBaseWeaponFiring( wep )

            else
                wep:PrimaryAttack()

            end

        elseif IsValid( wep ) then
            wep:PrimaryAttack()

        end
    end )
    if not self:HateBuggyWeapon( wep, successful ) then
        self:DoRangeGesture()
        wep.term_LastFire = CurTime()
        wep.terminator_FiredBefore = true
        self:RunTask( "OnAttack" )

    end
end

--[[------------------------------------
    Name: NEXTBOT:CanWeaponSecondaryAttack
    Desc: Returns can bot do secondary attack or not.
    Arg1: 
    Ret1: bool | Can do secondary attack
--]]------------------------------------
function ENT:CanWeaponSecondaryAttack()
    if not self:HasWeapon() or CurTime() < self.m_WeaponData.Secondary.NextShootTime then return false end

    local wep = self:GetActiveLuaWeapon()
    if CurTime() < wep:GetNextSecondaryFire() then return false end

    return true
end

--[[------------------------------------
    Name: NEXTBOT:WeaponSecondaryAttack
    Desc: Does secondary attack from bot's active weapon.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:WeaponSecondaryAttack()
    if not self:CanWeaponSecondaryAttack() then return end

    local wep = self:GetActiveLuaWeapon()

    local successful = ProtectedCall(function() wep:NPCShoot_Secondary(self:GetShootPos(),self:GetAimVector()) end)
    self:HateBuggyWeapon( wep, successful )
    self:DoRangeGesture()
end

--[[------------------------------------
    Name: NEXTBOT:DoRangeGesture
    Desc: Make primary attack range animation.
    Arg1: 
    Ret1: number | Animation duration.
--]]------------------------------------
function ENT:DoRangeGesture()
    local act = self:TranslateActivity( ACT_MP_ATTACK_STAND_PRIMARYFIRE )
    if not act or ( isnumber( act ) and act <= 0 ) then return end
    local seq
    if isstring( act ) then
        seq = self:LookupSequence( act )
        act = seq

    else
        seq = self:SelectWeightedSequence( act )

    end

    if not seq then return end

    self:DoGesture( act )

    return self:SequenceDuration( seq )
end

--[[------------------------------------
    Name: NEXTBOT:DoReloadGesture
    Desc: Make reload animation.
    Arg1: 
    Ret1: number | Animation duration.
--]]------------------------------------
function ENT:DoReloadGesture()
    local act = self:TranslateActivity( ACT_MP_RELOAD_STAND )
    if not act or act <= 0 then return end
    local seq = self:SelectWeightedSequence( act )

    self:DoGesture( act )

    return self:SequenceDuration( seq )
end

--[[------------------------------------
    Name: NEXTBOT:WeaponReload
    Desc: Reloads active weapon and do reload animation. Does nothing if we reloading already or if weapon clip is full.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:WeaponReload()
    if not self:HasWeapon() then return end

    local wep = self:GetActiveLuaWeapon()
    if wep:Clip1() >= wep:GetMaxClip1() then return end
    if CurTime() < self.m_WeaponData.NextReloadTime then return end

    local successful = ProtectedCall( function() wep:Reload() end )
    self:HateBuggyWeapon( wep, successful )
    local reloadTime = self:DoReloadGesture()

    if not reloadTime then return end
    self.IsReloadingWeapon = true

    local time = CurTime() + reloadTime
    timer.Simple( reloadTime, function()
        if not IsValid( self ) then return end
        self.IsReloadingWeapon = nil
        if not IsValid( wep ) then return end
        wep:SetClip1( wep:GetMaxClip1() )

    end )

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
function ENT:OnWeaponDrop( wep )
    self:RunTask( "OnWeaponDrop", wep )
end

--[[------------------------------------
    Name: NEXTBOT:CanPickupWeapon
    Desc: Returns can we pickup this weapon.
    Arg1: Entity | wep | Entity to test. Not necessary Weapon entity.
    Ret1: bool | Can pickup or not.
--]]------------------------------------

local cratesMaxDistFromGround = 75^2
local DistToSqr = FindMetaTable( "Vector" ).DistToSqr

function ENT:CanPickupWeapon( wep, doingHolstered, myTbl, wepsTbl )
    if not wep then return end
    wepsTbl = wepsTbl or wep:GetTable()

    if not wepsTbl then return end -- ????

    if wepsTbl.terminatorCrappyWeapon then return false end
    if IsValid( entMeta.GetOwner( wep ) ) and not doingHolstered then return false end

    local wepsParent = wep:GetParent()
    if IsValid( wepsParent ) and not doingHolstered then return false end

    if doingHolstered and wepsParent ~= self then return false end

    myTbl = myTbl or self:GetTable()
    if doingHolstered and wepsParent == self and not myTbl.IsHolsteredWeap( self, wep ) then return false end -- we're already using this one... 

    local blockWeaponNoticing = wep.blockWeaponNoticing or 0
    if blockWeaponNoticing > CurTime() then return end

    local class = entMeta.GetClass( wep )
    if class == crateClass and myTbl.HasFists then
        local wepPos = entMeta.GetPos( wep )
        local result = terminator_Extras.getNearestPosOnNav( wepPos )
        if result.area and result.area.IsValid and result.area:IsValid() and result.pos:DistToSqr( wepPos ) < cratesMaxDistFromGround then
            return true

        else
            return false

        end
    end
    if not wep:IsWeapon() then return false end
    if ( not wep:IsScripted() and not EngineAnalogs[ class ] ) then return false end
    if myTbl.GetWeightOfWeapon( self, wep ) < -2 then return false end

    if myTbl.EnemyIsLethalInMelee( self ) and DistToSqr( entMeta.GetPos( wep ), entMeta.GetPos( self:GetEnemy() ) ) < 500^2 then return false end

    return true

end

function ENT:GetWeightOfWeapon( wep )
    if not IsValid( wep ) then return -1 end
    local class = wep:GetClass()
    if class == crateClass then
        return 1
    end
    return terminator_Extras.EngineAnalogWeights[class] or wep:GetWeight() or 0

end

--[[------------------------------------
    Name: NEXTBOT:CanDropWeaponOnDie
    Desc: Decides can bot drop weapon on die. NOTE: Weapon also may not drop even with `true` if weapon's `SWEP:ShouldDropOnDie` returns `false`.
    Arg1: Weapon | wep | Current active weapon (this will be lua analog for engine weapon).
    Ret1: bool | Can drop.
--]]------------------------------------
function ENT:CanDropWeaponOnDie(wep)
    return not self:HasSpawnFlags(SF_NPC_NO_WEAPON_DROP)
end

--[[------------------------------------
    Name: NEXTBOT:ShouldWeaponAttackUseBurst
    Desc: Decides should bot shoot with bursts.
    Arg1: Weapon | wep | Current active weapon (this will be lua analog for engine weapon).
    Ret1: bool | Should use bursts.
--]]------------------------------------
function ENT:ShouldWeaponAttackUseBurst(wep)
    return not self:IsControlledByPlayer()
end

--[[------------------------------------
    Name: NEXTBOT:IsMeleeWeapon
    Desc: Returns true if weapon marked as for melee attacks (using CAP_* Enums).
    Arg1: (optional) Weapon | wep | Weapon to check (this should be lua analog for engine weapon). Without passing will be used active weapon.
    Ret1: bool | Weapon is melee weapon.
--]]------------------------------------
function ENT:IsMeleeWeapon( wep )
    wep = wep or self:GetActiveWeapon()

    if self:IsFists() then return true end
    if not IsValid( wep ) then return false end
    if wep.GetCapabilities then
        local caps = wep:GetCapabilities()
        if bit.band( caps, CAP_WEAPON_MELEE_ATTACK1 ) ~= 0 then return true end
        if bit.band( caps, CAP_INNATE_MELEE_ATTACK1 ) ~= 0 then return true end

    end
    if wep.IsMeleeWeapon == true then return true end

    local range = self:GetWeaponRange()
    if range and range < 150 then return true end

    return false

end

function ENT:IsRangedWeapon( wep )
    return not self:IsMeleeWeapon( wep )

end

function ENT:IsFists()
    local wep = self:GetWeapon()
    if not IsValid( wep ) then return end
    if wep:GetClass() == self.TERM_FISTS then return true end

    return nil

end

function ENT:DoFists()
    if self:IsFists() then return end
    if not self.DontDropPrimary then
        self:DropWeapon( false )


    end
    self.terminator_NextWeaponPickup = CurTime() + 2.5
    self:Give( self.TERM_FISTS )

end

function ENT:GiveAmmo()
    return nil

end

function ENT:GetAmmoCount()
    return self:GetActiveWeapon():Clip1() or 0

end

function ENT:PickupObject()
    return

end

function ENT:GetWeapon()
    return self:GetActiveLuaWeapon() or self:GetActiveWeapon()

end

local function weapSpread( wep )
    local spread = 0

    -- mw base
    if wep.Cone then
        spread = wep.Cone.Ads / 2

    elseif wep.Primary then
        local spreadInt = wep.Primary.Spread
        if isvector( spreadInt ) then
            spread = spreadInt:Length()

        elseif isnumber( spreadInt ) then
            spread = spreadInt

        end
    end
    return spread

end

local function weapBulletCount( wep )
    local count = 1
    local primary = wep.Primary

    if wep.Bullet and wep.Bullet.NumBullets then
        count = wep.Bullet.NumBullets

    elseif primary and primary.NumberofShots and primary.NumberofShots ~= 0 then
        count = primary.NumberofShots

    elseif primary and primary.NumShots and primary.NumShots ~= 0 then
        count = primary.NumShots

    end
    return count

end

local function weapDamage( wep )
    local dmg = 1
    local primary = wep.Primary

    if wep.Bullet and wep.Bullet.Damage then
        local damage = wep.Bullet.Damage
        if istable( damage ) then
            dmg = math.random( damage[1], damage[2] )

        elseif isnumber( damage ) then
            dmg = damage

        end
    elseif primary and primary.Damage and primary.Damage ~= 0 then
        dmg = primary.Damage

    end
    return dmg

end

function ENT:GetWeaponRange()
    local wep = self:GetActiveLuaWeapon() or self:GetActiveWeapon()

    if not IsValid( wep ) then return math.huge end
    if wep.ArcCW then return wep.Range * 52 end -- HACK
    if isnumber( wep.Range ) then return wep.Range end
    if isnumber( wep.MeleeWeaponDistance ) then return wep.MeleeWeaponDistance end
    if isnumber( wep.HitRange ) then return wep.HitRange end

    local shotgun = string.find( wep:GetClass(), "shotgun" )
    local spread = weapSpread( wep )

    if spread then
        local bulletCount = weapBulletCount( wep )
        local damage = weapDamage( wep )

        if damage > 500 then -- likely admin gun
            return math.huge

        end

        local num = spread + ( bulletCount / 1000 )
        if num > 0.05 then
            return 500

        end
        local range = math.abs( num - 0.05 )
        range = range * 2000 -- make num big
        range = range ^ 2.05 -- this works p good
        range = range + 500 -- cut off the really spready stuff

        if shotgun then
            range = math.min( range, 800 )

        end

        return range

    end

    if shotgun then return 800 end

    return math.huge

end

--[[------------------------------------
    Name: NEXTBOT:SetupEyeAngles
    Desc: (INTERNAL) Aiming bot to desired direction.
    Arg1: 
    Ret1: 
--]]------------------------------------

local math_max = math.max
local math_min = math.min
local math_abs = math.abs

function ENT:SetupEyeAngles()
    -- old angles
    local angp = self.m_PitchAim
    local angy = self:GetAngles().y

    -- new angles
    local desired = self:GetDesiredEyeAngles()
    local punch = self:GetViewPunchAngles()

    if self:IsControlledByPlayer() then
        desired = self:GetControlPlayer():EyeAngles()
    end

    local diffp = math.AngleDifference( desired.p, angp )
    local diffy = math.AngleDifference( desired.y, angy )
    local max = self.BehaveInterval * self.AimSpeed

    diffp = diffp < 0 and math_max( -max, diffp ) or math_min( max, diffp )
    diffy = diffy < 0 and math_max( -max, diffy ) or math_min( max, diffy )

    angp = angp + diffp
    angy = angy + diffy

    -- evil, horrible rare bug
    if math_abs( angp ) > 360 then
        angp = 0

    end

    self:SetAngles( Angle( 0, angy, 0 ) )

    self.m_PitchAim = angp
    self:SetPoseParameter( "aim_pitch", self.m_PitchAim + punch.p )
    self:SetPoseParameter( "aim_yaw", punch.y )

    self:SetEyeTarget( self:GetShootPos() + self:GetEyeAngles():Forward() * 100 )

end

hook.Add( "PlayerCanPickupWeapon", "TerminatorNextBot", function( ply,wep )
    -- Do not allow pickup when bot carries this weapon
    if IsValid( wep:GetOwner() ) and wep:GetOwner().TerminatorNextBot then
        return false
    end

    -- Do not allow pickup engine weapon analogs
    if EngineAnalogsReverse[wep:GetClass()] then
        return false
    end
end )

function ENT:getTheWeapon( oldTask, theWep, nextTask, theDat )
    if IsValid( theWep ) and self:IsHolsteredWeap( theWep ) then
        -- equip holstered weap
        self:SetupWeapon( theWep )

    else
        -- break task to get a weap
        self:TaskComplete( oldTask )
        self:StartTask2( "movement_getweapon", { Wep = potentialWep, nextTask = nextTask, nextTaskData = theDat }, "there's a weapon" )
        return true

    end
end

function ENT:NextWeapSearch( time )
    self.nextWeapSearch = CurTime() + time

end

function ENT:ResetWeaponSearchTimers()
    self.terminator_NextWeaponPickup = 0
    self.nextWeapSearch = CurTime() + 0.1
    self.cachedNewWeaponDat = nil

end

function ENT:canGetWeapon()
    -- can't do path to it
    local myTbl = self:GetTable()
    local nextNewPath = myTbl.nextNewPath or 0
    if nextNewPath > CurTime() then return false end

    local armed = not myTbl.IsFists( self )
    local nextSearch = myTbl.nextWeapSearch or 0
    if nextSearch < CurTime() then
        myTbl.NextWeapSearch( self, math.Rand( 2, 4 ) ) -- this is a cached result
        myTbl.cachedNewWeaponDat = myTbl.FindWeapon( self, myTbl ) -- find weapons

    end

    local wepDat = myTbl.cachedNewWeaponDat or {}
    local newWeap = wepDat.wep

    if not IsValid( newWeap ) then return false, nil end

    local justPickupTheDamnWep = not armed and myTbl.IsReallyAngry( self ) and not IsValid( newWeap:GetParent() ) and self:GetRangeTo( newWeap ) < 500

    -- we're pissed, just pick it up!
    if not justPickupTheDamnWep then
        -- by default, dont allow spam, this is set at the end of dropweapon!
        local nextWeaponPickup = myTbl.terminator_NextWeaponPickup or 0
        if nextWeaponPickup > CurTime() then return false end

    end

    -- crazy unholstering logic
    if armed then
        local currWeap = self:GetActiveWeapon()
        if not IsValid( currWeap ) then return true, newWeap end

        local rand = math.random( 1, 100 )

        local weapWeight = wepDat.weight or 0
        local currWeapWeight = myTbl.GetWeightOfWeapon( self, currWeap )

        local distToEnemy = myTbl.DistToEnemy or 0
        local range = wepDat.range or 0
        local currWeapRange = myTbl.GetWeaponRange( self, currWeap )

        local canHolster = myTbl.CanHolsterWeap( self, currWeap )
        local newIsHolstered = myTbl.IsHolsteredWeap( self, newWeap )

        local isBetter = weapWeight > ( currWeapWeight + 1 )
        local newHasRange = range > distToEnemy
        local oldHasRange = currWeapRange > distToEnemy

        local fillOutInventory = newHasRange and canHolster and not newIsHolstered and rand > 80 and newWeap:GetClass() ~= self:GetWeapon():GetClass()

        local betterWeap = isBetter or ( newHasRange and not oldHasRange ) or fillOutInventory
        local badWepOrBox = wepDat.isBox and myTbl.IsFists( self ) and weapWeight <= 1 and not myTbl.IsSeeEnemy

        local betterWeapOrJustHappyTohave = betterWeap or badWepOrBox
        local canGet = IsValid( newWeap ) and betterWeapOrJustHappyTohave
        return canGet, newWeap

    else
        return true, newWeap

    end
end

function ENT:GetTheBestWeapon()
    local nextGetBest = self.term_NextNeedsAWeaponNow or 0
    if nextGetBest > CurTime() then return end
    -- dont need a wep!
    if IsValid( self:GetWeapon() ) and self:GetWeaponRange( self:GetWeapon() ) > self.DistToEnemy then return end
    self.terminator_NeedsAWeaponNow = true
    self.term_NextNeedsAWeaponNow = CurTime() + math.random( 10, 20 )

end

-- can find item crates too
function ENT:FindWeapon( myTbl )
    local searchrange = self.WeaponSearchRange
    local wep
    local range
    local weight = -1

    -- also returns true for item_item_crate(s)
    local CanPickupWeapon = myTbl.CanPickupWeapon

    local seesEnemy = myTbl.IsSeeEnemy
    local distToEnemy = myTbl.DistToEnemy
    local ourHolstered = self:GetHolsteredWeapons()

    -- see if we can unholster a wep
    for holsteredWeap, _ in pairs( ourHolstered ) do
        if not IsValid( holsteredWeap ) then continue end
        if not CanPickupWeapon( self, holsteredWeap, true, myTbl ) then continue end

        local wepWeight = myTbl.GetWeightOfWeapon( self, holsteredWeap )
        local wepRange = myTbl.GetWeaponRange( self, holsteredWeap )

        if not wep or ( wepWeight > weight + 1 and wepRange >= distToEnemy ) then
            wep = holsteredWeap
            range = wepRange
            weight = wepWeight

        end
    end

    if IsValid( wep ) then return { wep = wep, weight = weight, range = range, isBox = nil } end

    local needsAWepNow = myTbl.terminator_NeedsAWeaponNow -- set by movement tasks if the enemy is unreachable
    local bestWep = myTbl.terminator_BestWeaponIEverFound
    local canPickupBest = IsValid( bestWep ) and CanPickupWeapon( self, bestWep, myTbl )

    if not canPickupBest and needsAWepNow then
        searchrange = 32000

    end

    local isBox
    local found
    if myTbl.AwarenessCheckRange >= searchrange and #myTbl.awarenessSubstantialStuff >= 1 then
        found = myTbl.awarenessSubstantialStuff -- save on a findinsphere if we can

    else
        found = ents.FindInSphere( self:GetPos(), searchrange )

    end

    for _, potentialWeap in ipairs( found ) do

        local wepsTbl = potentialWeap:GetTable()
        if not CanPickupWeapon( self, potentialWeap, false, myTbl, wepsTbl ) then continue end

        local wepWeight = myTbl.GetWeightOfWeapon( self, potentialWeap )

        if not wep or wepWeight > weight + 1 then
            local _, tr = terminator_Extras.PosCanSeeComplex( self:GetShootPos(), potentialWeap:WorldSpaceCenter(), self )
            if tr.Fraction > 0.25 then
                wep = potentialWeap

                local failedPathsToWeap = wep.failedWeaponPaths or 0
                if failedPathsToWeap > 2 and seesEnemy then
                    continue

                end
                local clearness = tr.Fraction - 1
                weight = wepWeight + ( clearness * 5 ) + ( -failedPathsToWeap * 20 )
                range = myTbl.GetWeaponRange( self, potentialWeap )
                isBox = wep:GetClass() == "item_item_crate"

            end
        end
    end
    local better = wep and not canPickupBest

    if not better and canPickupBest and wep then
        better = weight > myTbl.GetWeightOfWeapon( self, bestWep )

    end

    -- save best weapon
    if better then
        myTbl.terminator_BestWeaponIEverFound = wep

    end

    if not wep and canPickupBest and needsAWepNow then
        wep = bestWep
        weight = myTbl.GetWeightOfWeapon( self, bestWep )
        range = myTbl.GetWeaponRange( self, bestWep )
        isBox = wep:GetClass() == "item_item_crate"

    end

    return { wep = wep, weight = weight, range = range, isBox = isBox }

end

local function getTrackedDamage( me, wepOrClass )
    if IsValid( wepOrClass ) then
        local tracked = wepOrClass.terminator_TrackedDamageDealt or 0
        if me.trackedDamagingClasses and me.trackedDamagingClasses[ wepOrClass:GetClass() ] then
            tracked = tracked + me.trackedDamagingClasses[ wepOrClass:GetClass() ]

        end
        return tracked or 0

    elseif wepOrClass then
        if not me.trackedDamagingClasses then
            me.trackedDamagingClasses = {}

        end
        return me.trackedDamagingClasses[wepOrClass] or 0

    end
end
local function setTrackedDamage( me, wepOrClass, new )
    if IsValid( wepOrClass ) then
        wepOrClass.terminator_TrackedDamageDealt = new

    elseif wepOrClass and me.trackedDamagingClasses then
        if not me.trackedDamagingClasses then
            me.trackedDamagingClasses = {}

        end
        me.trackedDamagingClasses[wepOrClass] = new

    end
end

hook.Add( "PostEntityTakeDamage", "terminator_trackweapondamage", function( target, dmg )
    local attacker = dmg:GetAttacker()
    if not IsValid( attacker ) then return end
    if not attacker.isTerminatorHunterBased then return end

    local enem = attacker:GetEnemy()
    if not IsValid( enem ) then return end

    local targetIsVehicle = target.GetDriver
    if targetIsVehicle then
        if enem ~= target:GetDriver() then return end

    else
        if enem ~= target then return end

    end

    -- allow thrown crowbar + derivatives to actually get judged
    local inflictor = dmg:GetInflictor()
    local toJudgeWepOrClass = inflictor.terminator_Judger_WepClassToCredit
    if not toJudgeWepOrClass then
        toJudgeWepOrClass = attacker:GetActiveWeapon()

    end
    local trackedDamageDealt = getTrackedDamage( attacker, toJudgeWepOrClass )

    if not trackedDamageDealt then return end

    local dmgDealt = dmg:GetDamage()

    -- dont give up on burst firing weaps!
    if dmgDealt > 80 then
        dmgDealt = dmgDealt * 8
        if IsValid( toJudgeWepOrClass ) then
            toJudgeWepOrClass.terminator_IsBurst = true

        end

    elseif dmgDealt > 40 then
        dmgDealt = dmgDealt * 2

    end
    -- what a FUN wep!
    if dmg:IsExplosionDamage() then
        dmgDealt = dmgDealt * 2

    end

    setTrackedDamage( attacker, toJudgeWepOrClass, trackedDamageDealt + dmgDealt )

    timer.Simple( 0, function()
        if not IsValid( attacker ) then return end
        if attacker:Health() <= 0 then return end

        local goneTarget = not IsValid( target )
        if goneTarget or target:Health() <= 0 then
            if goneTarget or ( not target.term_DamageDealtTimes or target.term_DamageDealtTimes <= 1 ) then
                attacker:RunTask( "OnInstantKillEnemy" )

            else
                attacker:RunTask( "OnKillEnemy" )

            end
            target.term_DamageDealtTimes = nil
        else
            local old = target.term_DamageDealtTimes or 0
            target.term_DamageDealtTimes = old + 1 

        end
    end )
end )

--[[------------------------------------
    Name: NEXTBOT:GetAimVector
    Desc: Returns direction that used for weapon, including spread.
    Arg1: 
    Ret1: Vector | Aim direction.
--]]------------------------------------
function ENT:GetAimVector()
    local dir = self:GetEyeAngles():Forward()

    if self:HasWeapon() then
        local prof = self:GetCurrentWeaponProficiency() + 0.95
        local deg = 0 + ( 0.35 / prof )

        local velLeng = self:GetCurrentSpeed()
        if velLeng > 10 then
            deg = ( velLeng / 10 ) / prof

        end

        local active = self:GetActiveLuaWeapon()

        if active.NPC_CustomSpread then
            deg = self.WeaponSpread * ( active.NPC_CustomSpread / prof )

        elseif isfunction( active.GetNPCBulletSpread ) then
            deg = active:GetNPCBulletSpread( self:GetCurrentWeaponProficiency() ) / 4

        -- let the wep handle the spread
        elseif weapSpread( active ) ~= 0 then
            deg = 0

        end

        if self:IsCrouching() then
            deg = deg / 100

        end

        local nextOverrideWalk = self.term_nextMissingAlotWalk or 0

        local degToOverrideWalk = 11.25
        if active.terminator_NoLeading then
            degToOverrideWalk = degToOverrideWalk / 2

        end

        if self.IsSeeEnemy and deg > degToOverrideWalk and self.terminator_FiringIsAllowed and not self:inSeriousDanger() and nextOverrideWalk < CurTime() then
            self.term_nextMissingAlotWalk = CurTime() + 5
            if self:IsAngry() then
                local activeNotLua = self:GetActiveWeapon()
                local trackedDmg = getTrackedDamage( self, activeNotLua )
                if not self:IsCrouching() and trackedDmg > 100 and activeNotLua.terminator_ReallyLikesThisOne then
                    self.term_nextMissingAlotWalk = 0
                    self.overrideCrouch = CurTime() + 1

                end
            else-- walk if we miss with a boring weapon 
                self.forcedShouldWalk = CurTime() + 1 -- walk if we miss alot

            end

        end

        deg = deg / 180

        dir:Add( Vector( math.Rand( -deg, deg ), math.Rand( -deg, deg ), math.Rand( -deg, deg ) ) )

    end

    return dir
end

local dropWeps = CreateConVar( "termhunter_dropuselessweapons", 1, FCVAR_NONE, "Detect and drop useless weapons? Does not stop bot from dropping erroring weapons" )

-- is a weapon not being useful?

function ENT:JudgeWeapon()
    if self:IsFists() then return end
    if not dropWeps:GetBool() then return end
    if not IsValid( self:GetEnemy() ) then return end
    if not self.NothingOrBreakableBetweenEnemy then return end

    local myWeapon = self:GetActiveWeapon()
    if not IsValid( myWeapon ) then return end
    if myWeapon.terminator_IgnoreWeaponUtility then return end
    local weapsWeightToMe = self:GetWeightOfWeapon( myWeapon )

    local trackedAttackAttempts = myWeapon.terminator_TrackedAttackAttempts or 0
    myWeapon.terminator_TrackedAttackAttempts = trackedAttackAttempts + 1

    local myWepsClass = myWeapon:GetClass()
    local trackedDamageDealt = getTrackedDamage( self, myWeapon ) or 0

    local hasEvenDoneDamage = nil
    if trackedDamageDealt > 0 then
        hasEvenDoneDamage = true

    end

    -- tolerance for weapons
    local bonusAttackAttempts = 30
    local tolerance = 4
    if weapSpread( self:GetActiveLuaWeapon() ) or hasEvenDoneDamage then
        -- weapon that has spread!?!!? (real bullets!)
        -- or we've done damage with sometime in the past
        bonusAttackAttempts = 60
        tolerance = 8

    elseif self:IsMeleeWeapon( myWeapon ) then
        -- be much less forgiving with melee weaps!
        bonusAttackAttempts = 10
        tolerance = 1

    end

    local offsettedAttackAttempts = trackedAttackAttempts + -bonusAttackAttempts
    local giveUpOnWeap = nil

    if offsettedAttackAttempts > bonusAttackAttempts and not hasEvenDoneDamage then
        giveUpOnWeap = true

    elseif ( offsettedAttackAttempts / 2 ) > trackedDamageDealt and not myWeapon.terminator_NoLeading then
        -- see if this helps!
        myWeapon.terminator_NoLeading = true

    elseif ( offsettedAttackAttempts / tolerance ) > trackedDamageDealt then
        terminator_Extras.OverrideWeaponWeight( myWepsClass, weapsWeightToMe + -0.5 )
        local weightToMe = self:GetWeightOfWeapon( myWeapon )

        if weightToMe <= 2 and not hasEvenDoneDamage then
            giveUpOnWeap = true

        elseif weightToMe <= -2 then
            giveUpOnWeap = true

        end
    end
    if giveUpOnWeap then
        print( "Terminator spits in the face of a useless weapon\n" .. myWepsClass .. "\nphTOOEY!" )
        self:Anger( 5 )
        myWeapon.terminatorCrappyWeapon = true
        self:DropWeapon( true )

    end
    if not myWeapon.terminator_ReallyLikesThisOne and trackedDamageDealt > math.max( trackedAttackAttempts * 25, 250 ) then
        -- i like this one!
        myWeapon.terminator_ReallyLikesThisOne = true
        print( "Terminator finds deep satisfaction in using\n" .. myWepsClass )
        terminator_Extras.OverrideWeaponWeight( myWepsClass, weapsWeightToMe + 15 )

    end
end


function ENT:WeaponIsPlacable( wep )
    wep = wep or self:GetWeapon()

    if not wep.termPlace_ScoringFunc then return end
    if not wep.termPlace_PlacingFunc then return end

    return true

end