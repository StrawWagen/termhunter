AddCSLuaFile()

Terminator_EngineAnalogWeights = nil

function Terminator_AnalogWeightsCheck()
    Terminator_EngineAnalogWeights = Terminator_EngineAnalogWeights or {
        -- these weapons kinda suck
        ["weapon_shotgun"] = 1,
        ["weapon_pistol"] = 0,
        ["weapon_smg1"] = 2,
        ["weapon_357"] = 6,
    }

end


function Terminator_SetupAnalogWeight( wep )
    if not SERVER then return end
    Terminator_AnalogWeightsCheck()

    local class = wep.Folder
    class = string.TrimLeft( class, "weapons/" ) -- HACK HACK HACK
    class = string.TrimRight( class, "_better" ) -- HACK HACK HACK
    class = string.TrimRight( class, "_sb_anb" ) -- HACK

    local weight = Terminator_EngineAnalogWeights[ class ]
    if not weight then
        Terminator_EngineAnalogWeights[ class ] = wep.Weight
        --print( Terminator_EngineAnalogWeights[ class ] )

    end
end

function Terminator_OverrideWeaponWeight( class, newWeight )
    Terminator_EngineAnalogWeights[ class ] = newWeight

end

-- see ENT:GetWeightOfWeapon( wep ) in entities/weapons.lua