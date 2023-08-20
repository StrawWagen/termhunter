if not SERVER then return end

function util.CanBashDoor( door )
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
