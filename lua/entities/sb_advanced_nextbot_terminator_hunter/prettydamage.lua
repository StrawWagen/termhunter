
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"

local _CurTime = CurTime

--cool dmage system stuff
ENT.BGrpHealth = {}
ENT.OldBGrpSteps = {}
ENT.MedCal = 4
ENT.HighCal = 80

ENT.BGrpMaxHealth = {
    [0] = 30,
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
    damaged:MakeFeud( Damage:GetAttacker() )

    if not damaged.DoMetallicDamage then return end
    damaged.lastDamagedTime = _CurTime()
    local ToBGs = nil
    local BgDmg = false
    local BgDamage = 0
    local DamageG = Damage:GetDamage()

    if not Damage:IsExplosionDamage() then
        if DamageG >= damaged.HighCal then
            BgDmg = true
            BgDamage = Damage:GetDamage()
            Damage:SetDamage( DamageG / 3.5 )
            MedDamage( damaged, Damage )
        elseif DamageG > damaged.MedCal then
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
    elseif DamageG > 60 then
        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )
        Damage:SetDamage( math.Clamp( DamageG, 0, 100 ) )
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

hook.Add( "ScaleNPCDamage", "sb_anb_straw_terminator_damage", OnDamaged )

-- dmg w/o bodygroup data

function ENT:OnTakeDamage( Damage )
    if not self.DoMetallicDamage then return end
    self.lastDamagedTime = _CurTime()
    local attacker = Damage:GetAttacker()
    local BgDamage = 0

    if IsValid( attacker ) then
        local class = attacker:GetClass()

        if class == "func_door_rotating" or class == "func_door" then
            Damage:ScaleDamage( 0 )
            self.overrideMiniStuck = true

        end
    end

    if Damage:IsDamageType( DMG_ACID ) then --acid!
        Damage:ScaleDamage( 0 )
        BgDamage = 40

        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )

    elseif Damage:IsDamageType( DMG_DISSOLVE ) and Damage:GetDamage() >= 300 then --combine ball!
        Damage:SetDamage( 300 )
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

    elseif Damage:IsDamageType( DMG_SHOCK ) then
        Damage:ScaleDamage( 0.5 )
        BgDamage = 140

        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )

    elseif Damage:IsDamageType( DMG_BURN ) or Damage:IsDamageType( DMG_SLOWBURN ) or Damage:IsDamageType( DMG_DIRECT ) then -- fire damage!
        Damage:ScaleDamage( 0 )
        BgDamage = 1

        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, 6 ) )
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )

    elseif Damage:IsDamageType( DMG_CLUB ) then -- likely another terminator punching us!
        local DamageDamage = Damage:GetDamage()
        BgDamage = DamageDamage / 2

        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, 6 ) )
        table.remove( ToBGs, math.random( 0, 6 ) )
        BodyGroupDamage( self, ToBGs, BgDamage, Damage, DamageDamage < 40 )

    end
end