
-- ENT.term_SoundPitchShift
-- ENT.term_SoundLevelShift
-- ENT.term_SoundDSP

local CurTime = CurTime

-- helper function to get a number value from various types
local function asNumber( ent, entsTbl, var )
    if not var then return 0 end
    if isfunction( var ) then return var( ent, entsTbl ) end

    return var

end

function ENT:InitializeSpeaking()
    if not self.CanSpeak then return end
    self.NextTermSpeak = 0
    self.StuffToSay = {}

end

local function nextSpeakWhenSoundIsOver( ent, path, pitch )
    local duration = SoundDuration( path ) or 1 -- FOLLOW GMOD WIKI FOR ACCURATE MP3 DURATIONS! SAVE WITH CONSTANT BITRATE!
    local durDivisor = pitch / 100
    duration = duration / durDivisor
    ent.NextTermSpeak = CurTime() + duration

    return duration

end

local sndFlags = bit.bor( SND_CHANGE_PITCH, SND_CHANGE_VOL )

function ENT:SpokenLinesThink( myTbl )
    if not myTbl.CanSpeak then return end

    if myTbl.NextTermSpeak > CurTime() then return end
    local noLines = #myTbl.StuffToSay <= 0
    if myTbl.AlwaysPlayLooping or noLines then -- play looping idle/angry sounds
        local loopingSounds = nil
        local oldState = myTbl.term_OldLoopingSoundState
        local currState = nil
        if self:IsAngry() then
            loopingSounds = myTbl.AngryLoopingSounds
            currState = 1

        else
            loopingSounds = myTbl.IdleLoopingSounds
            currState = 0

        end
        if not loopingSounds or #loopingSounds <= 0 then return end

        if oldState ~= currState and myTbl.term_IdleLoopingSound then
            myTbl.term_OldLoopingSoundState = currState
            myTbl.term_IdleLoopingSound:Stop()
            myTbl.term_IdleLoopingSound = nil

        end

        if myTbl.term_IdleLoopingSound and myTbl.term_RestartIdleSound and myTbl.term_RestartIdleSound < CurTime() then
            myTbl.term_IdleLoopingSound:Stop()
            myTbl.term_IdleLoopingSound = nil

        end

        if not myTbl.term_IdleLoopingSound or not myTbl.term_IdleLoopingSound:IsPlaying() then
            if myTbl.term_IdleLoopingSound then
                myTbl.term_IdleLoopingSound:Stop()
                myTbl.term_IdleLoopingSound = nil

            end
            local pickedSound = loopingSounds[ math.random( 1, #loopingSounds ) ]

            local pitShift = asNumber( self, myTbl, myTbl.term_SoundPitchShift )
            local lvlShift = asNumber( self, myTbl, myTbl.term_SoundLevelShift )
            local dsp = asNumber( self, myTbl, myTbl.term_SoundDSP )
            local term_IdleLoopingSound = CreateSound( self, pickedSound )
            myTbl.term_IdleLoopingSound = term_IdleLoopingSound

            term_IdleLoopingSound:PlayEx( 0, math.random( 95, 105 ) + pitShift )
            term_IdleLoopingSound:SetSoundLevel( term_IdleLoopingSound:GetSoundLevel() + lvlShift )
            term_IdleLoopingSound:ChangeVolume( 1, math.Rand( 0.45, 0.75 ) )

            if dsp ~= 0 then
                term_IdleLoopingSound:SetDSP( dsp )

            end

            local duration = SoundDuration( pickedSound )
            if string.find( string.lower( pickedSound ), "loop" ) then
                duration = duration * math.random( 2, 4 )

            end
            myTbl.term_RestartIdleSound = CurTime() + duration
            self:CallOnRemove( "term_cleanupidlesound", function( ent )
                if not ent.term_IdleLoopingSound then return end
                ent.term_IdleLoopingSound:Stop()
                ent.term_IdleLoopingSound = nil

            end )
        end
    end

    if noLines then return end

    local speakDat = table.remove( myTbl.StuffToSay, 1 )

    local conditionFunc = speakDat.conditionFunc
    if isfunction( conditionFunc ) and not conditionFunc( self ) then return end

    local sentenceIn = speakDat.sent
    if sentenceIn then
        local sentence

        if istable( sentenceIn ) then
            sentence = sentenceIn[ math.random( 1, #sentenceIn ) ]

        elseif isstring( sentenceIn ) then
            sentence = sentenceIn

        end

        if not sentence then return end
        if isstring( myTbl.lastSpokenSentence ) and ( sentence == myTbl.lastSpokenSentence ) then return end

        if myTbl.term_IdleLoopingSound and not myTbl.AlwaysPlayLooping then
            myTbl.term_IdleLoopingSound:Stop()
            myTbl.term_IdleLoopingSound = nil

        end

        myTbl.lastSpokenSentence = sentence

        local pitShift = asNumber( self, myTbl, myTbl.term_SoundPitchShift )
        local lvlShift = asNumber( self, myTbl, myTbl.term_SoundLevelShift )
        -- EmitSentence doesnt take dsp

        local pitch = 100 + pitShift
        EmitSentence( sentence, self:GetShootPos(), self:EntIndex(), CHAN_VOICE, 1, 80 + lvlShift, SND_NOFLAGS, pitch )

        local additional = math.random( 10, 15 ) / 50

        local duration = SentenceDuration( sentence ) or 1
        local durDivisor = pitch / 100
        duration = duration / durDivisor
        myTbl.NextTermSpeak = CurTime() + ( duration + additional )
        return

    end
    local pathIn = speakDat.path
    if pathIn then
        local path

        if istable( pathIn ) then
            path = pathIn[ math.random( 1, #pathIn ) ]

        elseif isstring( pathIn ) then
            path = pathIn

        end

        if not path then return end
        if isstring( myTbl.lastSpokenSound ) and ( sentence == myTbl.lastSpokenSound ) then return end

        if myTbl.term_IdleLoopingSound and not myTbl.AlwaysPlayLooping then
            myTbl.term_IdleLoopingSound:Stop()
            myTbl.term_IdleLoopingSound = nil

        end

        myTbl.lastSpokenSound = path

        local pitShift = asNumber( self, myTbl, myTbl.term_SoundPitchShift )
        local lvlShift = asNumber( self, myTbl, myTbl.term_SoundLevelShift )
        local dsp = asNumber( self, myTbl, myTbl.term_SoundDSP )

        local pitch = 100 + pitShift

        self:EmitSound( path, 76 + lvlShift, pitch, 1, CHAN_VOICE, sndFlags, dsp )

        nextSpeakWhenSoundIsOver( self, path, pitch )
        return

    end
end

function ENT:Term_SpeakSoundNow( pathIn, specificPitchShift )
    specificPitchShift = specificPitchShift or 0

    local myTbl = self:GetTable()
    local pitShift = asNumber( self, myTbl, myTbl.term_SoundPitchShift )
    local lvlShift = asNumber( self, myTbl, myTbl.term_SoundLevelShift )
    local dsp = asNumber( self, myTbl, myTbl.term_SoundDSP )

    if istable( pathIn ) then
        pathIn = pathIn[ math.random( 1, #pathIn ) ]

    end

    local pitch = 100 + pitShift + specificPitchShift

    self:EmitSound( pathIn, 76 + lvlShift, pitch, 1, CHAN_VOICE, sndFlags, dsp )
    return nextSpeakWhenSoundIsOver( self, pathIn, pitch )

end

-- puts line on a table of other lines that bot sifts through, will never overwrite existing lines.
function ENT:Term_SpeakSound( pathIn, conditionFunc )
    if conditionFunc then
        table.insert( self.StuffToSay, { path = pathIn, conditionFunc = conditionFunc } )

    else
        if #self.StuffToSay >= 4 then return end -- don't add infinite stuff to say.
        if #self.StuffToSay >= 2 and math.random( 0, 100 ) >= 50 then return end
        table.insert( self.StuffToSay, { path = pathIn } )

    end
end

-- Immediately plays a sentence, bypassing StuffToSay queue
function ENT:Term_SpeakSentenceNow( sentenceIn, specificPitchShift )
    specificPitchShift = specificPitchShift or 0

    local myTbl = self:GetTable()
    local pitShift = asNumber( self, myTbl, myTbl.term_SoundPitchShift )
    local lvlShift = asNumber( self, myTbl, myTbl.term_SoundLevelShift )

    if istable( sentenceIn ) then
        sentenceIn = sentenceIn[ math.random( 1, #sentenceIn ) ]
    end

    local pitch = 100 + pitShift + specificPitchShift

    EmitSentence( sentenceIn, self:GetShootPos(), self:EntIndex(), CHAN_VOICE, 1, 80 + lvlShift, SND_NOFLAGS, pitch )
    local additional = math.random( 10, 15 ) / 50
    local duration = SentenceDuration( sentenceIn ) or 1
    local durDivisor = pitch / 100
    duration = duration / durDivisor
    myTbl.NextTermSpeak = CurTime() + ( duration + additional )
    return duration

end

function ENT:Term_SpeakSentence( sentenceIn, conditionFunc )
    if conditionFunc then
        table.insert( self.StuffToSay, { sent = sentenceIn, conditionFunc = conditionFunc } )

    else
        if #self.StuffToSay >= 4 then return end -- don't add infinite stuff to say.
        if #self.StuffToSay >= 2 and math.random( 0, 100 ) >= 50 then return end
        table.insert( self.StuffToSay, { sent = sentenceIn } )

    end
end

function ENT:Term_ClearStuffToSay()
    self.StuffToSay = {}
    self.NextTermSpeak = 0

end

function ENT:Term_DontSpeakFor( time )
    self.NextTermSpeak = CurTime() + time

end

hook.Add( "PlayerDeath", "terminator_killedenemy", function( _, _, killer )
    if not killer.OnKilledPlayerEnemyLine then return end
    killer.terminator_KilledPlayer = true

end )

hook.Add( "terminator_engagedenemywasbad", "terminator_killedenemy", function( self, enemyLost )
    if not self.OnKilledGenericEnemyLine then return end
    if not IsValid( enemyLost ) then return end
    if enemyLost:Health() <= 0 then
        if self.terminator_KilledPlayer and self.OnKilledPlayerEnemyLine then
            self.terminator_KilledPlayer = nil
            self:OnKilledPlayerEnemyLine( enemyLost )

        else
            self:OnKilledGenericEnemyLine( enemyLost )

        end
    end
end )