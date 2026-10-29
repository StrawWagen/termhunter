
local function SwitchToWep( bot, slotNum )
    local _, slottedWeaps = bot:GetHolsteredWeapons()
    local slotWep = slottedWeaps[slotNum]

    if not IsValid( slotWep ) then
        local actWep = bot:GetActiveLuaWeapon()
        if IsValid( actWep ) and not bot:IsFists() then
            bot:DropWeapon( false ) -- holster current weapon

        end
        return

    end
    bot:SetupWeapon( slotWep )

end

local specialActionsRequiredTypes = {
    ["inBind"] = { TYPE_NUMBER, TYPE_NIL },
    ["commandName"] = { TYPE_STRING, TYPE_NIL },
    ["name"] = { TYPE_STRING },
    ["desc"] = { TYPE_STRING },
    ["svAction"] = { TYPE_FUNCTION, TYPE_NIL },
    ["clAction"] = { TYPE_FUNCTION, TYPE_NIL },
    ["ratelimit"] = { TYPE_NUMBER },
    ["uses"] = { TYPE_NUMBER },
    ["drawHint"] = { TYPE_BOOL, TYPE_FUNCTION },

}

local requiredActionKeys = {
    "name",
}

local function validateActions( sentTbl, mySpecialActions )
    for actionName, actionDat in pairs( mySpecialActions ) do
        for _, reqKey in ipairs( requiredActionKeys ) do
            if actionDat[ reqKey ] == nil then
                local str = {
                    "Missing required key '", reqKey,
                    "' for special action '", actionName,
                    "' in class '", sentTbl.ClassName,
                    "'"
                }
                ErrorNoHaltWithStack( table.concat( str ) .. "\n" )
                return false

            end
        end
        for key, val in pairs( actionDat ) do
            local needed = specialActionsRequiredTypes[ key ]
            if not needed then continue end

            local valType = TypeID( val )
            local validType = false
            for _, neededType in ipairs( needed ) do
                if valType ~= neededType then continue end
                validType = true
                break

            end
            if not validType then
                local str = {
                    "Invalid type for special action '", actionName,
                    "' key '", key,
                    "' in class '", sentTbl.ClassName,
                    "'. Expected types: ", table.concat( needed, ", " ),
                    ", got: ", valType
                }
                ErrorNoHaltWithStack( table.concat( str ) .. "\n" )
                return false

            end
        end
    end
    return true

end


