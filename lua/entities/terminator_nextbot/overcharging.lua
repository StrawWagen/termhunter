function ENT:Overcharge()
    self.terminator_OverCharged = true
    self.glee_InterestingHunter = true

    self.WalkSpeed = math.max( self.WalkSpeed * 1.25, 130 )
    self.MoveSpeed = math.max( self.MoveSpeed * 1.25, 300 )
    self.RunSpeed = math.max( self.RunSpeed * 1.40, 550 )
    self.AccelerationSpeed = math.max( self.AccelerationSpeed * 1.40, 3000 )
    self.FistDamageMul = math.max( self.FistDamageMul * 2, 4 )
    self.ThrowingForceMul = math.max( self.ThrowingForceMul * 10, 25 )

    self.ShockDamageImmune = self.DoMetallicDamage

    self:ReallyAnger( 999999 )

    local center = self:WorldSpaceCenter()

    for _ = 1, 8 do
        local startPos = center + VectorRand() * 20
        local endPos = center + VectorRand() * 80

        local fx = EffectData()
        fx:SetStart( startPos )
        fx:SetOrigin( endPos )
        fx:SetScale( 1.5 )
        fx:SetMagnitude( 6 )
        fx:SetRadius( 20 )
        fx:SetNormal( Vector( 0.4, 0.6, 1 ) )
        fx:SetDamageType( 2 )
        fx:SetEntity( self )
        fx:SetFlags( 0 )
        util.Effect( "eff_term_goodarc", fx )
    end
end
