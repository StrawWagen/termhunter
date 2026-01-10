-- shared.lua
ENT.Type = "anim"
ENT.Base = "base_gmodentity"
ENT.PrintName = "Lightning Arc Cube"
ENT.Author = "regunkyle"
ENT.Category = "Fun + Games"
ENT.Spawnable = true
ENT.AdminOnly = false
ENT.RenderGroup = RENDERGROUP_BOTH

ARC_MODE_RANDOM = 0
ARC_MODE_TRACE = 1
ARC_MODE_CONNECT = 2

function ENT:SetupDataTables()
    self:NetworkVar( "Float", 0, "ArcScale" )
    self:NetworkVar( "Float", 1, "ArcSegments" )
    self:NetworkVar( "Float", 2, "ArcJitter" )
    self:NetworkVar( "Float", 3, "ArcRange" )
    self:NetworkVar( "Float", 4, "ArcRate" )
    self:NetworkVar( "Float", 5, "ArcBranchCount" )

    self:NetworkVar( "Int", 0, "ArcColorR" )
    self:NetworkVar( "Int", 1, "ArcColorG" )
    self:NetworkVar( "Int", 2, "ArcColorB" )
    self:NetworkVar( "Int", 3, "ArcMode" )

    self:NetworkVar( "Bool", 0, "ArcEnabled" )
    self:NetworkVar( "Bool", 1, "ArcNoLight" )
    self:NetworkVar( "Bool", 2, "ArcNoBranches" )
    self:NetworkVar( "Bool", 3, "ArcNoFade" )
    self:NetworkVar( "Bool", 4, "ArcNoSound" )
    self:NetworkVar( "Bool", 5, "ArcMultiTarget" )

    if SERVER then
        self:SetArcScale( 1 )
        self:SetArcSegments( 8 )
        self:SetArcJitter( 20 )
        self:SetArcRange( 256 )
        self:SetArcRate( 0.2 )
        self:SetArcBranchCount( 3 )
        self:SetArcColorR( 100 )
        self:SetArcColorG( 150 )
        self:SetArcColorB( 255 )
        self:SetArcMode( ARC_MODE_RANDOM )
        self:SetArcEnabled( true )
        self:SetArcNoLight( false )
        self:SetArcNoBranches( false )
        self:SetArcNoFade( false )
        self:SetArcNoSound( false )
        self:SetArcMultiTarget( false )
    end
end