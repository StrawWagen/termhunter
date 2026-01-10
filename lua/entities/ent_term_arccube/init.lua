-- init.lua
AddCSLuaFile( "shared.lua" )
AddCSLuaFile( "cl_init.lua" )
include( "shared.lua" )

function ENT:Initialize()
    self:SetModel( "models/hunter/blocks/cube025x025x025.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetUseType( SIMPLE_USE )

    local phys = self:GetPhysicsObject()
    if IsValid( phys ) then phys:Wake() end

    self.NextArc = 0
end

function ENT:Use( activator, caller )
    self:SetArcEnabled( not self:GetArcEnabled() )

    if IsValid( activator ) and activator:IsPlayer() then
        activator:ChatPrint( "Lightning Arc: " .. ( self:GetArcEnabled() and "ON" or "OFF" ) )
    end
end

function ENT:Think()
    if not self:GetArcEnabled() then return end
    if CurTime() < self.NextArc then return end

    self.NextArc = CurTime() + math.max( self:GetArcRate(), 0.01 )

    local startPos = self:GetPos()
    local mode = self:GetArcMode()
    local range = self:GetArcRange()

    if mode == ARC_MODE_CONNECT then
        self:FireConnectArcs( startPos, range )
    elseif mode == ARC_MODE_TRACE then
        local tr = util.TraceLine( {
            start = startPos,
            endpos = startPos - self:GetUp() * range,
            filter = self
        } )
        self:FireArc( startPos, tr.HitPos, false )
    else
        local dir = VectorRand():GetNormalized()
        local tr = util.TraceLine( {
            start = startPos,
            endpos = startPos + dir * range,
            filter = self
        } )
        self:FireArc( startPos, tr.HitPos, false )
    end
end

function ENT:FireConnectArcs( startPos, range )
    local targets = {}
    local validClasses = { ["prop_physics"] = true, ["ent_term_arccube"] = true }

    for _, ent in ipairs( ents.FindInSphere( startPos, range ) ) do
        if ent ~= self and ( ent:IsPlayer() or ent:IsNPC() or validClasses[ ent:GetClass() ] ) then
            targets[ #targets + 1 ] = ent:GetPos() + ( ent:OBBCenter() or vector_origin )
        end
    end

    local traceCount = self:GetArcMultiTarget() and 6 or 3
    for i = 1, traceCount do
        local tr = util.TraceLine( {
            start = startPos,
            endpos = startPos + VectorRand():GetNormalized() * range,
            filter = self
        } )
        if tr.Hit then targets[ #targets + 1 ] = tr.HitPos end
    end

    if #targets == 0 then return end

    local arcCount = self:GetArcMultiTarget() and math.min( #targets, 4 ) or 1
    for i = 1, arcCount do
        if #targets == 0 then break end
        local idx = math.random( #targets )
        self:FireArc( startPos, targets[ idx ], true )
        table.remove( targets, idx )
    end
end

function ENT:FireArc( startPos, endPos, useParentMode )
    local fx = EffectData()
    fx:SetStart( startPos )
    fx:SetOrigin( endPos )
    fx:SetScale( self:GetArcScale() )
    fx:SetMagnitude( self:GetArcSegments() )
    fx:SetRadius( self:GetArcJitter() )
    fx:SetDamageType( self:GetArcBranchCount() )
    fx:SetNormal( Vector( self:GetArcColorR() / 255, self:GetArcColorG() / 255, self:GetArcColorB() / 255 ) )
    fx:SetEntity( self )

    -- Flags: 1=NoLight, 2=NoBranches, 4=NoFade, 8=ParentMode, 16=NoSound
    local flags = 0
    if self:GetArcNoLight() then flags = flags + 1 end
    if self:GetArcNoBranches() then flags = flags + 2 end
    if self:GetArcNoFade() then flags = flags + 4 end
    if useParentMode then flags = flags + 8 end
    if self:GetArcNoSound() then flags = flags + 16 end
    fx:SetFlags( flags )

    util.Effect( "eff_term_goodarc", fx )
end

-- Duplicator support
local ArcProps = { "Scale", "Segments", "Jitter", "Range", "Rate", "BranchCount", "ColorR", "ColorG", "ColorB", "Mode", "Enabled", "NoLight", "NoBranches", "NoFade", "NoSound", "MultiTarget" }

function ENT:PreEntityCopy()
    local data = {}
    for _, prop in ipairs( ArcProps ) do
        data[ prop ] = self[ "GetArc" .. prop ]( self )
    end
    duplicator.StoreEntityModifier( self, "ArcData", data )
end

function ENT:PostEntityPaste( ply, ent, createdEntities )
    local data = self.ArcData
    if not data then return end

    for _, prop in ipairs( ArcProps ) do
        if data[ prop ] ~= nil then
            self[ "SetArc" .. prop ]( self, data[ prop ] )
        end
    end
end

duplicator.RegisterEntityModifier( "ArcData", function( ply, ent, data )
    ent.ArcData = data
end )