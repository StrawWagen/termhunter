
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

-- actions that can be taken while driving, exit control, switch weapon, drop weapon, etc.
-- automaically drawn while driving if drawHint is true
-- .inBind -- IN_ bitflag for mv:KeyPressed detection
-- .commandName -- +command string for HUD code to lookup player's bound key
-- if both of above are defined for one action, both must be pressed for action to trigger
-- .desc -- description of the action, unused for now
-- .svAction( driveController, driver, bot ) -- function run on server when action is taken
-- .clAction( driveController, driver, bot ) -- function run on client when action is taken
-- .ratelimit -- minimum time between action invocations
-- .syncCommand -- if true, forces action to be networked to clients, for non-shared setup
ENT.MySpecialActions = {
    ["StopControlling"] = {
        inBind = IN_ZOOM,
        drawHint = true,
        name = "Give up control",
        desc = "Stop controlling the bot", -- desc is unused for now

        svAction = function( drive, _driver, _bot ) drive:Stop() end,

    },
    ["Use"] = {
        inBind = IN_USE,
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
                blocker = blockerResult.Entity

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
function ENT:SetupSpecialActions( myTbl ) -- same system as ENT:DoClassTask
    local sentsToDo = myTbl.GetAllBaseClasses( self, myTbl )
    sentsToDo = table.Reverse( sentsToDo ) -- let higher up classes override lower ones

    local specialActions = {}

    for _, sentTbl in ipairs( sentsToDo ) do
        local mySpecialActions = sentTbl.MySpecialActions
        if not mySpecialActions then continue end
        if table.Count( mySpecialActions ) == 0 then continue end

        for actionName, actionData in pairs( mySpecialActions ) do
            specialActions[actionName] = actionData

        end
    end

    myTbl.SpecialActions = specialActions

end

--[[------------------------------------
    NEXTBOT:CanTakeAction
    Check if bot can take the specified action right now
    arg1: string | actionName | Name of action to check
    ret1: bool | canTake | True if bot can take the action
--]]------------------------------------
function ENT:CanTakeAction( actionName )
    local actionData = self.SpecialActions[actionName]
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
    if not self:CanTakeAction( actionName ) then return end
    local actionData = self.SpecialActions[actionName]

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

drive.Register( "drive_terminator_nextbot", {
    Init = function( self )
        if SERVER then
            self.Entity.Term_PlayerDriveController = self
            self.Entity:StartControlByPlayer( self.Player )
            timer.Simple( 0.5, function()
                if not IsValid( self.Entity ) then return end
                if not IsValid( self.Player ) then return end
                local drivingEnt = self.Player:GetDrivingEntity()
                if not IsValid( drivingEnt ) or drivingEnt ~= self.Entity then return end
                terminator_Extras.SyncDriveActions( self.Entity, self.Player )

            end )
        else
            self.Entity:SetPredictable( false )
            self.Entity:SetupCLDrivingHooks()
        end
    end,

    Stop = function(self)
        self.StopDriving = true

        if SERVER then
            self.Entity:StopControlByPlayer()

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

        end
    end,

    CalcView = function( self, view )
        local angles = self.Player:EyeAngles()

        local botpos = self.Entity:GetShootPos()
        local campos = LocalToWorld( self.Entity:GetControlCameraOffset(), angle_zero, botpos, angles )

        local tr = util.TraceHull( {
            start = botpos,
            endpos = campos,
            mins = Vector( view.znear, view.znear, view.znear ) * -3,
            maxs = Vector( view.znear, view.znear, view.znear ) * 3,
            mask = MASK_BLOCKLOS,
            filter = self.Entity,
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

    local toSync
    for actionName, actionData in pairs( actions ) do
        if not actionData.syncCommand then continue end
        toSync = toSync or {}
        toSync[actionName] = actionData

    end

    if not toSync then return end

    for actionName, actionData in pairs( toSync ) do
        net.Start( "Term_SyncDriveActions" )
            net.WriteEntity( bot )
            net.WriteString( actionName )
            net.WriteUInt( actionData.inBind or 0, 32 )
            net.WriteString( actionData.commandName )
            net.WriteString( actionData.name )
            net.WriteBool( actionData.drawHint )
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