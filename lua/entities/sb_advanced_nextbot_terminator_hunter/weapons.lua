-- Lua analogs to engine/unsupported weapons
local EngineAnalogs = {
    weapon_ar2 = "weapon_ar2_sb_anb",
    weapon_smg1 = "weapon_smg1_sb_anb",
    weapon_pistol = "weapon_pistol_sb_anb",
    weapon_357 = "weapon_357_sb_anb",
    weapon_crossbow = "weapon_crossbow_sb_anb_better",
    weapon_rpg = "weapon_rpg_sb_anb_better",
    weapon_shotgun = "weapon_shotgun_sb_anb",
    weapon_crowbar = "weapon_crowbar_sb_anb",
    weapon_stunstick = "weapon_stunstick_sb_anb",
    pist_weagon = "pist_weagon_sb_anb", -- lol
    manhack_welder = "manhack_welder_sb_anb",
    weapon_flechettegun = "weapon_flechettegun_sb_anb",
    gmod_camera = "gmod_camera_sb_anb",
    weapon_frag = "weapon_frag_sb_anb",
    --weapon_physcannon = "weapon_physcannon_sb_anb",
}

local crateClass = "item_item_crate"

local EngineAnalogsReverse = {}
for k,v in pairs( EngineAnalogs ) do EngineAnalogsReverse[v] = k end

termHunter_WeaponAnalogs = EngineAnalogs

local _IsValid = IsValid

--[[------------------------------------
    Name: NEXTBOT:Give
    Desc: Gives weapon to bot.
    Arg1: string | wepname | Class name of weapon.
    Ret1: Weapon | Weapon given to bot. Returns NULL if failed to give this weapon.
--]]------------------------------------
function ENT:Give(wepname)
    local wep = ents.Create(wepname)

    if _IsValid(wep) then
        if not wep:IsScripted() and not EngineAnalogs[wepname] then
            wep:Remove()

            return NULL
        end

        wep:SetPos(self:GetPos())
        wep:SetOwner(self)
        wep:Spawn()
        wep:Activate()

        return self:SetupWeapon(wep)
    end
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
function ENT:SetupWeapon(wep)

    if not _IsValid(wep) or wep==self:GetActiveWeapon() then return end

    -- Cannot hold engine weapons
    if not wep:IsScripted() and not EngineAnalogs[wep:GetClass()] then return end

    -- Clear old weapon
    if self:HasWeapon() then
        self:GetActiveWeapon():Remove()
    end

    ProtectedCall(function() self:OnWeaponEquip(wep) end)

    self:SetActiveWeapon(wep)

    -- Custom lua weapon analog for engine weapon, this need to have WEAPON metatable
    if EngineAnalogs[wep:GetClass()] then
        local actwep = ents.Create(EngineAnalogs[wep:GetClass()])
        actwep:SetOwner(self)
        actwep:Spawn()
        actwep:Activate()
        actwep:SetParent(wep)
        actwep:SetLocalPos(vector_origin)
        actwep:SetLocalAngles(angle_zero)
        actwep:PhysicsDestroy()
        actwep:AddSolidFlags(FSOLID_NOT_SOLID)
        actwep:AddEffects(EF_BONEMERGE)
        actwep:SetTransmitWithParent(true)

        actwep:SetClip1(wep:Clip1())
        actwep:SetClip2(wep:Clip2())

        hook.Add("Think",actwep,function(self)
            if not _IsValid( wep ) then return end
            wep:SetClip1(self:Clip1())
            wep:SetClip2(self:Clip2())
        end)

        hook.Add("EntityRemoved",actwep,function(self,ent)
            if ent==wep then self:Remove() end
        end)
        actwep:DeleteOnRemove(wep)

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
    actwep:SetWeaponHoldType(wep:GetHoldType())

    self:ReloadWeaponData()

    -- Actually setup weapon. Very similar to engine code.

    wep:SetVelocity(vector_origin)
    wep:RemoveSolidFlags(FSOLID_TRIGGER)
    wep:RemoveEffects(EF_ITEM_BLINK)
    wep:PhysicsDestroy()

    wep:SetParent(self)
    wep:SetMoveType(MOVETYPE_NONE)
    wep:AddEffects(EF_BONEMERGE)
    wep:AddSolidFlags(FSOLID_NOT_SOLID)
    wep:SetLocalPos(vector_origin)
    wep:SetLocalAngles(angle_zero)

    wep:SetTransmitWithParent(true)

    ProtectedCall(function() actwep:OwnerChanged() end)
    ProtectedCall(function() actwep:Equip(self) end)

    self:EmitSound( "Flesh.Strain", 80, 160, 0.8 )

    return actwep
