-- ent_term_arccube_net.lua
util.AddNetworkString( "arccube_property" )
util.AddNetworkString( "arccube_preset" )

local Handlers = {
    enabled = function( ent, v ) ent:SetArcEnabled( v == true ) end,
    scale = function( ent, v ) ent:SetArcScale( math.Clamp( tonumber( v ) or 1, 0.1, 50 ) ) end,
    segments = function( ent, v ) ent:SetArcSegments( math.Clamp( tonumber( v ) or 8, 3, 128 ) ) end,
    jitter = function( ent, v ) ent:SetArcJitter( math.Clamp( tonumber( v ) or 20, 1, 1000 ) ) end,
    range = function( ent, v ) ent:SetArcRange( math.Clamp( tonumber( v ) or 256, 16, 16384 ) ) end,
    rate = function( ent, v ) ent:SetArcRate( math.Clamp( tonumber( v ) or 0.2, 0.01, 30 ) ) end,
    branchcount = function( ent, v ) ent:SetArcBranchCount( math.Clamp( tonumber( v ) or 3, 0, 50 ) ) end,
    mode = function( ent, v ) ent:SetArcMode( math.Clamp( tonumber( v ) or 0, 0, 2 ) ) end,
    nolight = function( ent, v ) ent:SetArcNoLight( v == true ) end,
    nobranches = function( ent, v ) ent:SetArcNoBranches( v == true ) end,
    nofade = function( ent, v ) ent:SetArcNoFade( v == true ) end,
    nosound = function( ent, v ) ent:SetArcNoSound( v == true ) end,
    multitarget = function( ent, v ) ent:SetArcMultiTarget( v == true ) end,
    color = function( ent, v )
        if istable( v ) then
            ent:SetArcColorR( math.Clamp( tonumber( v[1] ) or 100, 0, 255 ) )
            ent:SetArcColorG( math.Clamp( tonumber( v[2] ) or 150, 0, 255 ) )
            ent:SetArcColorB( math.Clamp( tonumber( v[3] ) or 255, 0, 255 ) )
        end
    end,
}

local function ValidateRequest( ply, ent )
    return IsValid( ent ) and ent:GetClass() == "ent_term_arccube" and gamemode.Call( "CanProperty", ply, "arccube_settings", ent )
end

net.Receive( "arccube_property", function( len, ply )
    local ent = net.ReadEntity()
    local prop = net.ReadString()
    local value = net.ReadType()

    if not ValidateRequest( ply, ent ) then return end

    local handler = Handlers[ prop ]
    if handler then handler( ent, value ) end
end )

net.Receive( "arccube_preset", function( len, ply )
    local ent = net.ReadEntity()
    local preset = net.ReadTable()

    if not ValidateRequest( ply, ent ) then return end

    for prop, value in pairs( preset ) do
        local handler = Handlers[ prop ]
        if handler then handler( ent, value ) end
    end
end )