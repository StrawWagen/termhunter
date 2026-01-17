
local crunchFontLarge = "TerminatorHUD_Large"
local crunchFontSmall = "TerminatorHUD_Small"
local crunchFontMono  = "TerminatorHUD_Mono"

local uiScaleVert = ScrH() / 1080
local uiScaleHoris = ScrW() / 1920

--[[------------------------------------
    sizeScaled, copied from hunter's glee glee_sizeScaled
    Desc: scales sizes based on screen resolution
    Pass 1080p pixel values; they are scaled to the current resolution.

    Examples:
    - sizeScaled( 400 )           -> 400 * uiScaleHoris (same visual width as 400px at 1080p)
    - sizeScaled( nil, 26 )       -> 26  * uiScaleVert  (same visual height as 26px at 1080p)
    - sizeScaled( 64, 32 )        -> returns both scaled width and height

    Use nil for the axis you don’t need.
--]]-------------------------------------
local function sizeScaled( sizeX, sizeY )
    if sizeX and sizeY then
        return sizeX * uiScaleHoris, sizeY * uiScaleVert

    elseif sizeX then
        return sizeX * uiScaleHoris

    elseif sizeY then
        return sizeY * uiScaleVert

    end
end

terminator_Extras = terminator_Extras or {}

local function setupFonts()
    surface.CreateFont( crunchFontLarge, {
        font = "HL2MPTypeDeath",
        size = 46,
        weight = 900,
        extended = true,
    } )
    surface.CreateFont( crunchFontSmall, {
        font = "Tahoma",
        size = 18,
        weight = 600,
        extended = true,
    } )
    surface.CreateFont( crunchFontMono, {
        font = "Courier New",
        size = 18,
        weight = 500,
        extended = true,
    } )

end

hook.Add( "OnScreenSizeChanged", "terminator_playercontrol_setupfonts", function() setupFonts() end )
setupFonts()

local hpLerp = 0

-- Draw a HL2‑style health bar with a perceptual gradient: green (>50%), then smoothly shifting to red as health falls, to emphasize danger.
local function drawHL2HealthBar( x, y, w, h, frac )
    -- outer shadow frame
    surface.SetDrawColor( 0, 0, 0, 180 )
    local shadowAdded = sizeScaled( 4 )
    surface.DrawRect( x - shadowAdded, y - shadowAdded, w + shadowAdded * 2, h + shadowAdded * 2 )

    surface.SetDrawColor( 60, 60, 60, 255 )    -- bar background
    surface.DrawRect( x, y, w, h )
    local r, g
    if frac > 0.5 then
        local f = ( frac - 0.5 ) / 0.5
        r = 255 * ( 1 - f )
        g = 255
    else
        local f = frac / 0.5
        r = 255
        g = 255 * f
    end
    surface.SetDrawColor( r, g, 0, 255 )
    surface.DrawRect( x, y, math.max( 0, w * frac ), h ) -- health fill
    -- gloss
    surface.SetDrawColor( 255, 255, 255, 25 ) -- subtle top gloss to lift perceived depth without heavy styling
    surface.DrawRect( x, y, math.max( 0, w * frac ), h * 0.35 )
end

