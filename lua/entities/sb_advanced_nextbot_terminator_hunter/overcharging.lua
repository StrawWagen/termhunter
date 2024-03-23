function ENT:Overcharge()
    self.terminator_OverCharged = true
    self.WalkSpeed = 130
    self.MoveSpeed = 300
    self.RunSpeed = 550 -- bit faster than players... in a straight line
    self.AccelerationSpeed = 3000
    self.ShockDamageImmune = true
    self.FistDamageMul = 4
    self.ThrowingForceMul = 1000

    self:ReallyAnger( 999999 )

end