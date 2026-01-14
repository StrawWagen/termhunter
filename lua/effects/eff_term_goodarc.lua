-- GOODARC Effect
-- By regunkyle
--
-- ============================================
-- USAGE:
-- ============================================
-- local fx = EffectData()
-- fx:SetStart( startPos )               -- Start position
-- fx:SetOrigin( endPos )                -- End position
-- fx:SetScale( 1 )                      -- Overall scale
-- fx:SetMagnitude( 8 )                  -- Arc segments
-- fx:SetRadius( 20 )                    -- Arc jitter intensity
-- fx:SetNormal( Vector( 0.4, 0.6, 1 ) ) -- Color as RGB 0-1
-- fx:SetDamageType( 5 )                 -- Branch count
-- fx:SetEntity( ent )                   -- Parent entity
-- fx:SetFlags( 0 )                      -- Bitflags
-- util.Effect( "eff_term_goodarc", fx )
--
-- FLAGS:
--   1  = No dynamic light
--   2  = No branches
--   4  = No fade out
--   8  = Parent mode (start follows entity, end fixed in world)
--   16 = No sound
--
-- COLORS:
--   Blue:   Vector( 0.4, 0.6, 1 )
--   Red:    Vector( 1, 0.1, 0.1 )
--   Green:  Vector( 0.1, 1, 0.1 )
--   Cyan:   Vector( 0.1, 1, 1 )
--   White:  Vector( 1, 1, 1 )
--   Purple: Vector( 0.6, 0.1, 1 )
-- ============================================

