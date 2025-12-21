-- Customizable Lightning Arc Effect
-- By regunkyle
--
-- ============================================
-- USAGE EXAMPLE:
-- ============================================
-- local fx = EffectData()
-- fx:SetStart( startPos )               -- Start position ( required )
-- fx:SetOrigin( endPos )                -- End position ( required )
-- fx:SetScale( 1 )                      -- Overall scale ( required )
-- fx:SetMagnitude( 8 )                  -- Arc segments ( required )
-- fx:SetRadius( 20 )                    -- Arc jitter intensity ( required )
-- fx:SetNormal( Vector( 0.4, 0.6, 1 ) ) -- Color as Vector( R, G, B ) in 0-1 range ( required )
-- fx:SetEntity( ent )                   -- Parent to entity ( optional )
-- fx:SetFlags( 0 )                      -- Bitflags ( see below )
-- fx:SetSurfaceProp( 1 )                -- Beam width multiplier ( required )
-- fx:SetHitBox( 1 )                     -- Duration multiplier ( required )
-- fx:SetDamageType( 5 )                 -- Branch count ( required if using branches )
-- fx:SetMaterialIndex( 1 )              -- Flicker speed multiplier ( required )
-- fx:SetColor( 1 )                      -- Light brightness multiplier ( required )
-- util.Effect( "eff_term_goodarc", fx )
--
-- FLAGS ( defaults: branches ON, thick core ON, flicker ON, fade ON, light ON, sound ON ):
--   1  = No dynamic light
--   2  = No branches
--   4  = No fade out
--   8  = Parent mode ( start follows entity, end stays fixed in world )
--   16 = No thick core
--   32 = Static arc ( no flicker/regeneration )
--   64 = No sound
--
-- COLOR EXAMPLES:
--   Blue ( default ): Vector( 0.4, 0.6, 1 )
--   Red:              Vector( 1, 0.1, 0.1 )
--   Green:            Vector( 0.1, 1, 0.1 )
--   Cyan:             Vector( 0.1, 1, 1 )
--   White:            Vector( 1, 1, 1 )
--   Purple:           Vector( 0.6, 0.1, 1 )
--   Pink:             Vector( 1, 0.4, 0.7 )
--   Orange:           Vector( 1, 0.5, 0.1 )
-- ============================================

