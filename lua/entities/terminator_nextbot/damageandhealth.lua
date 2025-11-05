
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"

local isnumber = isnumber
local CurTime = CurTime

local entMeta = FindMetaTable( "Entity" )

function ENT:IsImmuneToDmg( _dmg ) -- stub, for ents based off this!
end

function ImmuneCheck( self, dmg )
    if self:IsImmuneToDmg( dmg ) then return true end

    local immuneMask = self.term_DMG_ImmunityMask
    if immuneMask and bit.band( dmg:GetDamageType(), immuneMask ) ~= 0 then dmg:ScaleDamage( 0 ) return true end

end

--[[------------------------------------
    THIS MANAGES THE BODYGROUP DAMAGE
    it's very hardcoded, some of the oldest code in the repo
--]]------------------------------------
ENT.BGrpHealth = {}
ENT.OldBGrpSteps = {}
ENT.MedCal = 4
ENT.HighCal = 80

ENT.BGrpMaxHealth = {
    [0] = 10,
    [1] = 150,
    [2] = 300,
    [3] = 100,
    [4] = 100,
    [5] = 120,
    [6] = 120,
}
ENT.BodyGroups = {
    ["Glasses"] = 0,
    ["Head"] = 1,
    ["Torso"] = 2,
    ["RArm"] = 3,
    ["LArm"] = 4,
    ["RLeg"] = 5,
    ["LLeg"] = 6,
}
ENT.HitTranslate = {
    [1] = { 0, 1 },
    [2] = { 2 },
    [3] = { 2 },
    [4] = { 4 },
    [5] = { 3 },
    [6] = { 6 },
    [7] = { 5 },
}
ENT.GroupSteps = {
    [0] = { [4] = 1, [3] = 2, [3] = 2, [2] = 2, [1] = 3 },
    [1] = { [3] = 0, [2] = 1, [1] = 2 },
    [2] = { [3] = 0, [2] = 0, [1] = 1 },
    [3] = { [3] = 0, [2] = 0, [1] = 1 },
    [4] = { [3] = 0, [2] = 0, [1] = 1 },
    [5] = { [3] = 0, [2] = 0, [1] = 1 },
    [6] = { [3] = 0, [2] = 0, [1] = 1 },
    --[1] = { 0, 1, 2 },
}

ENT.Rics = {
    "weapons/fx/rics/ric3.wav",
    "weapons/fx/rics/ric5.wav",
}
ENT.Chunks = {
    "physics/body/body_medium_break2.wav",
    "physics/body/body_medium_break3.wav",
    "physics/body/body_medium_break4.wav",
}
ENT.Whaps = {
    "physics/body/body_medium_impact_hard1.wav",
    "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav",
}
ENT.Hits = {
    "physics/metal/metal_sheet_impact_hard8.wav",
    "physics/metal/metal_sheet_impact_hard7.wav",
    "physics/metal/metal_sheet_impact_hard6.wav",
    "physics/metal/metal_sheet_impact_hard2.wav",
}
ENT.Creaks = {
    "physics/metal/metal_box_strain1.wav",
    "physics/metal/metal_box_strain2.wav",
    "physics/metal/metal_box_strain3.wav",
    "physics/metal/metal_box_strain4.wav",
}