local BeamMaterial = CreateMaterial( "xeno/beamlightning", "UnlitGeneric", {
    ["$basetexture"] = "sprites/spotlight",
    ["$additive"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
} )

-- Flags
local NO_LIGHT    = 1
local NO_BRANCHES = 2
local NO_FADE     = 4
local PARENT_MODE = 8
local NO_SOUND    = 16

-- Sounds
local ZapSounds = {
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

-- Reusable color objects
local renderCol = Color( 255, 255, 255 )
local coreCol = Color( 255, 255, 255 )

function EFFECT:Init( data )
    self.StartPos = data:GetStart()
    self.EndPos = data:GetOrigin()
    self.Scale = data:GetScale()
    self.Segments = math.floor( data:GetMagnitude() )
    self.Jitter = data:GetRadius()
    self.BranchCount = data:GetDamageType()

    self.Duration = math.max( 0.06 * self.Scale, 0.02 )
    self.DieTime = CurTime() + self.Duration

    -- Color from normal vector
    local col = data:GetNormal()
    self.Color = Color( col.x * 255, col.y * 255, col.z * 255 )
    self.CoreColor = Color(
        math.min( self.Color.r + 100, 255 ),
        math.min( self.Color.g + 100, 255 ),
        math.min( self.Color.b + 100, 255 )
    )

    -- Parse flags
    local flags = data:GetFlags()
    self.NoLight    = bit.band( flags, NO_LIGHT ) ~= 0
    self.NoBranches = bit.band( flags, NO_BRANCHES ) ~= 0
    self.NoFade     = bit.band( flags, NO_FADE ) ~= 0
    self.ParentMode = bit.band( flags, PARENT_MODE ) ~= 0
    self.NoSound    = bit.band( flags, NO_SOUND ) ~= 0

    -- Entity parenting
    local ent = data:GetEntity()
    if IsValid( ent ) then
        self.ParentEnt = ent
        self.StartOffset = ent:WorldToLocal( self.StartPos )
        if self.ParentMode then
            self.EndWorld = Vector( self.EndPos )
        else
            self.EndOffset = ent:WorldToLocal( self.EndPos )
        end
    end

    -- Initialize points (GenerateArc called in Think)
    self.Points = { self.StartPos, self.EndPos }
    self.NextFlicker = 0

    if not self.NoSound then
        self:PlaySound()
    end

    if not self.NoLight then
        self:CreateLight()
    end

    local pad = Vector( self.Jitter * 2, self.Jitter * 2, self.Jitter * 2 )
    self:SetRenderBoundsWS( self.StartPos, self.EndPos, pad )
end

function EFFECT:PlaySound()
    local vol = math.Clamp( 0.3 * self.Scale, 0, 1 )
    local pitch = math.Clamp( 120 - self.Scale * 15 + math.random( -10, 10 ), 50, 200 )

    sound.Play( ZapSounds[ math.random( #ZapSounds ) ], self.EndPos, 75, pitch, vol )

    if self.Scale >= 1 and math.random() > 0.5 then
        sound.Play( SparkSounds[ math.random( #SparkSounds ) ], self.EndPos, 70, pitch + math.random( -20, 20 ), vol * 0.6 )
    end

    if self.ParentMode then
        local pos = self.StartPos
        timer.Simple( 0.02, function()
            sound.Play( ZapSounds[ math.random( #ZapSounds ) ], pos, 70, pitch + 10, vol * 0.5 )
        end )
    end
end

function EFFECT:CreateLight()
    local id = self:EntIndex()

    local light = DynamicLight( id )
    if light then
        light.Pos = self.EndPos
        light.Size = math.min( 500 * self.Scale, 2000 )
        light.Decay = 3000
        light.R = self.Color.r
        light.G = self.Color.g
        light.B = self.Color.b
        light.Brightness = math.min( 1.25 * self.Scale, 5 )
        light.DieTime = self.DieTime + 0.1
    end

    if self.ParentMode then
        local light2 = DynamicLight( id + 4096 )
        if light2 then
            light2.Pos = self.StartPos
            light2.Size = math.min( 300 * self.Scale, 1500 )
            light2.Decay = 3000
            light2.R = self.Color.r
            light2.G = self.Color.g
            light2.B = self.Color.b
            light2.Brightness = math.min( 0.75 * self.Scale, 3 )
            light2.DieTime = self.DieTime + 0.1
        end
    end
end

function EFFECT:UpdatePositions()
    if not IsValid( self.ParentEnt ) then return end

    self.StartPos = self.ParentEnt:LocalToWorld( self.StartOffset )

    if self.ParentMode then
        self.EndPos = self.EndWorld
    else
        self.EndPos = self.ParentEnt:LocalToWorld( self.EndOffset )
    end
end

function EFFECT:GenerateArc()
    self:UpdatePositions()

    local dir = self.EndPos - self.StartPos
    local len = dir:Length()

    if len < 1 then
        self.Points = { self.StartPos, self.EndPos }
        self.Branches = nil
        return
    end

    dir:Normalize()
    local ang = dir:Angle()
    local right, up = ang:Right(), ang:Up()

    local points = { self.StartPos }
    for i = 1, self.Segments - 1 do
        local t = i / self.Segments
        local base = self.StartPos + dir * len * t
        local jit = self.Jitter * math.sin( t * math.pi )
        local offset = right * math.Rand( -jit, jit ) + up * math.Rand( -jit, jit )
        points[ #points + 1 ] = base + offset
    end
    points[ #points + 1 ] = self.EndPos

    self.Points = points

    if not self.NoBranches and self.BranchCount > 0 and #points >= 4 then
        self:GenerateBranches( dir, len )
    else
        self.Branches = nil
    end
end

function EFFECT:GenerateBranches( mainDir, mainLen )
    local branches = {}
    local used = {}

    for _ = 1, self.BranchCount do
        local maxIdx = math.max( 2, #self.Points - 2 )
        local idx = math.random( 2, maxIdx )

        for _ = 1, 10 do
            if not used[ idx ] then break end
            idx = math.random( 2, maxIdx )
        end
        used[ idx ] = true

        local start = self.Points[ idx ]
        local dir = VectorRand() + mainDir * 0.2
        dir:Normalize()
        local len = mainLen * math.Rand( 0.15, 0.4 )
        local segs = math.random( 2, 4 )

        local ang = dir:Angle()
        local right, up = ang:Right(), ang:Up()

        local branch = { start }
        for j = 1, segs do
            local t = j / segs
            local base = start + dir * len * t
            local jit = self.Jitter * 0.5 * ( 1 - t * 0.7 )
            local offset = right * math.Rand( -jit, jit ) + up * math.Rand( -jit, jit )
            branch[ #branch + 1 ] = base + offset
        end
        branch.width = math.Rand( 0.4, 0.7 )
        branches[ #branches + 1 ] = branch

        -- Sub-branch
        if segs >= 3 and math.random() > 0.5 then
            local subStart = branch[ 2 ]
            local subDir = VectorRand() + dir * 0.1
            subDir:Normalize()
            local subLen = len * math.Rand( 0.3, 0.5 )

            local sub = { subStart }
            for k = 1, 2 do
                local t = k / 2
                local base = subStart + subDir * subLen * t
                sub[ #sub + 1 ] = base + VectorRand() * self.Jitter * 0.3 * ( 1 - t )
            end
            sub.width = branch.width * 0.5
            branches[ #branches + 1 ] = sub
        end
    end

    self.Branches = branches
end

function EFFECT:Think()
    if CurTime() >= self.DieTime then return false end

    if CurTime() >= self.NextFlicker then
        self:GenerateArc()
        self.NextFlicker = CurTime() + math.Rand( 0.015, 0.035 )
    end

    return true
end

function EFFECT:Render()
    local timeLeft = self.DieTime - CurTime()
    if timeLeft <= 0 then return end

    local fade = self.NoFade and 1 or math.min( timeLeft / self.Duration, 1 )
    local width = 8 * self.Scale * fade
    local alpha = 255 * fade

    renderCol.r, renderCol.g, renderCol.b, renderCol.a = self.Color.r, self.Color.g, self.Color.b, alpha
    coreCol.r, coreCol.g, coreCol.b, coreCol.a = self.CoreColor.r, self.CoreColor.g, self.CoreColor.b, alpha

    render.SetMaterial( BeamMaterial )

    -- Main arc
    for i = 1, #self.Points - 1 do
        render.DrawBeam( self.Points[ i ], self.Points[ i + 1 ], width, 0, 1, renderCol )
        render.DrawBeam( self.Points[ i ], self.Points[ i + 1 ], width * 0.3, 0, 1, coreCol )
    end

    -- Branches
    if not self.Branches then return end

    for _, branch in ipairs( self.Branches ) do
        local bw = width * branch.width
        local segCount = #branch - 1

        for i = 1, segCount do
            local taper = 1 - ( ( i - 1 ) / segCount ) * 0.5
            local w = bw * taper
            render.DrawBeam( branch[ i ], branch[ i + 1 ], w, 0, 1, renderCol )
            render.DrawBeam( branch[ i ], branch[ i + 1 ], w * 0.3, 0, 1, coreCol )
        end
    end
end
