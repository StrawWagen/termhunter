
local entMeta = FindMetaTable( "Entity" )
local vecMeta = FindMetaTable( "Vector" )
local angMeta = FindMetaTable( "Angle" )
local locoMeta = FindMetaTable( "CLuaLocomotion" )

local TrFilterNoSelf = terminator_Extras.TrFilterNoSelf

--[[
    Two footstep types
    1. Human footsteps, tries to match player footstep behaviour
    2. Custom footsteps, just plays a custom sound with no laggy logic

    Two footstep timing types
    1. Timed, plays a sound every X seconds, adjusted by speed.
    2. Perfect footsteps, plays a sound when the foot is actually stepping, based on the angle of the foot.
]]


-- CUSTOM FOOTSTEP SOUNDS PREFAB, say you just want footsteps to play your custom sound, not player footsteps
-- ENT.Term_FootstepMode = "custom" -- set this to custom so the bot checks the below tbl, supported modes, "human" and "custom"
--[[ ENT.Term_FootstepSound = { -- sound to play when the bot steps
    path = "npc/zombie_poison/pz_left_foot1.wav",
    pitch = 85, -- pitch of the sound
    volume = 1, -- volume of the sound
    lvl = 80, -- lvl of the sound
    chan = CHAN_STATIC, -- channel to play the sound on, default is CHAN_AUTO
}
ENT.Term_FootstepSoundWalking = { -- sound to play when the bot is walking, if not set, uses Term_FootstepSound
    path = "npc/zombie/foot3.wav",
    pitch = 110,
    volume = 1,
    lvl = 73,
    chan = CHAN_STATIC, -- channel to play the sound on, default is CHAN_AUTO
} --]]

-- end prefab


-- PERFECT STEPPING PREFAB, say you have a supercop like enemy, a smart showpiece bot that people are gonna be looking at
-- ENT.Term_FootstepTiming = "perfect" -- can be "timed" or "perfect"
-- "timed" means they just play on a timer, and a bit faster when the bot moves faster
-- "perfect" actually checks the foot bone's positions, see below

-- REQUIRED
-- ENT.PerfectFootsteps_FeetBones = { "ValveBiped.Bip01_L_Foot", "ValveBiped.Bip01_R_Foot" } -- feet bone names.
-- this is the default for most playermodels, but custom models may have different names, so you can override it

-- ENT.PerfectFootsteps_SteppingCriteria = -0.8 -- how much the foot's forward vector must be facing down to be considered stepping
-- trial and error, too far below -0.8, and the sounds will miss some steps, too high above -0.8, and the sounds will play too early, or when the bot is not stepping
-- different models have different animations, so that's why it's customisable

-- optional
-- ENT.PerfectFootsteps_Up = Vector( 0, 0, 1 ) -- dont use this unless you know what vector:Dot() does, think enemies that walk on walls or something idk

-- end prefab


local defaultUp = Vector( 0, 0, 1 )
local defaultSteppingCriteria = -0.8 -- should work on default playermodels

