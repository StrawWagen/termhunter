
-- give the bot some weapons plssss!

local defaultWepsToDrop = 6
local doDropWeapons = CreateConVar( "terminator_playerdropweapons", "1", FCVAR_ARCHIVE, "Should players drop all their weapons when killed by terminators?" )
local maxWeaponsToDrop = CreateConVar( "terminator_playerdropweapons_droppedcount", "-1", FCVAR_ARCHIVE, "How many weapons to drop when terminators kill players, Default 6" )

local function setDropWeapons( ply, attacker, _ )
    if not attacker or attacker.isTerminatorHunterBased ~= true then return end
    if attacker.DontDropPrimary then return end -- they cant pick it up!
    if not attacker.CanFindWeaponsOnTheGround then return end -- they dont want to pick up weapons
    if GAMEMODE.IsReallyHuntersGlee == true then return end -- glee does its own thing
    if not doDropWeapons:GetBool() then return end

    local plysActiveWeapon = ply:GetActiveWeapon()

    local plysWeapons = ply:GetWeapons()
    ply.terminator_droppedweapons = ply.terminator_droppedweapons or {}

    for _, oldDropped in ipairs( ply.terminator_droppedweapons ) do
        if IsValid( oldDropped ) and not IsValid( oldDropped:GetParent() ) and not IsValid( oldDropped:GetOwner() ) then
            SafeRemoveEntity( oldDropped )
        end
    end

    local maxDrop = maxWeaponsToDrop:GetInt()
    if maxDrop <= -1 then
        maxDrop = defaultWepsToDrop

    end

    local droppingActiveAlready
    local weapsToDrop = {}
    for i = 1, maxDrop do
        local wepCount = #plysWeapons
        if wepCount <= 0 then break end

        randWepIndex = math.random( 1, wepCount )
        local randWep = table.remove( plysWeapons, randWepIndex )
        weapsToDrop[i] = randWep
        if randWep == plysActiveWeapon then
            droppingActiveAlready = true
            break

        end
    end

    if not droppingActiveAlready and IsValid( plysActiveWeapon ) then
        table.insert( weapsToDrop, plysActiveWeapon )

    end

    for _, wep in ipairs( weapsToDrop ) do

        if not IsValid( wep ) then continue end
        if wep.ShouldDropOnDie and wep:ShouldDropOnDie() == false and not termHunter_WeaponAnalogs[ wep:GetClass() ] then continue end

        -- create a new weapon.... spaget
        -- pretty sure DropWeapon doesnt work this late into player's death tho
        local newWep = ents.Create( wep:GetClass() )
        if not IsValid( newWep ) then continue end

        table.insert( ply.terminator_droppedweapons, newWep )

        newWep:SetPos( ply:GetShootPos() )
        newWep:SetAngles( AngleRand() )
        newWep:Spawn()

        newWep:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )
        local forceDir = ply:GetAimVector()

        timer.Simple( 0, function()
            if not IsValid( newWep ) then return end
            if not IsValid( ply ) then return end

            local newWepObj = newWep:GetPhysicsObject()
            if not IsValid( newWepObj ) then return end
            newWepObj:ApplyForceCenter( forceDir * newWepObj:GetMass() * math.random( 150, 300 ) )

        end )

        local wepWeight = 0
        if attacker.GetWeightOfWeapon then
            wepWeight = attacker:GetWeightOfWeapon( wep )

        end

        timer.Simple( math.random( 100, 140 ) + wepWeight * 40, function()
            if not IsValid( newWep ) then return end
            if IsValid( newWep:GetOwner() ) or IsValid( newWep:GetParent() ) then return end

            SafeRemoveEntity( newWep )

        end )

    end
end

hook.Add( "DoPlayerDeath", "straw_termdropper_dropweaponoverride", setDropWeapons )

hook.Add( "terminator_nextbot_noterms_exist", "termdropper_cleanupweapons", function()
    for _, ply in player.Iterator() do
        if not ply.terminator_droppedweapons then continue end
        for _, droppedWep in ipairs( ply.terminator_droppedweapons ) do
            if IsValid( droppedWep ) and not IsValid( droppedWep:GetParent() ) and not IsValid( droppedWep:GetOwner() ) then
                SafeRemoveEntity( droppedWep )

            end
        end
        ply.terminator_droppedweapons = nil

    end
end )
