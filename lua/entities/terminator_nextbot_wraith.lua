AddCSLuaFile()


ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Wraith"
ENT.Author = "Broadcloth0"
ENT.Spawnable = true
list.Set( "NPC", "terminator_nextbot_wraith", {
    Name = "Terminator Wraith",
    Class = "terminator_nextbot_wraith",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },

} )

if CLIENT then
    language.Add( "terminator_nextbot_wraith", ENT.PrintName )
    return

end

-- cleaned :steamhappy:
ENT.FistDamageMul = 1.565
ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_VERY_GOOD

ENT.SpawnHealth = terminator_Extras.healthDefault * 0.5

function ENT:CanWeaponPrimaryAttack()
    if not self:IsSolid() then return false end
    local nextAttack = self.terminator_NextAttack or 0
    if nextAttack > CurTime() then return end
    return BaseClass.CanWeaponPrimaryAttack( self )

end

-- copied from jerma modified & cleaned up a bit :) 
function ENT:CloakedMatFlicker()
    local toApply = { self }
    table.Add( toApply, self:GetChildren() )

    for _, ent in pairs( toApply ) do
        if not IsValid( ent ) then continue end
        local entsParent = ent:GetParent()
        if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

        if IsValid( ent ) then
            ent:SetMaterial( "effects/combineshield/comshieldwall3" )

        end
    end
    timer.Simple( math.Rand( 0.65, 0.75 ), function()
        if not IsValid( self ) then return end
        if self:IsSolid() then return end
        toApply = { self }
        table.Add( toApply, self:GetChildren() )

        for _, ent in pairs( toApply ) do
            if not IsValid( ent ) then continue end
            local entsParent = ent:GetParent()
            if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

            if IsValid( ent ) then
                ent:SetMaterial( "effects/combineshield/comshieldwall" )

            end
        end
    end )
end

function ENT:DoHiding( hide )
    local oldHide = not self:IsSolid()
    if hide == oldHide then return end
    local nextSwap = self.terminator_NextHidingSwap or 0
    if nextSwap > CurTime() then return end

    if hide then
        self:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
        self:SetSolidMask( MASK_NPCSOLID_BRUSHONLY )
        self:AddFlags( FL_NOTARGET )
        self:EmitSound( "ambient/levels/citadel/pod_open1.wav", 100, math.random( 110, 120 ) )
        self.terminator_NextHidingSwap = CurTime() + math.Rand( 0.25, 0.75 )

        self:CloakedMatFlicker()
        self:RemoveAllDecals()
        self.FootstepClomping = false

        local toApply = { self }
        table.Add( toApply, self:GetChildren() )
        for _, ent in pairs( toApply ) do
            if not IsValid( ent ) then continue end

            local entsParent = ent:GetParent()
            if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

            ent:DrawShadow( false )
            ent:SetNotSolid( true )

        end
    else
        self:EmitSound( "ambient/levels/citadel/pod_close1.wav", 100, math.random( 125, 130 ) )
        self.terminator_NextHidingSwap = CurTime() + math.Rand( 2.5, 3.5 )
        self:CloakedMatFlicker()

        timer.Simple( 0.35, function()
            if not IsValid( self ) then return end

            self.terminator_NextAttack = CurTime() + 0.10
            self:EmitSound( "buttons/combine_button5.wav", 140, 125 )
            self:SetCollisionGroup( COLLISION_GROUP_NPC )
            self:SetSolidMask( MASK_NPCSOLID )
            self:RemoveFlags( FL_NOTARGET )
            self.FootstepClomping = true
            self:OnStuck()

            local toApply = { self }
            table.Add( toApply, self:GetChildren() )
            for _, ent in pairs( toApply ) do
                if not IsValid( ent ) then continue end
                local entsParent = ent:GetParent()
                if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

                ent:DrawShadow( false )
                ent:SetMaterial( "" )
                ent:SetNotSolid( false )

            end
        end )
    end
end

function ENT:AdditionalThink()
    local speedSqr = self:GetCurrentSpeedSqr()
    local enem = self:GetEnemy()
    local doHide = IsValid( enem ) or speedSqr > 80^2
    local enemDist = self.DistToEnemy
    if doHide and speedSqr < 85^1 then
        doHide = false

    elseif doHide and IsValid( enem ) and enemDist < 120 then
        doHide = false
        self:ReallyAnger( 90 ) -- ANGRY

    end

    self:DoHiding( doHide )

    if not self:IsSolid() and math.Rand( 0, 100 ) < 0.5 then
        self:CloakedMatFlicker()

    end
end
