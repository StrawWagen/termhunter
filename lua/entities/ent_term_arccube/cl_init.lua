-- cl_init.lua
include( "shared.lua" )

function ENT:Draw()
    self:DrawModel()

    if not self:GetArcEnabled() or self:GetArcNoLight() then return end

    local dlight = DynamicLight( self:EntIndex() )
    if dlight then
        dlight.Pos = self:GetPos()
        dlight.R = self:GetArcColorR()
        dlight.G = self:GetArcColorG()
        dlight.B = self:GetArcColorB()
        dlight.Brightness = math.min( 2 * self:GetArcScale(), 5 )
        dlight.Size = math.min( 128 * self:GetArcScale(), 512 )
        dlight.Decay = 1000
        dlight.DieTime = CurTime() + 0.1
    end
end

-- Presets
local ArcPresets = {
    { name = "Default", settings = { scale = 1, segments = 8, jitter = 20, range = 256, rate = 0.2, branchcount = 3, color = { 100, 150, 255 }, mode = 0 } },
    { separator = true },
    { name = "Tesla Coil", settings = { scale = 1, segments = 12, jitter = 25, range = 300, rate = 0.08, branchcount = 3, color = { 150, 180, 255 }, mode = 2, multitarget = true } },
    { name = "Gentle Spark", settings = { scale = 0.5, segments = 6, jitter = 10, range = 128, rate = 0.3, branchcount = 0, nobranches = true } },
    { name = "Plasma Storm", settings = { scale = 3, segments = 24, jitter = 80, range = 1024, rate = 0.03, branchcount = 6, color = { 200, 50, 255 } } },
    { name = "Fire Arc", settings = { scale = 1.5, segments = 16, jitter = 40, range = 384, rate = 0.1, branchcount = 4, color = { 255, 100, 30 }, mode = 1 } },
    { name = "Chain Lightning", settings = { scale = 1, segments = 10, jitter = 30, range = 512, rate = 0.15, branchcount = 2, color = { 100, 200, 255 }, mode = 2, multitarget = true } },
    { name = "Welding Arc", settings = { scale = 0.3, segments = 4, jitter = 3, range = 64, rate = 0.02, color = { 255, 255, 255 }, mode = 1, nobranches = true } },
    { name = "Sith Lightning", settings = { scale = 1.2, segments = 14, jitter = 35, range = 400, rate = 0.04, branchcount = 5, color = { 180, 50, 255 } } },
    { separator = true },
    { name = "Electric Fence", settings = { scale = 0.4, segments = 5, jitter = 8, range = 96, rate = 0.5, color = { 255, 255, 100 }, nobranches = true } },
    { name = "Taser", settings = { scale = 0.2, segments = 3, jitter = 2, range = 32, rate = 0.015, color = { 100, 150, 255 }, mode = 1, nobranches = true } },
    { name = "Power Surge", settings = { scale = 2, segments = 20, jitter = 60, range = 768, rate = 0.05, branchcount = 4, color = { 255, 200, 50 } } },
    { name = "Lightning Strike", settings = { scale = 5, segments = 32, jitter = 150, range = 4096, rate = 2, branchcount = 8, color = { 220, 220, 255 }, mode = 1 } },
    { name = "Healing Beam", settings = { scale = 0.8, segments = 10, jitter = 12, range = 300, rate = 0.1, color = { 50, 255, 150 }, mode = 2, nobranches = true } },
    { name = "Death Ray", settings = { scale = 1.8, segments = 6, jitter = 5, range = 1024, rate = 0.05, color = { 255, 50, 20 }, mode = 1, nobranches = true, nofade = true } },
    { name = "Force Lightning", settings = { scale = 1, segments = 12, jitter = 28, range = 350, rate = 0.03, branchcount = 4, color = { 150, 180, 255 }, mode = 2, multitarget = true } },
    { name = "Arcane Magic", settings = { scale = 1.2, segments = 15, jitter = 35, range = 350, rate = 0.12, branchcount = 3, color = { 180, 80, 255 } } },
    { name = "Overcharge", settings = { scale = 4, segments = 28, jitter = 100, range = 1500, rate = 0.01, branchcount = 8, color = { 255, 255, 200 } } },
    { name = "Solar Flare", settings = { scale = 2.5, segments = 20, jitter = 70, range = 600, rate = 0.06, branchcount = 5, color = { 255, 180, 50 } } },
    { name = "Quiet Spark", settings = { scale = 0.5, segments = 6, jitter = 10, range = 128, rate = 0.2, nobranches = true, nosound = true } },
}

local ColorPresets = {
    { "Blue", 100, 150, 255 },
    { "Electric Blue", 50, 100, 255 },
    { "Red", 255, 30, 30 },
    { "Green", 30, 255, 30 },
    { "Yellow", 255, 255, 30 },
    { "Purple", 160, 30, 255 },
    { "Orange", 255, 130, 30 },
    { "White", 255, 255, 255 },
    { "Cyan", 50, 200, 200 },
    { "Pink", 255, 100, 150 },
}

local SliderValues = {
    scale = { 0.1, 0.25, 0.5, 1, 1.5, 2, 3, 5, 10 },
    segments = { 3, 4, 6, 8, 12, 16, 24, 32, 48 },
    jitter = { 1, 5, 10, 20, 40, 80, 150, 300 },
    range = { 32, 64, 128, 256, 512, 1024, 2048, 4096 },
    rate = { 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2 },
    branchcount = { 0, 1, 2, 3, 4, 5, 6, 8, 10 },
}

local function AddSlider( menu, label, value, values, callback )
    local sub = menu:AddSubMenu( label .. ": " .. value )
    for _, v in ipairs( values ) do
        sub:AddOption( tostring( v ), function() callback( v ) end )
    end
