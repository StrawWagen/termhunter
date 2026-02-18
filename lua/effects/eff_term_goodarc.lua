-- GOODARC Effect
-- By regunkyle
--
-- ============================================
-- USAGE:
-- ============================================
-- local fx = EffectData()
-- fx:SetOrigin( startPos )                -- Start position
-- fx:SetStart( endPos )                    -- End position
-- fx:SetNormal( Vector( 0, 0, 1 ) )        -- Starting direction
-- fx:SetScale( 1 )                         -- Overall scale
-- fx:SetMagnitude( 8 )                     -- Arc segments
-- fx:SetRadius( 20 )                       -- Arc position jitter intensity
-- fx:SetAngles( Angle( 102, 153, 255 ) )   -- Color
-- fx:SetDamageType( 5 )                    -- Branch count
-- fx:SetEntity( ent )                      -- Parent entity
-- fx:SetFlags( 0 )                         -- Bitflags
-- util.Effect( "eff_term_goodarc", fx )
--
-- IMPORTANT! every effect setting must be set! ( because of the historic effect settings bug )
--
-- FLAGS:
--   1   = No dynamic light
--   2   = No branches
--   4   = No fade out
--   8   = Parent mode ( start follows entity, end fixed to world coords )
--   16  = No sound
--   32  = Continue through world
--   64  = Don't turn ( always go straight towards endPos )
--   128 = No scorch decals ( decals rely on flag 32, disabling that also disables this )
--
-- COLORS:
--   Blue:   Vector( 0.4, 0.6, 1 )
--   Red:    Vector( 1, 0.1, 0.1 )
--   Green:  Vector( 0.1, 1, 0.1 )
--   Cyan:   Vector( 0.1, 1, 1 )
--   White:  Vector( 1, 1, 1 )
--   Purple: Vector( 0.6, 0.1, 1 )
-- ============================================

local math = math

local BeamMaterial = CreateMaterial( "xeno/beamlightning", "UnlitGeneric", {
    ["$basetexture"] = "sprites/spotlight",
    ["$additive"] = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
} )

-- Flags
local NO_LIGHT      = 1
local NO_BRANCHES   = 2
local NO_FADE       = 4
local PARENT_MODE   = 8
local NO_SOUND      = 16
local PASS_WORLD    = 32
local NO_TURN       = 64
local NO_DECAL      = 128

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

local function isInWorld( pos ) -- is the point inside the world, not in a wall?
    local inWorld = bit.band( util.PointContents( pos ), CONTENTS_SOLID ) == 0
    return inWorld

end

-- Reusable color objects
local renderCol = Color( 255, 255, 255 )
local coreCol = Color( 255, 255, 255 )
local vector_zero = Vector( 0, 0, 0 )
local bit_band = bit.band

function EFFECT:Init( data )
    self.StartPos = data:GetOrigin()
    self.EndPos = data:GetStart()
    self.StartDir = data:GetNormal() -- does nothing if NO_TURN is true
    self.Scale = data:GetScale()
    self.SegmentCount = math.floor( data:GetMagnitude() )
    local jitter = data:GetRadius()
    self.Jitter = jitter
    self.BranchCount = data:GetDamageType()

    self.Duration = math.max( 0.06 * self.Scale, 0.02 )
    self.DieTime = CurTime() + self.Duration

    -- Color from angle
    local col = data:GetAngles()
    self.Color = Color( col.x, col.y, col.z )
    self.CoreColor = Color(
        math.min( self.Color.r + 100, 255 ),
        math.min( self.Color.g + 100, 255 ),
        math.min( self.Color.b + 100, 255 )
    )

    -- Parse flags
    local flags = data:GetFlags()
    self.NoLight    = bit_band( flags, NO_LIGHT ) ~= 0
    self.NoBranches = bit_band( flags, NO_BRANCHES ) ~= 0
    self.NoFade     = bit_band( flags, NO_FADE ) ~= 0
    self.ParentMode = bit_band( flags, PARENT_MODE ) ~= 0
    self.NoSound    = bit_band( flags, NO_SOUND ) ~= 0
    self.PassWorld  = bit_band( flags, PASS_WORLD ) ~= 0
    self.NoTurn     = bit_band( flags, NO_TURN ) ~= 0
    self.NoDecal    = bit_band( flags, NO_DECAL ) ~= 0

    if self.StartDir == vector_zero then
        self.NoTurn = true

    end

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
    self.SetupPoints = false
    self.NextFlicker = 0

    if not self.NoSound then
        self:PlaySound()

    end

    if not self.NoLight then
        self:CreateLight()

    end

    local pad = Vector( jitter * 2, jitter * 2, jitter * 2 )
    self:SetRenderBoundsWS( self.StartPos, self.EndPos, pad )

