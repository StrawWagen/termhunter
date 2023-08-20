terminator_Extras.EngineAnalogWeights = nil

local function AnalogWeightsCheck()
    terminator_Extras.EngineAnalogWeights = terminator_Extras.EngineAnalogWeights or {
        -- these weapons kinda suck
        ["weapon_shotgun"] = 1,
        ["weapon_pistol"] = 0,
        ["weapon_smg1"] = 2,
        ["weapon_357"] = 6,
    }

end


terminator_Extras.SetupAnalogWeight = function( wep )
    if not SERVER then return end
    AnalogWeightsCheck()

    local class = wep.Folder
    class = string.TrimLeft( class, "weapons/" ) -- HACK HACK HACK
    class = string.TrimRight( class, "_better" ) -- HACK HACK HACK
    class = string.TrimRight( class, "_sb_anb" ) -- HACK

    local weight = terminator_Extras.EngineAnalogWeights[ class ]
    if not weight then
        terminator_Extras.EngineAnalogWeights[ class ] = wep.Weight
        --print( terminator_Extras.EngineAnalogWeights[ class ] )

    end
end

terminator_Extras.OverrideWeaponWeight = function( class, newWeight )
    terminator_Extras.EngineAnalogWeights[ class ] = newWeight

end

-- see ENT:GetWeightOfWeapon( wep ) in entities/weapons.lua