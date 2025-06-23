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

end