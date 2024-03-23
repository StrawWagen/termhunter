function ENT:InitializeSpeaking()
    if not self.CanSpeak then return end
    self.NextSpokenLine = 0
    self.StuffToSay = {}

end

function ENT:Term_PlaySentence( sentenceIn, conditionFunc )
    if conditionFunc then
        table.insert( self.StuffToSay, { sent = sentenceIn, cond = conditionFunc } )

    else
        if #self.StuffToSay >= 4 then return end -- don't add infinite stuff to say.
        if #self.StuffToSay >= 2 and math.random( 0, 100 ) >= 50 then return end
        table.insert( self.StuffToSay, { sent = sentenceIn } )

    end

end

function ENT:SpokenLinesThink()
    if not self.CanSpeak then return end
    if self.NextSpokenLine > CurTime() then return end
    if #self.StuffToSay <= 0 then return end

    local sentenceDat = table.remove( self.StuffToSay, 1 )

    local conditionFunc = sentenceDat.conditionFunc
    if isfunction( conditionFunc ) and not conditionFunc( self ) then return end

    local sentenceIn = sentenceDat.sent
    local sentence

    if istable( sentenceIn ) then
        sentence = sentenceIn[ math.random( 1, #sentenceIn ) ]

    elseif isstring( sentenceIn ) then
        sentence = sentenceIn

    end

    if not sentence then return end
    if isstring( self.lastSpokenSentence ) and ( sentence == self.lastSpokenSentence ) then return end

    self.lastSpokenSentence = sentence

    EmitSentence( sentence, self:GetShootPos(), self:EntIndex(), CHAN_AUTO, 1, 80, 0, 100 )

    local additional = math.random( 10, 15 ) / 10

    local duration = SentenceDuration( sentence ) or 1
    self.NextSpokenLine = CurTime() + ( duration + additional )

end

function ENT:SpeakLine( line )
    self:EmitSound( line, 85, 100, 1, CHAN_AUTO )

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