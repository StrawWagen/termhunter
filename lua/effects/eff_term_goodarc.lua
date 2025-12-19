-- Customizable Lightning Arc Effect
-- By regunkyle
--
-- ============================================
-- USAGE EXAMPLE:
-- ============================================
-- local fx = EffectData()
-- fx:SetStart( startPos )               -- Start position ( required )
-- fx:SetOrigin( endPos )                -- End position ( required )
-- fx:SetScale( 1 )                      -- Overall scale ( default: 1 )
-- fx:SetMagnitude( 8 )                  -- Arc segments 3-64 ( default: 8 )
-- fx:SetRadius( 20 )                    -- Arc jitter intensity ( default: 20 * scale )
-- fx:SetNormal( Vector( 0.4, 0.6, 1 ) ) -- Color as Vector( R, G, B ) in 0-1 range
-- fx:SetEntity( ent )                   -- Attach to entity ( optional )
-- fx:SetFlags( 0 )                      -- Bitflags ( see below )
-- fx:SetSurfaceProp( 1 )                -- Beam width multiplier ( default: 1 )
-- fx:SetHitBox( 1 )                     -- Duration multiplier ( default: 1 )
-- fx:SetDamageType( 5 )                 -- Branch count 0-10 ( default: auto when branches enabled )
-- fx:SetMaterialIndex( 1 )              -- Flicker speed multiplier ( default: 1 )
-- fx:SetColor( 2 )                      -- Light brightness multiplier ( default: 1 )
-- fx:SetAttachment( 1 )                   -- Sound volume 0-2 (default: 1, 0 = no sound)
-- fx:SetAngle( Angle( 100, 0, 0 ) )         -- Sound pitch in angle.p (default: 100)
-- util.Effect( "eff_term_goodarc", fx )
--
-- FLAGS:
--   1  = No dynamic light
--   2  = Enable branches
--   4  = No fade out
--   8  = Connect mode ( arc bends toward target )
--   16 = Thick core ( adds bright center beam )
--   32 = No flicker ( static arc )
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
local FLAG_BRANCHES = 2
local FLAG_NO_FADE = 4
local FLAG_CONNECT = 8
local FLAG_THICK_CORE = 16
local FLAG_NO_FLICKER = 32
local FLAG_NO_SOUND = 64

-- Electric sound pool
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
    self.Scale = math.max( data:GetScale() or 1, 0.1 )

    -- Width multiplier
    local widthMul = data:GetSurfaceProp()
    self.WidthMul = ( widthMul > 0 ) and widthMul or 1

    -- Duration multiplier
    local durMul = data:GetHitBox()
    self.DurationMul = ( durMul > 0 ) and durMul or 1

    -- Flicker speed multiplier
    local flickerMul = data:GetMaterialIndex()
    self.FlickerMul = ( flickerMul > 0 ) and flickerMul or 1

    -- Light brightness multiplier
    local lightMul = data:GetColor()
    self.LightMul = ( lightMul > 0 ) and lightMul or 1

    -- Sound settings
    local soundVol = data:GetAttachment()
    self.SoundVolume = ( soundVol >= 0 ) and math.Clamp( soundVol, 0, 2 ) or 1

    local soundAng = data:GetAngles()
    self.SoundPitch = ( soundAng and soundAng.p > 0 ) and math.Clamp( soundAng.p, 50, 200 ) or 100

    -- Timing
    self.Duration = math.Clamp( 0.06 * self.Scale * self.DurationMul, 0.02, 1 )
    self.DieTime = CurTime() + self.Duration

    -- Arc segments
    local segments = data:GetMagnitude()
    self.Segments = ( segments >= 3 ) and math.Clamp( math.floor( segments ), 3, 64 ) or 8

    -- Jitter intensity
    local radius = data:GetRadius()
    self.Jitter = ( radius > 0 ) and radius or ( 20 * self.Scale )

    -- Color from normal vector
    local col = data:GetNormal()
    if col:LengthSqr() > 0 then
        self.Color = Color(
            math.Clamp( col.x * 255, 0, 255 ),
            math.Clamp( col.y * 255, 0, 255 ),
            math.Clamp( col.z * 255, 0, 255 )
        )

    else
        self.Color = Color( 100, 150, 255 )

    end

    -- Bright core color
    self.CoreColor = Color(
        math.min( self.Color.r + 100, 255 ),
        math.min( self.Color.g + 100, 255 ),
        math.min( self.Color.b + 100, 255 )
    )

    -- Parse flags
    local flags = data:GetFlags() or 0
    self.NoLight = bit.band( flags, FLAG_NO_LIGHT ) ~= 0
    self.DoBranches = bit.band( flags, FLAG_BRANCHES ) ~= 0
    self.NoFade = bit.band( flags, FLAG_NO_FADE ) ~= 0
    self.ConnectMode = bit.band( flags, FLAG_CONNECT ) ~= 0
    self.ThickCore = bit.band( flags, FLAG_THICK_CORE ) ~= 0
    self.NoFlicker = bit.band( flags, FLAG_NO_FLICKER ) ~= 0
    self.NoSound = bit.band( flags, FLAG_NO_SOUND ) ~= 0

    -- Branch count
    local branchCount = data:GetDamageType()
    self.BranchCount = ( branchCount > 0 ) and math.Clamp( branchCount, 1, 10 ) or nil

    -- Entity attachment
    local ent = data:GetEntity()
    if IsValid( ent ) then
        self.AttachedEnt = ent
        self.AttachStartOffset = self.StartPos - ent:GetPos()
        self.AttachEndOffset = self.EndPos - ent:GetPos()

    end

    -- Generate initial arc
    self:GenerateArc()

    -- Play electric sound at end position
    if not self.NoSound and self.SoundVolume > 0 then
        self:PlayElectricSound()

    end

    -- Dynamic light
    if not self.NoLight then
        local dlight = DynamicLight( self:EntIndex() )
        if dlight then
            dlight.Pos = self.EndPos
            dlight.Size = 500 * self.Scale * self.LightMul
            dlight.Decay = 3000
            dlight.R = self.Color.r
            dlight.G = self.Color.g
            dlight.B = self.Color.b
            dlight.Brightness = math.Clamp( 1.25 * self.Scale * self.LightMul, 0, 20 )
            dlight.DieTime = self.DieTime + 0.1

        end

        -- Start light for connect mode
        if self.ConnectMode then
            local dlight2 = DynamicLight( self:EntIndex() + 4096 )
            if dlight2 then
                dlight2.Pos = self.StartPos
                dlight2.Size = 300 * self.Scale * self.LightMul
                dlight2.Decay = 3000
                dlight2.R = self.Color.r
                dlight2.G = self.Color.g
                dlight2.B = self.Color.b
                dlight2.Brightness = math.Clamp( 0.75 * self.Scale * self.LightMul, 0, 15 )
                dlight2.DieTime = self.DieTime + 0.1

            end
        end
    end

    self:SetRenderBoundsWS( self.StartPos, self.EndPos, Vector( 1, 1, 1 ) * self.Jitter * 2 )

