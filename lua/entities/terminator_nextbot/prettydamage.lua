
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"

local CurTime = CurTime

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

local function BodyGroupDamageThink( self, Group, Damage, Pos, Silent )
    if not isnumber( Group ) then return end
    if self:GetModel() ~= ARNOLD_MODEL then return end
    local CurrHSteps = self.GroupSteps[Group]
    if not istable( CurrHSteps ) then return end

    if not isnumber( self.BGrpHealth[Group] ) then
        self.BGrpHealth[Group] = self.BGrpMaxHealth[Group]
        self.OldBGrpSteps[Group] = 10
    end

    self.BGrpHealth[Group] = math.Clamp( self.BGrpHealth[Group] + -Damage, 1, math.huge )

    local Steps = table.Count( self.GroupSteps[Group] )
    local CurrStep = math.ceil( ( self.BGrpHealth[Group] / self.BGrpMaxHealth[Group] ) * Steps )
    local OldStep = self.OldBGrpSteps[Group]

    if OldStep <= CurrStep then return end
    self.OldBGrpSteps[Group] = CurrStep
    if Group ~= 0 then
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
local function BodyGroupDamage( self, ToBGs, BgDamage, Damage, Silent )
    if istable( ToBGs ) then
        local var = 0
        local Count = table.Count( ToBGs )
        while var < Count do
            var = var + 1
            local BGroup = ToBGs[var]
            BodyGroupDamageThink( self, BGroup, BgDamage, Damage:GetDamagePosition(), Silent )
        end
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
function ENT:CatDamage()
    self:EmitSound( table.Random( self.Creaks ), 85, 150, 1, CHAN_AUTO )
    self:EmitSound( table.Random( self.Hits ), 85, 80, 1, CHAN_AUTO )
end

-- dmg with bodygroup data

local function OnDamaged( damaged, Hitgroup, Damage )

    if not damaged.isTerminatorHunterBased then return end

    damaged.lastDamagedTime = CurTime()

    if damaged:PostTookDamage( Damage ) then return end

    if damaged.DoMetallicDamage then
        local ToBGs = nil
        local BgDmg = false
        local BgDamage = 0
        local DamageDealt = Damage:GetDamage()

        if not Damage:IsExplosionDamage() then
            if DamageDealt >= damaged.HighCal then
                BgDmg = true
                BgDamage = Damage:GetDamage()
                Damage:SetDamage( DamageDealt / 2.5 )
                MedDamage( damaged, Damage )
            elseif DamageDealt > damaged.MedCal then
                BgDmg = true
                BgDamage = Damage:GetDamage() / 3
                Damage:SetDamage( 1 )
                if Damage:IsBulletDamage() then
                    MedCalRics( damaged )
                end
            else
                BgDmg = true
                BgDamage = Damage:GetDamage() / 13
                Damage:SetDamage( 0 )
            end
        elseif DamageDealt > 60 then
            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )
            DamageDealt = DamageDealt * 0.75
            Damage:SetDamage( math.Clamp( DamageDealt, 0, 350 ) )
            BgDamage = 40
            damaged:CatDamage()
        end

        if BgDmg then
            if damaged:GetModel() ~= ARNOLD_MODEL then return end
            ToBGs = damaged.HitTranslate[Hitgroup] -- get bodygroups to do stuff to

            if not istable( ToBGs ) then return end

            local Data = EffectData()
            Data:SetOrigin( Damage:GetDamagePosition() )
            Data:SetScale( 1 )
            Data:SetRadius( 1 )
            Data:SetMagnitude( 1 )
            util.Effect( "Sparks", Data )
        end

        BodyGroupDamage( damaged, ToBGs, BgDamage, Damage )

    end

    damaged:HandleFlinching( Damage, Hitgroup )

end

hook.Add( "ScaleNPCDamage", "term_straw_terminator_damage", OnDamaged )

-- dmg w/o bodygroup data

