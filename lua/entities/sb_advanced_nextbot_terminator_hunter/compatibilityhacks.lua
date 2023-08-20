AddCSLuaFile()

-- hacky fixes for comaptibility with other common addons

-- had some weapon base problems that made this necessary iirc
function ENT:Classify()
    return CLASS_NONE

end

-- VJ BASE, connects with weapons.lua

if SERVER then
    function ENT:KeyDown()
        return nil
    end

    function ENT:VJ_GetDifficultyValue( int )
        return int
    end

    function ENT:fakeVjBaseWeaponFiring( wep ) -- copied code from vj base github, hope it doesnt change in future and break
        timer.Simple( wep.NPC_TimeUntilFire, function()
            if IsValid( wep ) and IsValid( self ) and IsValid( self:GetOwner() ) and CurTime() > wep.NPC_NextPrimaryFireT then
                wep:PrimaryAttack()
                if wep.NPC_NextPrimaryFire == false then return end -- Support for animation events
                wep.NPC_NextPrimaryFireT = CurTime() + wep.NPC_NextPrimaryFire
                for _, tv in ipairs( wep.NPC_TimeUntilFireExtraTimers ) do
                    timer.Simple( tv, function()
                        if not IsValid( wep ) or not IsValid( self ) or wep:NPCAbleToShoot() ~= true then return end
                        wep:PrimaryAttack()

                    end )
                end
            end
        end )
    end

end

--see SetupEntityRelationship in the big terminator.lua file

-- drg base
-- drg assumes that all nextbots are drg nextbots, stupid

if SERVER then
    function ENT:DrG_SetRelationship( ent, _ )
        self:AddEntityRelationship( ent, D_HT )

    end

end