local function BodyGroupDamageThink( self, Group, Damage, Pos, Silent ) -- on 1 bodygroup!
    if not isnumber( Group ) then return end
    if self:GetModel() ~= ARNOLD_MODEL then return end -- only this model has the correct bodygroups

    local CurrHSteps = self.GroupSteps[Group]
    if not istable( CurrHSteps ) then return end

    if not isnumber( self.BGrpHealth[Group] ) then -- first damage!
        self.BGrpHealth[Group] = self.BGrpMaxHealth[Group] -- set to max hp
        self.OldBGrpSteps[Group] = 10

    end

    self.BGrpHealth[Group] = math.Clamp( self.BGrpHealth[Group] + -Damage, 1, math.huge )

    local Steps = table.Count( self.GroupSteps[Group] )
    local CurrStep = math.ceil( ( self.BGrpHealth[Group] / self.BGrpMaxHealth[Group] ) * Steps )
    local OldStep = self.OldBGrpSteps[Group]

    if OldStep <= CurrStep then return end
    self.OldBGrpSteps[Group] = CurrStep
    if Group ~= 0 then -- state decreased, DAMAGE EFFECTS!
        if not Silent then
            self:EmitSound( table.Random( self.Whaps ), 75, math.random( 85, 90 ) )
            self:EmitSound( table.Random( self.Chunks ), 75, math.random( 115, 120 ) )

        end
        local Data = EffectData()
        Data:SetOrigin( Pos )
        Data:SetColor( 0 )
        Data:SetScale( 1 )
        Data:SetRadius( 1 )
        Data:SetMagnitude( 1 )
        util.Effect( "BloodImpact", Data )

    end
    if not isnumber( CurrHSteps[CurrStep] ) then return end
    self:SetBodygroup( Group, self.GroupSteps[Group][CurrStep] )

end

local function BodyGroupDamage( self, ToBGs, BgDamage, Damage, Silent ) -- on multiple bodygroups!
    local var = 0
    local Count = table.Count( ToBGs )
    while var < Count do
        var = var + 1
        local BGroup = ToBGs[var]
        BodyGroupDamageThink( self, BGroup, BgDamage, Damage:GetDamagePosition(), Silent )

    end
end

local function MedCalRics( self ) -- medium caliber ricochet sound
    self:EmitSound( table.Random( self.Rics ), 75, math.random( 92, 100 ), 1, CHAN_AUTO )

end

local function MedDamage( self, Damage ) -- medium damage sound
    self:EmitSound( table.Random( self.Hits ), 85, math.random( 105, 110 ), 1, CHAN_AUTO )

    if Damage:IsBulletDamage() then
        self:EmitSound( table.Random( self.Rics ), 85, math.random( 75, 80 ), 1, CHAN_AUTO )

    end
end

function ENT:CatDamage() -- cataSTROPIC DAMAGE sound
    self:EmitSound( table.Random( self.Creaks ), 85, 150, 1, CHAN_AUTO )
    self:EmitSound( table.Random( self.Hits ), 85, 80, 1, CHAN_AUTO )

end

--[[------------------------------------
    END hardcoded bodygroup damage
    Below hooks into it, but it handles damage for everything
--]]------------------------------------

-- dmg with bodygroup data ( bullets )
local function OnDamaged( damaged, Hitgroup, Damage )
    -- we only handle bullet damage here, other damage is handled in OnTakeDamage
    if not Damage:IsBulletDamage() then return end

    -- only handle terminator damage
    if not damaged.isTerminatorHunterBased then return end

    -- simple support for enemies that are immune to damagetypes
    if ImmuneCheck( damaged, Damage ) then return true end

    -- main damage hook, can return true inside to block damage
    if damaged:PostTookDamage( Damage ) then return true end

    -- damage hook with hitgroup data
    if damaged:PostTookBulletDamage( Damage, Hitgroup ) then return true end

    -- metal skeleton damage resist and sounds
    if damaged.DoMetallicDamage then
        local ToBGs
        local BgDamage
        local DamageDealt = Damage:GetDamage()

        if DamageDealt >= damaged.HighCal then -- strong weapon!
            BgDamage = Damage:GetDamage() * 1.5
            Damage:SetDamage( DamageDealt * 0.4 )
            MedDamage( damaged, Damage )
            MedCalRics( damaged )

        elseif DamageDealt > damaged.MedCal then -- weapon is crap
            BgDamage = Damage:GetDamage() / 2
            Damage:SetDamage( 1 )

            MedCalRics( damaged )

        else -- weapon is too weak to even do damage, or pierce the skin
            BgDamage = Damage:GetDamage() / 15
            Damage:SetDamage( 0 )

        end

        if BgDamage then
            -- do mdl check here, non-term model npcs still have an exoskeleton!
            -- if you really dont want stuff to make ricochet stuff, set DoMetallicDamage to nil
            if damaged:GetModel() ~= ARNOLD_MODEL then return end

            ToBGs = damaged.HitTranslate[Hitgroup] -- translate from hitgroup to bodygroups on that hitgroup
            if not ToBGs then return end

            BodyGroupDamage( damaged, ToBGs, BgDamage, Damage )

        end
    end

    -- ouch
    damaged:HandleFlinching( Damage, Hitgroup )

