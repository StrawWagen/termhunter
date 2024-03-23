
local MEMORY_WEAPONIZEDNPC = 32

local IsValid = IsValid

function ENT:EntShootPos( ent, random )
    local hitboxes = {}
    if not IsValid( ent ) then return end
    local sets = ent:GetHitboxSetCount()

    local isCrouchingPlayer = ent:IsPlayer() and ent:Crouching()

    if not isCrouchingPlayer and sets then
        for i = 0, sets - 1 do
            for j = 0,ent:GetHitBoxCount( i ) - 1 do
                local group = ent:GetHitBoxHitGroup( j, i )

                hitboxes[group] = hitboxes[group] or {}
                hitboxes[group][#hitboxes[group] + 1] = { ent:GetHitBoxBone( j, i ), ent:GetHitBoxBounds( j, i ) }
            end
        end

        local data

        if hitboxes[HITGROUP_HEAD] then
            data = hitboxes[HITGROUP_HEAD][ random and math.random( #hitboxes[HITGROUP_HEAD] ) or 1 ]
        elseif hitboxes[HITGROUP_CHEST] then
            data = hitboxes[HITGROUP_CHEST][ random and math.random( #hitboxes[HITGROUP_CHEST] ) or 1 ]
        elseif hitboxes[HITGROUP_GENERIC] then
            data = hitboxes[HITGROUP_GENERIC][ random and math.random( #hitboxes[HITGROUP_GENERIC] ) or 1 ]
        end

        if data then
            local bonem = ent:GetBoneMatrix( data[1] )
            local theCenter = data[2] + ( data[3] - data[2] ) / 2

            local pos = LocalToWorld( theCenter, angle_zero, bonem:GetTranslation(), bonem:GetAngles() )
            return pos
        end
    end

    --debugoverlay.Cross( ent:WorldSpaceCenter(), 5, 10, Color( 255,255,255 ), true )

    return ent:WorldSpaceCenter()
end


local standingOffset = Vector( 0, 0, 64 )
local crouchingOffset = Vector( 0, 0, 20 )
-- if alpha is below this, start the seeing calcs
local maxSeen = 150

local function shouldNotSeeEnemy( me, enemy )
    if not enemy.GetColor then return end

    local color = enemy:GetColor()
    local a = color.a
    if not a then return end
    if a == 255 then return end -- dont waste any more performance
    if a > maxSeen then return end
    if not me:CanSeePosition( enemy ) then return end
    if enemy:IsOnFire() then return end -- they are visible!

    local seen = math.abs( a - maxSeen )
    local enemDistSqr = me:GetPos():DistToSqr( enemy:GetPos() )

    local weapBite = 0
    local weap = nil
    if enemy.GetActiveWeapon then
        weap = enemy:GetActiveWeapon()
    end

    if weap and weap.GetHoldType and weap:GetHoldType() ~= "normal" then
        weapBite = 80
    end

    if enemy:FlashlightIsOn() or enemy.glee_Thirdperson_Flashlight then
        weapBite = weapBite + 80

    end

    local getEnemyResult = me:GetEnemy()
    local isAnOldEnemy = getEnemyResult == enemy
    local oldEnemyThatISee = isAnOldEnemy and me.IsSeeEnemy
    local mimicThatDidntMove = nil

    local doRandomSuspicious = nil
    local investigateRadius = nil

    local mimicBite = 0
    if enemy.gleeIsMimic then

        local lastPos = me:GetLastEnemyPosition( enemy )
        if lastPos and me:Visible( enemy ) then
            mimicThatDidntMove = lastPos:DistToSqr( enemy:GetPos() ) < 300^2

        end

        local velLenSqr = enemy:GetVelocity():LengthSqr()
        local theMimicPropOnTop = enemy.theMimicPropOnTop
        local currPos = theMimicPropOnTop:GetPos()
        local oldPos = theMimicPropOnTop.terminator_OldSpottedPos or currPos
        theMimicPropOnTop.terminator_OldSpottedPos = currPos

        if velLenSqr > 75^2 or oldEnemyThatISee then
            -- hey, why is that moving....
            mimicBite = mimicBite + 150

        elseif velLenSqr > 40^2 then
            mimicBite = mimicBite + 50
            doRandomSuspicious = true
            investigateRadius = 50

        elseif enemDistSqr < 1000^2 then
            mimicBite = mimicBite + -150

        -- far away and mimic, don't see them
        else
            return true

        end

        local distBetweenPos = ( oldPos - currPos ):LengthSqr()
        if distBetweenPos > 80^2 then
            mimicBite = mimicBite + 150

        elseif distBetweenPos > 40^2 then
            mimicBite = mimicBite + 150
            doRandomSuspicious = true

        elseif distBetweenPos > 10^2 then
            mimicBite = mimicBite + 50
            doRandomSuspicious = true
            investigateRadius = 50

        elseif distBetweenPos > 3^2 then
            mimicBite = mimicBite + 25
            doRandomSuspicious = true
            investigateRadius = 250

        end
    end

    local trulyInvisible = a < 15 and not enemy.gleeIsMimic
    local randomSeed = math.random( 0, maxSeen ) + weapBite + mimicBite


    -- i see enemy, make the chance of losing them really small
    local obviousEnemy = oldEnemyThatISee and randomSeed > seen * 0.1

    -- seen
    if obviousEnemy or mimicThatDidntMove then return end

    local seedIsGreater = math.random( 0, maxSeen ) > seen * 0.9

    local investigateNearby = doRandomSuspicious or ( enemDistSqr < 3000^2 and seedIsGreater and not enemy.gleeIsMimic )

    if investigateNearby then
        investigateRadius = investigateRadius or 500

        local randNoZ = VectorRand()
        randNoZ.z = 0

        local potentialPos = enemy:GetPos() + ( randNoZ * investigateRadius )

        if terminator_Extras.PosCanSee( enemy:GetShootPos(), potentialPos ) then
            me:UpdateEnemyMemory( enemy, potentialPos )
            me.EnemyLastPos = potentialPos
            me.EnemyLastHint = potentialPos

        end
    end

    if enemDistSqr < 75^2 and not enemy.gleeIsMimic then
        return

    elseif enemDistSqr < 45^2 then
        return

    -- NOT visible
    elseif randomSeed < seen or trulyInvisible then
        return true

    end

end

local ignorePlayers = GetConVar( "ai_ignoreplayers" )
function ENT:IgnoringPlayers()
    return ignorePlayers:GetBool()

end

local entMeta = FindMetaTable( "Entity" )
local _IsFlagSet = entMeta.IsFlagSet

function ENT:ShouldBeEnemy( ent )
    if _IsFlagSet( ent, FL_NOTARGET ) then return false end
    local isObject = _IsFlagSet( ent, FL_OBJECT )
    local isPly = ent:IsPlayer()
    local killer = ent.isTerminatorHunterKiller
    local interesting = isPly or ent:IsNextBot() or ent:IsNPC()
    local krangledKiller

    -- not interesting but it killed terminators? interesting!
    -- made to allow targeting nextbots/npcs that arent setup correctly, if they killed terminators!
    if killer and not ( interesting or isObject ) then
        local class = ent:GetClass()
        if isKiller and not ( ent:IsNextBot() or ent:IsNPC() or string.find( class, "npc" ) or string.find( class, "nextbot" ) ) then
            return false

        end

        krangledKiller = true

    elseif not isObject and not interesting then
        return false

    end

    if isPly and self:IgnoringPlayers() then return false end
    if hook.Run( "terminator_blocktarget", self, ent ) == true then return false end

    local class = ent:GetClass()
    local isDeadNPC = ent:IsNPC() and ( ent:GetNPCState() == NPC_STATE_DEAD or class == "npc_barnacle" and ent:GetInternalVariable( "m_takedamage" ) == 0 )

    if class == "rpg_missile" then return false end
    if class == "env_flare" then return false end
    if not ent.SBAdvancedNextBot and isDeadNPC then return false end
    if ( ent.SBAdvancedNextBot or not ent:IsNPC() ) and ent:Health() <= 0 then return false end

    local killerNotChummy = killer and ent.isTerminatorHunterChummy ~= self.isTerminatorHunterChummy
    local memory, _ = self:getMemoryOfObject( ent )
    local knowsItsAnEnemy = memory == MEMORY_WEAPONIZEDNPC or self:GetRelationship( ent ) == D_HT or krangledKiller or killerNotChummy
    if not knowsItsAnEnemy then return false end
    if self:GetRangeTo( ent ) > self.MaxSeeEnemyDistance and not isPly then return false end

    -- if player then, if they are transparent, randomly don't see them, unless we already saw them.
    if isPly and shouldNotSeeEnemy( self, ent ) then return false end

    return true

end

function ENT:ClearEnemyMemory( enemy )
    enemy = enemy or self:GetEnemy()
    self.m_EnemiesMemory[enemy] = nil

    if self:GetEnemy() == enemy then
        self:SetEnemy( NULL )
        hook.Run( "terminator_engagedenemywasbad", self, enemy )
    end
end

local isentity = isentity

function ENT:CanSeePosition( check )
    local pos = check
    if isentity( check ) then
        pos = self:EntShootPos( check )

    end

    local tr = util.TraceLine( {
        start = self:GetShootPos(),
        endpos = pos,
        mask = self.LineOfSightMask,
        filter = self
    } )

    local seeBasic = not tr.Hit or ( isentity( check ) and tr.Entity == check )
    return seeBasic

end

function ENT:FindEnemies()
    local ShouldBeEnemy = self.ShouldBeEnemy
    local CanSeePosition = self.CanSeePosition
    local UpdateEnemyMemory = self.UpdateEnemyMemory
    local EntShootPos = self.EntShootPos

    for _, ent in ipairs( ents.GetAll() ) do
        if ent == self or not ShouldBeEnemy( self, ent ) or not CanSeePosition( self, ent ) then continue end
        UpdateEnemyMemory( self, ent, EntShootPos( self, ent ) )

    end
end

function ENT:SetupEntityRelationship( ent )
    local disp,priority,theirdisp = self:GetDesiredEnemyRelationship( ent )
    self:SetEntityRelationship( ent, disp, priority )
    if ( ent:IsNPC() or ent:IsNextBot() ) and ent.AddEntityRelationship then
        if ent.SBAdvancedNextBot then
            --print( self, ent, theirdisp )
            timer.Simple( 0, function()
                if not IsValid( ent ) then return end
                if not IsValid( self ) then return end
                ent:SetEntityRelationship( self, theirdisp, nil )

            end )
            return

        end
        ent:AddEntityRelationship( self, theirdisp, 1 )
        -- stupid hack
        if ent.IsVJBaseSNPC == true then
            timer.Simple( 0, function()
                if not IsValid( ent ) or not IsValid( self ) or not istable( ent.CurrentPossibleEnemies ) then return end
                ent.CurrentPossibleEnemies[#ent.CurrentPossibleEnemies + 1] = self
            end )
        end
    end
end

function ENT:SetupRelationships()
    for _, ent in ipairs( ents.GetAll() ) do
        self:SetupEntityRelationship( ent )
    end

    local hookId = "sb_anb_terminator_relations_" .. self:GetCreationID()

    hook.Add( "OnEntityCreated", hookId, function( ent )
        if not IsValid( self ) then hook.Remove( "OnEntityCreated", hookId ) return end
        timer.Simple( 0.5, function()
            if not IsValid( self ) then return end
            if not IsValid( ent ) then return end
            self:SetupEntityRelationship( ent )
        end )
    end )
end

function ENT:MakeFeud( enemy )
    if not IsValid( enemy ) then return end
    if enemy == self then return end
    if not enemy.Health then return end
    if enemy:Health() <= 0 then return end
    if enemy:GetClass() == "rpg_missile" then return end -- crazy fuckin bug
    if enemy:GetClass() == "env_flare" then return end
    local maniacHunter = ( self:GetCreationID() % 15 ) == 1 or self.alwaysManiac
    local bothChummy = enemy.isTerminatorHunterChummy == self.isTerminatorHunterChummy
    if bothChummy and not maniacHunter then return end

    local Disp = self:Disposition( enemy )
    if not Disp then return end
    if enemy:IsPlayer() then
        self:AddEntityRelationship( enemy, D_HT, 1 ) -- hate players more than anything else

    else
        self:AddEntityRelationship( enemy, D_HT )

    end

    if enemy:IsPlayer() then return end
    if enemy.GetActiveWeapon and IsValid( enemy:GetActiveWeapon() ) then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    elseif enemy:GetPos():DistToSqr( self:GetPos() ) > 200^2 then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    end
    if not enemy.Disposition then return end
    Disp = enemy:Disposition( self )
    if Disp == D_HT then return end
    enemy:AddEntityRelationship( self, D_HT )

end

-- used in shouldcrouch in motionoverrides
function ENT:HasToCrouchToSeeEnemy()
    local enemy = self:GetEnemy()
    local myPos = self:GetPos()
    local decreaseRate = -1

    if self.tryCrouchingToSeeEnemy and IsValid( enemy ) then
        local nextSeeCheck = self.nextCrouchWouldSeeEnemyCheck or 0

        if nextSeeCheck < CurTime() then
            self.nextCrouchWouldSeeEnemyCheck = CurTime() + 0.2

            local enemyCheckPos = enemy:GetPos() + crouchingOffset * enemy:GetModelScale()
            local standingShootPos = myPos + standingOffset * self:GetModelScale()

            local standingSeeTraceConfig = {
                start = standingShootPos,
                endpos = enemyCheckPos,
                filter = self,
                mask = self.LineOfSightMask,
            }

            local standingSeeTraceResult = util.TraceLine( standingSeeTraceConfig )
            local hitTheEnem = IsValid( standingSeeTraceResult.Entity ) and standingSeeTraceResult.Entity == enemy
            local standingWouldSee = hitTheEnem or not standingSeeTraceResult.Hit

            -- standing would see the enemy
            if standingWouldSee then
                self.shouldCrouchToSeeWeight = math.Clamp( self.shouldCrouchToSeeWeight + decreaseRate, 0, math.huge )

                -- dont stop crouching instantly!
                if self.shouldCrouchToSeeWeight >= 1 then
                    return true

                else
                    self.shouldCrouchToSeeWeight = nil
                    self.tryCrouchingToSeeEnemy = nil
                    return false

                end
            end

            local crouchingShootPos = myPos + crouchingOffset * self:GetModelScale()

            local crouchSeeTraceConfig = {
                start = crouchingShootPos,
                endpos = enemyCheckPos,
                filter = self,
                mask = self.LineOfSightMask,
            }

            local crouchSeeTraceResult = util.TraceLine( crouchSeeTraceConfig )
            local crouchHitTheEnem = IsValid( crouchSeeTraceResult.Entity ) and crouchSeeTraceResult.Entity == enemy
            local crouchWouldSee = crouchHitTheEnem or not crouchSeeTraceResult.Hit

            if crouchWouldSee ~= true then
                self.shouldCrouchToSeeWeight = math.Clamp( self.shouldCrouchToSeeWeight + decreaseRate, 0, math.huge )
                return self.shouldCrouchToSeeWeight >= 1

            end

            self.shouldCrouchToSeeWeight = 5

            return true

        else
            return self.shouldCrouchToSeeWeight >= 1

        end
    end

    if IsValid( enemy ) and not self.IsSeeEnemy then
        self.tryCrouchingToSeeEnemy = true
        self.shouldCrouchToSeeWeight = 0
    end
end

function ENT:DoHardcodedRelations()
    self:SetClassRelationship( "player", D_HT,1 )
    self:SetClassRelationship( "npc_lambdaplayer", D_HT,1 )
    self:SetClassRelationship( "rpg_missile", D_NU )
    self:SetClassRelationship( "sb_advanced_nextbot_terminator_hunter", D_LI )
    self:SetClassRelationship( "sb_advanced_nextbot_terminator_hunter_slower", D_LI )
    self:SetClassRelationship( "sb_advanced_nextbot_terminator_hunter_fakeply", D_HT )
    self:SetClassRelationship( "sb_advanced_nextbot_soldier_follower", D_HT )
    self:SetClassRelationship( "sb_advanced_nextbot_soldier_friendly", D_HT )
    self:SetClassRelationship( "sb_advanced_nextbot_soldier_hostile", D_HT )

end

local function pals( ent1, ent2 )
    return ent1.isTerminatorHunterChummy == ent2.isTerminatorHunterChummy

end

local _dirToPos = terminator_Extras.dirToPos
local _PosCanSeeComplex = terminator_Extras.PosCanSeeComplex
local vecUp25 = Vector( 0, 0, 25 )

function ENT:AnotherHunterIsHeadingToEnemy()
    local myEnemy = self:GetEnemy()
    if not IsValid( myEnemy ) then return end

    local enemysPos = myEnemy:GetPos()
    local enemysShootPos = self:EntShootPos( myEnemy )

    local otherHunters = ents.FindByClass( "sb_advanced_nextbot_terminator_hunter*" )
    table.Shuffle( otherHunters )

    local myDirToEnemy = _dirToPos( self:GetPos(), enemysPos )

    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) and hunter:PathIsValid() then
            -- its not being sneaky!
            if hunter.IsSeeEnemy then continue end

            local path = hunter:GetPath()
            local pathEnd = path:GetEnd()
            local moveSpeed = hunter.MoveSpeed
            local distNeeded = moveSpeed * 6

            local pathEndDistToEnemy = pathEnd:DistToSqr( enemysPos )
            -- way too far to be going to enemy
            if pathEndDistToEnemy > distNeeded^2 then continue end

            -- is it coming in from another direction, or is it just going straight to enemy
            local dirDifference = ( myDirToEnemy - _dirToPos( pathEnd, enemysPos ) ):Length()
            if dirDifference < 0.25 and pathEndDistToEnemy > moveSpeed^2 then continue end

            -- finally
            if not _PosCanSeeComplex( pathEnd + vecUp25, enemysShootPos, { myEnemy } ) then continue end

            return true

        end
    end
end

function ENT:GetOtherHuntersProbableEntrance()
    local otherHunters = ents.FindByClass( "sb_advanced_nextbot_terminator_hunter*" )
    table.Shuffle( otherHunters )

    -- find a long path
    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) and hunter:PathIsValid() and hunter:GetPath():GetLength() > 750 then
            return hunter:GetPathHalfwayPoint()

        end
    end
    -- no other long paths! just avoid the other guys if we can
    for _, hunter in ipairs( otherHunters ) do
        if hunter ~= self and pals( self, hunter ) then
            if hunter.IsSeeEnemy and IsValid( hunter:GetEnemy() ) then
                -- between hunter and enemy
                return ( hunter:GetPos() + hunter:GetEnemy():GetPos() ) / 2

            else
                return hunter:GetPos()

            end
        end
    end
end

function ENT:SaveSoundHint( source, valuable, emitter )
    local soundHint = {}
    soundHint.emitter = emitter
    soundHint.source = source
    soundHint.valuable = valuable
    soundHint.time = CurTime()

    self.lastHeardSoundHint = soundHint

end

function ENT:validSoundHint()
    local hint = self.lastHeardSoundHint
    if not hint then return end

    local emitter = hint.emitter
    if IsValid( emitter ) then
        local interesting = emitter:IsPlayer() or emitter:IsNextBot() or emitter:IsNPC()
        if interesting then return true end

        local id = emitter:GetCreationID()
        local oldCount = self.heardThingCounts[ id ] or 0
        self.heardThingCounts[ id ] = oldCount + 1

        --print( emitter, oldCount )

        timer.Simple( 120, function()
            if not IsValid( self ) then return end
            self.heardThingCounts[ id ] = self.heardThingCounts[ id ] + -1

        end )

        if oldCount > 8 then
            self.lastHeardSoundHint = nil
            return false

        end
    end
    return true

end

function ENT:RegisterForcedEnemyCheckPos( enemy )
    if not IsValid( enemy ) then return end

    self.forcedCheckPositions = self.forcedCheckPositions or {}

    self.forcedCheckPositions[ enemy:GetCreationID() ] = enemy:GetPos()

end

function ENT:HandleFakeCrouching( data, enemy )
    local copying = self:GetNWEntity( "disguisedterminatorsmimictarget", nil )
    if not IsValid( copying ) then
        copying = enemy

    end
    if not IsValid( enemy ) then return end
    if enemy.terminator_CantConvinceImFriendly then return end
    if not ( data.baitcrouching or enemy.terminator_crouchingbaited == self ) then return end

    if not data.distToEnemyOld then
        data.distToEnemyOld = self.DistToEnemy

    elseif self.DistToEnemy > data.distToEnemyOld then
        self.forcedShouldWalk = 0
        data.distToEnemyOld = math.Clamp( self.DistToEnemy, data.distToEnemyOld, data.distToEnemyOld + 5 )
        return

    elseif self.DistToEnemy < data.distToEnemyOld then
        data.distToEnemyOld = self.DistToEnemy
        self.forcedShouldWalk = CurTime() + 1

    end

    data.baitcrouching = data.baitcrouching or CurTime()
    data.crouchbaitcount = data.crouchbaitcount or 0
    data.unpromptedcrouches = data.unpromptedcrouches or 0
    data.foolingjumpcount = data.foolingjumpcount or 0
    data.nextfoolingjump = data.nextfoolingjump or 0
    data.dofoolingjump = data.dofoolingjump or math.huge
    local crouch = 0

    local timeSinceStart = CurTime() - data.baitcrouching

    if copying:IsOnGround() then
        data.wasOnGround = true

    end
    if timeSinceStart > 0.5 and not copying:IsOnGround() and data.wasOnGround and data.nextfoolingjump < CurTime() then
        data.dofoolingjump = CurTime() + 0.25
        data.foolingjumpcount = data.foolingjumpcount + 1
        data.nextfoolingjump = CurTime() + 1 + data.foolingjumpcount * 5

    elseif data.dofoolingjump < CurTime() then
        data.dofoolingjump = math.huge
        self:Jump( 40 )

    elseif timeSinceStart > 0.5 and copying:IsOnGround() and copying.Crouching and copying:Crouching() then
        data.unpromptedcrouches = 0
        if data.didanunpromptedcrouchtimeout and data.slinkAway then
            data.slinkAway = data.slinkAway + -10

        elseif data.slinkAway then
            data.slinkAway = data.slinkAway + 0.75
            data.foolingjumpcount = data.foolingjumpcount + -1

        end
        crouch = 0.25

    elseif timeSinceStart > data.crouchbaitcount + -data.unpromptedcrouches * 0.55 and data.unpromptedcrouches < 4 then
        data.foolingjumpcount = data.foolingjumpcount + -0.5
        data.unpromptedcrouches = data.unpromptedcrouches + 1
        data.resetunpromptedcrouches = CurTime() + 3
        if data.slinkAway then
            data.slinkAway = data.slinkAway + 0.75
        end
        crouch = 0.3

    elseif data.resetunpromptedcrouches and data.resetunpromptedcrouches < CurTime() then
        data.didanunpromptedcrouchtimeout = true
        data.unpromptedcrouches = 0
        data.foolingjumpcount = 0

    end
    if crouch > 0 then
        data.crouchbaitcount = data.crouchbaitcount + 1
        self.overrideCrouch = CurTime() + crouch

    end
end