-- actions that can be taken while driving, exit control, switch weapon, drop weapon, etc.
-- see readme for detailed info
ENT.MySpecialActions = {
    ["StopControlling"] = {
        inBind = IN_ZOOM,
        drawHint = true,
        name = "Give up control",
        desc = "Stop controlling the bot", -- desc is unused for now

        svAction = function( drive, _driver, _bot )
            if drive.NextStopDriving > CurTime() then return end

            drive:Stop()

        end,
    },
    ["StopControllingToggleZoom"] = {
        commandName = "toggle_zoom",
        drawHint = false,
        name = "Give up control",
        desc = "Stop controlling the bot", -- desc is unused for now

        svAction = function( drive, _driver, _bot )
            if drive.NextStopDriving > CurTime() then return end

            drive:Stop()

        end,
    },
    ["DropCurrentWeapon"] = {
        commandName = "noclip",
        drawHint = true,
        name = "Drop current weapon",
        desc = "Drop the bot's current weapon", -- desc is unused for now

        svAction = function( _drive, _driver, bot )
            local actWep = bot:GetActiveLuaWeapon()
            if not IsValid( actWep ) then return end
            if bot:IsFists() then return end
            bot:DropWeapon( false )

        end,
    },
    ["ToggleFirstPerson"] = { -- by boomertaters
        commandName = "impulse 201",
        drawHint = true,
        name = "Toggle first person",
        desc = "Switch between first and third person",

        clAction = function( bot, _ply, pressed )
            if not pressed then return end
            bot.term_FirstPerson = not bot.term_FirstPerson

        end,
    },
    ["Use"] = {
        commandName = "+use",
        drawHint = function( bot )
            if bot.CanUseStuff or bot.CanFindWeaponsOnTheGround then
                return true

            end
        end,
        name = "Use",
        desc = "Interact with the environment",
        ratelimit = 0.15,

        svAction = function( _drive, _driver, bot )
            local shoot = bot:GetShootPos()
            local blocker
            -- find something to use, check under crosshair first
            local blockerResult = util.QuickTrace( shoot, bot:GetAimVector() * 80, bot )
            if blockerResult.Hit and IsValid( blockerResult.Entity ) then
                blocker = blockerResult.SetEntity

            end
            if not IsValid( blocker ) then -- now check nearby the crosshair
                local secondBiggerHullCheck = {
                    start = shoot,
                    endpos = shoot + bot:GetAimVector() * 80,
                    mins = Vector( -8, -8, -8 ),
                    maxs = Vector( 8, 8, 8 ),
                    ignoreworld = true,
                    filter = function( ent )
                        if ent == bot then return false end
                        if ent:GetParent() == bot then return false end
                        return true

                    end,
                }
                local hullResult = util.TraceHull( secondBiggerHullCheck )
                if hullResult.Hit and IsValid( hullResult.Entity ) and terminator_Extras.PosCanSee( hullResult.Entity:GetPos(), bot:GetShootPos() ) then
                    blocker = hullResult.Entity

                else
                    blocker = bot.LastShootBlocker

                end
            end

            if not IsValid( blocker ) then return end

            if bot.CanFindWeaponsOnTheGround and blocker:IsWeapon() then -- pickup if we can pick stuff up
                if IsValid( bot:GetActiveLuaWeapon() ) then
                    bot:DropWeapon( false )

                end
                bot:SetupWeapon( blocker )
                return

            end

            if not bot.CanUseStuff then return end
            bot:Use2( blocker )

        end,
    },
    ["WepSlot1"] = {
        commandName = "slot1",
        drawHint = false, -- not gonna make all the weapon slot stuff shared
        name = "Switch to Slot 1",
        desc = "Switch to bot's weapon in holster slot 1",

        svAction = function( _drive, _driver, bot )
            SwitchToWep( bot, 1 )

        end
    },
    ["WepSlot2"] = {
        commandName = "slot2",
        drawHint = false,
        name = "Switch to Slot 2",
        desc = "Switch to bot's weapon in holster slot 2",

        svAction = function( _drive, _driver, bot )
            SwitchToWep( bot, 2 )

        end
    },
    ["invprev"] = {
        commandName = "invprev",
        drawHint = false,
        name = "Switch to Previous Weapon",
        desc = "Switch to bot's previous weapon",

        svAction = function( _drive, _driver, bot )
            SwitchToWep( bot, 1 )

        end
    },
    ["invnext"] = {
        commandName = "invnext",
        drawHint = false,
        name = "Switch to Next Weapon",
        desc = "Switch to bot's next weapon",

        svAction = function( _drive, _driver, bot )
            SwitchToWep( bot, 2 )

        end
    },
}

-- ENT.SpecialActions -- auto-constructed tble of all drive actions from class hierarchy

--[[------------------------------------
    NEXTBOT:SetupSpecialActions
    Setup ENT.SpecialActions from ENT.MySpecialActions in class hierarchy
    Base special actions are overridden by derived class special actions
--]]------------------------------------
function ENT:SetupSpecialActions( myTbl ) -- same system as ENT:DoClassTasks
    local sentsToDo = myTbl.GetAllBaseClasses( self, myTbl )
    sentsToDo = table.Reverse( sentsToDo ) -- let higher up classes override lower ones

    local specialActions = myTbl.SpecialActions
    if not myTbl.SpecialActions then
        myTbl.SpecialActions = {}
        specialActions = myTbl.SpecialActions

    end

    for _, sentTbl in ipairs( sentsToDo ) do
        local mySpecialActions = sentTbl.MySpecialActions
        if not mySpecialActions then continue end
        if table.Count( mySpecialActions ) == 0 then continue end

        local valid = validateActions( sentTbl, mySpecialActions )
        if not valid then continue end

        for actionName, actionData in pairs( mySpecialActions ) do
            specialActions[actionName] = actionData

        end
    end
end

