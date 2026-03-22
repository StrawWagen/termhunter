local listening = nil
local entMeta = FindMetaTable( "Entity" )
local vecMeta = FindMetaTable( "Vector" )
local ipairs = ipairs
local FL_NOTARGET = FL_NOTARGET
local IsValid = IsValid
local math = math

terminator_Extras = terminator_Extras or {}
terminator_Extras.listeners = terminator_Extras.listeners or {}

local goodClassCache
local lastSoundLevels

local function cleanupListenerTbl()
    if not listening then
        listening = true
        goodClassCache = {}
        lastSoundLevels = {}
        terminator_Extras.terminator_alerter_goodClassCache = goodClassCache -- put in _G for profilers
        terminator_Extras.terminator_alerter_lastSoundLevels = lastSoundLevels

    end
    local listeners = terminator_Extras.listeners
    for index, curr in pairs( listeners ) do
        if IsValid( curr ) then continue end
        table.remove( listeners, index )

    end

    if #listeners <= 0 then
        listening = nil
        goodClassCache = nil
        lastSoundLevels = nil
        terminator_Extras.terminator_alerter_goodClassCache = nil
        terminator_Extras.terminator_alerter_lastSoundLevels = nil

    end
end

cleanupListenerTbl()

-- adds something to the listener table
-- ENT:SaveSoundHint( source, valuable, emittingEnt ) is called whenever it hears anything
-- valuable is true if the sound definitely has an enemy player/npc emitting it

function terminator_Extras.RegisterListener( listener )
    if not IsValid( listener ) then return end
    if listener.term_IsListening then return end

    timer.Simple( 0, function()
        cleanupListenerTbl()

    end )

    table.insert( terminator_Extras.listeners, listener )
    listener.term_IsListening = true

    listener:CallOnRemove( "terminator_cleanupsoundlisteners", function()
        cleanupListenerTbl()

    end )
end

local function terminatorsSendSoundHint( thing, src, range, valuable )
    if not range then return end
    if not src then return end
    if range < 200 then return end -- dont waste perf on useless sounds!
    for _ = 1, 10 do
        if IsValid( thing ) and thing.GetParent and IsValid( entMeta.GetParent( thing ) ) then -- find true parent
            thing = entMeta.GetParent( thing )

        else
            break

        end
    end

    local thingTbl

    if IsValid( thing ) then
        if entMeta.IsFlagSet( thing, FL_NOTARGET ) then return end -- dont alert for stuff that doesnt want to be targeted

        thingTbl = entMeta.GetTable( thing )
        if thingTbl.usedByTerm then return end -- was recently used by a term bot, that probably caused the sound

        local last = thingTbl.term_LastSoundEmit
        local cur = CurTime()
        if last then
            local since = cur - last.time
            local uselessBlockingValuable = not last.valuable and valuable
            if since < 5 and not uselessBlockingValuable then
                local cutoff = last.range - ( since * 100 )
                if cutoff > range then return end -- this JUST created a louder sound, dont waste perf on this quiet sound

            end
        end
        thingTbl.term_LastSoundEmit = {
            time = cur,
            range = range,
            valuable = valuable,

        }
    end

    local rangeSqr = range^2

    local listeners = terminator_Extras.listeners
    local pleaseCleanup

    -- time to alert!
    for _, currTerm in ipairs( listeners ) do
        if thing == currTerm then continue end

        local termsTbl = entMeta.GetTable( currTerm )
        if not termsTbl then -- null ent
            pleaseCleanup = true
            continue

        end
        if IsValid( thing ) and termsTbl.isTerminatorHunterChummy == thingTbl.isTerminatorHunterChummy then continue end -- bots know when sounds are coming from buddies

        if vecMeta.DistToSqr( entMeta.GetPos( currTerm ), src ) > rangeSqr then continue end
        termsTbl.SaveSoundHint( currTerm, src, valuable, thing )

    end

    if pleaseCleanup then
        cleanupListenerTbl()

    end
end

local squareVarQuiet = 1.5
local squareVarLoud = 1.65

local customRanges = {
    ["weapon_pistol"] = 7000,
    ["weapon_357"] = 12000,
    ["weapon_smg1"] = 7000,
    ["weapon_ar2"] = 12000,
    ["weapon_shotgun"] = 8000,
}

hook.Add( "PostEntityFireBullets", "termalerter_firebullets", function( entity, data )
    if not listening then return end
    if not IsValid( entity ) then return end

    local range = nil
    local weap = nil
    if entity:IsNPC() or entity:IsPlayer() then
        weap = entity:GetActiveWeapon()

    end
    local customRange = nil
    if IsValid( weap ) then
        customRange = customRanges[entMeta.GetClass( weap )]

    end
    if customRange then
        range = customRange

    elseif not customRange then
        local dmg = 60
        if data.Damage > 0 then
            dmg = math.Round( data.Damage )

        end
        local num = data.Num or 1
        if num > 1 then
            num = math.Clamp( data.Num / 2, 1, math.huge )

        end

        -- bulletFire is never silent, its always gonna be used for something 'loud'
        local totalDmg = dmg * num
        range = math.Clamp( totalDmg * 200, 3000, 10000 )

    end

    local src = data.Src
    terminatorsSendSoundHint( entity, src, range, true )

end )



