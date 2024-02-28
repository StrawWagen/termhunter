function ENT:InitializeSpeaking()
    if not self.CanSpeak then return end
    self.NextSpokenLine = 0
    self.StuffToSay = {}

end

function ENT:PlaySentence( sentenceIn )
    if #self.StuffToSay >= 4 then return end -- don't add infinite stuff to say.
    if #self.StuffToSay >= 2 and math.random( 0, 100 ) >= 50 then return end
    table.insert( self.StuffToSay, sentenceIn )

end

function ENT:SpokenLinesThink()
    if not self.CanSpeak then return end
    if self.NextSpokenLine > CurTime() then return end
    if #self.StuffToSay <= 0 then return end

    local sentenceIn = table.remove( self.StuffToSay, 1 )

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


hook.Add( "terminator_engagedenemywasbad", "supercop_killedenemy", function( self, enemyLost )
    if not self.OnKilledEnemyLine then return end
    if not IsValid( enemyLost ) then return end
    if enemyLost:Health() <= 0 then
        self:OnKilledEnemyLine( enemyLost )
    end
end )