--[[------------------------------------
    NEXTBOT:CanTakeAction
    Check if bot can take the specified action right now
    arg1: string | actionName | Name of action to check
    ret1: bool | canTake | True if bot can take the action
--]]------------------------------------
function ENT:CanTakeAction( actionName )
    local specialActions = self.SpecialActions
    if not specialActions then return end -- too early, called inside Initialize

    local actionData = specialActions[actionName]
    if not actionData then return end
    if not ( actionData.svAction or actionData.clAction ) then return end

    local ratelimt = actionData.ratelimit
    if ratelimt then
        self.m_LastActionTimes = self.m_LastActionTimes or {}
        local lastTime = self.m_LastActionTimes[actionName] or 0
        if CurTime() - lastTime < ratelimt then return end

    end

    local uses = actionData.uses
    if uses then
        self.m_ActionUsesRemaining = self.m_ActionUsesRemaining or {}
        local usesLeft = self.m_ActionUsesRemaining[actionName] or uses
        if usesLeft <= 0 then return end

    end
    return true

end

--[[------------------------------------
    NEXTBOT:TakeAction
    Run an action, either from player driving or AI logic
    arg1: string | actionName | Name of action to take, must exist in ENT.SpecialActions
    arg2: driveController | driveController | Optional optimisation, controller driving the bot if any
--]]------------------------------------
function ENT:TakeAction( actionName, driveController )
    local specialActions = self.SpecialActions
    if not specialActions then ErrorNoHaltWithStack( "BOT:TakeAction called before bot finished setting up..." ) return end -- called inside Initialize...

    if not self:CanTakeAction( actionName ) then return end
    local actionData = specialActions[actionName]

    driveController = driveController or self.Term_PlayerDriveController
    local driver
    if driveController then
        driver = driveController.Player

    end

    if actionData.ratelimit then
        self.m_LastActionTimes = self.m_LastActionTimes or {}
        self.m_LastActionTimes[actionName] = CurTime()

    end

    local uses = actionData.uses
    if uses then
        local usesLeft = self.m_ActionUsesRemaining[actionName] or uses
        self.m_ActionUsesRemaining[actionName] = usesLeft - 1

        if IsValid( driver ) then
            terminator_Extras.SyncDriveActions( self, driver )

        end
    end

    if SERVER and actionData.svAction then
        actionData.svAction( driveController, driver, self )

    elseif CLIENT and actionData.clAction then
        actionData.clAction( driveController, driver, self )

    end
end

--[[------------------------------------
    NEXTBOT:GetEntityDriveMode
    Sets right drive mode
--]]------------------------------------
function ENT:GetEntityDriveMode( _ply )
    return "drive_terminator_nextbot"

end

--[[------------------------------------
    Name: NEXTBOT:ModifyControlPlayerButtons
    Desc: Allows modify buttons when bot controlled by player.
    Arg1: number | btns | Buttons from MoveData.
    Ret1: any | Return modified buttons (number) or nil to not change.
--]]------------------------------------
function ENT:ModifyControlPlayerButtons( btns )
    return self:RunTask( "ModifyControlPlayerButtons", btns )

end

if CLIENT then
    local baseDraw = ENT.Draw
    local hiddenScale = Vector( 0, 0, 0 )
    local normalScale = Vector( 1, 1, 1 )

    function ENT:Draw()
        if not self.term_FirstPerson or self:GetControlPlayer() ~= LocalPlayer() then return baseDraw( self ) end

        local headBone = self:LookupBone( self.Term_FirstPersonHeadBone or "ValveBiped.Bip01_Head1" )
        if not headBone then return baseDraw( self ) end

        self:ManipulateBoneScale( headBone, hiddenScale )
        self:SetupBones()
        baseDraw( self )
        self:ManipulateBoneScale( headBone, normalScale )

    end
end

