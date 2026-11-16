
-- client half of autorun/server/terminator_workshopcontent.lua, downloads and mounts workshop content
--     terminator_Extras.AddOnDemandWorkshop( "174117071" ) -- mounts it for just this client
-- ENT.MyWorkshopContentIds on a terminator nextbot does the same when one's made clientside, while terminator_myworkshopcontentids_ondemand is on
-- the server's ids come in by net, terminator_Extras.SetOnDemandWorkshop's by NW2, all through the same queue

terminator_Extras = terminator_Extras or {}

local developerVar = GetConVar( "developer" )

local function isDeveloping()
    return developerVar:GetInt() > 0

end

local function devPrint( ... )
    if not isDeveloping() then return end
    permaPrint( ... )

end

-- id -> true
terminator_Extras.onDemandWorkshopIds = terminator_Extras.onDemandWorkshopIds or {}
local onDemandIds = terminator_Extras.onDemandWorkshopIds


-- FIXING MATERIALS --
-- anything that called Material() before its content was mounted is stuck holding an error material, eg killicons made at startup
-- so every error material gets recorded here, and fixed in place once content mounts
-- this has to be in place before they're made, hence autorun

terminator_Extras.invalidMats = terminator_Extras.invalidMats or {}
local invalidMats = terminator_Extras.invalidMats
terminator_Extras.oldMaterial = terminator_Extras.oldMaterial or Material
local oldMaterial = terminator_Extras.oldMaterial

-- Material( "Foo\\bar" ) and a mounted "materials/foo/bar.vmt" are the same material
-- pngs keep their extension, they're a different material to a vmt of the same name
local function normalizeMatName( name )
    name = string.lower( string.Replace( name, "\\", "/" ) )
    name = string.gsub( name, "^materials/", "" )
    name = string.gsub( name, "%.vmt$", "" )
    return name

end

-- ... is whatever Material() returned, passed back untouched
local function recordIfError( name, params, ... )
    local mat = ...
    if not isstring( name ) then return ... end
    if not mat or not mat:IsError() then return ... end

    -- a missing vmt gives back the one error material every missing vmt shares, fixing that in place would retexture all of them
    -- missing pngs get a material of their own
    if mat:GetName() == "___error" then return ... end

    local key = normalizeMatName( name )
    if not invalidMats[key] then
        invalidMats[key] = { name = name, mat = mat, params = params }

    end
    return ...

end

function Material( ... )
    local name, params = ...
    return recordIfError( name, params, oldMaterial( ... ) )

end

-- SetShader does nothing, so to keeps its own shader, eg a png's UnlitGeneric can't become VertexLitGeneric
local function copyMaterialParams( from, to )
    for key, value in pairs( from:GetKeyValues() ) do
        if isnumber( value ) then
            if math.floor( value ) == value then
                to:SetInt( key, value )

            else
                to:SetFloat( key, value )

            end
        elseif isvector( value ) then
            to:SetVector( key, value )

        elseif ismatrix( value ) then
            to:SetMatrix( key, value )

        elseif isstring( value ) then
            to:SetString( key, value )

        elseif TypeID( value ) == TYPE_TEXTURE then
            to:SetTexture( key, value )

        end
    end
end