end

function EFFECT:PlayElectricSound()
    local volume = 0.3 * self.SoundVolume * math.Clamp( self.Scale, 0.5, 2 )
    local pitch = self.SoundPitch + math.random( -10, 10 )

    -- Main zap sound at end position
    local zapSound = ElectricSounds[math.random( #ElectricSounds )]
    sound.Play( zapSound, self.EndPos, 75, pitch, volume )

    -- Additional spark sound for larger arcs
    if self.Scale >= 1 and math.random() > 0.5 then
        local sparkSound = SparkSounds[math.random( #SparkSounds )]
        sound.Play( sparkSound, self.EndPos, 70, pitch + math.random(-20, 20), volume * 0.6 )

    end

    -- Sound at start for connect mode
    if self.ConnectMode then
        timer.Simple( 0.02, function()
            local zapSound2 = ElectricSounds[math.random( #ElectricSounds )]
            sound.Play( zapSound2, self.StartPos, 70, pitch + 10, volume * 0.5 )

        end )
    end
end

function EFFECT:GenerateArc()
    if IsValid( self.AttachedEnt ) then
        local entPos = self.AttachedEnt:GetPos()
        self.StartPos = entPos + self.AttachStartOffset
        self.EndPos = entPos + self.AttachEndOffset

    end

    local startPos = self.StartPos
    local endPos = self.EndPos
    local direction = endPos - startPos
    local length = direction:Length()

    if length < 1 then
        self.Points = {startPos, endPos}
        self.Branches = nil
        return

    end

    direction:Normalize()

    local ang = direction:Angle()
    local right = ang:Right()
    local up = ang:Up()

    self.Points = { startPos }

    -- Connect mode: arc bends toward target
    if self.ConnectMode then
        local bendPoint = length * math.Rand( 0.3, 0.5 )
        local bendOffset = ( right * math.Rand( -1, 1 ) + up * math.Rand( -1, 1 ) ):GetNormalized() * length * 0.3
        local midPoint = startPos + direction * bendPoint + bendOffset

        -- First segment: start to bend point
        local seg1Count = math.floor( self.Segments * 0.4 )
        local dir1 = ( midPoint - startPos ):GetNormalized()
        local len1 = ( midPoint - startPos ):Length()
        local ang1 = dir1:Angle()
        local right1, up1 = ang1:Right(), ang1:Up()

        for i = 1, seg1Count do
            local frac = i / ( seg1Count + 1 )
            local basePos = startPos + dir1 * len1 * frac
            local falloff = math.sin( frac * math.pi )
            local offsetX = math.Rand( -1, 1 ) * self.Jitter * falloff * 0.7
            local offsetY = math.Rand( -1, 1 ) * self.Jitter * falloff * 0.7
            self.Points[#self.Points + 1] = basePos + right1 * offsetX + up1 * offsetY

        end

        self.Points[#self.Points + 1] = midPoint

        -- Second segment: bend point to end
        local seg2Count = self.Segments - seg1Count
        local dir2 = ( endPos - midPoint ):GetNormalized()
        local len2 = ( endPos - midPoint ):Length()
        local ang2 = dir2:Angle()
        local right2, up2 = ang2:Right(), ang2:Up()

        for i = 1, seg2Count - 1 do
            local frac = i / seg2Count
            local basePos = midPoint + dir2 * len2 * frac
            local falloff = math.sin( frac * math.pi )
            local offsetX = math.Rand( -1, 1 ) * self.Jitter * falloff * 0.7
            local offsetY = math.Rand( -1, 1 ) * self.Jitter * falloff * 0.7
            self.Points[#self.Points + 1] = basePos + right2 * offsetX + up2 * offsetY

        end
    else
        -- Normal mode
        for i = 1, self.Segments - 1 do
            local frac = i / self.Segments
            local basePos = startPos + direction * length * frac
            local falloff = math.sin( frac * math.pi )
            local offsetX = math.Rand( -1, 1 ) * self.Jitter * falloff
            local offsetY = math.Rand( -1, 1 ) * self.Jitter * falloff
            self.Points[#self.Points + 1] = basePos + right * offsetX + up * offsetY

        end
    end

    self.Points[#self.Points + 1] = endPos

    -- Generate branches
    if self.DoBranches and #self.Points >= 4 then
        self:GenerateBranches( direction, length )

    else
        self.Branches = nil

    end
end

function EFFECT:GenerateBranches( mainDir, mainLength )
    self.Branches = {}

    local branchCount = self.BranchCount or math.Clamp( math.floor( self.Segments / 2.5 ), 1, 6 )
    local usedIndices = {}

    for _ = 1, branchCount do
        local attempts = 0
        local pointIdx

        repeat
            pointIdx = math.random( 2, math.max( 2, #self.Points - 2 ) )
            attempts = attempts + 1

        until not usedIndices[pointIdx] or attempts > 10

        usedIndices[pointIdx] = true

        local branchStart = self.Points[pointIdx]
        local branchDir = ( VectorRand() + mainDir * 0.2 ):GetNormalized()
        local branchLen = mainLength * math.Rand( 0.15, 0.4 )
        local branchSegs = math.random( 2, 4 )

        local branch = {branchStart}
        local bAng = branchDir:Angle()
        local bRight, bUp = bAng:Right(), bAng:Up()

        for j = 1, branchSegs do
            local t = j / branchSegs
            local pos = branchStart + branchDir * branchLen * t
            local jitter = self.Jitter * 0.5 * ( 1 - t * 0.7 )
            pos = pos + bRight * math.Rand( -1, 1 ) * jitter + bUp * math.Rand( -1, 1 ) * jitter
            branch[#branch + 1] = pos

        end

        branch.width = math.Rand( 0.4, 0.7 )
        self.Branches[#self.Branches + 1] = branch

        -- Sub-branches
        if branchSegs >= 3 and math.random() > 0.5 then
            local subStart = branch[2]
            local subDir = ( VectorRand() + branchDir * 0.1 ):GetNormalized()
            local subLen = branchLen * math.Rand( 0.3, 0.5 )

            local subBranch = {subStart}
            for k = 1, 2 do
                local t = k / 2
                local pos = subStart + subDir * subLen * t
                pos = pos + VectorRand() * self.Jitter * 0.3 * ( 1 - t )
                subBranch[#subBranch + 1] = pos

            end

            subBranch.width = branch.width * 0.5
            self.Branches[#self.Branches + 1] = subBranch

        end
    end
end

function EFFECT:Think()
    if CurTime() >= self.DieTime then return false end

    if self.NoFlicker then return true end

    self.NextFlicker = self.NextFlicker or 0
    if CurTime() >= self.NextFlicker then return true end

    self:GenerateArc()
    self.NextFlicker = CurTime() + math.Rand( 0.015, 0.035 ) / self.FlickerMul

    return true

end

function EFFECT:Render()
    local timeLeft = self.DieTime - CurTime()
    if timeLeft <= 0 then return end

    local alpha = self.NoFade and 1 or math.Clamp( timeLeft / self.Duration, 0, 1 )
    local width = 8 * self.Scale * self.WidthMul * alpha

    local col = Color( self.Color.r, self.Color.g, self.Color.b, 255 * alpha )
    local coreCol = Color( self.CoreColor.r, self.CoreColor.g, self.CoreColor.b, 255 * alpha )

    render.SetMaterial( BeamMaterial )

    -- Draw main arc
    local points = self.Points
    for i = 1, #points - 1 do
        render.DrawBeam( points[i], points[i + 1], width, 0, 1, col )

        if not self.ThickCore then continue end
        render.DrawBeam( points[i], points[i + 1], width * 0.3, 0, 1, coreCol )

    end

    -- Draw branches
    local branches = self.Branches
    if not branches then return end
    for _, branch in ipairs( branches ) do
        local bWidth = width * ( branch.width or 0.5 )
        for i = 1, #branch - 1 do
            local taper = 1 - ( ( i - 1 ) / ( #branch - 1 ) ) * 0.5
            render.DrawBeam( branch[i], branch[i + 1], bWidth * taper, 0, 1, col )

            if not self.ThickCore then continue end
            render.DrawBeam( branch[i], branch[i + 1], bWidth * taper * 0.3, 0, 1, coreCol )

        end
    end
end