end

hook.Add( "ScaleNPCDamage", "term_straw_terminator_damage", function( ... ) OnDamaged( ... ) end )


-- dmg w/o bodygroup data
function ENT:OnTakeDamage( Damage )
    self.lastDamagedTime = CurTime()

    -- bullet damage is handled above since that hook has bodygroup data
    if Damage:IsBulletDamage() then return end

    -- simple support for enemies that are immune to damagetypes
    if ImmuneCheck( self, Damage ) then return true end

    -- main damage hook, can return true inside to block damage
    if self:PostTookDamage( Damage ) then return true end

    -- horrible evil immortal zombie torso bug
    if Damage:GetDamage() >= 1 and self:Health() <= 0 and ( not self.Term_DyingUntil or self.Term_DyingUntil < CurTime() ) then -- HACK!
        SafeRemoveEntityDelayed( self, 1 )

    end

    -- metal skeleton damage resist and sounds
    if self.DoMetallicDamage then
        local attacker = Damage:GetAttacker()
        local BgDamage
        local ToBGs
        local SilentBgDmg

        if IsValid( attacker ) then
            local class = attacker:GetClass()

            -- instakilling doors!
            -- kill their damage and try to get the hell out of their way
            if class == "func_door_rotating" or class == "func_door" then
                local newDmg = math.Clamp( Damage:GetDamage(), 0, 25 )
                Damage:SetDamage( newDmg )
                self:ReallyAnger( 10 )
                self.overrideMiniStuck = true

            end
        end

        if Damage:IsDamageType( DMG_BLAST ) then
            local DamageDamage = Damage:GetDamage()
            if DamageDamage > 60 then -- ignore minor explosions
                DamageDamage = DamageDamage * 0.9 -- minor resist
                Damage:SetDamage( math.Clamp( DamageDamage, 0, terminator_Extras.healthDefault / 2.9 ) ) -- default to at least ~3 shots to kill term

                BgDamage = 40 + DamageDamage * 0.5
                ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
                table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )

                self:CatDamage()

            end
        elseif Damage:IsDamageType( DMG_ACID ) or Damage:IsDamageType( DMG_POISON ) then -- that has no effect on my skeleton!
            Damage:ScaleDamage( 0 )

            BgDamage = 40 -- but ow ouch my skin!
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

        elseif Damage:IsDamageType( DMG_SHOCK ) then
            if self.ShockDamageImmune then -- glee!
                Damage:ScaleDamage( 0.01 )

            else
                Damage:ScaleDamage( 0.5 )

            end

            BgDamage = 140
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

        elseif Damage:IsDamageType( DMG_DISSOLVE ) and Damage:GetDamage() >= 455 then --combine ball!
            Damage:SetDamage( terminator_Extras.healthDefault * 0.55 ) -- two shot kill

            BgDamage = 140 -- very effective!
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

            table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )

            local potentialBall = Damage:GetInflictor()

            if string.find( potentialBall:GetClass(), "ball" ) then
                potentialBall:Fire( "Explode" )

            end

            self:CatDamage()
            self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )

        -- fire damage, needs to support vfire...
        elseif Damage:IsDamageType( DMG_BURN ) or Damage:IsDamageType( DMG_SLOWBURN ) or ( Damage:IsDamageType( DMG_DIRECT ) and ( IsValid( attacker ) and string.find( attacker:GetClass(), "fire" ) ) ) then
            Damage:ScaleDamage( 0.05 ) -- dont ignore instakill damage, eg, lava

            BgDamage = 1
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

            table.remove( ToBGs, math.random( 0, 6 ) )

        elseif Damage:IsDamageType( DMG_CLUB ) then -- likely another terminator punching us!
            local DamageDamage = Damage:GetDamage()
            Damage:ScaleDamage( 0.5 )

            BgDamage = DamageDamage / 2
            SilentBgDmg = DamageDamage < 40
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

            table.remove( ToBGs, math.random( 0, 6 ) )
            table.remove( ToBGs, math.random( 0, 6 ) )

        -- sharp melee
        elseif Damage:IsDamageType( DMG_SLASH ) then
            local DamageDamage = Damage:GetDamage()

            BgDamage = DamageDamage / 1.5 -- takes chunks out of us
            SilentBgDmg = DamageDamage < 40
            Damage:ScaleDamage( 0.15 ) -- but our skeleton is tough!

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, 6 ) )
            table.remove( ToBGs, math.random( 0, 6 ) )

        elseif Damage:IsDamageType( DMG_CRUSH ) then
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }

            if Damage:GetDamage() < 100 then -- try harder!
                Damage:ScaleDamage( 0.15 )

                table.remove( ToBGs, math.random( 0, 6 ) )
                table.remove( ToBGs, math.random( 0, 6 ) )
                table.remove( ToBGs, math.random( 0, 6 ) )

            else -- tried too hard!
                Damage:ScaleDamage( 1.5 )

            end

            local DamageDamage = Damage:GetDamage()
            BgDamage = DamageDamage
            SilentBgDmg = DamageDamage < 40

        end
        if ToBGs and BgDamage then
            BodyGroupDamage( self, ToBGs, BgDamage, Damage, SilentBgDmg )

        end
    -- combine balls on non-metallic skeletons
    elseif Damage:IsDamageType( DMG_DISSOLVE ) then
        local potentialBall = Damage:GetInflictor()
        if string.find( potentialBall:GetClass(), "ball" ) then -- this is definitely a ball!
            -- remove balls if they deal than 1000 damage
            local ballHealth = potentialBall.term_Ballhealth or 1000
            local healthTaken = self:Health()
            ballHealth = ballHealth - healthTaken
            if ballHealth <= 1 then
                potentialBall:Fire( "Explode" )

            else
                util.ScreenShake( self:GetPos(), healthTaken * 0.25, 20, 0.25, 500 + healthTaken )
                potentialBall.term_Ballhealth = ballHealth

            end

            self:ReallyAnger( 60 )

            self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )

        end
    end

    -- ouch
    self:HandleFlinching( Damage, 0 )

