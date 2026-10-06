AddCSLuaFile()

-- bros naked

ENT.Base = "terminator_nextbot_snail_skinless"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Endoskeleton (Rusted)"
terminator_Extras.RegisterNPC( "terminator_nextbot_snail_skinlessrusty", ENT, {
    Weapons = { "weapon_terminatorfists_term" },

} )

ENT.CoroutineThresh = terminator_Extras.baseCoroutineThresh / 4

ENT.IsFodder = true
ENT.HasBrains = false
ENT.IsStupid = true

ENT.AimSpeed = 100
ENT.WalkSpeed = 50
ENT.MoveSpeed = 75
ENT.RunSpeed = 100

if CLIENT then return end

local function runAct()
    if math.random( 0, 100 ) < 25 then
        return ACT_HL2MP_RUN_FIST

    else
        return ACT_HL2MP_WALK_ZOMBIE_04

    end
end

local IdleActivity = ACT_HL2MP_IDLE_ZOMBIE
ENT.IdleActivity = IdleActivity
ENT.IdleActivityTranslations = {
    [ACT_MP_STAND_IDLE]                 = IdleActivity,
    [ACT_MP_WALK]                       = ACT_HL2MP_WALK_ZOMBIE_02,
    [ACT_MP_RUN]                        = runAct,
    [ACT_MP_CROUCH_IDLE]                = ACT_HL2MP_IDLE_CROUCH,
    [ACT_MP_CROUCHWALK]                 = ACT_HL2MP_WALK_CROUCH,
    [ACT_MP_RELOAD_STAND]               = IdleActivity + 6,
    [ACT_MP_RELOAD_CROUCH]              = IdleActivity + 7,
    [ACT_MP_JUMP]                       = ACT_HL2MP_JUMP_FIST,
    [ACT_MP_SWIM]                       = ACT_HL2MP_SWIM,
    [ACT_LAND]                          = ACT_LAND,
}

ENT.FistRangeMul = 0.9
ENT.ThrowingForceMul = 0.75

ENT.MyClassTask = {
    OnCreated = function( self, data )
        for i, matName in ipairs( self:GetMaterials() ) do
            local rusted = matName .. "_rusted"
            self:SetSubMaterial( i - 1, rusted )

        end
    end,
    Think = function( self, data )
        local lastSpark = data.lastSpark or 0

        local add = math.Rand( 3, 50 )
        add = add / math.min( self:GetIdealMoveSpeed(), 0.5 ) * 0.1
        local nextSpark = lastSpark + add

        if nextSpark > CurTime() then return end
        data.lastSpark = CurTime()

        local hitboxSetCount = self:GetHitboxSetCount()
        if not hitboxSetCount then return end -- ???

        local randomSet = math.random( 0, hitboxSetCount - 1 )

        local hitboxCount = self:GetHitBoxCount( randomSet )
        local randomHitboxId = math.random( 0, hitboxCount - 1 )

        local bone = self:GetHitBoxBone( randomHitboxId, randomSet )
        local randomBone = self:GetBonePosition( bone )

        local startPos = self:WorldSpaceCenter()
        if randomBone then
            startPos = randomBone

        end

        local Data = EffectData()
        Data:SetOrigin( startPos )
        Data:SetScale( 0.5 )
        Data:SetRadius( 0.5 )
        Data:SetMagnitude( 1 )
        Data:SetNormal( VectorRand() )
        util.Effect( "Sparks", Data )

        self:EmitSound( "physics/metal/metal_box_strain" .. math.random( 1, 4 ) .. ".wav", math.random( 60, 70 ), math.random( 110, 140 ), CHAN_ITEM )

    end,
}

ENT.TERM_WEAPON_PROFICIENCY = WEAPON_PROFICIENCY_POOR

function ENT:AdditionalSpreadOverride( deg )
    deg = deg + 22.5
    return deg

end

function ENT:EnemyIsLethalInMelee()
    return -- no fear

end

function ENT:inSeriousDanger()
    return false -- no fear

end

function ENT:EnemyIsUnkillable()
    return false

end
