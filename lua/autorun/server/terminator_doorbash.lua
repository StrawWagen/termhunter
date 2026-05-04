-- is this a real fake door?
-- returns true if door has space both sides
-- false if door goes into a wall
terminator_Extras.CanBashDoor = function( door )
    if door:GetClass() ~= "prop_door_rotating" then return nil end

    local nextCheck = door.nextDoorSmashValidityCheck or 0
    if nextCheck < CurTime() then
        door.nextDoorSmashValidityCheck = CurTime() + 2.5

        local center = door:WorldSpaceCenter()
        local forward = door:GetForward()
        local starOffset = forward * 25
        local endOffset  = forward * 2

        local traceDatF = {
            mask = MASK_SOLID_BRUSHONLY,
            start = center + starOffset,
            endpos = center + endOffset
        }

        local traceDatB = {
            mask = MASK_SOLID_BRUSHONLY,
            start = center + -starOffset,
            endpos = center + -endOffset
        }

        --debugoverlay.Line( center + starOffset, center + forward, 30, Color( 255, 255, 255 ), true )
        --debugoverlay.Line( center + -starOffset, center + -endOffset, 30, Color( 255, 255, 255 ), true )

        local traceBack = util.TraceLine( traceDatB )
        local traceFront = util.TraceLine( traceDatF )

        local canSmash = not traceBack.Hit and not traceFront.Hit
        door.doorCanSmashCached = canSmash
        return canSmash

    else
        return door.doorCanSmashCached

    end
end

hook.Add( "PlayerUse", "term_dontusebusteddoors", function( _, used )
    if used.terminator_busteddoor then return false end

end )


-- code from the sanic nextbot, the greatest nexbot
local function detachAreaPortals( attacker, door )

    local doorName = door:GetName()
    if doorName == "" then return end

    for _, portal in ipairs( ents.FindByClass( "func_areaportal" ) ) do
        local portalTarget = portal:GetInternalVariable( "m_target" )
        if portalTarget == doorName then

            portal:Input( "Open", attacker, door )

            portal:SetSaveValue( "m_target", "" )
        end
    end
end

function terminator_Extras.DoorHitSound( ent )
    ent:EmitSound( "ambient/materials/door_hit1.wav", 85, math.random( 80, 120 ) )

end

function terminator_Extras.BreakSound( ent )
    local Snd = "physics/wood/wood_furniture_break" .. tostring( math.random( 1, 2 ) ) .. ".wav"
    ent:EmitSound( Snd, 95, math.random( 80, 90 ) )

end

function terminator_Extras.StrainSound( ent )
    local Snd = "physics/wood/wood_strain" .. tostring( math.random( 2, 4 ) ) .. ".wav"
    ent:EmitSound( Snd, 80, math.random( 60, 70 ) )

end

function terminator_Extras.DehingeDoor( attacker, door, noCollided )
    local pos = door:GetPos()
    local ang = door:GetAngles()
    local mdl = door:GetModel()
    local ski = door:GetSkin()

    door:SetKeyValue( "returndelay", -1 )
    door:Fire( "Open" )
    detachAreaPortals( attacker:GetOwner(), door )

    local getRidOf = { door }
    terminator_Extras.tableAdd( getRidOf, door:GetChildren() )
    for _, toRid in pairs( getRidOf ) do
        toRid:SetNotSolid( true )
        toRid:SetNoDraw( true )
        -- dont allow plys to use this
        toRid.terminator_busteddoor = true

    end
    local prop = ents.Create( "prop_physics" )
    prop:SetPos( pos )
    prop:SetAngles( ang )
    prop:SetModel( mdl )
    prop:SetSkin( ski or 0 )
    prop:Spawn()

    prop:SetPhysicsAttacker( attacker or game.GetWorld() )
    local obj = prop:GetPhysicsObject()
    if IsValid( obj ) then
        local vel = terminator_Extras.dirToPos( attacker:GetPos(), door:WorldSpaceCenter() ) * 30000
        obj:ApplyForceOffset( vel, attacker:GetPos() )

    end

    if noCollided then
        prop:SetCollisionGroup( COLLISION_GROUP_DEBRIS )

    end

    prop.isBustedDoor = true
    prop.bustedDoorHp = 400

    if terminator_Extras.SmartSleepEntity then
        terminator_Extras.SmartSleepEntity( prop, 20 )

    end

    terminator_Extras.DoorHitSound( prop )
    terminator_Extras.BreakSound( prop )

    return prop

end

function terminator_Extras.OpenDoorQuicklyAwayFrom( door, bashAwayFrom )
    local newName = "term_SoftBashDoorRotating_" .. bashAwayFrom:EntIndex()
    bashAwayFrom.term_PreBashName = bashAwayFrom:GetName()
    bashAwayFrom:SetName( newName )

    if not door.term_defaultsGrabbed then
        door.term_defaultsGrabbed = true
        local values = door:GetKeyValues()
        door.term_oldBashSpeed = values["speed"]
        door.term_oldOpenDir = values["opendir"]
        door.term_oldOpenDmg = values["dmg"]

    end

    door:SetKeyValue( "speed", "500" )
    door:SetKeyValue( "opendir", 0 )
    door:SetKeyValue( "dmg", 100 )
    door:Fire( "unlock", "", .01 )
    door:Fire( "openawayfrom", newName, .01 )

    timer.Simple( 0.02, function()
        if not IsValid( bashAwayFrom ) or bashAwayFrom:GetName() ~= newName then return end

        bashAwayFrom:SetName( bashAwayFrom.term_PreBashName )

    end )

    timer.Simple( 0.3, function()
        if not IsValid( door ) then return end
        if door.term_oldBashSpeed then
            door:SetKeyValue( "speed", door.term_oldBashSpeed )

        end
        if door.term_oldOpenDir then
            door:SetKeyValue( "opendir", door.term_oldOpenDir )

        end
        if door.term_oldOpenDmg then
            door:SetKeyValue( "dmg", door.term_oldOpenDmg )

        end
    end )
end