function ENT:OnTakeDamage( Damage )
    self.lastDamagedTime = CurTime()

    if self:PostTookDamage( Damage ) then return end

    if self.DoMetallicDamage then
        local attacker = Damage:GetAttacker()
        local BgDamage = 0
        local ToBGs

        if IsValid( attacker ) then
            local class = attacker:GetClass()

            if class == "func_door_rotating" or class == "func_door" then
                Damage:ScaleDamage( 0 )
                self.overrideMiniStuck = true

            end
        end

        if Damage:IsDamageType( DMG_ACID ) or Damage:IsDamageType( DMG_POISON ) then -- that has no effect on my skeleton!
            Damage:ScaleDamage( 0 )
            BgDamage = 40

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            BodyGroupDamage( self, ToBGs, BgDamage, Damage )

        elseif Damage:IsDamageType( DMG_SHOCK ) then
            if self.ShockDamageImmune then
                Damage:ScaleDamage( 0.01 )

            else
                Damage:ScaleDamage( 0.5 )

            end
            BgDamage = 140

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            BodyGroupDamage( self, ToBGs, BgDamage, Damage )

        elseif Damage:IsDamageType( DMG_DISSOLVE ) and Damage:GetDamage() >= 455 then --combine ball!
            Damage:SetDamage( terminator_Extras.healthDefault * 0.55 )
            BgDamage = 140

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )
            BodyGroupDamage( self, ToBGs, BgDamage, Damage )

            local potentialBall = Damage:GetInflictor()

            if string.find( potentialBall:GetClass(), "ball" ) then
                potentialBall:Fire( "Explode" )

            end

            self:CatDamage()
            self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )

        elseif Damage:IsDamageType( DMG_BURN ) or Damage:IsDamageType( DMG_SLOWBURN ) or Damage:IsDamageType( DMG_DIRECT ) then -- fire damage!
            Damage:ScaleDamage( 0 )
            BgDamage = 1

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, 6 ) )
            BodyGroupDamage( self, ToBGs, BgDamage, Damage )

        elseif Damage:IsDamageType( DMG_CLUB ) then -- likely another terminator punching us!
            local DamageDamage = Damage:GetDamage()
            BgDamage = DamageDamage / 2

            Damage:ScaleDamage( 0.5 )

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, 6 ) )
            table.remove( ToBGs, math.random( 0, 6 ) )
            BodyGroupDamage( self, ToBGs, BgDamage, Damage, DamageDamage < 40 )

        elseif Damage:IsDamageType( DMG_SLASH ) then
            local DamageDamage = Damage:GetDamage()
            BgDamage = DamageDamage / 1.5 -- takes chunks out of us 

            Damage:ScaleDamage( 0.15 ) -- but our skeleton is tough!

            ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
            table.remove( ToBGs, math.random( 0, 6 ) )
            table.remove( ToBGs, math.random( 0, 6 ) )
            BodyGroupDamage( self, ToBGs, BgDamage, Damage, DamageDamage < 40 )

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
            BgDamage = DamageDamage -- takes chunks out of us 
            BodyGroupDamage( self, ToBGs, BgDamage, Damage, DamageDamage < 40 )

        end
    elseif Damage:IsDamageType( DMG_DISSOLVE ) and Damage:GetDamage() >= 455 then --combine ball!
        local potentialBall = Damage:GetInflictor()
        if string.find( potentialBall:GetClass(), "ball" ) then
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

local MEMORY_VOLATILE = 8
local MEMORY_DAMAGING = 64

function ENT:PostTookDamage( dmg )

    self:RunTask( "OnDamaged", dmg )
    self:MakeFeud( dmg:GetAttacker() )

    local dmgPos = self:getBestPos( dmg:GetAttacker() )
    self.TookDamagePos = dmgPos
    local time = math.Rand( 1, 1.5 )
    if self:IsAngry() then
        time = time * 0.5

    end
    if self.AimSpeed < 200 then
        time = time + ( 200 - self.AimSpeed ) / 100

    end
    timer.Simple( time, function()
        if not IsValid( self ) then return end
        if self.TookDamagePos ~= dmgPos then return end
        self.TookDamagePos = nil

    end )


    if dmg:GetDamage() <= 75 then return end

    local attacker = dmg:GetAttacker()
    if attacker and attacker == self:GetEnemy() then
        -- make group of bots react to 1 getting damaged
        local ourChummy = self.isTerminatorHunterChummy
        for _, curr in ipairs( self.awarenessSubstantialStuff ) do
            if curr.isTerminatorHunterChummy ~= ourChummy then continue end
            if curr:GetEnemy() ~= attacker then continue end
            timer.Simple( math.Rand( 0.5, 1.5 ), function()
                if not IsValid( curr ) then return end
                if not curr.Anger then return end
                curr:Anger( math.random( 5, 10 ) )

            end )
        end
    end

    if self.IsStupid then return end

    -- dont walk in this area ever again!
    local areas = navmesh.Find( self:GetPos(), dmg:GetDamage(), self.JumpHeight, self.JumpHeight )
    for _, area in ipairs( areas ) do
        table.insert( self.hazardousAreas, area )

    end

    local inflictor = dmg:GetInflictor()
    local trueDamager = IsValid( inflictor ) and not IsValid( inflictor:GetOwner() ) and not inflictor:IsPlayer() and not inflictor:IsNPC()
    if trueDamager then
        if dmg:IsExplosionDamage() then
            self:memorizeEntAs( inflictor, MEMORY_VOLATILE )

        else
            self:memorizeEntAs( inflictor, MEMORY_DAMAGING )

        end
    end
end

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

-- it's very subtle, but yes this works
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
    local maxDamageWeight = math.min( self:GetMaxHealth() * .25, 50 )
    local weight = damageDealt / maxDamageWeight

    if weight < 0.05 then return end
    weight = math.Clamp( weight, 0, 0.95 )

    local playRate = 2 - ( weight * 1.15 )

    if weight > 0.75 and self.loco:GetVelocity():Length() > ( self.RunSpeed * 0.75 ) then
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

function ENT:HandleWeaponOnDeath( wep, dmg )
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

function ENT:OnKilled( dmg )
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

    if not self:RunTask( "PreventBecomeRagdollOnKilled", dmg ) then
        if dmg:IsDamageType( DMG_DISSOLVE ) then
            self:DissolveEntity()
            self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )
            hook.Run( "OnTerminatorKilledDissolve", self, dmg:GetAttacker(), dmg:GetInflictor() )

        else
            hook.Run( "OnTerminatorKilledRagdoll", self, dmg:GetAttacker(), dmg:GetInflictor() )

        end
        self:BecomeRagdoll( dmg )

    end

    self:RunTask( "OnKilled", dmg )
    hook.Run( "OnNPCKilled", self, dmg:GetAttacker(), dmg:GetInflictor() )

    for _, child in ipairs( self:GetChildren() ) do
        if not IsValid( child ) then continue end
        local parent = child:GetParent()
        if not IsValid( parent ) or parent ~= self then continue end
        if child:IsWeapon() then continue end
        child:SetNoDraw( true )

    end
end