-- Draw weapon / ammo panel; early returns keep indentation flat.
local function drawWeaponPanel( self )
    if not self:HasWeapon() then return end
    local wep = self:GetActiveWeapon()
    if not IsValid( wep ) then return end

    local clip1, max1 = self:GetWeaponClip1(), self:GetWeaponMaxClip1()
    local clip2, max2 = self:GetWeaponClip2(), self:GetWeaponMaxClip2()
    local name = wep:GetPrintName() or wep:GetClass()

    local panelW = sizeScaled( 300 )
    local panelH = sizeScaled( 120 )
    local panelX = ScrW() - panelW - sizeScaled( 34 )
    local panelY = ScrH() - sizeScaled( 180 )

    local shadowAdded = sizeScaled( 4 )
    local nameTextOffsetX, nameTextOffsetY = sizeScaled( 10, 8 )
    local ammoTextOffsetX, ammoTextOffsetY = sizeScaled( 10, 18 )
    local ammoTextOffsetX2, ammoTextOffsetY2 = sizeScaled( 10, 70 )

    surface.SetDrawColor( 0, 0, 0, 170 )                     -- weapon panel frame shadow
    surface.DrawRect( panelX - shadowAdded, panelY - shadowAdded, panelW + shadowAdded * 2, panelH + shadowAdded * 2 )
    surface.SetDrawColor( 35, 35, 35, 255 )                  -- weapon panel fill
    surface.DrawRect( panelX, panelY, panelW, panelH )

    draw.SimpleText( name, crunchFontSmall, panelX + nameTextOffsetX, panelY + nameTextOffsetY, Color( 255, 230, 120 ), TEXT_ALIGN_LEFT ) -- weapon name

    local primaryTxt = ( clip1 >= 0 and max1 > 0 ) and ( clip1 .. " / " .. max1 ) or "--"
    draw.SimpleText( primaryTxt, crunchFontLarge, panelX + panelW - ammoTextOffsetX, panelY + ammoTextOffsetY, Color( 255, 255, 255 ), TEXT_ALIGN_RIGHT ) -- primary ammo

    -- Secondary ammo only if weapon supports it and has capacity or current count.
    if clip2 < 0 then return end
    if max2 <= 0 and clip2 <= 0 then return end

    local secondaryTxt = clip2 .. " / " .. max2
    draw.SimpleText( secondaryTxt, crunchFontMono, panelX + panelW - ammoTextOffsetX2, panelY + ammoTextOffsetY2, Color( 200, 200, 200 ), TEXT_ALIGN_RIGHT ) -- secondary ammo

end

local validBinds = {
    -- Primary / secondary fire
    [IN_ATTACK]        = "+attack",
    [IN_ATTACK2]       = "+attack2",

    -- Movement
    [IN_FORWARD]       = "+forward",
    [IN_BACK]          = "+back",
    [IN_MOVELEFT]      = "+moveleft",
    [IN_MOVERIGHT]     = "+moveright",
    [IN_JUMP]          = "+jump",
    [IN_DUCK]          = "+duck",
    [IN_WALK]          = "+walk",
    [IN_SPEED]         = "+speed",
    [IN_BULLRUSH]      = "+bullrush",    -- usually sprint on HL2/Source mods

    -- Interaction / utility
    [IN_USE]           = "+use",
    [IN_RELOAD]        = "+reload",
    [IN_ZOOM]          = "+zoom",
    [IN_SCORE]         = "+score",       -- scoreboard (TAB)

    -- Weapon slot cycling (interpreted by engine / scripts)
    [IN_WEAPON1]       = "+weapon1",
    [IN_WEAPON2]       = "+weapon2",
    [IN_GRENADE1]      = "+grenade1",
    [IN_GRENADE2]      = "+grenade2",

    -- Alt / modifier keys
    [IN_ALT1]          = "+alt1",
    [IN_ALT2]          = "+alt2",
}

local function validStr( str )
    if not str then return end
    if str == "" then return end
    return true
end

-- convert IN_ bitflag to full command, eg IN_JUMP -> "+jump"
-- if commandName, and inBind, treat display both as a combo
local function resolveDriveActionBinding( actionData )
    local commandName = actionData.commandName

    local inBind = actionData.inBind
    local inBindCmd = inBind and validBinds[inBind] or nil
    if not inBindCmd then
        if validStr( commandName ) then
            return string.upper( commandName ), true

        else
            return

        end
    end

    if validStr( commandName ) then
        inBindCmd = inBindCmd .. " & " .. string.upper( commandName )

    end

    return string.upper( inBindCmd ), true

end

local isBoundColor = Color( 235, 235, 235 )
local unboundColor = Color( 255, 50, 50 )
local shadowCol = Color( 0, 0, 0, 200 )

local hudPaddingFromScreenEdge = 24

