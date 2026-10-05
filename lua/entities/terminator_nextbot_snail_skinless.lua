AddCSLuaFile()

-- bros naked

ENT.Base = "terminator_nextbot_snail"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Endoskeleton"
terminator_Extras.RegisterNPC( "terminator_nextbot_snail_skinless", ENT, {
    Weapons = { "weapon_terminatorfists_term" },

} )

local SKELETON_MODEL = "models/terminator/player/skeleton/t800nw.mdl"

if CLIENT then return end

function terminator_Extras.becomeEndoskeleton( ent )
    ent.Models = { SKELETON_MODEL }
    ent.Term_BloodColor = BLOOD_COLOR_MECH

    ent.Hits = {
        "physics/metal/metal_canister_impact_hard1.wav",
        "physics/metal/metal_canister_impact_hard2.wav",
        "physics/metal/metal_canister_impact_hard3.wav",
    }
    ent.Creaks = {
        "physics/metal/metal_box_strain1.wav",
        "physics/metal/metal_box_strain2.wav",
        "physics/metal/metal_box_strain3.wav",
        "physics/metal/metal_box_strain4.wav",
    }

    if CurTime() - ent:GetCreationTime() < 0.1 then return end -- new ent, we are in OnPreCreated

    ent:SetModel( SKELETON_MODEL )
    ent:SetBloodColor( BLOOD_COLOR_MECH )

end

ENT.MyClassTask = {
    OnPreCreated = function( self, data )
        terminator_Extras.becomeEndoskeleton( self )

    end,
}