-- stick our fingers in emithint
sound._TermTakeover_EmitHint = sound._TermTakeover_EmitHint or sound.EmitHint
sound.EmitHint = function( ... )
    hook.Run( "Term_SoundEmitHint", ... )
    return sound._TermTakeover_EmitHint( ... )

end

hook.Add( "Term_SoundEmitHint", "termalerter_soundhint", function( hint, pos, volume, _, owner )
    if not listening then return end

    local combat = bit.band( hint, SOUND_COMBAT ) > 0
    local danger = bit.band( hint, SOUND_DANGER ) > 0

    if not combat and not danger then return end

    local radius = volume * 5 -- example, 600 to 3000 radius

    local valuable = nil
    if owner and owner:IsPlayer() then
        valuable = true
    end

    terminatorsSendSoundHint( owner, pos, radius, valuable )

end )


-- bl damage
util._TermTakeover_BlastDamage = util._TermTakeover_BlastDamage or util.BlastDamage
util.BlastDamage = function( ... )
    hook.Run( "Term_BlastDamage", ... )
    return util._TermTakeover_BlastDamage( ... )

end

hook.Add( "Term_BlastDamage", "termalerter_blastdamage", function( _, attacker, damageOrigin, damageRadius, damage )
    if not listening then return end

    local radiusComponent = damageRadius * 0.2
    local volume = math.Clamp( damage * radiusComponent, 1000, 10000 )

    terminatorsSendSoundHint( attacker, damageOrigin, volume, true )

end )


-- bl damage info
util._TermTakeover_BlastDamageInfo = util._TermTakeover_BlastDamageInfo or util.BlastDamageInfo
util.BlastDamageInfo = function( ... )
    hook.Run( "Term_BlastDamageInfo", ... )
    return util._TermTakeover_BlastDamageInfo( ... )

end

hook.Add( "Term_BlastDamageInfo", "termalerter_blastdamageinfo", function( dmg, damageOrigin, damageRadius )
    if not listening then return end

    local damage = dmg:GetDamage()
    local radiusComponent = damageRadius * 0.2
    local volume = math.Clamp( damage * radiusComponent, 1000, 10000 )

    terminatorsSendSoundHint( attacker, damageOrigin, volume, true )

end )



-- env_explosion reading
hook.Add( "OnEntityCreated", "termalerter_env_explosion", function( entity )
    if not listening then return end
    if not IsValid( entity ) then return end
    if entMeta.GetClass( entity ) ~= "env_explosion" then return end

    timer.Simple( 0, function()
        if not listening then return end

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

        terminatorsSendSoundHint( attacker, pos, volume, true )

    end )
end )

local function handleNormalSound( ent, pos, level )
    if not listening then return end
    if not pos then return end

    local squareInternal = squareVarQuiet
    if level and level >= 80 then
        squareInternal = squareVarLoud
    end

    local volume = ( level^squareInternal )
    volume = math.Clamp( volume, 5, 18000 ) -- exponential?
    --print( volume, class, soundLvl2 )

    terminatorsSendSoundHint( ent, pos, volume, false )

end

sound._TermTakeover_soundPlay = sound._TermTakeover_soundPlay or sound.Play
sound.Play = function( ... )
    hook.Run( "Term_SoundPlayHook", ... )
    return sound._TermTakeover_soundPlay( ... )
end


hook.Add( "Term_SoundPlayHook", "termalerter_soundplayhook", function( name, pos, level, _, volume )
    if not listening then return end

    if not name then return end
    if not pos then return end

    volume = volume or 1
    level = level or 75

    local volumeAdjusted = level * volume
    timer.Simple( 0, function()
        if not listening then return end
        handleNormalSound( nil, pos, volumeAdjusted, name )

    end )

end )


local string_StartsWith = string.StartWith

hook.Add( "EntityEmitSound", "termalerter_soundinfo", function( soundDat )
    if not listening then return end
    local entity = soundDat.Entity
    if not IsValid( entity ) then return end

    local class = entMeta.GetClass( entity )
    local cache = goodClassCache[class]
    if cache == false then return end -- dont spam sound info

    if cache == nil then
        local valid

        if string_StartsWith( class, "item" ) then
            valid = true

        elseif string_StartsWith( class, "prop" ) then
            valid = true

        elseif string_StartsWith( class, "player" ) then
            valid = true

        elseif string_StartsWith( class, "func" ) then
            valid = true

        elseif entity.IsNPC and entity:IsNPC() then
            valid = true

        elseif entity.IsNextBot and entity:IsNextBot() then
            valid = true

        elseif entity.IsWeapon and entity:IsWeapon() then
            valid = true

        end
        if not valid then goodClassCache[class] = false return end
        goodClassCache[class] = true

    end

    local soundLevel = soundDat.SoundLevel * soundDat.Volume
    local lastSoundLevel = lastSoundLevels[entity]
    if lastSoundLevel and soundLevel < lastSoundLevel then return end -- dont spam sound info

    timer.Simple( 0.1, function()
        if not listening then return end

        lastSoundLevels[entity] = nil
        if not IsValid( entity ) then return end

        local pos = entMeta.GetPos( entity )
        handleNormalSound( entity, pos, soundLevel, soundDat.SoundName )

    end )
end )