end

function EFFECT:PlaySound()
    local vol = math.Clamp( 0.3 * self.Scale, 0, 1 )
    local pitch = math.Clamp( 120 - self.Scale * 15 + math.random( -10, 10 ), 50, 200 )

    sound.Play( ZapSounds[math.random( #ZapSounds )], self.EndPos, 75, pitch, vol )

    if self.Scale >= 1 and math.random() > 0.5 then
        sound.Play( SparkSounds[math.random( #SparkSounds )], self.EndPos, 70, pitch + math.random( -20, 20 ), vol * 0.6 )

    end

    if self.ParentMode then
        local pos = self.StartPos
        timer.Simple( 0.02, function()
            sound.Play( ZapSounds[math.random( #ZapSounds )], pos, 70, pitch + 10, vol * 0.5 )

        end )
    end
end

function EFFECT:CreateLight()
    local id = self:EntIndex()
    local myColor = self.Color
    local scale = self.Scale

    local light = DynamicLight( id )
    if light then
        light.Pos = self.EndPos
        light.Size = math.min( 500 * scale, 2000 )
        light.Decay = 3000
        light.R = myColor.r
        light.G = myColor.g
        light.B = myColor.b
        light.Brightness = math.min( 1.25 * scale, 5 )
        light.DieTime = self.DieTime + 0.1

    end

    if self.ParentMode then
        local light2 = DynamicLight( id + 4096 )
        if light2 then
            light2.Pos = self.StartPos
            light2.Size = math.min( 300 * scale, 1500 )
            light2.Decay = 3000
            light2.R = myColor.r
            light2.G = myColor.g
            light2.B = myColor.b
            light2.Brightness = math.min( 0.75 * scale, 3 )
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

function EFFECT:GenerateSegmentPoints( startPos, endPos, segCount, jitterFunc, startDir )
    local points = { startPos }

    local dirToEnd = endPos - startPos
    local totalDist = dirToEnd:Length()
    dirToEnd:Normalize()

    local passWorld = self.PassWorld
    local useCurving = startDir and not self.NoTurn

    -- For curving arcs
    local stepSize = totalDist / segCount
    local currentPos
    local blendFactor
    local blendPerSeg
    if useCurving then
        currentPos = startPos
        currentDir = startDir

        -- TODO; make these configurable somehow
        blendFactor = 0.55 -- starting blend factor, bigger = turn less sharply
        blendPerSeg = -0.05 -- how much to reduce blend factor each segment

    end

    for i = 1, segCount - 1 do
        local t = i / segCount
        local base
        local potentialDir
        local moveDir

        if useCurving then
            -- blend current dir with desired dir, and step forward
            potentialDir = ( currentDir * blendFactor ) + ( ( 1 - blendFactor ) * dirToEnd )
            potentialDir:Normalize()
            base = currentPos + potentialDir * stepSize

            moveDir = potentialDir

        else
            -- straight, cheaper and simpler
            base = startPos + dirToEnd * totalDist * t

            moveDir = dirToEnd

        end

        -- apply jitter perpendicular to movement direction
        local ang = moveDir:Angle()
        local right, up = ang:Right(), ang:Up()
        local rx, ry, rz = right.x, right.y, right.z
        local ux, uy, uz = up.x, up.y, up.z

        local jitter = jitterFunc( t )
        local rightJitter = math.Rand( -jitter, jitter )
        local upJitter = math.Rand( -jitter, jitter )

        local offsetX = rx * rightJitter + ux * upJitter
        local offsetY = ry * rightJitter + uy * upJitter
        local offsetZ = rz * rightJitter + uz * upJitter
        local point = Vector( base.x + offsetX, base.y + offsetY, base.z + offsetZ )

        -- World collision check
        if not passWorld and not isInWorld( point ) then
            return points, point, i + 1

        end

        if useCurving then
            currentPos = point
            currentDir = potentialDir
            -- turn more aggresively over time
            blendFactor = math.Clamp( blendFactor + blendPerSeg, 0, 1 )

        end

        points[#points + 1] = point

    end

    return points, nil, nil

end

function EFFECT:GenerateArc()
    self:UpdatePositions()

    local dist = self.StartPos:Distance( self.EndPos )

    if dist < 1 then
        self.Points = { self.StartPos, self.EndPos }
        self.Branches = nil
        return

    end

    local jitterFunc = function( t )
        return self.Jitter * math.sin( t * math.pi )

    end

    local points, hitPoint, hitSegment = self:GenerateSegmentPoints( self.StartPos, self.EndPos, self.SegmentCount, jitterFunc, self.StartDir )

    if hitPoint then
        self.EndPos = hitPoint
        self.SegmentCount = hitSegment
        if not self.NoDecal then
            local scorchStart = points[#points]
            local decalPath = self.Scale >= math.Rand( 1.5, 3 ) and "Scorch" or "SmallScorch"
            util.Decal( decalPath, scorchStart, self.EndPos )

        end
    end

    points[#points + 1] = self.EndPos
    self.Points = points

    if not self.NoBranches and self.BranchCount > 0 and #points >= 4 then
        local dirToEnd = ( self.EndPos - self.StartPos ):GetNormalized()
        self:GenerateBranches( dirToEnd, dist )

    else
        self.Branches = nil

    end
end

function EFFECT:GenerateBranches( mainDir, mainLen )
    local branches = {}
    local used = {}
    local points = self.Points

    for _ = 1, self.BranchCount do
        local lastValidPoint = math.max( 2, #points - 2 )
        local branchStartPoint = math.random( 2, lastValidPoint )

        for _ = 1, 10 do
            if not used[branchStartPoint] then break end
            branchStartPoint = math.random( 2, lastValidPoint )

        end
        used[branchStartPoint] = true

        local start = points[branchStartPoint]
        local branchDir = VectorRand() + mainDir * 0.2
        branchDir:Normalize()
        local len = mainLen * math.Rand( 0.15, 0.4 )
        local segs = math.random( 2, 4 )

        local branchJitterFunc = function( t )
            return self.Jitter * 0.5 * ( 1 - t * 0.7 )

        end

        local branchEnd = start + branchDir * len
        local branch = self:GenerateSegmentPoints( start, branchEnd, segs, branchJitterFunc, nil )
        branch.width = math.Rand( 0.4, 0.7 )
        branches[#branches + 1] = branch

        -- Sub-branch
        if segs >= 3 and math.random() > 0.5 and #branch >= 2 then
            local subStart = branch[2]
            local subDir = VectorRand() + branchDir * 0.1
            subDir:Normalize()

            local subLen = len * math.Rand( 0.3, 0.5 )

            local subJitterFunc = function( t )
                return self.Jitter * 0.3 * ( 1 - t )

            end

            local subEnd = subStart + subDir * subLen
            local sub = self:GenerateSegmentPoints( subStart, subEnd, 2, subJitterFunc, nil )
            sub.width = branch.width * 0.5
            branches[#branches + 1] = sub

        end
    end

    self.Branches = branches

end

function EFFECT:Think()
    if CurTime() >= self.DieTime then return false end

    if CurTime() >= self.NextFlicker then
        self:GenerateArc()
        self.SetupPoints = true
        self.NextFlicker = CurTime() + math.Rand( 0.015, 0.035 )
    end

    return true

end

local render = render

function EFFECT:Render()
    if not self.SetupPoints then return end

    local timeLeft = self.DieTime - CurTime()
    if timeLeft <= 0 then return end

    local fade = self.NoFade and 1 or math.min( timeLeft / self.Duration, 1 )
    local width = 8 * self.Scale * fade
    local alpha = 255 * fade

    local myColor = self.Color
    local myCoreColor = self.CoreColor

    renderCol.r, renderCol.g, renderCol.b, renderCol.a = myColor.r, myColor.g, myColor.b, alpha
    coreCol.r, coreCol.g, coreCol.b, coreCol.a = myCoreColor.r, myCoreColor.g, myCoreColor.b, alpha

    render.SetMaterial( BeamMaterial )

    local points = self.Points

    -- Main arc
    for i = 1, #points - 1 do
        render.DrawBeam( points[i], points[i + 1], width, 0, 1, renderCol )
        render.DrawBeam( points[i], points[i + 1], width * 0.3, 0, 1, coreCol )

    end

    -- Branches
    if not self.Branches then return end

    for _, branch in ipairs( self.Branches ) do
        local bw = width * branch.width
        local segCount = #branch - 1

        for i = 1, segCount do
            local taper = 1 - ( ( i - 1 ) / segCount ) * 0.5
            local w = bw * taper
            render.DrawBeam( branch[i], branch[i + 1], w, 0, 1, renderCol )
            render.DrawBeam( branch[i], branch[i + 1], w * 0.3, 0, 1, coreCol )

        end
    end
end
