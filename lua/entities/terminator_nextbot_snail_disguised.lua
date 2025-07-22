AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Doppelganger"
list.Set( "NPC", "terminator_nextbot_snail_disguised", {
    Name = ENT.PrintName,
    Class = "terminator_nextbot_snail_disguised",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },
} )

if CLIENT then
    language.Add( "terminator_nextbot_snail_disguised", ENT.PrintName )

end

local isADoppelGanger

local function checkIfThereIsADoppelganger()
    if #ents.FindByClass( "terminator_nextbot_snail_disguised" ) > 0 then
        isADoppelGanger = true

    else
        isADoppelGanger = false

    end
end

ENT.WalkSpeed = 75
ENT.MoveSpeed = 200
ENT.RunSpeed = 360
ENT.AccelerationSpeed = 1500
ENT.JumpHeight = 70 * 2.5
ENT.FistDamageMul = 1
ENT.ThrowingForceMul = 1

ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_GOOD

ENT.duelEnemyTimeoutMul = 5

ENT.Term_FootstepMsReductionPerUnitSpeed = 0.8

function ENT:AdditionalClientInitialize()
    timer.Simple( 0, checkIfThereIsADoppelganger )
    self:CallOnRemove( "checkiftheresdoppelganger", function()
        timer.Simple( 0, checkIfThereIsADoppelganger )

    end )
end

function ENT:AdditionalInitialize()
    local stuffWeCanMimic = {}
    local someoneDead
    local plys = player.GetAll()
    for _, ply in ipairs( plys ) do
        if ply:Health() <= 0 then
            someoneDead = true
            break

        end
    end
    if someoneDead then
        for _, ply in ipairs( plys ) do
            if ply:Health() <= 0 then
                table.insert( stuffWeCanMimic, ply )

            end
        end
    else
        stuffWeCanMimic = plys

    end

    local randomPlayerToMimic = table.Random( stuffWeCanMimic )
    self:MimicPlayer( randomPlayerToMimic )

end

--https://github.com/Facepunch/garrysmod/blob/master/garrysmod/lua/matproxy/player_color.lua
function ENT:GetPlayerColor()
    local mimicing = self:GetNWEntity( "disguisedterminatorsmimictarget", nil )
    if not IsValid( mimicing ) then return vector_origin end

    return mimicing:GetPlayerColor()

end

function ENT:MimicPlayer( toMimic )
    self:SetModel( toMimic:GetModel() )

    local plysBodyGroups = toMimic:GetBodyGroups()

    for _, bGroup in pairs( plysBodyGroups ) do
        self:SetBodygroup( bGroup["id"], toMimic:GetBodygroup( bGroup["id"] ) )

    end

    self:SetNWEntity( "disguisedterminatorsmimictarget", toMimic )
    self.MimicTarget = toMimic

end

function ENT:AdditionalThink( myTbl )
    if not IsValid( myTbl.MimicTarget ) then return end
    if myTbl.MimicTarget.IsTyping and myTbl.MimicTarget:IsTyping() then
        self:AddGesture( ACT_GMOD_IN_CHAT, 1 )

    end
end

function ENT:Nick()
    local disguisedAs = self:GetNWEntity( "disguisedterminatorsmimictarget", nil )
    if not IsValid( disguisedAs ) then return end
    return disguisedAs:Nick()

end

if not CLIENT then return end

local function paintNameAndHealth( toPaint )

    local text = "ERROR"
    local font = "TargetID"

    text = toPaint:Nick()

    surface.SetFont( font )
    local w, h = surface.GetTextSize( text )

    local MouseX, MouseY = gui.MousePos()

    if MouseX == 0 and MouseY == 0 then

        MouseX = ScrW() / 2
        MouseY = ScrH() / 2

    end

    local x = MouseX
    local y = MouseY

    x = x - w / 2
    y = y + 30

    -- The fonts internal drop shadow looks lousy with AA on
    draw.SimpleText( text, font, x + 1, y + 1, Color( 0, 0, 0, 120 ) )
    draw.SimpleText( text, font, x + 2, y + 2, Color( 0, 0, 0, 50 ) )
    draw.SimpleText( text, font, x, y, GAMEMODE:GetTeamColor( toPaint ) )

    y = y + h + 5

    local hp = toPaint:Health()
    if hp <= 0 then
        hp = 100

    end

    text = hp .. "%"
    font = "TargetIDSmall"

    surface.SetFont( font )
    w, h = surface.GetTextSize( text )
    x = MouseX - w / 2

    draw.SimpleText( text, font, x + 1, y + 1, Color( 0, 0, 0, 120 ) )
    draw.SimpleText( text, font, x + 2, y + 2, Color( 0, 0, 0, 50 ) )
    draw.SimpleText( text, font, x, y, GAMEMODE:GetTeamColor( toPaint ) )

end

hook.Add( "HUDPaint", "terminator_PaintDisguisedNameAndHealth", function()
    if not isADoppelGanger then return end

    if hook.Run( "HUDDrawTargetID" ) ~= nil then return end

    local tr = LocalPlayer():GetEyeTrace()
    if not tr.Hit then return end
    if tr.HitWorld then return end
    local hitEnt = tr.Entity
    if not IsValid( hitEnt ) then return end

    if not hitEnt.Nick then return end
    if not hitEnt:Nick() then return end
    if hitEnt:IsPlayer() then return end

    local myObserverTarget = LocalPlayer():GetObserverTarget()

    if IsValid( myObserverTarget ) and myObserverTarget == hitEnt then return end

    local thingToPaint = hitEnt:GetNWEntity( "disguisedterminatorsmimictarget", nil )
    if not IsValid( thingToPaint ) then return end

    paintNameAndHealth( thingToPaint )

end )
