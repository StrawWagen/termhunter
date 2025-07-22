
local CurTime = CurTime

terminator_Extras = terminator_Extras or {}

terminator_Extras.alreadyCreated = terminator_Extras.alreadyCreated or {}
local alreadyCreated = terminator_Extras.alreadyCreated
local nextRecieve = 0
local debuggingVar = GetConVar( "terminator_event_debug" )

local function debugPrint( ... )
    if not debuggingVar then return end
    if not debuggingVar:GetBool() then return end
    permaPrint( ... )

end


-- big thinker func
-- client doesnt have a clue what events are on the server, so the server tells client about 1 of em whenever it needs to know ply's progress on that 1
-- this makes the least amount of permanent cvars for as few people as possible
-- also its neat
net.Receive( "terminator_event_setupclientvars", function()
    local cur = CurTime()
    if nextRecieve > cur then debugPrint( "CLTERMEVENT; fail 0 " ) return end
    nextRecieve = cur + 0.01

    local varName = net.ReadString()
    if not GetGlobal2Bool( varName ) then debugPrint( "CLTERMEVENT; fail 1 ", varName ) return end -- this check might not be needed, or might not be effective

    if alreadyCreated[varName] then debugPrint( "CLTERMEVENT; fail 2 ", varName ) return end

    alreadyCreated[varName] = CreateClientConVar( varName, 0, true, true, "Auto-generated command used to keep track of your progress in a 'Terminator' event" )

    debugPrint( "CLTERMEVENT; success ", varName )

end )


-- QOL stuff

local asking
local function askForAllCvars()
    permaPrint( "Getting all event convars..." )
    net.Start( "terminator_event_askforallcvars" )
    net.SendToServer()

end

local function askToResetAllProgress()
    if asking then permaPrint( "wait..." ) return end -- kind of anti-exploit
    asking = true

    askForAllCvars()

    timer.Simple( 3, function()
        asking = nil
        for name, var in pairs( terminator_Extras.alreadyCreated ) do
            permaPrint( "Old progress for", name, var:GetInt() )

        end
        for name, _ in pairs( terminator_Extras.alreadyCreated ) do
            LocalPlayer():ConCommand( name .. " " .. 0 )
            permaPrint( "Reset...", name )

        end
    end )
end

local function askForAllCvarsCommand()
    if asking then permaPrint( "wait..." ) return end
    asking = true

    askForAllCvars()

    timer.Simple( 3, function()
        asking = nil
        for name, var in pairs( terminator_Extras.alreadyCreated ) do
            permaPrint( name, var:GetInt() )

        end
    end )
end

concommand.Add( "cl_termevent_resetallprogress", function() askToResetAllProgress() end, nil, "Requests the cvars for every event, then resets them all to 0" )
concommand.Add( "cl_termevent_getallprogress", function() askForAllCvarsCommand() end, nil, "Requests the cvars for every event" )