drive.Register( "drive_terminator_nextbot", {
    Init = function( self )

        if SERVER then
            self.NextPosUpdateCheck = CurTime() + 1
            self.NextStopDriving = CurTime() + 1
            self.Entity.Term_PlayerDriveController = self
            self.Entity:StartControlByPlayer( self.Player )
            timer.Simple( 0.05, function()
                if not IsValid( self.Entity ) then return end
                if not IsValid( self.Player ) then return end
                local drivingEnt = self.Player:GetDrivingEntity()
                if not IsValid( drivingEnt ) or drivingEnt ~= self.Entity then return end
                terminator_Extras.SyncDriveActions( self.Entity, self.Player )

            end )

            hook.Run( "Term_OnStartedDriving", self.Player, self.Entity, self )
        else
            self.Entity:SetPredictable( false )
            self.Entity:SetupCLDrivingHooks()
        end
    end,

    Stop = function(self)
        self.StopDriving = true

        hook.Run( "Term_OnStoppedDriving", self.Player, self.Entity, self )

        if SERVER then
            self.Entity:StopControlByPlayer()

        else
            self.Entity.term_FirstPerson = nil

        end
    end,

    StartMove = function(self,mv,cmd)
        self.Player:SetObserverMode(OBS_MODE_CHASE)

        -- check if our binds are pressed
        for actionName, actionData in pairs( self.Entity.SpecialActions ) do
            local pressed
            if actionData.inBind then
                if actionData.commandName then continue end -- if inBind and commandName, it's a combo and the client handles it for us
                pressed = mv:KeyPressed( actionData.inBind )

            end
            if not pressed then continue end
            self.Entity:TakeAction( actionName, self )

        end

        if SERVER then
            local btns = mv:GetButtons()
            self.Entity.m_ControlPlayerButtons = self.Entity:ModifyControlPlayerButtons( btns, cmd ) or btns

            if self.NextPosUpdateCheck < CurTime() then -- keep our PAS up to date with the bot!
                self.NextPosUpdateCheck = CurTime() + 1
                local driver = self.Player
                if not driver:Alive() then
                    driver:SetPos( self.Entity:GetShootPos() )

                end
            end
        end
    end,

    CalcView = function( self, view )
        local bot = self.Entity
        local angles = self.Player:EyeAngles()
        local botpos = bot:GetShootPos()

        if bot.term_FirstPerson then
            local eyes = bot:GetAttachment( bot:LookupAttachment( "eyes" ) )
            local pos = eyes and eyes.Pos or botpos

            local flat = angles:Forward()
            flat.z = 0
            flat:Normalize()

            view.origin = pos + flat * ( 3 + math.Clamp( angles.p * 0.1, 0, 5 ) )
            view.angles = angles
            view.znear = 0.5
            return

        end

        local campos = LocalToWorld( bot:GetControlCameraOffset(), angle_zero, botpos, angles )

        local tr = util.TraceHull( {
            start = botpos,
            endpos = campos,
            mins = Vector( view.znear, view.znear, view.znear ) * -3,
            maxs = Vector( view.znear, view.znear, view.znear ) * 3,
            mask = MASK_BLOCKLOS,
            filter = bot,
        } )

        view.origin = tr.HitPos
        view.angles = angles

    end,
}, "drive_base" )

hook.Add( "CanDrive", "TerminatorNextBotControl", function( _ply, ent )
    if ent.TerminatorNextBot then
        return true

    end
end )

if not SERVER then return end

util.AddNetworkString( "Term_SyncDriveActions" )
function terminator_Extras.SyncDriveActions( bot, ply )
    local actions = bot.SpecialActions
    if not actions then return end

    for actionName, actionData in pairs( actions ) do
        local hasUses = isnumber( actionData.uses ) and actionData.uses >= 0
        local usesLeft = 0
        if hasUses then
           usesLeft = bot.m_ActionUsesRemaining and bot.m_ActionUsesRemaining[actionName] or actionData.uses

        end
        net.Start( "Term_SyncDriveActions" )
            net.WriteEntity( bot )
            net.WriteString( actionName )
            net.WriteUInt( actionData.inBind or 0, 32 )
            net.WriteString( actionData.commandName or "" )
            net.WriteString( actionData.name )
            net.WriteBool( actionData.drawHint or false )
            net.WriteBool( hasUses )
            net.WriteUInt( usesLeft, 32 )
        net.Send( ply )

    end
end

util.AddNetworkString( "Term_DriveAction" )
net.Receive( "Term_DriveAction", function( _len, ply )
    local ent = net.ReadEntity()
    local actionName = net.ReadString()

    if not IsValid( ent ) then return end
    local entsTbl = ent:GetTable()
    if not entsTbl.TerminatorNextBot then return end

    local drivingEnt = ply:GetDrivingEntity()
    if drivingEnt ~= ent then return end

    ent:TakeAction( actionName )

end )