end

--[[------------------------------------
    Name: NEXTBOT:DropWeapon
    Desc: Drops current active weapon.
    Arg1: (optional) Vector | velocity | Sets velocity of weapon. Max speed is 400.
    Arg2: (optional) bool | justdrop | If true, just drop weapon from current hand position. Don't apply velocity and position.
    Ret1: Weapon | Dropped weapon. If active weapon is lua analog of engine weapon, then this will be engine weapon, not lua analog.
--]]------------------------------------
function ENT:DropWeapon( velocity, justdrop )
    local wep = self:GetActiveWeapon()
    if not _IsValid( wep ) then return end

    local actwep = self:GetActiveLuaWeapon()

    if not justdrop then
        velocity = velocity or self:GetEyeAngles():Forward() * 200
        local spd = velocity:Length()
        velocity = velocity / spd
        velocity:Mul( math.min( spd, 400 ) )
    end

    self:SetActiveWeapon( NULL )

    -- Unparenting weapon. Very similar to engine code.

    wep:SetParent()
    wep:RemoveEffects( EF_BONEMERGE )
    wep:RemoveSolidFlags( FSOLID_NOT_SOLID )
    wep:CollisionRulesChanged()

    wep:SetOwner( NULL )

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

    ProtectedCall( function() actwep:OwnerChanged() end )
    ProtectedCall( function() actwep:OnDrop() end )

    -- Restoring engine weapon from lua analog
    if wep ~= actwep then
        if actwep:Clip1() > 0 then
            if not _IsValid( wep ) then return end
            wep:SetClip1( actwep:Clip1() )

        else
            timer.Simple( 0, function()
                if not _IsValid( wep ) then return end
                wep:SetClip1( wep:GetMaxClip1() )

            end )

        end
        if actwep:Clip2() > 0 then
            if not _IsValid( wep ) then return end
            wep:SetClip2( actwep:Clip2() )

        else
            timer.Simple( 0, function()
                if not _IsValid( wep ) then return end
                wep:SetClip2( wep:GetMaxClip2() )

            end )
        end

        actwep:DontDeleteOnRemove( wep )
        actwep:Remove()

    end

    ProtectedCall( function() self:OnWeaponDrop( wep ) end )

    if not justdrop then
        wep:SetPos( self:GetShootPos() )
        wep:SetAngles( self:GetEyeAngles() )

        local phys = wep:GetPhysicsObject()
        if _IsValid( phys ) then
            phys:AddVelocity( velocity )
            phys:AddAngleVelocity( Vector( 200, 200, 200 ) )

        else
            wep:SetVelocity( velocity )

        end
    else
        local iBIndex,iWeaponBoneIndex

        if wep:GetBoneCount() > 0 then
            for boneIndex = 0, wep:GetBoneCount() - 1 do
                iBIndex = self:LookupBone( wep:GetBoneName( boneIndex ) )

                if iBIndex then
                    iWeaponBoneIndex = boneIndex
                    break

                end
            end

            if not iBIndex then
                iWeaponBoneIndex = wep:LookupBone( "ValveBiped.Weapon_bone" )
                iBIndex = iWeaponBoneIndex and self:LookupBone( "ValveBiped.Weapon_bone" )

            end
        else
            iWeaponBoneIndex = wep:LookupBone( "ValveBiped.Weapon_bone" )
            iBIndex = iWeaponBoneIndex and self:LookupBone( "ValveBiped.Weapon_bone" )

        end

        if iBIndex then
            local wm = wep:GetBoneMatrix( iWeaponBoneIndex )
            local m = self:GetBoneMatrix( iBIndex )

            local lp,la = WorldToLocal( wep:GetPos(), wep:GetAngles(), wm:GetTranslation(), wm:GetAngles() )
            local p,a = LocalToWorld( lp, la, m:GetTranslation(), m:GetAngles() )

            wep:SetPos( p )
            wep:SetAngles( a )

        else
            local dir = self:GetAimVector()
            dir.z = 0

            wep:SetPos( self:GetShootPos() + dir * 10 )

        end

        local phys = wep:GetPhysicsObject()
        if _IsValid( phys ) then
            phys:AddVelocity( self.loco:GetVelocity() )

        else
            wep:SetVelocity( self.loco:GetVelocity() )

        end
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
    if isnumber( wep.NPC_NextPrimaryFireT ) then -- vj BASE
        return wep.NPC_NextPrimaryFireT
    elseif wep and self.m_WeaponData.Primary.NextShootTime then
        return self.m_WeaponData.Primary.NextShootTime
    elseif wep.GetNextPrimaryFire then
        return wep:GetNextPrimaryFire()
    end