local function drawSpecialActions( bot )
    local specialActions = bot.SpecialActions
    if not specialActions then return end

    local lines = {}
    for _, data in pairs( specialActions ) do
        local drawHint = data.drawHint
        if not drawHint then continue end
        if isfunction( drawHint ) and not drawHint( bot ) then continue end
        if not ( data.commandName or data.inBind ) then continue end
        local keyName, isBound = resolveDriveActionBinding( data )
        if not keyName then continue end
        lines[#lines + 1] = {
            key = keyName,
            bound = isBound,
            name = data.name or "?",
            uses = data.actionHasUses and data.actionUsesLeft or nil,
            --desc = data.desc, todo, not useful yet
        }
    end

    if #lines <= 0 then return end
    table.sort( lines, function( a, b ) return a.key < b.key end ) -- pairs would make flicker

    local startX = sizeScaled( hudPaddingFromScreenEdge ) -- align with health bar's left edge
    local startY = ScrH() - sizeScaled( 210 )
    local lineH = sizeScaled( 20 )
    surface.SetFont( crunchFontSmall )

    local y = 0
    for i = 1, #lines do
        local l = lines[i]
        local notBoundYap = ( not l.bound and " NOT BOUND" ) or ""
        local text = "[" .. l.key .. notBoundYap .. "] "
        text = text .. l.name
        if l.uses ~= nil then
            text = text .. " (" .. tostring( l.uses ) .. " left)"
        end
        local col = l.bound and isBoundColor or unboundColor

        -- heavier pseudo-outline shadow for readability on mixed backgrounds
        local sx = startX
        local sy = startY + y
        draw.SimpleText( text, crunchFontSmall, sx - 1, sy, shadowCol, TEXT_ALIGN_LEFT )
        draw.SimpleText( text, crunchFontSmall, sx + 1, sy, shadowCol, TEXT_ALIGN_LEFT )
        draw.SimpleText( text, crunchFontSmall, sx, sy - 1, shadowCol, TEXT_ALIGN_LEFT )
        draw.SimpleText( text, crunchFontSmall, sx, sy + 1, shadowCol, TEXT_ALIGN_LEFT )

        -- main text
        draw.SimpleText( text, crunchFontSmall, sx, sy, col, TEXT_ALIGN_LEFT )
        y = y - lineH

    end
end

local function drawCrosshair( x, y )
    local scale = sizeScaled( 1 )
    -- Minimal crosshair: HL2 style gap cross.
    surface.SetDrawColor( 255, 200, 0, 255 ) -- amber for high contrast on varied map backgrounds
    surface.DrawRect( x - 1 * scale, y - 1 * scale, 2 * scale, 2 * scale )    -- crosshair center
    surface.DrawRect( x - 12 * scale, y - 1 * scale, 6 * scale, 2 * scale )   -- left arm
    surface.DrawRect( x + 6 * scale, y - 1 * scale, 6 * scale, 2 * scale )    -- right arm
    surface.DrawRect( x - 1 * scale, y - 12 * scale, 2 * scale, 6 * scale )   -- top arm
    surface.DrawRect( x - 1 * scale, y + 6 * scale, 2 * scale, 6 * scale )    -- bottom arm

end

local hpShadowCol = Color( 0, 0, 0, 180 )
local hpTextCol = Color( 255, 220, 40 )

--[[------------------------------------
    Name: NEXTBOT:ModifyPlayerControlHUD
    Desc: Allows modify HUD with bot's info.
    Arg1: number | chx | Crosshair X pos.
    Arg2: number | chy | Crosshair Y pos.
    Ret1: bool | Return true to prevent drawing default HUD.
--]]------------------------------------
-- HUD override while driving a Terminator bot.
function ENT:ModifyPlayerControlHUD( chx, chy )
    -- Override default HUD entirely for a controlled bot.
    local realHP = math.max( 0, self:Health() )
    local maxHP = math.max( 1, self:GetMaxHealth() )
    local frac = realHP / maxHP

    -- Smooth transition for bar fill.
    hpLerp = Lerp( FrameTime() * 6, hpLerp, frac )

    drawCrosshair( chx, chy )

    -- Health bar (bottom left)
    local barW = sizeScaled( 480 )
    local barH = sizeScaled( 18 )
    local barX = sizeScaled( hudPaddingFromScreenEdge )
    local barY = ScrH() - sizeScaled( 110 )
    drawHL2HealthBar( barX, barY, barW, barH, hpLerp )

    -- Large numeric health for quick peripheral recognition.
    local hpTxt = tostring( realHP )
    local hpShadowAlpha = 180 * ( 0.4 + 0.6 * hpLerp )
    hpShadowCol.a = hpShadowAlpha
    local textX = barX + sizeScaled( 6 )
    local textY = barY - sizeScaled( 46 )
    local text2X = barX + sizeScaled( 4 )
    local text2Y = barY - sizeScaled( 48 )
    draw.SimpleText( hpTxt, crunchFontLarge, textX, textY, hpShadowCol, TEXT_ALIGN_LEFT ) -- shadow
    draw.SimpleText( hpTxt, crunchFontLarge, text2X, text2Y, hpTextCol, TEXT_ALIGN_LEFT ) -- main text

    -- Weapon / ammo panel (right side)
    drawWeaponPanel( self )

    -- Special action hints (bindings)
    drawSpecialActions( self )

    return true -- Prevent default HUD elements for this state.
