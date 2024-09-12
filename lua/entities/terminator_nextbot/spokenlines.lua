function ENT:InitializeSpeaking()
    if not self.CanSpeak then return end
    self.NextTermSpeak = 0
    self.StuffToSay = {}

end

local function nextSpeakWhenSoundIsOver( ent, path )
    local additional = math.random( 10, 15 ) / 25

    local duration = SoundDuration( path ) or 1
    if string.EndsWith( path, ".mp3" ) and duration == 60 then --bug
        duration = 5

    end
    ent.NextTermSpeak = CurTime() + ( duration + additional )

end

local sndFlags = bit.bor( SND_CHANGE_PITCH, SND_CHANGE_VOL )

function ENT:SpokenLinesThink()
    if not self.CanSpeak then return end
    local myTbl = self:GetTable()

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

            local pitShift = myTbl.term_SoundPitchShift or 0
            local lvlShift = myTbl.term_SoundLevelShift or 0
            myTbl.term_IdleLoopingSound = CreateSound( self, pickedSound )
            myTbl.term_IdleLoopingSound:PlayEx( 0, math.random( 95, 105 ) + pitShift )
            myTbl.term_IdleLoopingSound:SetSoundLevel( myTbl.term_IdleLoopingSound:GetSoundLevel() + lvlShift )
            myTbl.term_IdleLoopingSound:ChangeVolume( 1, math.Rand( 0.45, 0.75 ) )
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

        local pitShift = myTbl.term_SoundPitchShift or 0
        local lvlShift = myTbl.term_SoundLevelShift or 0
        EmitSentence( sentence, self:GetShootPos(), self:EntIndex(), CHAN_AUTO, 1, 80 + lvlShift, 0, 100 + pitShift )

        local additional = math.random( 10, 15 ) / 50

        local duration = SentenceDuration( sentence ) or 1
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

        local pitShift = myTbl.term_SoundPitchShift or 0
        local lvlShift = myTbl.term_SoundLevelShift or 0
        if isfunction( pitShift ) then
            pitShift = pitShift( self )

        end
        if isfunction( lvlShift ) then
            lvlShift = lvlShift( self )

        end
        self:EmitSound( path, 76 + lvlShift, 100 + pitShift, 1, CHAN_VOICE, sndFlags )

        nextSpeakWhenSoundIsOver( self, path )
        return

    end
end

function ENT:Term_SpeakSoundNow( pathIn, specificPitchShift )
    specificPitchShift = specificPitchShift or 0

    local pitShift = myTbl.term_SoundPitchShift or 0
    local lvlShift = myTbl.term_SoundLevelShift or 0
    if isfunction( pitShift ) then
        pitShift = pitShift( self )

    end
    if isfunction( lvlShift ) then
        lvlShift = lvlShift( self )

    end
    self:EmitSound( pathIn, 76 + lvlShift, 100 + pitShift + specificPitchShift, 1, CHAN_VOICE, sndFlags )
    nextSpeakWhenSoundIsOver( self, pathIn )

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

function ENT:Term_SpeakSound( pathIn, conditionFunc )
    if conditionFunc then
        table.insert( self.StuffToSay, { path = pathIn, conditionFunc = conditionFunc } )

    else
        if #self.StuffToSay >= 4 then return end -- don't add infinite stuff to say.
        if #self.StuffToSay >= 2 and math.random( 0, 100 ) >= 50 then return end
        table.insert( self.StuffToSay, { path = pathIn } )

    end
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