end

local function AddToggle( menu, label, value, callback )
    local prefix = value and "☑ " or "☐ "
    menu:AddOption( prefix .. label, function() callback( not value ) end )
end

properties.Add( "arccube_settings", {
    MenuLabel = "Arc Settings",
    Order = 1000,
    MenuIcon = "icon16/lightning.png",

    Filter = function( self, ent, ply )
        return IsValid( ent ) and ent:GetClass() == "ent_term_arccube" and gamemode.Call( "CanProperty", ply, "arccube_settings", ent )
    end,

    MenuOpen = function( self, option, ent, tr )
        local menu = option:AddSubMenu()

        -- Enable toggle
        local enabled = ent:GetArcEnabled()
        menu:AddOption( enabled and "⚡ Disable" or "⚡ Enable", function()
            self:Send( ent, "enabled", not enabled )
        end ):SetIcon( enabled and "icon16/stop.png" or "icon16/accept.png" )

        menu:AddSpacer()

        -- Mode
        local modes = { [0] = "Random", [1] = "Trace Down", [2] = "Connect" }
        local modeMenu = menu:AddSubMenu( "Mode: " .. modes[ ent:GetArcMode() ] )
        for id, name in pairs( modes ) do
            modeMenu:AddOption( name, function() self:Send( ent, "mode", id ) end )
        end

        menu:AddSpacer()

        -- Settings
        AddSlider( menu, "Scale", ent:GetArcScale(), SliderValues.scale, function( v ) self:Send( ent, "scale", v ) end )
        AddSlider( menu, "Segments", ent:GetArcSegments(), SliderValues.segments, function( v ) self:Send( ent, "segments", v ) end )
        AddSlider( menu, "Jitter", ent:GetArcJitter(), SliderValues.jitter, function( v ) self:Send( ent, "jitter", v ) end )
        AddSlider( menu, "Range", ent:GetArcRange(), SliderValues.range, function( v ) self:Send( ent, "range", v ) end )
        AddSlider( menu, "Rate", ent:GetArcRate() .. "s", SliderValues.rate, function( v ) self:Send( ent, "rate", v ) end )
        AddSlider( menu, "Branches", ent:GetArcBranchCount(), SliderValues.branchcount, function( v ) self:Send( ent, "branchcount", v ) end )

        menu:AddSpacer()

        -- Color
        local colorMenu = menu:AddSubMenu( "Color" )
        for _, c in ipairs( ColorPresets ) do
            colorMenu:AddOption( c[1], function() self:Send( ent, "color", { c[2], c[3], c[4] } ) end )
        end
        colorMenu:AddSpacer()
        colorMenu:AddOption( "Custom...", function() self:OpenColorPicker( ent ) end ):SetIcon( "icon16/color_wheel.png" )

        menu:AddSpacer()

        -- Toggles
        local toggleMenu = menu:AddSubMenu( "Options" )
        AddToggle( toggleMenu, "No Branches", ent:GetArcNoBranches(), function( v ) self:Send( ent, "nobranches", v ) end )
        AddToggle( toggleMenu, "No Fade", ent:GetArcNoFade(), function( v ) self:Send( ent, "nofade", v ) end )
        AddToggle( toggleMenu, "No Light", ent:GetArcNoLight(), function( v ) self:Send( ent, "nolight", v ) end )
        AddToggle( toggleMenu, "No Sound", ent:GetArcNoSound(), function( v ) self:Send( ent, "nosound", v ) end )
        AddToggle( toggleMenu, "No Turn", ent:GetArcNoTurn(), function( v ) self:Send( ent, "noturn", v ) end )
        AddToggle( toggleMenu, "Pass World", ent:GetArcPassWorld(), function( v ) self:Send( ent, "passworld", v ) end )
        toggleMenu:AddSpacer()
        AddToggle( toggleMenu, "Multi-Target", ent:GetArcMultiTarget(), function( v ) self:Send( ent, "multitarget", v ) end )

        menu:AddSpacer()

        -- Presets
        local presetMenu = menu:AddSubMenu( "Presets" )
        for _, p in ipairs( ArcPresets ) do
            if p.separator then
                presetMenu:AddSpacer()
            else
                presetMenu:AddOption( p.name, function() self:SendPreset( ent, p.settings ) end )
            end
        end
    end,

    Action = function( self, ent )
        self:Send( ent, "enabled", not ent:GetArcEnabled() )
    end,

    Send = function( self, ent, prop, value )
        net.Start( "arccube_property" )
        net.WriteEntity( ent )
        net.WriteString( prop )
        net.WriteType( value )
        net.SendToServer()
    end,

    SendPreset = function( self, ent, preset )
        net.Start( "arccube_preset" )
        net.WriteEntity( ent )
        net.WriteTable( preset )
        net.SendToServer()
    end,

    OpenColorPicker = function( self, ent )
        local frame = vgui.Create( "DFrame" )
        frame:SetSize( 280, 350 )
        frame:SetTitle( "Arc Color" )
        frame:Center()
        frame:MakePopup()

        local mixer = vgui.Create( "DColorMixer", frame )
        mixer:Dock( FILL )
        mixer:SetPalette( true )
        mixer:SetAlphaBar( false )
        mixer:SetColor( Color( ent:GetArcColorR(), ent:GetArcColorG(), ent:GetArcColorB() ) )

        local btn = vgui.Create( "DButton", frame )
        btn:Dock( BOTTOM )
        btn:SetTall( 30 )
        btn:SetText( "Apply" )
        btn.DoClick = function()
            local c = mixer:GetColor()
            self:Send( ent, "color", { c.r, c.g, c.b } )
            frame:Close()
        end
    end
} )