local BeamMaterial = CreateMaterial( "xeno/beamlightning", "UnlitGeneric", {
    ["$basetexture"] = "sprites/spotlight",
    ["$additive"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
} )

local FLAG_NO_LIGHT = 1
local FLAG_NO_BRANCHES = 2
local FLAG_NO_FADE = 4
local FLAG_PARENT = 8
local FLAG_NO_THICK_CORE = 16
local FLAG_STATIC = 32
local FLAG_NO_SOUND = 64

local defaultBeamColor = Color( 100, 150, 255 )
local defaultBeamCoreColor = Color( 200, 250, 255 )
local renderBoundsVector = Vector( 1, 1, 1 )
local renderCol = Color( 255, 255, 255, 255 )
local renderCoreCol = Color( 255, 255, 255, 255 )

local ElectricSounds = {
    "ambient/energy/zap1.wav",
    "ambient/energy/zap2.wav",
    "ambient/energy/zap3.wav",
    "ambient/energy/zap5.wav",
    "ambient/energy/zap6.wav",
    "ambient/energy/zap7.wav",
    "ambient/energy/zap8.wav",
    "ambient/energy/zap9.wav",
}

local SparkSounds = {
    "ambient/energy/spark1.wav",
    "ambient/energy/spark2.wav",
    "ambient/energy/spark3.wav",
    "ambient/energy/spark4.wav",
    "ambient/energy/spark5.wav",
    "ambient/energy/spark6.wav",
}

function EFFECT:Init( data )
    self.StartPos = data:GetStart()
    self.EndPos = data:GetOrigin()
    self.Scale = data:GetScale()
    self.WidthMul = data:GetSurfaceProp()
    self.DurationMul = data:GetHitBox()
    self.FlickerMul = data:GetMaterialIndex()
    self.LightMul = data:GetColor()
    self.Segments = math.floor( data:GetMagnitude() )
    self.Jitter = data:GetRadius()
    self.BranchCount = data:GetDamageType()

    self.SoundVolume = 0.3 * self.Scale
    self.SoundPitch = 120 - self.Scale * 15

    self.Duration = math.max( 0.06 * self.Scale * self.DurationMul, 0.02 )
    self.DieTime = CurTime() + self.Duration

    local col = data:GetNormal()
    if col:LengthSqr() > 0 then
        self.Color = Color(
            col.x * 255,
            col.y * 255,
            col.z * 255
        )

        self.CoreColor = Color(
            math.min( self.Color.r + 100, 255 ),
            math.min( self.Color.g + 100, 255 ),
            math.min( self.Color.b + 100, 255 )
        )
    else
        self.Color = defaultBeamColor
        self.CoreColor = defaultBeamCoreColor
    end

    local flags = data:GetFlags()
    self.NoLight = bit.band( flags, FLAG_NO_LIGHT ) ~= 0
    self.NoBranches = bit.band( flags, FLAG_NO_BRANCHES ) ~= 0
    self.NoFade = bit.band( flags, FLAG_NO_FADE ) ~= 0
    self.ParentMode = bit.band( flags, FLAG_PARENT ) ~= 0
    self.NoThickCore = bit.band( flags, FLAG_NO_THICK_CORE ) ~= 0
    self.Static = bit.band( flags, FLAG_STATIC ) ~= 0
    self.NoSound = bit.band( flags, FLAG_NO_SOUND ) ~= 0

    local ent = data:GetEntity()
    if IsValid( ent ) then
        self.ParentEnt = ent
        self.ParentStartOffset = ent:WorldToLocal( self.StartPos )
        
        if self.ParentMode then
            self.ParentEndWorld = Vector( self.EndPos )
        else
            self.ParentEndOffset = ent:WorldToLocal( self.EndPos )
        end
        
        self.LastParentPos = ent:GetPos()
        self.LastParentAng = ent:GetAngles()
    end

    self:GenerateArc()

    if not self.NoSound and self.SoundVolume > 0 then
        self:PlayElectricSound()
    end

    if not self.NoLight then
        local effectIdx = self:EntIndex()
        local dlight = DynamicLight( effectIdx )
        if dlight then
            dlight.Pos = self.EndPos
            dlight.Size = math.min( 500 * self.Scale * self.LightMul, 2000 )
            dlight.Decay = 3000
            dlight.R = self.Color.r
            dlight.G = self.Color.g
            dlight.B = self.Color.b
            dlight.Brightness = math.min( 1.25 * self.Scale * self.LightMul, 5 )
            dlight.DieTime = self.DieTime + 0.1
        end

        if self.ParentMode then
            local dlight2 = DynamicLight( effectIdx + 4096 )
            if dlight2 then
                dlight2.Pos = self.StartPos
                dlight2.Size = math.min( 300 * self.Scale * self.LightMul, 1500 )
                dlight2.Decay = 3000
                dlight2.R = self.Color.r
                dlight2.G = self.Color.g
                dlight2.B = self.Color.b
                dlight2.Brightness = math.min( 0.75 * self.Scale * self.LightMul, 3 )
                dlight2.DieTime = self.DieTime + 0.1
            end
        end
    end

    local jitterPadding = self.Jitter * 2
    renderBoundsVector.x = jitterPadding
    renderBoundsVector.y = jitterPadding
    renderBoundsVector.z = jitterPadding
    self:SetRenderBoundsWS( self.StartPos, self.EndPos, renderBoundsVector )
end

function EFFECT:PlayElectricSound()
    local volume = self.SoundVolume
    local pitch = self.SoundPitch + math.random( -10, 10 )

    local zapSound = ElectricSounds[math.random( #ElectricSounds )]
    sound.Play( zapSound, self.EndPos, 75, pitch, volume )

    if self.Scale >= 1 and math.random() > 0.5 then
        local sparkSound = SparkSounds[math.random( #SparkSounds )]
        sound.Play( sparkSound, self.EndPos, 70, pitch + math.random( -20, 20 ), volume * 0.6 )
    end

    if self.ParentMode then
        local startPos = self.StartPos
        timer.Simple( 0.02, function()
            local zapSound2 = ElectricSounds[math.random( #ElectricSounds )]
            sound.Play( zapSound2, startPos, 70, pitch + 10, volume * 0.5 )
        end )
    end
end

function EFFECT:UpdateParentPositions()
    if not IsValid( self.ParentEnt ) then return false end
    
    local entPos = self.ParentEnt:GetPos()
    local entAng = self.ParentEnt:GetAngles()
    
    local moved = false
    if self.LastParentPos and self.LastParentAng then
        local posDiff = entPos:DistToSqr( self.LastParentPos ) > 0.1
        local angDiff = entAng ~= self.LastParentAng
        moved = posDiff or angDiff
    end
    
    self.LastParentPos = entPos
    self.LastParentAng = entAng
    
    self.StartPos = self.ParentEnt:LocalToWorld( self.ParentStartOffset )
    
    if self.ParentMode and self.ParentEndWorld then
        self.EndPos = self.ParentEndWorld
    elseif self.ParentEndOffset then
        self.EndPos = self.ParentEnt:LocalToWorld( self.ParentEndOffset )
    end
    
    return moved
end

function EFFECT:GenerateArc()
    self:UpdateParentPositions()

    local startPos = self.StartPos
    local endPos = self.EndPos
    local direction = endPos - startPos
    local length = direction:Length()

    if length < 1 then
        self.Points = { startPos, endPos }
        self.Branches = nil
        return
    end

    direction:Normalize()

    local ang = direction:Angle()
    local right = ang:Right()
    local up = ang:Up()
    local points = { startPos }
    local segments = self.Segments
    local jitter = self.Jitter

    for i = 1, segments - 1 do
        local frac = i / segments
        local basePos = startPos + direction * length * frac
        local falloff = math.sin( frac * math.pi )
        local jitterAmount = jitter * falloff
        local offsetX = math.Rand( -1, 1 ) * jitterAmount
        local offsetY = math.Rand( -1, 1 ) * jitterAmount
        points[#points + 1] = basePos + right * offsetX + up * offsetY
    end

    points[#points + 1] = endPos
    self.Points = points

    if not self.NoBranches and #points >= 4 then
        self:GenerateBranches( direction, length )
    else
        self.Branches = nil
    end
end

function EFFECT:GenerateBranches( mainDir, mainLength )
    local branches = {}
    local points = self.Points
    local pointCount = #points
    local branchCount = self.BranchCount
    local jitter = self.Jitter
    local usedIndices = {}

    for b = 1, branchCount do
        local pointIdx = nil
        local maxIdx = math.max( 2, pointCount - 2 )
        
        for attempt = 1, 10 do
            local testIdx = math.random( 2, maxIdx )
            if not usedIndices[testIdx] then
                pointIdx = testIdx
                break
            end
        end
        
        if not pointIdx then
            pointIdx = math.random( 2, maxIdx )
        end
        
        usedIndices[pointIdx] = true

        local branchStart = points[pointIdx]
        local branchDir = VectorRand() + mainDir * 0.2
        branchDir:Normalize()
        local branchLen = mainLength * math.Rand( 0.15, 0.4 )
        local branchSegs = math.random( 2, 4 )

        local branch = { branchStart }
        local bAng = branchDir:Angle()
        local bRight = bAng:Right()
        local bUp = bAng:Up()

        for j = 1, branchSegs do
            local t = j / branchSegs
            local distAlongBranch = branchLen * t
            local basePos = branchStart + branchDir * distAlongBranch
            local taper = 1 - t * 0.7
            local branchJitter = jitter * 0.5 * taper
            local offsetX = math.Rand( -1, 1 ) * branchJitter
            local offsetY = math.Rand( -1, 1 ) * branchJitter
            local finalPos = basePos + bRight * offsetX + bUp * offsetY
            branch[#branch + 1] = finalPos
        end

        branch.width = math.Rand( 0.4, 0.7 )
        branches[#branches + 1] = branch

        if branchSegs >= 3 and math.random() > 0.5 then
            local subStart = branch[2]
            local subDir = VectorRand() + branchDir * 0.1
            subDir:Normalize()
            local subLen = branchLen * math.Rand( 0.3, 0.5 )

            local subBranch = { subStart }
            for k = 1, 2 do
                local t = k / 2
                local distAlongSub = subLen * t
                local basePos = subStart + subDir * distAlongSub
                local taper = 1 - t
                local subJitter = jitter * 0.3 * taper
                local randomOffset = VectorRand() * subJitter
                local finalPos = basePos + randomOffset
                subBranch[#subBranch + 1] = finalPos
            end

            subBranch.width = branch.width * 0.5
            branches[#branches + 1] = subBranch
        end
    end

    self.Branches = branches
end

function EFFECT:Think()
    if CurTime() >= self.DieTime then return false end

    local shouldRegenerate = false
    
    if IsValid( self.ParentEnt ) then
        local entMoved = self:UpdateParentPositions()
        if entMoved then
            shouldRegenerate = true
        end
    end
    
    if not self.Static then
        self.NextFlicker = self.NextFlicker or 0
        if CurTime() >= self.NextFlicker then
            shouldRegenerate = true
            self.NextFlicker = CurTime() + math.Rand( 0.015, 0.035 ) / self.FlickerMul
        end
    end
    
    if shouldRegenerate then
        self:GenerateArc()
    end

    return true
end

function EFFECT:Render()
    local timeLeft = self.DieTime - CurTime()
    if timeLeft <= 0 then return end

    local fade = self.NoFade and 1 or ( timeLeft / self.Duration )
    if fade > 1 then fade = 1 end

    local width = 8 * self.Scale * self.WidthMul * fade
    local fadeAlpha = 255 * fade

    local myColor = self.Color
    renderCol.r = myColor.r
    renderCol.g = myColor.g
    renderCol.b = myColor.b
    renderCol.a = fadeAlpha

    local myCoreColor = self.CoreColor
    renderCoreCol.r = myCoreColor.r
    renderCoreCol.g = myCoreColor.g
    renderCoreCol.b = myCoreColor.b
    renderCoreCol.a = fadeAlpha

    render.SetMaterial( BeamMaterial )

    local points = self.Points
    local thickCore = not self.NoThickCore
    local pointCount = #points
    
    for i = 1, pointCount - 1 do
        render.DrawBeam( points[i], points[i + 1], width, 0, 1, renderCol )

        if thickCore then
            render.DrawBeam( points[i], points[i + 1], width * 0.3, 0, 1, renderCoreCol )
        end
    end

    local branches = self.Branches
    if not branches then return end

    for _, branch in ipairs( branches ) do
        local bWidth = width * ( branch.width or 0.5 )
        local branchSegCount = #branch - 1

        for i = 1, branchSegCount do
            local taper = 1 - ( ( i - 1 ) / branchSegCount ) * 0.5
            local segWidth = bWidth * taper
            render.DrawBeam( branch[i], branch[i + 1], segWidth, 0, 1, renderCol )

            if thickCore then
                render.DrawBeam( branch[i], branch[i + 1], segWidth * 0.3, 0, 1, renderCoreCol )
            end
        end
    end
end
