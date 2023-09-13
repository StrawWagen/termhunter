
-- give the bot some weapons plssss!

local doDropWeapons = CreateConVar( "terminator_playerdropweapons", "1", FCVAR_ARCHIVE, "Should players drop all their weapons when killed by terminators?" )
local maxWeaponsToDrop = CreateConVar( "terminator_playerdropweapons_count", "5", FCVAR_ARCHIVE, "How many weapons to drop when terminators kill players, Default 5" )

local function setDropWeapons( ply, attacker, _ )
    if not attacker or attacker.isTerminatorHunterBased ~= true then return end
    if attacker.DontDropPrimary then return end -- they cant pick it up!
    if GAMEMODE.IsReallyHuntersGlee == true then return end
    if not doDropWeapons:GetBool() then return end

    local weapsToDrop = ply:GetWeapons()
    ply.terminator_droppedweapons = ply.terminator_droppedweapons or {}

    for _, oldDropped in ipairs( ply.terminator_droppedweapons ) do
        if IsValid( oldDropped ) and not IsValid( oldDropped:GetParent() ) and not IsValid( oldDropped:GetOwner() ) then
            SafeRemoveEntity( oldDropped )
        end
    end

    table.sort( weapsToDrop, function( a, b )
        return attacker:GetWeightOfWeapon( a ) < attacker:GetWeightOfWeapon( b )

    end )

    local maxDrop = maxWeaponsToDrop:GetInt()

    -- randomly remove one of the worst weapons until we have just enough
    while #weapsToDrop > maxDrop do
        table.remove( weapsToDrop, math.random( 1, 4 ) )

    end

    for _, wep in ipairs( weapsToDrop ) do

        if not IsValid( wep ) then continue end
        if wep.ShouldDropOnDie and wep:ShouldDropOnDie() == false and not termHunter_WeaponAnalogs[ wep:GetClass() ] then continue end

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
            if not newWepObj or not newWepObj.IsValid or not newWepObj:IsValid() then return end
            newWepObj:ApplyForceCenter( forceDir * newWepObj:GetMass() * math.random( 150, 300 ) )

        end )

        local wepWeight = 0
        if attacker.GetWeightOfWeapon then
            wepWeight = attacker:GetWeightOfWeapon( wep )

        end

        timer.Simple( math.random( 240, 280 ) + wepWeight * 40, function()
            if not IsValid( newWep ) then return end
            if IsValid( newWep:GetOwner() ) or IsValid( newWep:GetParent() ) then return end

            SafeRemoveEntity( newWep )

        end )

    end
end


hook.Add( "DoPlayerDeath", "straw_termdropper_dropweaponoverride", setDropWeapons )