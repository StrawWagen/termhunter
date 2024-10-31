
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"

local CurTime = CurTime

ENT.term_DMG_ImmunityMask = nil -- bitmask of DMG

--cool dmage system stuff
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

local function MedCalRics( self )
    self:EmitSound( table.Random( self.Rics ), 75, math.random( 92, 100 ), 1, CHAN_AUTO )

end

local function MedDamage( self, Damage )
    self:EmitSound( table.Random( self.Hits ), 85, math.random( 105, 110 ), 1, CHAN_AUTO )

    if Damage:IsBulletDamage() then
        self:EmitSound( table.Random( self.Rics ), 85, math.random( 75, 80 ), 1, CHAN_AUTO )

    end
end

function ENT:CatDamage() -- cataSTROPIC DAMAGE
    self:EmitSound( table.Random( self.Creaks ), 85, 150, 1, CHAN_AUTO )
    self:EmitSound( table.Random( self.Hits ), 85, 80, 1, CHAN_AUTO )

end


-- dmg with bodygroup data ( bullets )
local function OnDamaged( damaged, Hitgroup, Damage )

    if not Damage:IsBulletDamage() then return end
    if not damaged.isTerminatorHunterBased then return end
    if damaged:PostTookDamage( Damage ) then return true end

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

    damaged:HandleFlinching( Damage, Hitgroup )

end

hook.Add( "ScaleNPCDamage", "term_straw_terminator_damage", function( ... ) OnDamaged( ... ) end )


-- dmg w/o bodygroup data
function ENT:OnTakeDamage( Damage )
    self.lastDamagedTime = CurTime()

    if Damage:IsDamageType( DMG_BULLET ) then return end -- handled ABOVE!

    if self:PostTookDamage( Damage ) then return true end

    if self.DoMetallicDamage then
        local attacker = Damage:GetAttacker()
        local BgDamage
        local ToBGs
        local SilentBgDmg

        if IsValid( attacker ) then
            local class = attacker:GetClass()

            if class == "func_door_rotating" or class == "func_door" then
                Damage:ScaleDamage( 0 )
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

        elseif Damage:IsDamageType( DMG_BURN ) or Damage:IsDamageType( DMG_SLOWBURN ) or ( Damage:IsDamageType( DMG_DIRECT ) and ( IsValid( attacker ) and string.find( attacker:GetClass(), "fire" ) ) ) then -- fire damage!
            Damage:ScaleDamage( 0 )

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
    elseif Damage:IsDamageType( DMG_DISSOLVE ) and Damage:GetDamage() >= 455 then -- NOT metallic damage, but handling a combine ball!
        local potentialBall = Damage:GetInflictor()
        if string.find( potentialBall:GetClass(), "ball" ) then -- this is definitely a ball!
            local ballHealth = potentialBall.term_Ballhealth or 1000
            local healthTaken = self:Health()
            ballHealth = ballHealth - healthTaken
            if ballHealth <= 1 then
                potentialBall:Fire( "Explode" )

            else
                util.ScreenShake( self:GetPos(), healthTaken * 0.25, 20, 0.25, 500 + healthTaken )
                potentialBall.term_Ballhealth = ballHealth

            end
        end

        self:ReallyAnger( 60 )

        self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )

    end

    self:HandleFlinching( Damage, 0 )

end


function ENT:IsImmuneToDmg( _dmg ) -- stub, for ents based off this!
end

local MEMORY_VOLATILE = 8
local MEMORY_DAMAGING = 64

