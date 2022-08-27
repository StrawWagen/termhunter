if SERVER then

    local function sqrDistGreaterThan( Dist1, Dist2 )
        local Dist2 = Dist2 ^ 2
        return Dist1 > Dist2
    end
    
    local function sqrDistLessThan( Dist1, Dist2 )
        local Dist2 = Dist2 ^ 2
        return Dist1 < Dist2
    end

    local function terminatorsSendSoundHint( attacker, src, range )
        if not range then return end
        local attackerInternal = attacker or NULL
        local terms = ents.FindByClass( "sb_advanced_nextbot_terminator_hunter" )
        for termInd, currTerm in pairs( terms ) do
            local distToSrc = currTerm:GetPos():DistToSqr( src )
            local isMe = attackerInternal == currTerm 
            if sqrDistLessThan( distToSrc, range ) and not isMe then
                currTerm.lastHeardSoundHint = src
                currTerm.lastHeardSoundTime = CurTime()
                if IsValid( attackerInternal ) then 
                    if currTerm:GetRelationship( attackerInternal ) == D_HT then
                        currTerm:UpdateEnemyMemory( attackerInternal, src )
                    end
                end
            end
        end
    end

    local customRanges = { 
        ["weapon_pistol"] = 4000,
        ["weapon_357"] = 6000,
        ["weapon_smg1"] = 5000,
        ["weapon_ar2"] = 6000,
        ["weapon_shotgun"] = 5000,
    }

    local function bulletFireThink( entity, data )
        if not IsValid( entity ) then return end

        local range = nil
        local weap = nil
        if entity:IsNPC() or entity:IsPlayer() then
            weap = entity:GetActiveWeapon()
        end
        local customRange = nil
        if IsValid( weap ) then
            customRange = customRanges[ weap:GetClass() ]
        end
        if customRange then 
            range = customRange
        elseif not customRange then
            local dmg = 60
            if data.Damage > 0 then
                dmg = math.Round( data.Damage )
            end
            local num = 1
            if num > 1 then
                num = math.Clamp( data.Num / 2, 1, math.huge )
            end 
            local totalDmg = dmg * num
            range = math.Clamp( totalDmg * 200, 3000, 10000 ) -- bigger gunz are louder
        end

        local src = data.Src

        terminatorsSendSoundHint( entity, src, range )

    end
    hook.Add( "EntityFireBullets", "straw_termalerter_firebullets", bulletFireThink )



    -- stick our fingers in emithint
    sound._EmitHint = sound._EmitHint or sound.EmitHint
    sound.EmitHint = function( ... )
        hook.Run( "StrawSoundEmitHint", ... )
        return sound._EmitHint( ... )
    end

    local function soundHintThink( hint, pos, volume, duration, owner )

        local combat = bit.band( hint, SOUND_COMBAT ) > 0
        local danger = bit.band( hint, SOUND_DANGER ) > 0

        if not combat then return end
        if not danger then return end
        
        local radius = volume * 5 -- example, 600 to 3000 radius

        terminatorsSendSoundHint( owner, pos, radius )

    end
    hook.Add( "StrawSoundEmitHint", "straw_termalerter_soundhint", soundHintThink )



    -- bl damage
    util._NextBotHook_BlastDamage = util._NextBotHook_BlastDamage or util.BlastDamage
    util.BlastDamage = function( ... )
        hook.Run( "StrawBlastDamage", ... )
        return util._NextBotHook_BlastDamage( ... )
    end

    local function blastDamageHintThink( inflictor, attacker, damageOrigin, damageRadius, damage )
        
        local radiusComponent = damageRadius * 0.2
        local volume = math.Clamp( damage * radiusComponent, 1000, 10000 )

        terminatorsSendSoundHint( attacker, damageOrigin, volume )

    end
    hook.Add( "StrawBlastDamage", "straw_termalerter_blastdamage", blastDamageHintThink )
    

    -- bl damage info
    util._NextBotHook_BlastDamageInfo = util._NextBotHook_BlastDamageInfo or util.BlastDamageInfo
    util.BlastDamageInfo = function( ... )
        hook.Run( "StrawBlastDamageInfo", ... )
        return util._NextBotHook_BlastDamageInfo( ... )
    end

    local function blastDamageInfoHintThink( dmg, damageOrigin, damageRadius )
        
        local damage = dmg:GetDamage() 
        local radiusComponent = damageRadius * 0.2
        local volume = math.Clamp( damage * radiusComponent, 1000, 10000 )

        terminatorsSendSoundHint( attacker, damageOrigin, volume )

    end

    hook.Add( "StrawBlastDamageInfo", "straw_termalerter_blastdamageinfo", blastDamageInfoHintThink )



    -- env_explosion reading
    local function explosionHintThink( entity )
        if not IsValid( entity ) then return end
        if entity:GetClass() ~= "env_explosion" then return end

        timer.Simple( engine.TickInterval(), function()

            if not IsValid( entity ) then return end
            local keys = entity:GetKeyValues()
            
            local damage = keys["iMagnitude"] or 0
            local radius = damage
            if keys["iRadiusOverride"] or 0 > 0 then
                radius = keys["iRadiusOverride"]
            end
            local pos = entity:GetPos()

            local radiusComponent = radius * 0.2
            local volume = math.Clamp( damage * radiusComponent, 1000, 10000 )

            terminatorsSendSoundHint( attacker, pos, volume )

        end )
    end

    hook.Add( "OnEntityCreated", "straw_termalerter_explosioninfo", explosionHintThink )

end