local function fixBrokeMaterials( stuffMounted )
    local materialsMounted = {}
    for _, mountedName in ipairs( stuffMounted ) do
        if string.StartsWith( mountedName, "materials/" ) then
            table.insert( materialsMounted, mountedName )

        end
    end

    devPrint( "terminator_Extras: trying to fix " .. #materialsMounted .. " materials" )

    if isDeveloping() then
        permaPrint( "terminator_Extras: workshop content mounted" )
        PrintTable( materialsMounted )
        for _, matData in pairs( invalidMats ) do
            permaPrint( matData.name )

        end
    end

    for _, mountedName in ipairs( materialsMounted ) do
        local key = normalizeMatName( mountedName )
        local matData = invalidMats[key]
        if not matData then continue end

        local nameToTry = string.gsub( mountedName, "^materials/", "" )
        local tempMat = oldMaterial( nameToTry, matData.params )
        if tempMat:IsError() then
            devPrint( "terminator_Extras: " .. nameToTry .. " FAILFIX 1" )
            continue

        end

        devPrint( "terminator_Extras: fixing material " .. matData.name .. " with " .. nameToTry )
        -- the broken material is what everything's holding, so it gets the real one's params, not replaced
        copyMaterialParams( tempMat, matData.mat )
        matData.mat:Recompute()
        invalidMats[key] = nil
        devPrint( "terminator_Extras: " .. matData.name .. " fixed!" )

    end
end


-- DOWNLOADING --
-- one download at a time, each id only ever tried once

local contentTried = {}
local contentTodo = {}
local nextThink = 0
local downloading
local downloadGivesUpAt = 0

-- a callback that never comes would hold up the queue forever
-- generous, a big addon on a slow connection takes a while
local downloadTimeout = 120

local function tryDoingContent()
    local cur = CurTime()
    if downloading and downloadGivesUpAt > cur then return end
    if nextThink > cur then return end
    if #contentTodo <= 0 then return true end -- all done

    local currContent = table.remove( contentTodo, 1 )
    if contentTried[currContent] then return end

    -- only attempt once, tried count based approach, was too fragile
    contentTried[currContent] = true
    downloading = true
    downloadGivesUpAt = cur + downloadTimeout
    nextThink = cur + 0.1

    MsgN( "terminator_Extras: mounting " .. currContent )
    steamworks.DownloadUGC( currContent, function( path )
        downloading = nil
        nextThink = CurTime() + 0.1

        if not path then return end
        local succeeded, stuffMounted = game.MountGMA( path )

        if not succeeded then return end
        MsgN( "terminator_Extras: successfully mounted " .. currContent )

        if not stuffMounted then return end
        fixBrokeMaterials( stuffMounted )

    end )
end

local downloadVar = CreateClientConVar( "terminator_workshopcontent_download", 1, true, false, "Download and mount workshop content the server or bots need? Without it some models and materials may be missing.", 0, 1 )

local function queueContent( id )
    if not downloadVar:GetBool() then return end
    if contentTried[id] then return end
    table.insert( contentTodo, id )

    hook.Add( "Think", "terminator_WorkshopContent", function()
        local allDone = tryDoingContent()
        if allDone then hook.Remove( "Think", "terminator_WorkshopContent" ) return end

    end )
end

local function requireId( id )
    onDemandIds[id] = true
    queueContent( id )

end

-- opting back in gets what was skipped
cvars.AddChangeCallback( "terminator_workshopcontent_download", function( _, _, new )
    if tobool( new ) ~= true then return end
    for id in pairs( onDemandIds ) do
        queueContent( id )

    end
end, "terminator_WorkshopContent" )


-- WHERE IDS COME FROM --

-- terminator_Extras.AddOnDemandWorkshop, serverside
net.Receive( "terminator_workshopcontent", function()
    local count = net.ReadUInt( 16 )
    for _ = 1, count do
        requireId( net.ReadString() )

    end
end )

-- terminator_Extras.SetOnDemandWorkshop, arrives with the ent
hook.Add( "EntityNetworkedVarChanged", "terminator_WorkshopContent", function( _, name, _, ids )
    if name ~= "term_OnDemandWorkshop" then return end
    if not ids or ids == "" then return end

    for _, id in ipairs( string.Explode( ",", ids ) ) do
        requireId( id )

    end
end )

-- ENT.MyWorkshopContentIds is read by the terminator nextbot's own Initialize


-- PUBLIC --

function terminator_Extras.AddOnDemandWorkshop( id )
    requireId( id )

end

-- can't unmount, this only stops it being required
function terminator_Extras.RemoveOnDemandWorkshop( id )
    onDemandIds[id] = nil

end

function terminator_Extras.IsOnDemandWorkshop( id )
    return onDemandIds[id] == true

end
