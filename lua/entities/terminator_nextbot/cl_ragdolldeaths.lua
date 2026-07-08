
hook.Add( "CreateClientsideRagdoll", "terminator_fixcorpsemats", function( died, newRagdoll )
    if not died.isTerminatorHunterBased then return end

    terminator_Extras.copyMatsOver( died, newRagdoll )

    if died.AdditionalRagdollDeathEffects then
        died:AdditionalRagdollDeathEffects( newRagdoll )

    end

    local scale = died:GetModelScale()

    if scale <= terminator_Extras.MDLSCALE_LARGE then return end

    local offsetVec = Vector( 0, 0, scale )

    -- JANK ASF
    -- if you have a better way to do this, please pr it LOL
    for i = 0, newRagdoll:GetBoneCount() do
        local oldScale = newRagdoll:GetManipulateBoneScale( i )
        local oldOffset = newRagdoll:GetManipulateBonePosition( i )
        newRagdoll:ManipulateBoneScale( i, oldScale * scale )
        newRagdoll:ManipulateBonePosition( i, oldOffset + offsetVec )

    end

    for i = 1, newRagdoll:GetPhysicsObjectCount() do
        local currObj = newRagdoll:GetPhysicsObject( i )
        currObj:SetMass( currObj:GetMass() * scale )

    end
end )