end

function ENT:SetupCLDrivingHooks()
    local toTeardown = {}

    toTeardown[#toTeardown + 1] = "PlayerBindPress"
    hook.Add( "PlayerBindPress", "Term_CLDriving", function( ply, bind, pressed, code )
        if not self.commandNames then return end -- wait...

        local commandName = self.commandNames[bind]
        if not commandName then return end

        if self.commandCombos[commandName] >= IN_ATTACK and not ply:KeyDown( self.commandCombos[commandName] ) then return end -- it needs both down

        if self.commandClActions[commandName] then
            self.commandClActions[commandName]( self, ply, pressed, code )

        end
        if self.commandSvActions[commandName] then
            net.Start( "Term_DriveAction" )
                net.WriteEntity( self )
                net.WriteString( commandName )
            net.SendToServer()

        end
    end )

    toTeardown[#toTeardown + 1] = "HUDPaint"
    hook.Add( "HUDPaint", "Term_CLDriving", function()
        local crosshairTrace = util.TraceLine( {
            start = self:GetShootPos(),
            endpos = self:GetShootPos() + self:GetEyeAngles():Forward() * 56756, -- large distance constant: effectively 'infinite' ray for crosshair placement
            mask = MASK_SHOT,
            filter = self,
        } )
        local chp = crosshairTrace.HitPos:ToScreen()

        self:ModifyPlayerControlHUD( chp.x, chp.y )

    end )

    -- Suppress base HUD pieces while driving.
    local suppressed = {
        ["CHudHealth"] = true,
        ["CHudBattery"] = true,
        ["CHudAmmo"] = true,
        ["CHudSecondaryAmmo"] = true,
        ["CHudDamageIndicator"] = true,

    }

    toTeardown[#toTeardown + 1] = "HUDShouldDraw"
    hook.Add( "HUDShouldDraw", "Term_CLDriving", function( name )
        if suppressed[name] then return false end

    end )

    hook.Add( "RenderScene", "Term_CLDriving", function()
        if IsValid( LocalPlayer():GetDrivingEntity() ) then return end
        for _, hookName in ipairs( toTeardown ) do
            hook.Remove( hookName, "Term_CLDriving" )

        end
        toTeardown = nil
        self.StopDriving = nil
        hook.Remove( "RenderScene", "Term_CLDriving" )

    end )
end

-- sync us up to actions only defined on server
net.Receive( "Term_SyncDriveActions", function( len )
    local ent = net.ReadEntity()
    if not IsValid( ent ) then return end
    if not ent.isTerminatorHunterBased then return end

    local actionId = net.ReadString() -- name
    local actionInBind = net.ReadUInt( 32 ) -- input binding
    local actionCommandName = net.ReadString() -- console command that triggers this
    local actionName = net.ReadString() -- display name
    local actionDraw = net.ReadBool() -- whether to draw in HUD hints
    local actionHasUses = net.ReadBool()
    local actionUsesLeft = net.ReadUInt( 32 )

    local drivingEnt = LocalPlayer():IsDrivingEntity()
    if not drivingEnt then return end

    local specialActions = ent.SpecialActions
    if not specialActions then
        specialActions = {}
        ent.SpecialActions = specialActions
        ent:SetupCLDrivingHooks()

    end
    local currAction = ent.SpecialActions[actionId] or {}

    currAction.inBind = actionInBind ~= "" and tonumber( actionInBind ) or nil
    currAction.commandName = actionCommandName
    currAction.name = actionName
    currAction.drawHint = actionDraw
    currAction.svAction = function() return end -- always a server action if we're being told about it
    currAction.actionHasUses = actionHasUses
    currAction.actionUsesLeft = actionUsesLeft

    ent.SpecialActions[actionId] = currAction

    ent.commandNames = {}
    ent.commandCombos = {}
    ent.commandSvActions = {}
    ent.commandClActions = {}
    -- setup commandName stuff
    for name, actionData in pairs( ent.SpecialActions ) do
        if not actionData.commandName then continue end

        ent.commandNames[actionData.commandName] = name
        ent.commandSvActions[name] = isfunction( actionData.svAction )

        if actionData.inBind then
            ent.commandCombos[name] = actionData.inBind

        end

        if not actionData.clAction then continue end
        ent.commandClActions[name] = actionData.clAction

    end
end )