function ENT:PostTookDamage( dmg ) -- always called when it takes damage!

    local immuneMask = self.term_DMG_ImmunityMask
    if immuneMask and bit.band( dmg:GetDamageType(), immuneMask ) ~= 0 then dmg:ScaleDamage( 0 ) return true end

    if self:IsImmuneToDmg( dmg ) then return true end

    local attacker = dmg:GetAttacker()
    ProtectedCall( function() self:RunTask( "OnDamaged", dmg ) end )

    if attacker:GetParent() ~= self then
        self:MakeFeud( dmg:GetAttacker() )

        local dmgSourcePos = self:getBestPos( dmg:GetAttacker() )
        self.TookDamagePos = dmgSourcePos

        local time = math.Rand( 1, 1.5 )
        if self:IsAngry() then
            time = time * 0.5

        end
        if self.AimSpeed < 200 then
            time = time + ( 200 - self.AimSpeed ) / 100

        end
        timer.Simple( time, function()
            if not IsValid( self ) then return end
            if self.TookDamagePos ~= dmgSourcePos then return end
            self.TookDamagePos = nil

        end )

    end


    if dmg:GetDamage() <= 75 then return end

    -- make groups of bots react to 1 getting damaged
    local nextGroupAnger = self.term_NextDamagedGroupAnger or 0
    if attacker and attacker == self:GetEnemy() and nextGroupAnger < CurTime() then
        self.term_NextDamagedGroupAnger = CurTime() + 5

        for _, ally in ipairs( self:GetNearbyAllies() ) do
            if ally:GetEnemy() ~= attacker then continue end

            timer.Simple( math.Rand( 0.5, 1.5 ), function()
                if not IsValid( ally ) then return end
                if not ally.Anger then return end
                ally.term_NextDamagedGroupAnger = CurTime() + 1
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

    if self.IsStupid or self.IsFodder then return end -- durr

    -- dont walk in this area ever again!
    local areas = navmesh.Find( self:GetPos(), dmg:GetDamage(), self.JumpHeight, self.JumpHeight )
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

end

function ENT:HandleWeaponOnDeath( wep, dmg ) -- drop our weapons!
    if dmg:IsDamageType( DMG_DISSOLVE ) then
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

function ENT:OnKilled( dmg )
    if self.term_Dead then return end
    self.term_Dead = true

    self:AdditionalOnKilled( dmg )

    local wep = self:GetActiveWeapon()
    local weps = { wep }

    local _, holsteredWeaps = self:GetHolsteredWeapons()
    table.Add( weps, holsteredWeaps )
    for _, currWep in pairs( weps ) do
        if not IsValid( currWep ) then continue end
        self:HandleWeaponOnDeath( currWep, dmg )

    end

    if self.term_IdleLoopingSound then
        self.term_IdleLoopingSound:Stop()
        self.term_IdleLoopingSound = nil

    end

    local ragdoll

    if not self:RunTask( "PreventBecomeRagdollOnKilled", dmg ) then
        if dmg:IsDamageType( DMG_DISSOLVE ) then
            self:DissolveEntity()
            self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )
            hook.Run( "OnTerminatorKilledDissolve", self, dmg:GetAttacker(), dmg:GetInflictor() )

        else
            hook.Run( "OnTerminatorKilledRagdoll", self, dmg:GetAttacker(), dmg:GetInflictor() )

        end
        ragdoll = self:BecomeRagdoll( dmg )

    end

    for _, child in ipairs( self:GetChildren() ) do
        if not IsValid( child ) then continue end

        local parent = child:GetParent()
        if not IsValid( parent ) or parent ~= self then continue end
        if child:IsWeapon() then continue end

        -- annoying bug
        child:SetNoDraw( true )

    end

    -- do these last just in case something below here errors
    self:RunTask( "OnKilled", dmg, ragdoll )
    hook.Run( "OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor() )

end


function ENT:InitializeHealthRegen()
    if not isnumber( self.HealthRegen ) then return end -- what is this? a non-number in my number machine???
    self.HealthRegenInterval = isnumber( self.HealthRegenInterval ) and self.HealthRegenInterval or 1

    self.NextRegenHeal = 0
    self.HealthRegenThink = function( me )
        if me.NextRegenHeal > CurTime() then return end
        me.NextRegenHeal = CurTime() + me.HealthRegenInterval

        local oldHealth = me:Health()
        if oldHealth <= 0 then return end

        local newHealth = math.Clamp( oldHealth + me.HealthRegen, 0, me:GetMaxHealth() )
        me:SetHealth( newHealth )

    end
end