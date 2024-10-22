AddCSLuaFile()

ENT.Base = "terminator_nextbot"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator"
list.Set( "NPC", "terminator_nextbot_snail_disguised", {
    Name = "Terminator Doppleganger",
    Class = "terminator_nextbot_snail_disguised",
    Category = "Terminator Nextbot",
    Weapons = { "weapon_terminatorfists_term" },
} )

if CLIENT then
    language.Add( "terminator_nextbot_snail_disguised", ENT.PrintName )

end

local isADoppleGanger

local function checkIfThereIsADoppleganger()
    if #ents.FindByClass( "terminator_nextbot_snail_disguised" ) > 0 then
        isADoppleGanger = true

    else
        isADoppleGanger = false

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

local sndFlags = bit.bor( SND_CHANGE_PITCH, SND_CHANGE_VOL )

-- copied the original function
function ENT:MakeFootstepSound( volume, surface, mul )
    mul = mul or 1
    -- here is why i copied over this function
    mul = mul * 0.85
    local foot = self.m_FootstepFoot
    self.m_FootstepFoot = not foot
    self.m_FootstepTime = CurTime()

    if not surface then
        local tr = util.TraceEntity( {
            start = self:GetPos(),
            endpos = self:GetPos() - Vector( 0, 0, 5 ),
            filter = self,
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
        }, self )

        surface = tr.SurfaceProps
    end

    if not surface then return end

    surface = util.GetSurfaceData( surface )
    if not surface then return end

    local sound = foot and surface.stepRightSound or surface.stepLeftSound

    if sound then
        local pos = self:GetPos()

        local filter = RecipientFilter()
        filter:AddAllPlayers()

        if not self:OnFootstep( pos, foot, sound, volume, filter ) then

            local intVolume = volume or 1
            self:EmitSound( sound, 88 * mul, 85 * mul, intVolume, CHAN_STATIC, sndFlags )

            local clompingLvl = 80

            if self:GetCurrentSpeed() < self.RunSpeed then
                clompingLvl = 70

            end

            clompingLvl = clompingLvl * mul

            self:EmitSound( "npc/zombie_poison/pz_left_foot1.wav", clompingLvl, math.random( 20, 30 ) / mul, intVolume / 1.5, CHAN_STATIC )

        end
    end
end

function ENT:GetFootstepSoundTime()
    local time = 400
    local speed = self:GetCurrentSpeed()

    time = time - ( speed * 0.8 )

    if self:IsCrouching() then
        time = time + 100
    end

    return time

end

function ENT:AdditionalClientInitialize()
    timer.Simple( 0, checkIfThereIsADoppleganger )
    self:CallOnRemove( "checkiftheresdoppleganger", function()
        timer.Simple( 0, checkIfThereIsADoppleganger )

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

function ENT:AdditionalThink()
    if not IsValid( self.MimicTarget ) then return end
    if self.MimicTarget.IsTyping and self.MimicTarget:IsTyping() then
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
    if not isADoppleGanger then return end

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