--[[------------------------------------
    Name: NEXTBOT:ProcessFootsteps
    Desc: Processes footsteps
    Args: myTbl - Optimisation
    Returns: None
--]]------------------------------------
function ENT:ProcessFootsteps( myTbl )
    if not locoMeta.IsOnGround( myTbl.loco ) then return end

    local curSpeed = myTbl.GetCurrentSpeed( self )
    local stepTiming = myTbl.Term_FootstepTiming or "timed" -- "timed" or "perfect"

    if stepTiming == "timed" then -- cheap timed footsteps
        local time = myTbl.m_FootstepTime
        local nextStepTime = myTbl.GetFootstepSoundTime( self, myTbl, curSpeed )
        local imWalkin = curSpeed > myTbl.WalkSpeed * 0.5
        local timeForAStep = CurTime() - time >= nextStepTime / 1000

        if timeForAStep and imWalkin then
            myTbl.MakeFootstepSound( self, myTbl, 1, 1, entMeta.GetPos( self ), curSpeed )

        end

    elseif stepTiming == "perfect" then -- perfect stepping, for showpiece NPCs, boss npcs. see comments above
        local feetBones = myTbl.PerfectFootsteps_FeetBones
        if not feetBones then
            ErrorNoHaltWithStack( "Perfect footstepping enabled without defined ENT.PerfectFootsteps_FeetBones????" )

        end

        local oldStepping = myTbl.perfect_OldStepping or {}
        local currStepping = {}

        local dotVec = myTbl.PerfectFootsteps_Up or defaultUp
        local criteria = myTbl.PerfectFootsteps_SteppingCriteria or defaultSteppingCriteria

        for _, foot in ipairs( feetBones ) do
            local footBone = entMeta.LookupBone( self, foot )
            if not footBone then
                myTbl.Term_FootstepTiming = "timed" -- no err spam pls
                ErrorNoHaltWithStack( "Perfect footstepping ENT.PerfectFootsteps_FeetBones tbl, with invalid bone: " .. foot .. " for " .. self:GetClass() .. "\nA custom model could be causing this!" )
                return

            end
            local footPos, footAng = entMeta.GetBonePosition( self, entMeta.LookupBone( self, foot ) )
            local dot = vecMeta.Dot( angMeta.Forward( footAng ), dotVec )

            currStepping[foot] = dot < criteria
            if currStepping[foot] and not oldStepping[foot] then -- only step, when the foot goes from outside the :Dot criteria, into it
                myTbl.MakeFootstepSound( self, myTbl, 1, 1, footPos, curSpeed )

            end
        end

        myTbl.perfect_OldStepping = currStepping

    end
end

--[[------------------------------------
    Name: NEXTBOT:GetFootstepSoundTime
    Desc: Returns the time between footsteps, adjusted by speed and crouching
    Args: myTbl - Optimisation
    Returns: time in milliseconds
--]]------------------------------------
function ENT:GetFootstepSoundTime( myTbl, curSpeed )
    -- Base time between footsteps in milliseconds - represents the default interval when standing still
    local time = myTbl.Term_BaseMsBetweenSteps

    -- Calculate how much to reduce the time between steps based on movement speed
    -- Faster movement = smaller intervals between footsteps = more frequent stepping sounds
    local speedAdjustment = curSpeed * myTbl.Term_FootstepMsReductionPerUnitSpeed
    time = time - speedAdjustment

    if myTbl.IsCrouching( self ) then
        time = time + 100

    end

    return time

end

local function asNum( varOrTbl )
    if isnumber( varOrTbl ) then
        return varOrTbl

    elseif istable( varOrTbl ) and #varOrTbl == 1 then
        return varOrTbl[1]

    elseif istable( varOrTbl ) and #varOrTbl == 2 then
        return math.random( varOrTbl[1], varOrTbl[2] )

    end

    return nil

end

-- stub
function ENT:AdditionalFootstep( _footPos, _foot, _stepSound, _volume, _filter )
    -- this is a stub for custom footsteps, can be overridden in derived classes
    -- if it returns true, blocks default sound playing
end

local downFive = Vector( 0, 0, -5 )
local sndFlags = bit.bor( SND_CHANGE_PITCH, SND_CHANGE_VOL )

--[[------------------------------------
    Name: ENT:MakeFootstepSound
    Desc: Plays a footstep sound based on the surface and speed
          You can override this entire function but i'd advise against it
    Arg1: myTbl - Optimisation table
    Arg2: volumeMul - Multiplier for the volume of the sound
    Arg3: soundWeightAdj - Adjusts the sound level and pitch, set higher if you want the sound to be "heavier"
    Arg4: footPos - Position of the foot, defaults to entity position
    Arg5: curSpeed - Current speed of the entity
    Returns: None
--]]------------------------------------

