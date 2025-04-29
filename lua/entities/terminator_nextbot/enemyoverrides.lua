
local MEMORY_WEAPONIZEDNPC = 32

local IsValid = IsValid
local LocalToWorld = LocalToWorld
local entMeta = FindMetaTable( "Entity" )

local IsFlagSet = entMeta.IsFlagSet

local blockRandomInfighting = CreateConVar( "terminator_block_random_infighting", 0, FCVAR_ARCHIVE, "Block random infighting?" )
local blockAllInfighting = CreateConVar( "terminator_block_infighting", 0, FCVAR_ARCHIVE, "Disable ALL infighting?" )


local playersCache -- i love overoptimisation
local npcClassCache
local nextbotClassCache

terminator_Extras.DOINGTYPECACHE = terminator_Extras.DOINGTYPECACHE or nil
local function doPlayersCache()
    playersCache = {}
    for _, ply in player.Iterator() do
        playersCache[ply] = true

    end
end

if terminator_Extras.DOINGTYPECACHE then -- the joys of autorefresh
    doPlayersCache()
    npcClassCache = {}
    nextbotClassCache = {}

end

hook.Add( "terminator_nextbot_oneterm_exists", "setup_shouldbeenemy_playercache", function()
    doPlayersCache()
    npcClassCache = {}
    nextbotClassCache = {}
    terminator_Extras.DOINGTYPECACHE = true
    timer.Create( "term_cache_players", 2, 0, function()
        doPlayersCache()
    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "setupshouldbeenemy_playercache", function()
    timer.Remove( "term_cache_players" )
    playersCache = nil
    npcClassCache = nil
    nextbotClassCache = nil
    terminator_Extras.DOINGTYPECACHE = nil

end )

function ENT:IsPlyNoIndex( ent )
    return playersCache[ent]

end


-- i love overoptimisation x 2
local notEnemyCache = {} -- this cache is used to skip alot of _index calls, perf, on checking if props, static things are enemies
hook.Add( "terminator_nextbot_oneterm_exists", "setup_shouldbeenemy_notenemycache", function()
    timer.Create( "term_cache_isnotenemy", 5, 0, function()
        notEnemyCache = {}

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "setup_shouldbeenemy_notenemycache", function()
    timer.Remove( "term_cache_isnotenemy" )
    notEnemyCache = {}

end )

local function isNpcEntClass( ent, class ) -- more optimized than ent:IsNPC(), worth it to have 40+ npcs spawned
    local cached = npcClassCache[class]
    if cached == nil then
        cached = ent:IsNPC()
        npcClassCache[class] = cached

    end
    return cached

end
local function isNextbotEntClass( ent, class ) -- ditto
    local cached = nextbotClassCache[class]
    if cached == nil then
        cached = ent:IsNextBot()
        nextbotClassCache[class] = cached

    end
    return cached

end

local function isNextbotOrNpcEnt( ent )
    local class = entMeta.GetClass( ent )
    return isNpcEntClass( ent, class ) or isNextbotEntClass( ent, class )

end


local fogRange
-- from CFC's LFS fork, code by reeedox
local function setFogRange()
    local fogController = ents.FindByClass( "env_fog_controller" )[1]
    if not IsValid( fogController ) then return end

    local fogRangeInt = fogController:GetKeyValues().farz
    if not fogRangeInt then return end
    if fogRangeInt <= 0 then return end
    fogRange = fogRangeInt -- bit of leeway

end

hook.Add( "terminator_nextbot_oneterm_exists", "setup_fograngecheck", function()
    setFogRange()
    timer.Create( "term_cache_fogrange", 5, 0, function()
        setFogRange()

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "teardown_fograngecheck", function()
    timer.Remove( "term_cache_fogrange" )
    fogRange = nil

end )

local function isBeyondFog( _, dist )
    if not fogRange then return end
    return dist > fogRange

end

ENT.IsBeyondFog = isBeyondFog

local function pals( ent1, ent2 )
    return ent1.isTerminatorHunterChummy == ent2.isTerminatorHunterChummy

end

function ENT:enemyBearingToMeAbs()
    local enemy = self:GetEnemy()
    if not IsValid( enemy ) then return 0 end
    local myPos = self:GetPos()
    local enemyPos = enemy:GetPos()
    local enemyAngle = enemy:EyeAngles()

    return math.abs( terminator_Extras.BearingToPos( myPos, enemyAngle, enemyPos, enemyAngle ) )

end

do
    local matrixMeta = FindMetaTable( "VMatrix" )

    local function cacheEntShootPos( ent, entsTbl, pos )
        entsTbl.term_cachedEntShootPos = pos
        timer.Simple( 0.01, function() -- cache this for barely more than a tick, HUGE perf save if there's lots and lots of bots
            if not IsValid( ent ) then return end
            entsTbl.term_cachedEntShootPos = nil

        end )
        return pos

    end

    function ENT:EntShootPos( ent, random, entsTbl )
        if not entsTbl and not IsValid( ent ) then return end -- entstbl is supplied if the ent is already valid, so we dont need to check
        entsTbl = entsTbl or entMeta.GetTable( ent )

        local hardCache = entsTbl.term_cachedEntShootPos
        if hardCache then return hardCache end

        local isPly = playersCache[ent]
        local isPlayerInVehicle = isPly and ent:InVehicle()

        if isPlayerInVehicle then
            local pos = self:getBestPos( ent:GetVehicle() )
            return cacheEntShootPos( ent, entsTbl, pos )

        end

        local isCrouchingPlayer = isPly and ent:Crouching()

        if not isCrouchingPlayer then
            local sets = entMeta.GetHitboxSetCount( ent )
            if sets then
                local hitboxes = {}
                entsTbl = entsTbl or ent:GetTable()
                local data = entsTbl.term_cachedHitboxData or nil


                if not data then
                    for num1 = 0, sets - 1 do
                        for num2 = 0, entMeta.GetHitBoxCount( ent, num1 ) - 1 do
                            local group = entMeta.GetHitBoxHitGroup( ent, num2, num1 )

                            hitboxes[group] = hitboxes[group] or {}
                            hitboxes[group][#hitboxes[group] + 1] = { entMeta.GetHitBoxBone( ent, num2, num1 ), entMeta.GetHitBoxBounds( ent, num2, num1 ) }

                        end
                    end

                    if hitboxes[HITGROUP_HEAD] then
                        data = hitboxes[HITGROUP_HEAD][ random and math.random( #hitboxes[HITGROUP_HEAD] ) or 1 ]

                    elseif hitboxes[HITGROUP_CHEST] then
                        data = hitboxes[HITGROUP_CHEST][ random and math.random( #hitboxes[HITGROUP_CHEST] ) or 1 ]

                    elseif hitboxes[HITGROUP_GENERIC] then
                        data = hitboxes[HITGROUP_GENERIC][ random and math.random( #hitboxes[HITGROUP_GENERIC] ) or 1 ]

                    end
                    entsTbl.term_cachedHitboxData = data
                    -- just in case their model changes
                    timer.Simple( math.Rand( 5, 10 ), function()
                        if not IsValid( self ) then return end
                        if not IsValid( ent ) then return end
                        entsTbl.term_cachedHitboxData = nil

                    end )
                end

                if data then
                    local bonem = entMeta.GetBoneMatrix( ent, data[1] )
                    if bonem then
                        local theCenter = data[2] + ( data[3] - data[2] ) / 2

                        local pos = LocalToWorld( theCenter, angle_zero, matrixMeta.GetTranslation( bonem ), matrixMeta.GetAngles( bonem ) )
                        return cacheEntShootPos( ent, entsTbl, pos )

                    end
                end
            end
        end

        --debugoverlay.Cross( ent:WorldSpaceCenter(), 5, 10, Color( 255,255,255 ), true )
        local pos = entMeta.WorldSpaceCenter( ent )
        return cacheEntShootPos( ent, entsTbl, pos )

    end
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

    local doRandomSuspicious = nil
    local investigateRadius = nil

    local trulyInvisible = a < 15
    local randomSeed = math.random( 0, maxSeen ) + weapBite


    -- i see enemy, make the chance of losing them really small
    local obviousEnemy = oldEnemyThatISee and randomSeed > seen * 0.1

    -- seen
    if obviousEnemy then return end

    local seedIsGreater = math.random( 0, maxSeen ) > seen * 0.9

    local investigateNearby = doRandomSuspicious or ( enemDistSqr < 3000^2 and seedIsGreater )

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

    if enemDistSqr < 75^2 then
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

local bearingToPos = terminator_Extras.BearingToPos
local math_abs = math.abs

local function PosIsInFov( self, myAng, myPos, checkPos, fov )
    fov = fov or self.Term_FOV
    if not fov or fov >= 180 then return true end

    myAng = myAng or self:GetEyeAngles()
    myPos = myPos or self:GetPos()
    -- this is dumb
    local fovInverse = bearingToPos( myPos, myAng, checkPos, myAng )
    return ( math_abs( fovInverse ) - 180 ) > -fov

end

ENT.PosIsInFov = PosIsInFov

local function IsInMyFov( self, ent, fov )
    fov = fov or self.Term_FOV
    if not fov or fov >= 180 then return true end

    return PosIsInFov( self, nil, self:GetPos(), ent:GetPos() )

end

ENT.IsInMyFov = IsInMyFov

function ENT:ShouldBeEnemy( ent, fov, myTbl, entsTbl )
    if notEnemyCache[ent] then return false end

    if IsFlagSet( ent, FL_NOTARGET ) then
        return false

    end
    local isObject = IsFlagSet( ent, FL_OBJECT )
    local isPly = playersCache[ent]

    local killer
    local krangledKiller
    local class = entMeta.GetClass( ent )

    if not ent.isTerminatorHunterKiller then
        local interesting = isPly or isNextbotEntClass( ent, class ) or isNpcEntClass( ent, class )
        if not isObject and not interesting then
            notEnemyCache[ent] = true
            return false

        end
    else
        -- if an ent has killed terminators
        -- we do more thurough checks on it!
        -- made to allow targeting nextbots/npcs that arent setup correctly, if they killed terminators!
        if not ( isPly or isNextbotEntClass( ent, class ) or isNpcEntClass( ent, class ) or string.find( class, "npc" ) or string.find( class, "nextbot" ) ) then return false end
        krangledKiller = true

    end
    -- most ents never get past this point!

    entsTbl = entsTbl or entMeta.GetTable( ent )
    myTbl = myTbl or entMeta.GetTable( self )

    if isPly and myTbl.IgnoringPlayers( self ) then
        return false

    end

    if class == "rpg_missile" then return false end
    if class == "env_flare" then return false end

    local isDeadNPC = isNpcEntClass( ent, class ) and ( ent:GetNPCState() == NPC_STATE_DEAD or class == "npc_barnacle" and entMeta.GetInternalVariable( ent, "m_takedamage" ) == 0 )

    if not entsTbl.TerminatorNextBot and isDeadNPC then return false end
    if ( entsTbl.TerminatorNextBot or not isNpcEntClass( ent, class ) ) and entMeta.Health( ent ) <= 0 then return false end

    local killerNotChummy = killer and entsTbl.isTerminatorHunterChummy ~= myTbl.isTerminatorHunterChummy
    local memory, _ = myTbl.getMemoryOfObject( self, myTbl, ent )
    local knowsItsAnEnemy = memory == MEMORY_WEAPONIZEDNPC or myTbl.TERM_GetRelationship( self, myTbl, ent ) == D_HT or krangledKiller or killerNotChummy
    if not knowsItsAnEnemy then return false end

    if hook.Run( "terminator_blocktarget", self, ent ) == true then return false end

    local inFov = IsInMyFov( self, ent, fov )
    local rangeTo = self:GetRangeTo( ent )

    local maxSeeingDist = myTbl.MaxSeeEnemyDistance

    if not inFov and rangeTo > 200 then return false end -- ignore fov if really close

    if isPly then -- ignore maxSeeingDist for plys
        if isBeyondFog( nil, rangeTo ) then -- but dont ignore fog 
            return false

        end
    elseif rangeTo > maxSeeingDist then
        return false

    end

    -- if player then, if they are transparent, randomly don't see them, unless we already saw them.
    if isPly and shouldNotSeeEnemy( self, ent ) then return false end

    local noHealthChangeCount = entsTbl.term_NoHealthChangeCount
    if myTbl.JudgesEnemies and noHealthChangeCount then
        local weirdUnkillable = noHealthChangeCount > 50 and noHealthChangeCount >= ( 100 + ( entMeta.GetCreationID( self ) % 100 ) )
        if weirdUnkillable then return false end

    end

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

do
    local isentity = isentity

    function ENT:CanSeePosition( check, myTbl, checksTbl )
        myTbl = myTbl or self:GetTable()
        local pos = check
        if isentity( check ) then
            pos = myTbl.EntShootPos( self, check, checksTbl )

        end

        local tr = util.TraceLine( {
            start = myTbl.GetShootPos( self ),
            endpos = pos,
            mask = self.LineOfSightMask,
            filter = self
        } )

        local seeBasic = not tr.Hit or ( isentity( check ) and tr.Entity == check )
        return seeBasic

    end
end

function ENT:FindEnemies( myTbl )
    myTbl = myTbl or self:GetTable()
    local ShouldBeEnemy = myTbl.ShouldBeEnemy
    local CanSeePosition = myTbl.CanSeePosition
    local UpdateEnemyMemory = myTbl.UpdateEnemyMemory
    local EntShootPos = myTbl.EntShootPos
    local myFov = myTbl.Term_FOV
    local found
    if myFov >= 180 then
        found = ents.FindInSphere( self:GetPos(), myTbl.MaxSeeEnemyDistance )

    else
        found = ents.FindInCone( self:GetShootPos(), self:GetEyeAngles():Forward(), myTbl.MaxSeeEnemyDistance, math.cos( math.rad( myFov ) ) )

    end

    for _, ent in ipairs( found ) do
        if ( ent ~= self ) and ( not notEnemyCache[ ent ] ) then
            local entsTbl = ent:GetTable()
            if ShouldBeEnemy( self, ent, myFov, myTbl, entsTbl ) and CanSeePosition( self, ent, myTbl, entsTbl ) then
                UpdateEnemyMemory( self, ent, EntShootPos( self, ent, entsTbl ), true )

            end
        end
    end
end

--[[------------------------------------
    Name: NEXTBOT:ForgetOldEnemies
    Desc: (INTERNAL) Clears bot memory from enemies that not valid, not updating very long time or not should be enemy.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:ForgetOldEnemies( myTbl )
    local cur = CurTime()
    local myFov = myTbl.Term_FOV
    local forgetEnemyTime = myTbl.ForgetEnemyTime

    for ent, memory in pairs( myTbl.m_EnemiesMemory ) do
        if ( not IsValid( ent ) ) or ( ( cur - memory.lastupdate ) >= forgetEnemyTime ) or ( not myTbl.ShouldBeEnemy( self, ent, myFov, myTbl, ent:GetTable() ) ) then
            myTbl.ClearEnemyMemory( self, ent )

        end
    end
end

do
    local Either = Either

    function ENT:FindPriorityEnemy( myTbl )
        myTbl = myTbl or self:GetTable()
        local notsee = {}
        local enemy, bestRange, priority
        local ignorePriority = false
        local myFov = myTbl.Term_FOV
        local closeEnemDistSqr = myTbl.CloseEnemyDistance^2

        for curr, _ in pairs( myTbl.m_EnemiesMemory ) do
            if not IsValid( curr ) then continue end
            local entsTbl = curr:GetTable()
            if not myTbl.ShouldBeEnemy( self, curr, myFov, myTbl, entsTbl ) then continue end

            if not myTbl.CanSeePosition( self, curr, myTbl, entsTbl ) then
                notsee[#notsee + 1] = curr
                continue
            end

            local rang = self:GetRangeSquaredTo( curr )
            if not rang then continue end -- ???????
            local _, pr = myTbl.TERM_GetRelationship( self, myTbl, curr )

            if not ignorePriority and rang <= closeEnemDistSqr then
                -- too close, we now ignore priority for all enemies, focus on proximity
                ignorePriority = true

            end
            if not enemy or Either( ignorePriority, rang < bestRange, Either( pr == priority, rang < bestRange, pr > priority ) ) then
                enemy, bestRange, priority = curr, rang, pr

            end
        end

        if not enemy then
            -- we dont see any enemy, but we know last position

            for _, curr in ipairs( notsee ) do
                local lastPos = self:GetLastEnemyPosition( curr )
                if not lastPos then continue end -- ???
                local rang = self:GetRangeSquaredTo( lastPos )

                if not enemy or rang < bestRange then
                    enemy, bestRange = curr, rang
                end
            end
        end

        return enemy or NULL

    end

    local INT_MIN = -2147483648
    local DEF_RELATIONSHIP_PRIORITY = INT_MIN

    --[[------------------------------------
        Name: NEXTBOT:TERM_GetRelationship
        Desc: Returns how bot feels about this entity, optimized.
        Arg1: self's GetTable
        Arg2: Entity | ent | Entity to get disposition from.
        Ret1: number | Priority disposition. See D_* Enums.
        Ret2: number | Priority of disposition.
    --]]------------------------------------
    function ENT:TERM_GetRelationship( myTbl, ent )
        local d, priority

        local entr = myTbl.m_EntityRelationships[ent]
        if entr then
            d, priority = entr[1], entr[2]
        end

        local classr = myTbl.m_ClassRelationships[ entMeta.GetClass( ent )]
        if classr and ( not priority or classr[2] > priority ) then
            d, priority = classr[1], classr[2]
        end

        -- killers are higher priority
        local killerStatus = myTbl.isTerminatorHunterKiller
        if priority and killerStatus then
            local mul = 1 + ( killerStatus * 0.1 )
            priority = priority * mul

        end

        priority = priority or DEF_RELATIONSHIP_PRIORITY
        d = d or D_NU

        return d, priority

    end

    -- for non-term code that won't supply myTbl
    function ENT:GetRelationship( ent )
        local myTbl = entMeta.GetTable( self )
        return myTbl.TERM_GetRelationship( self, myTbl, ent )

    end

    function ENT:Disposition( ent )
        local myTbl = entMeta.GetTable( self )
        return myTbl.TERM_GetRelationship( self, myTbl, ent )

    end
end

function ENT:SetupEntityRelationship( myTbl, ent, entsTbl )
    if notEnemyCache[ent] then return end
    local disp, priority, theirDisp = myTbl.GetDesiredEnemyRelationship( self, myTbl, ent, entsTbl, true )
    myTbl.Term_SetEntityRelationship( self, ent, disp, priority )
    timer.Simple( 0, function()
        if not IsValid( ent ) then return end
        if not IsValid( self ) then return end
        --print( ent, "has relation with", self, theirDisp )

        if entsTbl.TerminatorNextBot then
            myTbl.Term_SetEntityRelationship( self, theirDisp, nil )
            return

        end
        if ent.AddEntityRelationship then
            ent:AddEntityRelationship( self, theirDisp, 0 )

        end

        -- stupid hack
        if entsTbl.IsVJBaseSNPC == true then
            if not IsValid( ent ) or not IsValid( self ) or not istable( entsTbl.CurrentPossibleEnemies ) then return end
            entsTbl.CurrentPossibleEnemies[#entsTbl.CurrentPossibleEnemies + 1] = self

        end
    end )
end

function ENT:GetDesiredEnemyRelationship( myTbl, ent, entsTbl, isFirst )
    local disp
    local theirDisp
    local priority = 1

    local hardCodedRelation = myTbl.term_HardCodedRelations[entMeta.GetClass( ent )]
    if hardCodedRelation then
        disp = hardCodedRelation[1] or disp
        theirDisp = hardCodedRelation[2] or theirDisp
        priority = hardCodedRelation[3] or priority
        return disp, priority, theirDisp

    end

    if entsTbl.isTerminatorHunterChummy then
        if pals( self, ent ) then
            disp = D_LI
            theirDisp = D_LI

        else
            disp = D_HT
            theirDisp = D_HT

        end

    elseif playersCache[ent] then
        disp = D_HT
        theirDisp = D_HT

        priority = 1000
        if isFirst then
            local newDisp = myTbl.OnFirstRelationWithPlayer( self, ent, disp, priority, theirDisp )
            if newDisp then
                disp = newDisp

            end
        end

    elseif isNextbotOrNpcEnt( ent ) then
        disp = D_HT
        theirDisp = D_HT

        local memories = {}
        if myTbl.awarenessMemory then
            memories = myTbl.awarenessMemory

        end
        local key = myTbl.getAwarenessKey( self, ent )
        local memory = memories[key]
        if memory == MEMORY_WEAPONIZEDNPC then
            priority = priority + 200

        else
            -- what usually happens, npc is flagged as boring
            disp = D_NU
            --print("boringent" )
            priority = priority + 100

        end
        if ent:Health() then -- seagulls
            local theirHp = entMeta.Health( ent )
            local ourHp = entMeta.Health( self )
            if theirHp < ourHp / 100 then
                theirDisp = D_FR

            end
        end
    else
        disp = D_HT
        theirDisp = D_HT

    end
    return disp, priority, theirDisp

end

function ENT:SetupRelationships( myTbl )
    local SetupEntityRelationship = myTbl.SetupEntityRelationship
    for _, ent in ents.Iterator() do
        if not notEnemyCache[ent] then
            local entsTbl = ent:GetTable()
            if not ( playersCache[ent] or isNextbotOrNpcEnt( ent ) or entsTbl.isTerminatorHunterKiller ) then
                notEnemyCache[ent] = true

            else
                SetupEntityRelationship( self, myTbl, ent, entsTbl )

            end
        end
    end

    hook.Add( "OnEntityCreated", self, function( _, ent )
        if notEnemyCache[ent] then return end
        timer.Simple( 0.5, function()
            if not IsValid( self ) then return end
            if not IsValid( ent ) then return end
            local entsTbl = ent:GetTable()
            myTbl.SetupEntityRelationship( self, myTbl, ent, entsTbl )

        end )
    end )
end

function ENT:IsManiacTerm()
    if self.neverManiac then return end

    local maniacHunter = self.alwaysManiac
    if isfunction( maniacHunter ) then -- script infighting
        maniacHunter = maniacHunter( self )
        if maniacHunter then
            self.alwaysManiac = maniacHunter -- condition was met, save result!

        end
    end
    if not maniacHunter and not blockRandomInfighting:GetBool() then -- random infighting
        maniacHunter = ( self:GetCreationID() % 40 ) == 1 -- infighting funny

    end
    return maniacHunter

end

function ENT:MakeFeud( enemy )
    if not IsValid( enemy ) then return end
    if enemy == self then return end
    if not enemy.Health then return end
    if enemy:Health() <= 0 then return end

    local class = enemy:GetClass()
    if class == "rpg_missile" then return false end -- crazy fuckin bug
    if class == "env_flare" then return false end -- just as crazy

    if pals( self, enemy ) then
        if blockAllInfighting:GetBool() then return end
        local imManiac = self:IsManiacTerm()
        local maniacFight = imManiac or ( enemy.IsManiacTerm and enemy:IsManiacTerm() )
        if not maniacFight then return end
        if imManiac then
            self.isTerminatorHunterChummy = self.isTerminatorHunterChummy .. "_manaic_" .. tostring( self:GetCreationID() )

        end
    end

    local isPly = playersCache[enemy]
    local priority

    if isPly then
        priority = 1000
        self:Term_SetEntityRelationship( enemy, D_HT, priority ) -- hate players more than anything else

    elseif isNpcEntClass( enemy, class ) or isNextbotEntClass( enemy, class ) then
        priority = 100
        self:Term_SetEntityRelationship( enemy, D_HT, priority )

    else
        priority = 1
        self:Term_SetEntityRelationship( enemy, D_HT, priority )

    end

    if isPly then return end
    if enemy.GetActiveWeapon and IsValid( enemy:GetActiveWeapon() ) then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    elseif enemy:GetPos():DistToSqr( self:GetPos() ) > 200^2 then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )

    end

    if not enemy.Disposition then return end
    local disp = enemy:Disposition( self )

    if disp == D_HT then return end
    if enemy.TerminatorNextBot then
        enemy:Term_SetEntityRelationship( self, D_HT, priority )

    elseif enemy.AddEntityRelationship then
        enemy:AddEntityRelationship( self, D_HT, priority )

    end
end

-- used in shouldcrouch in motionoverrides
function ENT:HasToCrouchToSeeEnemy()
    local enemy = self:GetEnemy()
    local myPos = self:GetPos()
    local decreaseRate = -1

    if self.tryCrouchingToSeeEnemy and IsValid( enemy ) then
        local enemysPos = enemy:GetPos()
        local nextSeeCheck = self.nextCrouchWouldSeeEnemyCheck or 0

        if nextSeeCheck < CurTime() then
            self.nextCrouchWouldSeeEnemyCheck = CurTime() + 0.2

            local enemysScale = enemy:GetModelScale() or 1 -- this was nil somehow

            local enemyCheckPos = enemysPos + crouchingOffset * enemysScale
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

local _dirToPos = terminator_Extras.dirToPos
local _PosCanSeeComplex = terminator_Extras.PosCanSeeComplex
local vecUp25 = Vector( 0, 0, 25 )

function ENT:AnotherHunterIsHeadingToEnemy()
    local myEnemy = self:GetEnemy()
    if not IsValid( myEnemy ) then return end

    local enemysPos = myEnemy:GetPos()
    local enemysShootPos = self:EntShootPos( myEnemy )

    local otherHunters = ents.FindByClass( "terminator_nextbot*" )
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
    local otherHunters = ents.FindByClass( "terminator_nextbot*" )
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
        local interesting = emitter:IsPlayer() or isNextbotOrNpcEnt( emitter )
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
    -- disgusied terms crouch and jump at the same time as their disguise
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

function ENT:GetNearbyAllies()
    local cache = self.term_NearbyAlliesCache
    if cache then return cache end

    local allies = {}
    for _, ent in ipairs( ents.FindByClass( "terminator_nextbot*" ) ) do
        if ent == self or not pals( self, ent ) or self:GetPos():DistToSqr( ent:GetPos() ) > self.InformRadius^2 then continue end

        table.insert( allies, ent )

    end
    self.term_NearbyAlliesCache = allies
    timer.Simple( 2, function()
        if not IsValid( self ) then return end
        self.term_NearbyAlliesCache = nil

    end )
    return allies

end

-- ignore enemies that aren't taking damage!
-- this is reset in damageandhealth when bots are damaged
-- and when players respawn
function ENT:JudgeEnemy( enemy )
    if not self.JudgesEnemies then return end
    local judgeableWeapon = self:IsFists()
    if not judgeableWeapon then
        local myWeapon = self:GetActiveWeapon()
        if IsValid( myWeapon ) then
            judgeableWeapon = self:Term_GetTrackedDamage( myWeapon ) > 10

        end
    end

    if not judgeableWeapon then return end

    local currHealth = enemy:Health()
    local noChangeCount = enemy.term_NoHealthChangeCount or 0
    if currHealth <= 0 then
        enemy.term_NoHealthChangeCount = math.min( 0, noChangeCount + -100 )
        return

    end

    local oldHealth = enemy.term_OldHealth or 0

    if oldHealth == currHealth then
        noChangeCount = noChangeCount + 1
        enemy.term_NoHealthChangeCount = noChangeCount

    else
        enemy.term_NoHealthChangeCount = math.min( 0, noChangeCount + -100 )

    end

    enemy.term_OldHealth = currHealth

end

hook.Add( "terminator_nextbot_oneterm_exists", "setup_nohealthchange_reset", function()
    hook.Add( "PlayerSpawn", "terminator_reset_nohealthchangecount", function( ply )
        local noChangeCount = ply.term_NoHealthChangeCount or 0
        ply.term_NoHealthChangeCount = math.min( 0, noChangeCount + -100 )
        ply.term_OldHealth = nil

    end )
end )
hook.Add( "terminator_nextbot_noterms_exist", "setup_nohealthchange_reset", function()
    hook.Remove( "PlayerSpawn", "terminator_reset_nohealthchangecount" )
    for _, ply in player.Iterator() do
        --ply.term_NoHealthChangeCount = nil -- dont clean this up, too lame for bots to restart the whole process again
        ply.term_OldHealth = nil

    end
end )

local vec_up25 = Vector( 0, 0, 25 )

function ENT:Term_LookAround( myTbl )
    local cur = CurTime()
    local myPos = self:GetPos()

    local myArea = myTbl.GetTrueCurrentNavArea( self )
    local _, aheadSegment = myTbl.GetNextPathArea( self, myArea ) -- top of the jump
    if not aheadSegment then
        aheadSegment = self:GetPath():GetCurrentGoal()

    end
    local laddering = myTbl.terminator_HandlingLadder

    local lookAtGoalTime = myTbl.term_LookAtPathGoal or 0
    local lookAtGoal = lookAtGoalTime > cur and self:PathIsValid()

    local disrespecting = myTbl.GetCachedDisrespector( self )
    local speedToStopLookingFarAhead = terminator_Extras.term_DefaultSpeedToAimAtProps
    if IsValid( disrespecting ) then
        local myNearestPointToIt = self:NearestPoint( disrespecting:WorldSpaceCenter() )
        local itsNearestPointToMyNearestPoint = disrespecting:NearestPoint( myNearestPointToIt )
        if myNearestPointToIt:DistToSqr( itsNearestPointToMyNearestPoint ) < 8^2 then
            myTbl.PhysicallyPushEnt( self, disrespecting, 250 )

        end
        if not myTbl.LookAheadOnlyWhenBlocked and myTbl.EntIsInMyWay( self, disrespecting, 140, aheadSegment ) then
            speedToStopLookingFarAhead = terminator_Extras.term_InterruptedSpeedToAimAtProps

        end
    end

    local pathIsValid = myTbl.PathIsValid( self )
    local lookAtPos
    local myVelLengSqr = myTbl.loco:GetVelocity():LengthSqr()
    local movingSlow = myVelLengSqr < speedToStopLookingFarAhead
    local sndHint = myTbl.lastHeardSoundHint
    local genericHint = myTbl.term_GenericLookAtPos
    local sndCuriosity = 0.5

    local freshnessFocus = 0.25
    if self:IsReallyAngry() then
        freshnessFocus = 1.5

    elseif self:IsAngry() then
        freshnessFocus = 0.75

    end
    local enemyStillFresh = ( myTbl.LastEnemySpotTime - cur ) > freshnessFocus

    local lookAtEnemyLastPos = myTbl.LookAtEnemyLastPos or 0
    local shouldLookTime = lookAtEnemyLastPos > cur

    if sndHint and sndHint.valuable then
        sndCuriosity = 2

    end

    local seeEnem = myTbl.IsSeeEnemy
    --local lookAtType

    if not seeEnem and myTbl.interceptPeekTowardsEnemy and myTbl.lastInterceptTime + 2 > cur then
        lookAtPos = myTbl.lastInterceptPos
        --lookAtType = "intercept"

    elseif myTbl.TookDamagePos and ( not seeEnem or ( myTbl.TookDamagePos:Distance( myPos ) < ( myTbl.DistToEnemy * 0.75 ) and not myTbl.IsReallyAngry( self ) ) ) then
        lookAtPos = myTbl.TookDamagePos
        --lookAtType = "tookdamage"

    elseif not seeEnem and sndHint and sndHint.time + sndCuriosity > cur then
        lookAtPos = sndHint.source
        --lookAtType = "soundhint"

    elseif not seeEnem and genericHint and genericHint.time + sndCuriosity > cur then
        lookAtPos = genericHint.source
        --lookAtType = "generichint"

    elseif lookAtGoal and pathIsValid and not seeEnem and ( enemyStillFresh or shouldLookTime or ( math.random( 1, 100 ) < 4 and self:CanSeePosition( myTbl.EnemyLastPos, myTbl ) ) ) then
        if not shouldLookTime then
            myTbl.LookAtEnemyLastPos = cur + sndCuriosity

        end
        lookAtPos = myTbl.EnemyLastPos
        --lookAtType = "enemylastpos"

    elseif lookAtGoal and pathIsValid and not seeEnem and laddering then
        lookAtPos = myPos + self:GetVelocity() * 100
        --lookAtType = "laddering"

    elseif lookAtGoal and ( movingSlow or pathIsValid ) then
        lookAtPos = aheadSegment.pos + vec_up25
        --lookAtType = "lookatpath1"

        if not self:IsOnGround() or movingSlow then
            if IsValid( disrespecting ) then
                lookAtPos = myTbl.getBestPos( self, disrespecting )
                --lookAtType = "lookatpath_disrespector"

            else
                lookAtPos = aheadSegment.pos + vec_up25
                --lookAtType = "lookatpath2"

            end
        elseif lookAtPos:DistToSqr( myPos ) < 400^2 then
            -- attempt to look farther ahead
            local _, segmentAheadOfUs = myTbl.GetNextPathArea( self, myArea, 3, true )
            if segmentAheadOfUs then
                lookAtPos = segmentAheadOfUs.pos + vec_up25
                --lookAtType = "lookatpath3"

            end
        end
    end

    if lookAtPos then
        local myShoot = self:GetShootPos()
        if lookAtPos.z > myPos.z - 25 and lookAtPos.z < myPos.z + 25 then
            lookAtPos.z = myShoot.z

        end
        local ang = ( lookAtPos - myShoot ):Angle()
        local notADramaticHeightChange = ( lookAtPos.z > myPos.z + -100 ) or ( lookAtPos.z < myPos.z + 100 )
        if notADramaticHeightChange and not laddering and not IsValid( disrespecting ) then
            ang.p = 0

        end

        --print( "lookatpos", lookAtType, pathIsValid )

        self:SetDesiredEyeAngles( ang )

        return true

    end
end


do
    local dynamicallyLagCompensating = {}

    function ENT:InitializeLagCompensation()
        if game.SinglePlayer() then return end
        if self.IsFodder then
            dynamicallyLagCompensating[self] = false
            self:CallOnRemove( "term_cleanupdynamic_lagcomp", function()
                dynamicallyLagCompensating[self] = nil

            end )
        else
            self:SetLagCompensated( true )

        end
    end

    local function compensate( ent )
        if dynamicallyLagCompensating[ent] == true then return end
        dynamicallyLagCompensating[ent] = true
        ent:LagCompensation( true )

    end
    local function unCompensate( ent )
        if dynamicallyLagCompensating[ent] == false then return end
        dynamicallyLagCompensating[ent] = false
        ent:LagCompensation( false )

    end

    hook.Add( "terminator_nextbot_oneterm_exists", "setup_dynamic_lagcomp", function()
        hook.Add( "terminator_spotenemy", "term_dynamic_lagcomp", function( term, newEnemy )
            if dynamicallyLagCompensating[term] == nil then return end
            if not playersCache[newEnemy] then return end

            compensate( term )

        end )
        hook.Add( "terminator_enemychanged", "term_dynamic_lagcomp", function( term, newEnemy, prevEnemy )
            if dynamicallyLagCompensating[term] == nil then return end
            if playersCache[newEnemy] then
                compensate( term )

            elseif playersCache[prevEnemy] then
                unCompensate( term )

            end
        end )
        hook.Add( "terminator_loseenemy", "term_dynamic_lagcomp", function( term )
            if dynamicallyLagCompensating[term] == nil then return end
            unCompensate( term )

        end )
    end )
    hook.Add( "terminator_nextbot_noterms_exist", "teardown_dynamic_lagcomp", function()
        hook.Remove( "terminator_spotenemy", "term_dynamic_lagcomp" )
        hook.Remove( "terminator_enemychanged", "term_dynamic_lagcomp" )
        hook.Remove( "terminator_loseenemy", "term_dynamic_lagcomp" )

    end )
end


function ENT:InitializeListening( myTbl )
    if not myTbl.CanHearStuff then return end
    terminator_Extras.RegisterListener( self )

end