end

--[[------------------------------------
    Name: NEXTBOT:PostTookBulletDamage
    Desc: Called after taking bullet damage, provides hitgroup data.
    Arg1: DamageInfo | _dmg | Damage info.
    Arg2: number | _hitGroup | Hitgroup of the damage.
    Ret1: any | blockDamage | If this isn't nil, damage is blocked.
--]]------------------------------------
function ENT:PostTookBulletDamage( _dmg, _hitGroup )
end

--[[------------------------------------
    Name: NEXTBOT:PostTookDamage
    Desc: Called after taking ANY damage, provides damage info.
    Arg1: DamageInfo | _dmg | Damage info.
    Ret1: any | blockDamage | If this isn't nil, damage is blocked.
--]]------------------------------------
local MEMORY_VOLATILE = 8
local MEMORY_DAMAGING = 64
function ENT:PostTookDamage( dmg )
    local myTbl = entMeta.GetTable( self )

    local attacker = dmg:GetAttacker()
    local validAttacker = IsValid( attacker )
    if validAttacker then
        -- they attacked us so they're an enemy we should engage!
        attacker.term_NoHealthChangeCount = -1000

    end

    local friendlyFireMul = myTbl.FriendlyFireMul
    if friendlyFireMul and friendlyFireMul ~= 1 then
        local attackerDisp = myTbl.TERM_GetRelationship( self, myTbl, attacker )
        if attackerDisp == D_LI then -- buddies with attacker, scale the damage down
            dmg:ScaleDamage( friendlyFireMul )

        end
        if dmg:GetDamage() <= 0 then
            return true -- no damage, no need to do anything else

        end
    end

    local blockDamage
    ProtectedCall( function()
        blockDamage = myTbl.RunTask( self, "OnDamaged", dmg )

    end )
    if blockDamage then return true end

    local cur = CurTime()
    local nextNoticeDamage = myTbl.term_NextNoticeDamage or 0
    if nextNoticeDamage > cur then return end

    local damage = dmg:GetDamage()

    local add = math.Clamp( damage, 0, 250 ) / 250
    myTbl.term_NextNoticeDamage = cur + add

    local parent = validAttacker and attacker:GetParent() or nil

     -- on fire damage is from fire parented to us, ignore that for feuding and looking at damage
    if validAttacker and attacker ~= self and not ( IsValid( parent ) and parent == self ) then
        myTbl.MakeFeud( self, attacker )

        local dmgSourcePos = myTbl.getBestPos( self, attacker )

        local toAttackerDisp, toAttackerPri = myTbl.TERM_GetRelationship( self, myTbl, attacker )
        if toAttackerDisp == D_LI then return end -- dont look at friends

        local currEnemy = myTbl.GetEnemy( self )
        local currEnemyPri = 0
        if IsValid( currEnemy ) then
            _, currEnemyPri = myTbl.TERM_GetRelationship( self, myTbl, currEnemy )

        end
        -- look at attacker if they are more important than current enemy
        local updateEnemy = self:GetRangeTo( attacker ) < myTbl.CloseEnemyDistance
        updateEnemy = updateEnemy or ( dmg:IsBulletDamage() and toAttackerPri > currEnemyPri + 1 and terminator_Extras.PosCanSee( myTbl.GetShootPos( self ), dmgSourcePos ) and dmgSourcePos:Distance( attacker:GetPos() ) < 350 )
        if updateEnemy then
            myTbl.UpdateEnemyMemory( self, attacker, attacker:GetPos() )

        end

        local time = math.Clamp( damage / 50, math.Rand( 0.5, 1.5 ), 3 )
        if myTbl.IsAngry( self ) then -- blinded by rage
            time = time * 0.5

        end
        if myTbl.AimSpeed < 200 then -- look longer if we aim slow
            time = time + ( 200 - myTbl.AimSpeed ) / 100

        end

        if attacker ~= currEnemy then -- look at it
            myTbl.TookDamagePos = dmgSourcePos
            timer.Simple( time, function()
                if not IsValid( self ) then return end
                if myTbl.TookDamagePos ~= dmgSourcePos then return end
                myTbl.TookDamagePos = nil

            end )
        end
    end


    if dmg:GetDamage() <= 75 then return end

    local cheap = self.IsStupid or self.IsFodder -- durr

    -- make groups of bots react to 1 getting damaged
    local nextGroupAnger = self.term_NextDamagedGroupAnger or 0
    if validAttacker and attacker == self:GetEnemy() and nextGroupAnger < cur then
        self.term_NextDamagedGroupAnger = cur + 5

        self:Anger( math.random( 5, 10 ) )

        for _, ally in ipairs( self:GetNearbyAllies() ) do
            if not IsValid( ally ) then return end -- GetNearbyAllies is cached
            if ally:GetEnemy() ~= attacker then continue end

            local delay = math.Rand( 0.5, 1.5 )
            if cheap then
                delay = delay * math.Rand( 1, 3 )

            end

            timer.Simple( delay, function()
                if not IsValid( ally ) then return end
                if not ally.Anger then return end
                ally.term_NextDamagedGroupAnger = CurTime() + delay
                ally:Anger( math.random( 5, 10 ) )

            end )
        end
    end

    local inflictor = dmg:GetInflictor()
    local trueDamager = IsValid( inflictor ) and not IsValid( inflictor:GetOwner() ) and not inflictor:IsPlayer() and not inflictor:IsNPC() and IsValid( inflictor:GetPhysicsObject() )
    if trueDamager then
        if dmg:IsExplosionDamage() then
            self:memorizeEntAs( inflictor, MEMORY_VOLATILE )

        else
            self:memorizeEntAs( inflictor, MEMORY_DAMAGING )

        end
    end

    if cheap then return end

    local radius = dmg:GetDamage()
    radius = math.min( radius, 250 ) -- no huge radius pls

    -- dont walk in this area ever again!
    local areas = navmesh.Find( self:GetPos(), radius, self.JumpHeight, self.JumpHeight )
    for _, area in ipairs( areas ) do
        table.insert( self.hazardousAreas, area )

    end
