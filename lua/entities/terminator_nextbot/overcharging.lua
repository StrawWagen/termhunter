
local math = math

function ENT:CanOvercharge()
    if self.terminator_OverCharged then return false end
    if self.DoMetallicDamage then return true end
    if self:GetMaxHealth() < terminator_Extras.healthDefault * 0.5 then return false end
    return true

end

local fxColor = Angle( 102, 153, 255 )

function ENT:Overcharge()
    self:EmitSound( "ambient/levels/labs/electric_explosion1.wav", 100, 80 )

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

    local timerName = "term_overchargedlightning_" .. self:GetCreationID()
    timer.Create( timerName, 0.1, 0, function()
        if not IsValid( self ) then timer.Remove( timerName ) return end
        if self:Health() <= 0 then timer.Remove( timerName ) return end

        if math.random( 0, 100 ) > 25 then return end
        if self.IsSilentStepping and self:IsSilentStepping() then return end

        terminator_Extras.EmitWeakLightningArcFrom( self )

    end )
end

local zaps = {
    "ambient/energy/zap1.wav",
    "ambient/energy/zap2.wav",
    "ambient/energy/zap3.wav",
    "ambient/energy/zap7.wav",
    "ambient/energy/zap8.wav",
}


function terminator_Extras.EmitWeakLightningArcFrom( ent, scale, hitCallback )
    local hitboxSetCount = ent:GetHitboxSetCount()
    if not hitboxSetCount then return end -- ???

    local randomSet = math.random( 0, hitboxSetCount - 1 )

    local hitboxCount = ent:GetHitBoxCount( randomSet )
    local randomHitboxId = math.random( 0, hitboxCount - 1 )

    local bone = ent:GetHitBoxBone( randomHitboxId, randomSet )
    local randomBone = ent:GetBonePosition( bone )

    local startPos = ent:WorldSpaceCenter()
    if randomBone then
        startPos = randomBone

    end

    local lightningScale = scale or math.Rand( 0.5, 1.5 )

    -- LOUD spark sound, let people know this is here
    ent:EmitSound( zaps[math.random( 1, #zaps )], 80, math.random( 100, 120 ), math.Rand( 0.8, 1 ) * lightningScale, CHAN_ITEM )

    local endingDir = VectorRand()
    endingDir.z = math.min( endingDir.z, math.Rand( -1, 0.25 ) ) -- mostly down
    endingDir:Normalize()
    local endPos = startPos + endingDir * math.Rand( 128, 256 )

    local startingDir = VectorRand()
    startingDir.z = math.max( startingDir.z, 0.5 ) -- always up
    startingDir:Normalize()

    -- ignite entities that might be in the path of the lightning
    if lightningScale >= math.Rand( 0.9, 1.1 ) then
        local igniteTr = {
            start = startPos,
            endpos = endPos,
            filter = ent,
            mask = MASK_SOLID,
        }
        local igniteRes = util.TraceLine( igniteTr )
        if IsValid( igniteRes.Entity ) then
            if hitCallback then
                hitCallback( ent, igniteRes.Entity )

            else
                igniteRes.Entity:Ignite( lightningScale * math.random( 1, 2 ), 0 )

            end
        end
    end

    local fx = EffectData()
        fx:SetOrigin( startPos )
        fx:SetStart( endPos )
        fx:SetNormal( startingDir ) -- starting direction
        fx:SetScale( lightningScale ) -- beam scale
        fx:SetMagnitude( math.random( 4, 12 ) ) -- arc segs
        fx:SetAngles( fxColor ) -- color
        fx:SetRadius( 20 ) -- arc pos jitter
        fx:SetDamageType( 2 ) -- branch count
        fx:SetEntity( ent ) -- parent entity
        fx:SetFlags( 0 ) -- don't disable anything
    util.Effect( "eff_term_goodarc", fx )

    local spark = EffectData()
        spark:SetOrigin( startPos )
        spark:SetNormal( -startingDir )
        spark:SetMagnitude( 1 )
        spark:SetScale( 1 )
        spark:SetRadius( 3 )
    util.Effect( "Sparks", spark )

end