function ENT:MakeFootstepSound( myTbl, volumeMul, soundWeightAdj, footPos, curSpeed )
    if myTbl and isnumber( myTbl ) then
        volumeMul = myTbl
        myTbl = entMeta.GetTable( self )

    end
    footPos = footPos or entMeta.GetPos( self )
    curSpeed = curSpeed or myTbl.GetCurrentSpeed( self )
    volumeMul = volumeMul or 1
    soundWeightAdj = soundWeightAdj or 1

    local stepMode = myTbl.Term_FootstepMode or "human"

    local foot = myTbl.m_FootstepFoot
    myTbl.m_FootstepFoot = not foot
    myTbl.m_FootstepTime = CurTime()

    local stepSurface
    local stepSound

    local lvl = 80
    local pitch = 100
    local volume = 1
    local chan = CHAN_AUTO
    local walking = curSpeed <= myTbl.MoveSpeed

    if stepMode == "human" then
        local tr = util.TraceEntity( {
            start = footPos,
            endpos = footPos + downFive,
            filter = TrFilterNoSelf( self ),
            mask = self:GetSolidMask(),
            collisiongroup = self:GetCollisionGroup(),
        }, self )

        stepSurface = util.GetSurfaceData( tr.SurfaceProps )
        stepSound = stepSurface and ( foot and stepSurface.stepRightSound or stepSurface.stepLeftSound )

        if stepSurface then
            local stepMat = stepSurface.material

            if stepMat == MAT_CONCRETE then
                volume = walking and 0.8 or 1

            elseif stepMat == MAT_METAL then
                volume = walking and 0.8 or 1

            elseif stepMat == MAT_DIRT then
                volume = walking and 0.4 or 0.6

            elseif stepMat == MAT_VENT then
                volume = 1 -- HES IN THE VENTS!!!!!!

            elseif stepMat == MAT_GRATE then
                volume = walking and 0.6 or 0.8

            elseif stepMat == MAT_TILE then
                volume = walking and 0.8 or 1

            elseif stepMat == MAT_SLOSH then
                volume = walking and 0.8 or 1

            end

        end
    elseif stepMode == "custom" then
        if walking and myTbl.Term_FootstepSoundWalking then
            stepSound = myTbl.Term_FootstepSoundWalking

        else
            stepSound = myTbl.Term_FootstepSound -- can be string "example.wav", or a table with .path, .pitch, .volume, .lvl keys, or a table of tables with .path, etc, keys

        end
        if istable( stepSound ) and not stepSound.path then
            if #stepSound <= 2 then
                stepSound = stepSound[foot and 2 or 1] -- if just 2 sounds, pick one based on foot, first one is left foot, second is right foot

            else
                stepSound = stepSound[math.random( 1, #stepSound )] -- more than two sounds, just pick a random one

            end
        end
        if istable( stepSound ) then
            stepSound = stepSound.path or nil
            pitch = asNum( stepSound.pitch ) or pitch
            volume = asNum( stepSound.volume ) or volume
            lvl = asNum( stepSound.lvl ) or lvl
            chan = stepSound.chan or CHAN_AUTO

        end
    end

    volume = volume * volumeMul

    local filter
    if myTbl.Term_FootstepIgnorePAS then
        filter = RecipientFilter()
        filter:AddAllPlayers()

    end

    if not stepSound then return end
    if self:AdditionalFootstep( footPos, foot, stepSound, volume, filter ) then return end

    if self.Term_FootstepShake then
        local shakeData = self.Term_FootstepShake
        util.ScreenShake( footPos, shakeData.amplitude * soundWeightAdj, shakeData.frequency / soundWeightAdj, shakeData.duration * soundWeightAdj, shakeData.radius * soundWeightAdj )

    end

    if self.FootstepClomping then
        local clompingLvl = 86
        if self:GetCurrentSpeed() < self.RunSpeed then
            clompingLvl = 76

        end
        local lvlShift = self.term_SoundLevelShift
        if lvlShift then
            clompingLvl = clompingLvl + lvlShift

        end
        clompingLvl = clompingLvl * soundWeightAdj

        local pit = math.random( 20, 30 )
        local pitShift = self.term_SoundPitchShift
        if pitShift then
            pit = pit + pitShift

        end
        pit = pit / soundWeightAdj

        self:EmitSound( "npc/zombie_poison/pz_left_foot1.wav", clompingLvl, pit, volume / 1.5, CHAN_STATIC )

    end

    self:EmitSound( stepSound, lvl * soundWeightAdj, pitch * soundWeightAdj, volume, chan, sndFlags, nil, filter )

end