end

-- flinching
local flinchesForGroups = {
    [HITGROUP_GENERIC] = ACT_FLINCH_PHYSICS,
    [HITGROUP_HEAD] = ACT_FLINCH_HEAD,
    [HITGROUP_CHEST] = ACT_FLINCH_CHEST,
    [HITGROUP_STOMACH] = ACT_FLINCH_STOMACH,
    [HITGROUP_LEFTARM] = ACT_FLINCH_LEFTARM,
    [HITGROUP_RIGHTARM] = ACT_FLINCH_RIGHTARM,
    [HITGROUP_LEFTLEG] = ACT_FLINCH_LEFTLEG,
    [HITGROUP_RIGHTLEG] = ACT_FLINCH_RIGHTLEG,
}

-- it's very subtle, but yes this works ( on most models... )
function ENT:HandleFlinching( dmg, hitGroup )
    local nextFlinch = self.term_NexFlinch or 0
    if nextFlinch > CurTime() then return end

    local gesture = nil

    if hitGroup then
        gesture = flinchesForGroups[hitGroup]

    end
    if not gesture then return end
    if istable( gesture ) then
        gesture = gesture[math.random( 1, #gesture )]

    end

    local damageDealt = dmg:GetDamage()
    local maxDamageWeight = math.min( self:GetMaxHealth() * .25, 50 ) -- weight of anim
    local weight = damageDealt / maxDamageWeight

    if weight < 0.05 then return end
    weight = math.Clamp( weight, 0, 0.95 )

    local playRate = 2 - ( weight * 1.15 )

    if weight > 0.75 and self:GetCurrentSpeed() > ( self.RunSpeed * 0.75 ) then
        local old = self.overrideCrouch or 0
        local added = math.max( old + weight * 0.25, CurTime() + weight * 0.5 )
        if self:IsReallyAngry() then
            added = added - 1

        end
        self.overrideCrouch = added

    end

    local layer = self:AddGesture( gesture )
    self:SetLayerPlaybackRate( layer, playRate )
    self:SetLayerWeight( layer, weight )

    self.term_NexFlinch = CurTime() + weight / 2

end

function ENT:HandleWeaponOnDeath( wep, dissolving ) -- drop our weapons!
    if dissolving then
        self:DissolveEntity( wep )
        timer.Simple( 0, function()
            if not IsValid( self ) then return end
            if not IsValid( wep ) then return end
            wep = self:DropWeapon( true, wep )

        end )
    else
        if self:CanDropWeaponOnDie( wep ) then
            timer.Simple( 0, function()
                if not IsValid( self ) then return end
                if not IsValid( wep ) then return end
                self:DropWeapon( true, wep )

            end )

        else
            wep:Remove()

        end
    end
end

function ENT:AdditionalOnKilled( _dmg ) -- stub! for your convenience
end

function ENT:HandleDeathAnim( _dmg ) -- stub!
end


--[[------------------------------------
	NEXTBOT:OnKilled
	Initialize death ragdoll and call hooks
--]]------------------------------------
function ENT:OnKilled( dmg )
    if self.term_Dead then ErrorNoHaltWithStack( "tried to die twice" ) return end
    self.term_Dead = true

    local attacker = dmg:GetAttacker()
    local inflictor = dmg:GetInflictor()
    local damage = dmg:GetDamage()
    local damageType = dmg:GetDamageType()
    local damagePos = dmg:GetDamagePosition()
    local damageForce = dmg:GetDamageForce()

    self:AdditionalOnKilled( dmg )
    local deathAniming

    local extraDeathAnim = self:RunTask( "GetDeathAnim", dmg )

    if self.Term_DeathAnim or extraDeathAnim then
        local deathAnimDat = self.Term_DeathAnim or extraDeathAnim
        local deathAct = deathAnimDat.act
        if deathAct and not ( isnumber( deathAct ) and deathAct <= 0 ) then
            deathAniming = true

            local startFunc = deathAnimDat.startFunc
            if startFunc then
                startFunc( self )

            end

            self:RunTask( "OnStartDying", dmg )

            local rate = deathAnimDat.rate or 1
            self:StopMoving()
            self:DoGesture( deathAct, rate, true )

            local duration = self:SequenceDuration( deathSeq ) / rate
            self.Term_DyingUntil = CurTime() + duration
            timer.Simple( duration, function()
                if not IsValid( self ) then return end

                local finishFunc = deathAnimDat.finishFunc
                if finishFunc then
                    finishFunc( self )

                end

                -- doesn't pass dmg object because there's just 1 global damage object, it'll be some other damage event by the time we call this
                self:FinishDying( attacker, inflictor, nil, damage, damageType, damagePos, damageForce )

            end )
        end
    end

    if deathAniming then return end
    self:FinishDying( attacker, inflictor, dmg, damage, damageType, damagePos, damageForce )

end

function ENT:FinishDying( attacker, inflictor, dmg, damage, damageType, damagePos, damageForce )

    if not IsValid( attacker ) then
        attacker = game.GetWorld()

    end
    if not IsValid( inflictor ) then
        inflictor = game.GetWorld()

    end

    local dissolving = bit.band( damageType, DMG_DISSOLVE ) ~= 0

    timer.Simple( 10, function() -- HACK
        if not IsValid( self ) then return end
        if not self.term_Dead then return end

        if self:Health() > 0 then return end
        SafeRemoveEntity( self )

    end )

    local wep = self:GetActiveWeapon()
    local weps = { wep }

    local _, holsteredWeaps = self:GetHolsteredWeapons()
    table.Add( weps, holsteredWeaps )
    for _, currWep in pairs( weps ) do
        if not IsValid( currWep ) then continue end
        self:HandleWeaponOnDeath( currWep, dissolving )

    end

    if self.term_IdleLoopingSound then
        self.term_IdleLoopingSound:Stop()
        self.term_IdleLoopingSound = nil

    end

    local ragdoll

    if dmg then
        local preventRagdoll, blockRemove = self:RunTask( "PreventBecomeRagdollOnKilled", dmg )

        if not preventRagdoll then
            if dissolving then
                self:DissolveEntity()
                self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )
                hook.Run( "OnTerminatorKilledDissolve", self, dmg )

            else
                hook.Run( "OnTerminatorKilledRagdoll", self, dmg )

            end

            ragdoll = self:BecomeRagdoll( dmg )

        elseif not blockRemove then
            SafeRemoveEntityDelayed( self, 5 )

        end
    else
        inflictor = IsValid( inflictor ) and inflictor or attacker

        hook.Run( "OnTerminatorKilledScripted", self, attacker, inflictor, damageType, damagePos, damageForce )

        dmg = DamageInfo() -- scripted death, the dmg object is definitely a new damageevent by now
        dmg:SetAttacker( attacker )
        dmg:SetInflictor( inflictor )
        dmg:SetDamage( damage )
        dmg:SetDamageType( damageType )
        dmg:SetDamagePosition( damagePos )
        dmg:SetDamageForce( damageForce )
        ragdoll = self:BecomeRagdoll( dmg )

    end

    if IsValid( ragdoll ) and self.AdditionalRagdollDeathEffects then
        self:AdditionalRagdollDeathEffects( ragdoll )

    end

    for _, child in ipairs( self:GetChildren() ) do
        if not IsValid( child ) then continue end

        local parent = child:GetParent()
        if not IsValid( parent ) or parent ~= self then continue end
        if child:IsWeapon() then continue end

        -- annoying bug
        child:SetNoDraw( true )

    end
    self:SetNoDraw( true )

    -- do these last just in case something below here errors
    hook.Run( "OnNPCKilled", self, attacker, inflictor )
    self:RunTask( "OnKilled", attacker, inflictor, ragdoll )
    self:RunTask( "OnKilledDmg", dmg )

end


function ENT:InitializeHealthRegen()
    if not isnumber( self.HealthRegen ) then return end -- what is this? a non-number in my number machine???
    self.HealthRegenInterval = isnumber( self.HealthRegenInterval ) and self.HealthRegenInterval or 1

    self.NextRegenHeal = 0
    self.HealthRegenThink = function( me )
        if me.NextRegenHeal > CurTime() then return end
        me.NextRegenHeal = CurTime() + me.HealthRegenInterval

        local oldHealth = me:Health()
        if oldHealth <= 0 then return end -- dont cause resurrect issues

        local newHealth = math.Clamp( oldHealth + me.HealthRegen, 0, me:GetMaxHealth() )
        me:SetHealth( newHealth )

    end
end


function ENT:OnFirstRelationWithPlayer( ply ) -- for boss npcs, etc
    local extraHpPerPly = self.ExtraSpawnHealthPerPlayer
    if not extraHpPerPly then return end
    if ply:IsFlagSet( FL_NOTARGET ) then return end

    local plysDone = self.ExtraSpawnHealthPlayersDone or 0
    self.ExtraSpawnHealthPlayersDone = plysDone + 1
    if plysDone <= 0 then return end -- ignore first ply

    self.SpawnHealth = self.SpawnHealth + extraHpPerPly
    self:SetMaxHealth( self:GetMaxHealth() + extraHpPerPly )
    self:SetHealth( self:GetMaxHealth() )

end

local lungSize = 15

function ENT:InitializeDrowning( myTbl )
    local breathesAir = myTbl.BreathesAir
    local breathesWater = myTbl.BreathesWater

    if not ( breathesAir or breathesWater ) then return end
    if breathesAir and breathesWater then return end -- can breath in both air and water, won't drown

    myTbl.term_BreathCount = lungSize
    myTbl.term_NextDrownThink = CurTime() + 1

    function self:DrowningThink( myTbl2 )
        if myTbl2.term_NextDrownThink > CurTime() then return end
        myTbl2.term_NextDrownThink = CurTime() + 1

        local underwater = self:WaterLevel() >= 3
        local breathing
        if breathesAir then
            breathing = not underwater

        elseif breathesWater then
            breathing = underwater

        end
        local old = myTbl2.term_BreathCount
        if breathing then
            myTbl2.term_BreathCount = math.max( old + 10, lungSize )

        else
            if old < 0 then
                local world = game.GetWorld()
                local dmg = DamageInfo()
                dmg:SetDamage( math.min( self:GetMaxHealth() * 0.15, 100 ) )
                dmg:SetAttacker( world )
                dmg:SetInflictor( world )
                dmg:SetDamagePosition( self:GetPos() )
                dmg:SetDamageType( DMG_DROWN )
                self:TakeDamageInfo( dmg )

                self:Term_SpeakSoundNow( "player/pl_drown" .. math.random( 2, 3 ) .. ".wav" )

                self.NextRegenHeal = CurTime() + 5
                self:RunTask( "OnDrown" )
                self:ReallyAnger( 30 )
                self:StartSwimming()

            else
                myTbl2.term_BreathCount = old + -1

            end
        end
    end
end

--[[
-- stub, make sure you add this shared, this is called for client ragdolls too
function ENT:AdditionalRagdollDeathEffects( ragdoll )
end
--]]