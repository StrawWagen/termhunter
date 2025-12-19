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

    local scale = data:GetScale()
    self.Scale = ( scale and scale > 0 ) and scale or 1

    local widthMul = data:GetSurfaceProp()
    self.WidthMul = ( widthMul and widthMul > 0 ) and widthMul or 1

    local durMul = data:GetHitBox()
    self.DurationMul = ( durMul and durMul > 0 ) and durMul or 1

    local flickerMul = data:GetMaterialIndex()
    self.FlickerMul = ( flickerMul and flickerMul > 0 ) and flickerMul or 1

    local lightMul = data:GetColor()
    self.LightMul = ( lightMul and lightMul > 0 ) and lightMul or 1

    self.SoundVolume = 0.3 * self.Scale
    self.SoundPitch = 120 - self.Scale * 15

    self.Duration = math.max( 0.06 * self.Scale * self.DurationMul, 0.02 )
    self.DieTime = CurTime() + self.Duration

    local segments = data:GetMagnitude()
    self.Segments = ( segments and segments >= 3 ) and math.floor( segments ) or 8

    local radius = data:GetRadius()
    self.Jitter = ( radius and radius > 0 ) and radius or ( 20 * self.Scale )

    local col = data:GetNormal()
    if col and col:LengthSqr() > 0 then
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

    local flags = data:GetFlags() or 0
    self.NoLight = bit.band( flags, FLAG_NO_LIGHT ) ~= 0
    self.DoBranches = bit.band( flags, FLAG_BRANCHES ) ~= 0
    self.NoFade = bit.band( flags, FLAG_NO_FADE ) ~= 0
    self.ConnectMode = bit.band( flags, FLAG_CONNECT ) ~= 0
    self.ThickCore = bit.band( flags, FLAG_THICK_CORE ) ~= 0
    self.NoFlicker = bit.band( flags, FLAG_NO_FLICKER ) ~= 0
    self.NoSound = bit.band( flags, FLAG_NO_SOUND ) ~= 0

    local branchCount = data:GetDamageType()
    self.BranchCount = ( branchCount and branchCount > 0 ) and branchCount or nil

    local ent = data:GetEntity()
    if IsValid( ent ) then
        self.AttachedEnt = ent
        self.AttachStartOffset = ent:WorldToLocal( self.StartPos )
        self.AttachEndOffset = ent:WorldToLocal( self.EndPos )
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

        if self.ConnectMode then
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

    if self.ConnectMode then
        local startPos = self.StartPos
        timer.Simple( 0.02, function()
            local zapSound2 = ElectricSounds[math.random( #ElectricSounds )]
            sound.Play( zapSound2, startPos, 70, pitch + 10, volume * 0.5 )
        end )
    end
end

function EFFECT:GenerateArc()
    if IsValid( self.AttachedEnt ) then
        self.StartPos = self.AttachedEnt:LocalToWorld( self.AttachStartOffset )
        self.EndPos = self.AttachedEnt:LocalToWorld( self.AttachEndOffset )
    end

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

    self.Points = { startPos }

    if self.ConnectMode then
        local bendPoint = length * math.Rand( 0.3, 0.5 )
        local bendOffset = ( right * math.Rand( -1, 1 ) + up * math.Rand( -1, 1 ) ):GetNormalized() * length * 0.3
        local midPoint = startPos + direction * bendPoint + bendOffset

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

    if self.DoBranches and #self.Points >= 4 then
        self:GenerateBranches( direction, length )
    else
        self.Branches = nil
    end
end

function EFFECT:GenerateBranches( mainDir, mainLength )
    self.Branches = {}

    local branchCount = self.BranchCount or math.max( 1, math.floor( self.Segments / 2.5 ) )
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

        local branch = { branchStart }
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

        if branchSegs >= 3 and math.random() > 0.5 then
            local subStart = branch[2]
            local subDir = ( VectorRand() + branchDir * 0.1 ):GetNormalized()
            local subLen = branchLen * math.Rand( 0.3, 0.5 )

            local subBranch = { subStart }
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
    if CurTime() < self.NextFlicker then return true end

    self:GenerateArc()
    self.NextFlicker = CurTime() + math.Rand( 0.015, 0.035 ) / self.FlickerMul

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
    local thickCore = self.ThickCore
    for i = 1, #points - 1 do
        render.DrawBeam( points[i], points[i + 1], width, 0, 1, renderCol )

        if thickCore then
            render.DrawBeam( points[i], points[i + 1], width * 0.3, 0, 1, renderCoreCol )
        end
    end

    local branches = self.Branches
    if not branches then return end

    for _, branch in ipairs( branches ) do
        local bWidth = width * ( branch.width or 0.5 )
        local branchLen = #branch - 1

        for i = 1, branchLen do
            local taper = 1 - ( ( i - 1 ) / branchLen ) * 0.5
            render.DrawBeam( branch[i], branch[i + 1], bWidth * taper, 0, 1, renderCol )

            if thickCore then
                render.DrawBeam( branch[i], branch[i + 1], bWidth * taper * 0.3, 0, 1, renderCoreCol )
            end
        end
    end
end
