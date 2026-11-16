
-- workshop content clients download and mount on demand, the server needs it mounted already
--     terminator_Extras.AddOnDemandWorkshop( "174117071" )
-- the rest, and ENT.MyWorkshopContentIds, are in the README
-- client half, autorun/client/terminator_cl_workshopcontent.lua

terminator_Extras = terminator_Extras or {}

util.AddNetworkString( "terminator_workshopcontent" )

local onDemandVar = GetConVar( "terminator_myworkshopcontentids_ondemand" ) -- autorun/sh_terminator_workshopcontent.lua

-- id -> true
terminator_Extras.onDemandWorkshopIds = terminator_Extras.onDemandWorkshopIds or {}
local onDemandIds = terminator_Extras.onDemandWorkshopIds

local developerVar = GetConVar( "developer" )


-- CONFLICTS WITH resource.AddWorkshop --
-- an id that's also resource.AddWorkshop'd downloads at join anyway, so getting it on demand does nothing
-- one of the two should go, so both get reported, with where they came from

-- id -> traceback, or which class it's on
terminator_Extras.workshopAddedAtJoin = terminator_Extras.workshopAddedAtJoin or {}
local addedAtJoin = terminator_Extras.workshopAddedAtJoin
terminator_Extras.workshopAddedOnDemand = terminator_Extras.workshopAddedOnDemand or {}
local addedOnDemand = terminator_Extras.workshopAddedOnDemand

local reportedConflicts = {}

-- harmless for players, it just wastes the system, so it only gets loud with developer on
local function reportConflict( id )
    if reportedConflicts[id] then return end
    if not addedAtJoin[id] or not addedOnDemand[id] then return end
    reportedConflicts[id] = true

    local msg = "terminator_Extras: workshop id " .. id .. " is resource.AddWorkshop'd, so it downloads at join, and getting it on demand does nothing. Remove one of them.\n"
        .. "resource.AddWorkshop'd at:" .. addedAtJoin[id] .. "\n"
        .. "added on demand at:" .. addedOnDemand[id] .. "\n"

    if developerVar:GetInt() > 0 then
        ErrorNoHalt( msg )

    else
        permaPrint( msg )

    end
end

-- where is a traceback or which class it's on. only the first of each is kept
local function recordOnDemand( id, where )
    if addedOnDemand[id] then return end
    addedOnDemand[id] = where
    reportConflict( id )

end

local function recordAtJoin( id, where )
    if addedAtJoin[id] then return end
    addedAtJoin[id] = where
    reportConflict( id )

end

-- level 3, skips this and the public function that called it
local function callerTraceback()
    return "\n" .. debug.traceback( "", 3 )

end

-- misses calls from autorun files that load before this one
terminator_Extras.oldAddWorkshop = terminator_Extras.oldAddWorkshop or resource.AddWorkshop
local oldAddWorkshop = terminator_Extras.oldAddWorkshop

function resource.AddWorkshop( ... )
    recordAtJoin( tostring( ... ), "\n" .. debug.traceback( "", 2 ) )
    return oldAddWorkshop( ... )

end


-- BOTS' CONTENT --
-- every class's ENT.MyWorkshopContentIds, at join or on demand
-- classes have no traceback, so it's the class and where it's from

hook.Add( "InitPostEntity", "terminator_WorkshopContent", function()
    local onDemand = onDemandVar:GetBool()

    for class, stored in pairs( scripted_ents.GetList() ) do
        local ids = scripted_ents.GetMember( class, "MyWorkshopContentIds" )
        if isstring( ids ) then ids = { ids } end
        if istable( ids ) then
            local where = " ENT.MyWorkshopContentIds on " .. class .. ", " .. tostring( stored.t.Folder )
            for _, id in ipairs( ids ) do
                if onDemand then
                    recordOnDemand( id, where )

                else
                    -- straight to the original, so it's recorded with the class, not this file
                    recordAtJoin( id, where )
                    oldAddWorkshop( id )

                end
            end
        end
    end
end )


-- SENDING --

local function send( ids, plys )
    net.Start( "terminator_workshopcontent", false )
        net.WriteUInt( #ids, 16 )
        for _, id in ipairs( ids ) do
            net.WriteString( id )

        end
    net.Send( plys )

end

local function sendAll( plys )
    local ids = table.GetKeys( onDemandIds )
    if #ids <= 0 then return end
    send( ids, plys )

end


-- RESENDING --
-- clients only ever try an id once, so repeats cost nothing
-- and a client that missed one, eg it was still loading, gets it next time

-- once a player can move, they're loaded in enough to get net messages, see https://github.com/CFC-Servers/gm_playerload
local loadQueue = {}

hook.Add( "PlayerInitialSpawn", "terminator_WorkshopContent", function( ply )
    if next( onDemandIds ) == nil then return end
    loadQueue[ply] = true

    hook.Add( "SetupMove", "terminator_WorkshopContent", function( loadingPly, _, cmd )
        if not loadQueue[loadingPly] then return end
        if cmd:IsForced() then return end

        loadQueue[loadingPly] = nil
        sendAll( { loadingPly } )

        if next( loadQueue ) == nil then
            hook.Remove( "SetupMove", "terminator_WorkshopContent" )

        end
    end )
end )

-- they left before loading in
hook.Add( "PlayerDisconnected", "terminator_WorkshopContent", function( ply )
    loadQueue[ply] = nil

end )

local function startBackupResends()
    timer.Create( "terminator_WorkshopContent", 60, 0, function()
        sendAll( player.GetAll() )

    end )
end


-- PUBLIC --

-- every client, including ones who join later
function terminator_Extras.AddOnDemandWorkshop( id )
    recordOnDemand( id, callerTraceback() )

    if onDemandIds[id] then return end
    onDemandIds[id] = true

    send( { id }, player.GetAll() )
    startBackupResends()

end

-- just stops sending it, clients can't unmount
function terminator_Extras.RemoveOnDemandWorkshop( id )
    onDemandIds[id] = nil
    if next( onDemandIds ) ~= nil then return end

    timer.Remove( "terminator_WorkshopContent" )

end

function terminator_Extras.IsOnDemandWorkshop( id )
    return onDemandIds[id] == true

end

-- NW2 only reaches clients ent gets sent to, so only they download it
function terminator_Extras.SetOnDemandWorkshop( ent, ids )
    if isstring( ids ) then ids = { ids } end
    for _, id in ipairs( ids ) do
        recordOnDemand( id, callerTraceback() )

    end
    ent:SetNW2String( "term_OnDemandWorkshop", table.concat( ids, "," ) )

end