end

--[[------------------------------------
    Name: NEXTBOT:CanWeaponPrimaryAttack
    Desc: Returns can bot do primary attack or not.
    Arg1: 
    Ret1: bool | Can do primary attack
--]]------------------------------------
function ENT:CanWeaponPrimaryAttack()
    local wep = self:GetActiveLuaWeapon() or self:GetActiveWeapon()
    if not IsValid( wep ) then return end
    local noErrors, result = pcall( function() -- no MORE ERRORS!

        local nextShoot = self:AssumeWeaponNextShootTime() or 0

        if not wep or CurTime() < nextShoot then return end
        if wep.CanPrimaryAttack and not wep:CanPrimaryAttack() then return end

        return true

    end )
    if noErrors == false then
        -- this makes me SICK!
        terminator_Extras.OverrideWeaponWeight( wep:GetClass(), -100 )
        wep.terminatorCrappyWeapon = true
        print( "Terminator fired buggy weapon!\ndisgustang!!!!" )
        ErrorNoHaltWithStack( result )
        return

    end
    return result

end

--[[------------------------------------
    Name: NEXTBOT:WeaponPrimaryAttack
    Desc: Does primary attack from bot's active weapon. This also uses burst data from weapon.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:WeaponPrimaryAttack()
    local wep = self:GetActiveLuaWeapon() or self:GetWeapon()
    if not self:CanWeaponPrimaryAttack() then return end

    local data = self.m_WeaponData.Primary

    local isSetupProperly = isfunction( wep.GetNPCBurstSettings ) and isfunction( wep.GetNPCRestTimes )

    local noErrors, theError = pcall( function() -- cant be too safe here

        if isSetupProperly then --SB base weapon probably

            local npcShootCall, shootCallsError = pcall( function() wep:NPCShoot_Primary( self:GetShootPos(), self:GetAimVector() ) end )
            if npcShootCall == false then
                wep.terminatorCrappyWeapon = true
                print( "Terminator fired buggy weapon!\ndisgustang!!!!" )
                self:DropWeapon()
                print( shootCallsError )
                return

            end

            self:DoRangeGesture()

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
                local bmin, bmax, frate = wep:GetNPCBurstSettings()
                data.NextShootTime = math.max( CurTime() + frate, data.NextShootTime )

            end

        elseif wep.NPCShoot_Primary then --some other kind of weapon
            --debugoverlay.Line( self:GetShootPos(), self:GetShootPos() + self:GetAimVector() * 100, 20  )
            self:fakeVjBaseWeaponFiring( wep )

        elseif _IsValid( wep ) then
            wep:PrimaryAttack()

        end
    end )
    if noErrors == false then
        -- disgustang
        terminator_Extras.OverrideWeaponWeight( wep:GetClass(), -100 )
        wep.terminatorCrappyWeapon = true
        print( "Terminator fired buggy weapon!\ndisgustang!!!!" )
        ErrorNoHaltWithStack( theError )

    end
end

--[[------------------------------------
    Name: NEXTBOT:CanWeaponSecondaryAttack
    Desc: Returns can bot do secondary attack or not.
    Arg1: 
    Ret1: bool | Can do secondary attack
--]]------------------------------------
function ENT:CanWeaponSecondaryAttack()
    if not self:HasWeapon() or CurTime()<self.m_WeaponData.Secondary.NextShootTime then return false end
    
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
    if not self:CanWeaponSecondaryAttack() then return end
    
    local wep = self:GetActiveLuaWeapon()
    
    ProtectedCall(function() wep:NPCShoot_Secondary(self:GetShootPos(),self:GetAimVector()) end)
    self:DoRangeGesture()
end

--[[------------------------------------
    Name: NEXTBOT:GetAimVector
    Desc: Returns direction that used for weapon, including spread.
    Arg1: 
    Ret1: Vector | Aim direction.
--]]------------------------------------
function ENT:GetAimVector()
    local dir = self:GetEyeAngles():Forward()
    
    if self:HasWeapon() then
        local deg = 0.4
        local active = self:GetActiveLuaWeapon()
        if isfunction( active.GetNPCBulletSpread ) then
            deg = active:GetNPCBulletSpread( self:GetCurrentWeaponProficiency() ) / 4
            deg = math.sin( math.rad( deg ) ) / 1.5
        end
        
        dir:Add(Vector(math.Rand(-deg,deg),math.Rand(-deg,deg),math.Rand(-deg,deg)))
    end
    
    return dir
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
    if not self:HasWeapon() then return end
    
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

local cratesMaxDistFromGround = 75^2

function ENT:CanPickupWeapon(wep)
    if not _IsValid( wep ) then return false end
    if wep.terminatorCrappyWeapon then return false end
    if _IsValid( wep:GetOwner() ) then return false end
    if _IsValid( wep:GetParent() ) then return false end

    local blockWeaponNoticing = wep.blockWeaponNoticing or 0
    if blockWeaponNoticing > CurTime() then return end

    local conventionalNpcWeap = ( wep:IsScripted() and wep.CanBePickedUpByNPCs and wep:CanBePickedUpByNPCs() )
    local class = wep:GetClass()
    if class == crateClass and self.HasFists then
        local wepPos = wep:GetPos()
        local result = terminator_Extras.getNearestPosOnNav( wepPos )
        if result.area and result.area.IsValid and result.area:IsValid() and result.pos:DistToSqr( wepPos ) < cratesMaxDistFromGround then
            return true

        else
            return false

        end
    end
    if not conventionalNpcWeap and not EngineAnalogs[class] then return false end
    if _IsValid( wep.terminatorTaking ) and wep.terminatorTaking ~= self then return false end
    if self:GetWeightOfWeapon( wep ) < -50 then return false end

    if self:EnemyIsLethalInMelee() and wep:GetPos():DistToSqr( self:GetEnemy():GetPos() ) < 500^2 then return false end

    return true

end

function ENT:GetWeightOfWeapon( wep )
    if not _IsValid( wep ) then return -1 end
    local class = wep:GetClass()
    if class == crateClass then
        return 1
    end
    return terminator_Extras.EngineAnalogWeights[class] or wep:GetWeight()

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

    if not _IsValid( wep ) then return false end 
    if not wep.GetCapabilities then return false end

    local caps = wep:GetCapabilities()
    if bit.band( caps, CAP_WEAPON_MELEE_ATTACK1 ) ~= 0 then return true end
    if bit.band( caps, CAP_INNATE_MELEE_ATTACK1 ) ~= 0 then return true end
    if wep.IsMeleeWeapon == true then return true end

    return false

end

function ENT:IsFists()
    local wep = self:GetWeapon()
    if not _IsValid( wep ) then return end
    if wep:GetClass() == self.TERM_FISTS then return true end

    return nil

end

function ENT:DoFists()
    if self:IsFists() then return end
    if not self.DontDropPrimary then
        self:DropWeapon()


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

function ENT:GetWeaponRange()
    local wep = self:GetActiveLuaWeapon() or self:GetActiveWeapon()

    if not _IsValid( wep ) then return math.huge end
    if wep.ArcCW then return wep.Range * 52 end
    if isnumber( wep.Range ) then return wep.Range end
    if isnumber( wep.MeleeWeaponDistance ) then return wep.MeleeWeaponDistance end
    if string.find( wep:GetClass(), "shotgun" ) then return 1000 end

    return math.huge

end

hook.Add("PlayerCanPickupWeapon","SBAdvancedNextBot",function(ply,wep)
    -- Do not allow pickup when bot carries this weapon
    if _IsValid(wep:GetOwner()) and wep:GetOwner().SBAdvancedNextBot then
        return false
    end

    -- Do not allow pickup engine weapon analogs
    if EngineAnalogsReverse[wep:GetClass()] then
        return false
    end
end )

function ENT:HasWeapon2()
    local realWeapon = self:GetActiveWeapon():IsValid() and ( CLIENT or self:GetActiveLuaWeapon():IsValid() )
    if not realWeapon then return false end
    local unarmed = self:GetWeapon():GetClass() == self.TERM_FISTS
    return realWeapon and not unarmed
end

function ENT:canGetWeapon()
    local nextNewPath = self.nextNewPath or 0
    if nextNewPath > CurTime() then return false end

    -- dont allow spam, this is set at the end of dropweapon!
    local nextWeaponPickup = self.terminator_NextWeaponPickup or 0
    if nextWeaponPickup > CurTime() then return false end

    local armed = self:HasWeapon2()
    local nextSearch = self.nextWeapSearch or 0
    if nextSearch < CurTime() then
        self.nextWeapSearch = CurTime() + math.random( 1, 2 )
        self.cachedNewWeapon = self:FindWeapon()

    end
    local newWeap = self.cachedNewWeapon
    if armed then
        local weapWeight = self:GetWeightOfWeapon( newWeap )
        local currWeapWeight = self:GetWeightOfWeapon( self:GetActiveWeapon() )
        local betterWeapOrJustHappyTohave = weapWeight > ( currWeapWeight + 1 ) or ( self:IsFists() and weapWeight <= 1 and not self.IsSeeEnemy )
        local canGet = _IsValid( newWeap ) and betterWeapOrJustHappyTohave
        return canGet, newWeap

    else
        return _IsValid( newWeap ), newWeap

    end
end

-- can find item crates too
function ENT:FindWeapon()
    local searchrange = 2000
    local wep,weight

    local _CanPickupWeapon = self.CanPickupWeapon

    for _, potentialWeap in ipairs( ents.FindInSphere( self:GetPos(), searchrange ) ) do

        if not _CanPickupWeapon( self, potentialWeap ) then continue end

        local wepWeight = self:GetWeightOfWeapon( potentialWeap )

        if not wep or wepWeight > weight + 1 then
            local _, tr = terminator_Extras.PosCanSeeComplex( self:GetShootPos(), potentialWeap:WorldSpaceCenter(), self )
            if tr.Fraction > 0.25 then
                wep = potentialWeap

                local failedPathsToWeap = wep.failedWeaponPaths or 0
                weight = wepWeight + ( -tr.Fraction * 5 ) + ( -failedPathsToWeap * 5 )

            end
        end
    end
    return wep

end

hook.Add( "EntityTakeDamage", "terminator_trackweapondamage", function( target, dmg )
    local attacker = dmg:GetAttacker()
    if not IsValid( attacker ) then return end
    if not attacker.isTerminatorHunterBased then return end
    local weapEquipped = attacker:GetWeapon()
    if not IsValid( weapEquipped ) then return end

    local trackedDamageDealt = weapEquipped.terminator_TrackedDamageDealt or 0

    local dmgDealt = dmg:GetDamage()

    -- dont give up on burst firing weaps!
    if dmgDealt > 80 then
        dmgDealt = dmgDealt * 8

    elseif dmgDealt > 40 then
        dmgDealt = dmgDealt * 2

    end

    weapEquipped.terminator_TrackedDamageDealt = trackedDamageDealt + dmgDealt

end )

--TODO: this is way too quick to mark weapons as bad in singleplayer for some reason

function ENT:JudgeWeapon()
    if self:IsFists() then return end
    if not IsValid( self:GetEnemy() ) then return end

    local myWeapon = self:GetWeapon()
    if not IsValid( myWeapon ) then return end
    if myWeapon.terminator_IgnoreWeaponUtility then return end
    local weapsWeightToMe = self:GetWeightOfWeapon( myWeapon )

    trackedAttackAttempts = myWeapon.terminator_TrackedAttackAttempts or 0
    myWeapon.terminator_TrackedAttackAttempts = trackedAttackAttempts + 1

    local offset = 100
    if self:IsMeleeWeapon( myWeapon ) then
        -- be much less forgiving with melee weaps!
        offset = 15

    end
    local offsettedAttackAttempts = trackedAttackAttempts + -offset
    local trackedDamageDealt = myWeapon.terminator_TrackedDamageDealt or 0
    local trackedDamageScaled = trackedDamageDealt * 2

    if offsettedAttackAttempts > trackedDamageScaled then
        terminator_Extras.OverrideWeaponWeight( myWeapon:GetClass(), weapsWeightToMe + -5 )
        myWeapon.terminatorCrappyWeapon = true
        print( "Terminator spits in the face of a useless weapon\nphTOOEY!" )

        local weightToMe = self:GetWeightOfWeapon( myWeapon )
        if weightToMe <= 2 then
            self:DropWeapon()

        end
    end
    if not myWeapon.terminator_ReallyLikesThisOne and trackedDamageDealt > math.max( trackedAttackAttempts * 25, 250 ) then
        -- i like this one!
        myWeapon.terminator_ReallyLikesThisOne = true
        terminator_Extras.OverrideWeaponWeight( myWeapon:GetClass(), weapsWeightToMe + 15 )

    end
end