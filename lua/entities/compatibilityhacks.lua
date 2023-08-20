AddCSLuaFile()

-- hacky fixes for comaptibility with other common addons

-- VJ BASE, connects with weapons.lua

function ENT:Classify()
    return CLASS_NONE

end

if SERVER then
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
    function ENT:DrG_SetRelationship( ent, disp )
        self:AddEntityRelationship( ent, D_HT )

    end

end