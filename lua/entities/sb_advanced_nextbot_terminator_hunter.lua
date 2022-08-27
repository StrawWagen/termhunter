AddCSLuaFile()

ENT.Base = "sb_advanced_nextbot_soldier_base"
DEFINE_BASECLASS( ENT.Base )
ENT.PrintName = "Terminator Hunter"

list.Set( "NPC", "sb_advanced_nextbot_terminator_hunter", {
	Name = ENT.PrintName,
	Class = "sb_advanced_nextbot_terminator_hunter",
	Category = "SB Advanced Nextbots",
	Weapons = {"weapon_terminatorfists_sb_anb"},
} )

if CLIENT then
	language.Add( "sb_advanced_nextbot_terminator_hunter", "Terminator Hunter" )
	return
end

local TERM_FISTS = "weapon_terminatorfists_sb_anb"
local ARNOLD_MODEL = "models/terminator/player/arnold/arnold.mdl"

CreateConVar( "termhunter_modeloverride", ARNOLD_MODEL, FCVAR_NONE, "Override the terminator nextbot's spawned-in model. Model needs to be rigged for player movement" )

local function termModel()
    local convar = GetConVar( "termhunter_modeloverride" )
    local model = ARNOLD_MODEL
    if convar then
        local varModel = convar:GetString()
        if varModel then 
            model = varModel
        end
    end
    return model
end

if not termModel() then 
    RunConsoleCommand( "termhunter_modeloverride", ARNOLD_MODEL )
end

if not navExtraDataHunter then
    navExtraDataHunter = {}
end


--utility functions begin

local function bearingToPos( pos1, ang1, pos2, ang2 )
    local localPos = WorldToLocal( pos1, ang1, pos2, ang2 )
    local bearing = 180 / math.pi * math.atan2( localPos.y, localPos.x )
    return bearing
end

local function getBestPos( ent )
    local obj = ent:GetPhysicsObject()
    local pos = ent:GetPos()
    if IsValid( obj ) then
        center = obj:GetMassCenter()
        if center ~= Vector() then
            pos = ent:LocalToWorld( center )
        end
    end
    return pos
end

local function getNearestNav( pos )
    if not pos then return NULL end
    local Dat = {
        start = pos,
        endpos = pos + Vector( 0,0,-500 ),
        mask = 131083
    }
    local Trace = util.TraceLine( Dat )
    if not Trace.HitWorld then return NULL end
    local navArea = navmesh.GetNearestNavArea( pos, false, 2000, false, true, -2 )
    if not navArea then return NULL end
    if not navArea:IsValid() then return NULL end
    return navArea
end

local function getNearestPosOnNav( pos )
    local result = { pos = nil, area = NULL }
    if not pos then return result end
    local navFound = getNearestNav( pos )
    if not navFound then return result end
    if not navFound:IsValid() then return result end
    result = { pos = navFound:GetClosestPointOnArea( pos ), area = navFound }
    return result
end

local function getBestForwardArea( startArea, direction ) --mega hack
    if not startArea:IsValid() then return NULL end
    if not direction then return NULL end
    local canDoUnderWater = startArea:IsUnderwater()
    local size = math.max( startArea:GetSizeX(), startArea:GetSizeY() ) * 2
    local checkPos = startArea:GetCenter() + ( direction * size )
    local areas = startArea:GetAdjacentAreas()
    local areaOut = NULL
    table.sort( areas, function( a, b ) -- sort areas by distance to curr area 
        local ADist = a:GetCenter():DistToSqr( checkPos )
        local BDist = b:GetCenter():DistToSqr( checkPos )
        return ADist < BDist 
    end )
    for I, area in ipairs( areas ) do
        if not area:IsUnderwater() or canDoUnderWater then 
            areaOut = area
            break
        end
    end
    return areaOut
end

local function SqrDistGreaterThan( Dist1, Dist2 )
    local Dist2 = Dist2 ^ 2
    return Dist1 > Dist2
end

local function SqrDistLessThan( Dist1, Dist2 )
    local Dist2 = Dist2 ^ 2
    return Dist1 < Dist2
end

local function PosCanSee( startPos, endPos )
    if not startPos then return end
    if not endPos then return end
    
    local mask = {
        start = startPos,
        endpos = endPos,
        mask = 16395
    }
    local trace = util.TraceLine( mask )
    return not trace.Hit, trace
    
end
local function PosCanSee2( startPos, endPos )
    if not startPos then return end
    if not endPos then return end
    
    local mask = {
        filter = self,
        start = startPos,
        endpos = endPos,
        mask = MASK_OPAQUE
    }
    local trace = util.TraceLine( mask )
    return not trace.Hit, trace
    
end

local function DirToPos( startPos, endPos )
    if not startPos then return end
    if not endPos then return end

    return ( endPos - startPos ):GetNormalized()

end 

local function Dist2D( Pos1, Pos2 ) -- return 2d dist
    return Pos1:Distance( Vector( Pos2[1], Pos2[2], Pos1[3] ) )
end

-- accurate method that does not require laggy sqrt 
local function distBetweenTwoAreas( area1, area2 )
    local dir = area1:GetCenter() - area2:GetCenter()
    local dist = 0
    if dir[1] > dir[2] then
        dist = ( area1:GetSizeX() + area2:GetSizeX() ) * 0.5
    else
        dist = ( area1:GetSizeY() + area2:GetSizeY() ) * 0.5
    end
    return dist
end

-- iterative function that finds connected area with the best score
-- areas with highest return from scorefunc are selected
-- areas that return 0 score from scorefunc are ignored
-- returns the best scoring area if it's further than dist or no other options exist
local function findValidNavResult( data, start, radius, scoreFunc )
    local pos = start
    local res = getNearestPosOnNav( pos )
    local cur = res.area
    if not IsValid(cur) then return end
    local curId = cur:GetID()
    
    local opened = { [curId] = true }
    local closed = {}
    local distances = { [curId] = cur:GetCenter():Distance(pos) }
    local scores = { [curId] = 1 }

    while !table.IsEmpty( opened ) do
        local _,bestArea = table.Random( opened )
        local bestScore = 0
        for currOpenedId, isOpen in pairs( opened ) do
            local myScore = scores[currOpenedId]
            if isnumber( myScore ) then
                if myScore > bestScore then 
                    bestScore = myScore
                    bestArea = currOpenedId
                end
            end
        end 

        local areaId = bestArea
        opened[areaId] = nil
        closed[areaId] = true
        
        local area = navmesh.GetNavAreaByID(areaId)
        local myDist = distances[areaId]
        local noMoreOptions = table.Count( opened ) == 1 and table.Count( closed ) >= 2

        if noMoreOptions then
            local _,bestClosedAreaId = table.Random( closed )
            local bestClosedScore = 0
            for currClosedId, _ in pairs( closed ) do
                local currClosedScore = scores[currClosedId]
                if isnumber( currClosedScore ) then
                    if currClosedScore > bestClosedScore then 
                        bestClosedScore = currClosedScore
                        bestClosedAreaId = currClosedId
                    end
                end
            end 
            local bestClosedArea = navmesh.GetNavAreaByID(bestClosedAreaId)
            return bestClosedArea:GetCenter(), bestClosedArea

        elseif myDist > radius then
            return area:GetCenter(), area
            
        end
        
        for k,adjArea in ipairs(area:GetAdjacentAreas()) do
            local adjID = adjArea:GetID() 
            if !closed[adjID] then
                local adjDist = distBetweenTwoAreas( area, adjArea )
                local distance = myDist + adjDist
                distances[adjID] = distance
                scores[adjID] = scoreFunc( data, area, adjArea )
                opened[adjID] = scores[adjID] > 0
            end
        end
    end
end
-- util funcs end


function ENT:ShouldBeEnemy(ent)
    local isPly = ent:IsPlayer()
	if ent:IsFlagSet(FL_NOTARGET) or !isPly and !ent:IsNPC() and !ent:IsFlagSet(FL_OBJECT) then return false end
	if isPly and GetConVar("ai_ignoreplayers"):GetBool() then return false end
	if !ent.SBAdvancedNextBot and ent:IsNPC() and (ent:GetNPCState()==NPC_STATE_DEAD or ent:GetClass()=="npc_barnacle" and ent:GetInternalVariable("m_takedamage")==0) then return false end
	if (ent.SBAdvancedNextBot or !ent:IsNPC()) and ent:Health()<=0 then return false end
	if self:GetRelationship(ent)!=D_HT then return false end
	if self:GetRangeTo(ent)>self.MaxSeeEnemyDistance and not isPly then return false end
	
	return true
end

local MEMORY_MEMORIZING = 1
local MEMORY_INERT = 2
local MEMORY_BREAKABLE = 4
local MEMORY_VOLATILE = 8
local MEMORY_THREAT = 16
local MEMORY_WEAPONIZEDNPC = 32

function ENT:caresAbout( ent )
    if not IsValid( ent ) then return end
    if not IsValid( ent:GetPhysicsObject() ) then return end
    if ent:IsFlagSet( FL_WORLDBRUSH ) then return end
    if ent:IsPlayer() then return end
    if ent == self then return end
    return true
end

function getAwarenessKey( ent )
    local model = ent:GetModel()
    local class = ent:GetClass()
    if not isstring( class ) or not isstring( model ) then return "" end
    return class .. " " .. model 
end

function ENT:memorizeEntAs( dat1, memory )
    local key = nil
    if isentity( dat1 ) then
        key = getAwarenessKey( dat1 )
    elseif isstring( dat1 ) then
        key = dat1
    end
    self.awarenessMemory[key] = memory
end

function ENT:understandObject( ent )
    local key = getAwarenessKey( ent )
    local memory = self.awarenessMemory[key]
    if isnumber( memory ) then
        if memory == MEMORY_MEMORIZING then 
            table.insert( self.awarenessUnknown, ent )
            
        elseif memory == MEMORY_INERT then

        elseif memory == MEMORY_BREAKABLE then -- entities that we can shoot if they're blocking us

        elseif memory == MEMORY_VOLATILE then -- entities that we can shoot to damage enemies
            table.insert( self.awarenessVolatiles, ent )
        elseif memory == MEMORY_THREAT then
            ---print( "aaa", key )
        end
        local stateKey = ent:GetPos() + ent:GetForward()
        if self.memorizedStates[ent:GetCreationID()] then
            local nextValidObservation = ent.nextValdTerminatorObservation or 0
            if nextValidObservation < CurTime() then -- if this changed while it was far away from us 
                if self.memorizedStates[ent:GetCreationID()] ~= stateKey then
                    self.notciedChangedEntity = ent:GetPos() 
                    debugoverlay.Cross( self.notciedChangedEntity, 10, 5, Color( 255, 0, 0 ), true )
                end
            end
        end
        ent.nextValdTerminatorObservation = CurTime() + 2
        self.memorizedStates[ent:GetCreationID()] = stateKey
    else
        local class = ent:GetClass()
        local isFunc = class:StartWith( "func_" )
        local isDynamic = class:StartWith( "prop_dynamic" )
        if isFunc then 
            local isFuncBreakable = class:StartWith( "func_breakable" )
            if isFuncBreakable then
                self:memorizeEntAs( ent, MEMORY_BREAKABLE )
            else
                self:memorizeEntAs( ent, MEMORY_INERT )
            end
        elseif isDynamic then
            self:memorizeEntAs( ent, MEMORY_INERT )
        else
            self:memorizeEntAs( ent, MEMORY_MEMORIZING )
            table.insert( self.awarenessUnknown, ent )
        end
    end
end

function ENT:understandSurroundings()
    self.awarenessUnknown = {}
    self.awarenessVolatiles = {}
    local pos = self:GetPos()
    local surroundings = ents.FindInSphere( pos, 1500 )
    local substantialStuff = {} 
    for extent, currEnt in ipairs( surroundings ) do
        if extent > 400 then -- cap this!
            break
        end
        if self:caresAbout( currEnt ) then
            table.insert( substantialStuff, currEnt )
        end  
    end
    table.sort( substantialStuff, function( a, b ) -- sort areas by distance to curr area 
        local ADist = a:GetPos():DistToSqr( pos )
        local BDist = b:GetPos():DistToSqr( pos )
        return ADist < BDist 
    end )
    for _, currEnt in ipairs( substantialStuff ) do
        self:understandObject( currEnt )
    end
end

function ENT:getShootableVolatiles( enemy )
    if not self.awarenessVolatiles then return end
    if not enemy then return end
    for _, currVolatile in ipairs( self.awarenessVolatiles ) do
        if IsValid( currVolatile ) then
            local pos = getBestPos( currVolatile )
            if SqrDistLessThan( pos:DistToSqr( enemy:GetPos() ), 300 ) then
                if PosCanSee( self:GetShootPos(), pos ) then
                    return currVolatile
                end
            end
        end
    end
end



function ENT:SetupRelationships()
	for k,v in ipairs(ents.GetAll()) do
		self:SetupEntityRelationship(v)
	end
	
	hook.Add("OnEntityCreated",self,function(self, ent )
        if not IsValid( self ) then return end
        timer.Simple( 0.5, function()
            if not IsValid( self ) then return end
            if not IsValid( ent ) then return end
		    self:SetupEntityRelationship(ent)
        end )
	end)
end

function ENT:GetDesiredEnemyRelationship(ent)
    local disp = D_HT
    local theirdisp = D_HT
    local priority = 1000
    
    if ent:GetClass() == self:GetClass() then
        disp = D_LI
        theirdisp = D_LI
    end

    if ent:IsPlayer() then
        priority = 1
    elseif ent:IsNPC() then
        local memories = {}
        if self.awarenessMemory then
            memories = self.awarenessMemory
        end
        local key = getAwarenessKey( ent )
        local memory = memories[key]
        if memory == MEMORY_WEAPONIZEDNPC then
            priority = priority + -300 
        else
            disp = D_NU
            --print("boringent" )
            priority = priority + -100
        end
    end

    return disp,priority,theirdisp
end

function ENT:SetupEntityRelationship(ent)
    local disp,priority,theirdisp = self:GetDesiredEnemyRelationship(ent)
    self:SetEntityRelationship(ent,disp,priority)
    if ent:IsNPC() then
        ent:AddEntityRelationship(self,theirdisp)
    end
end

function ENT:GetFootstepSoundTime()
	local time = 400
	local speed = self:GetCurrentSpeed()
    
	time = time - speed * 0.55

	if self:IsCrouching() then
		time = time+50
	end

	return time
end


function ENT:MakeFootstepSound(volume,surface)
	local foot = self.m_FootstepFoot
	self.m_FootstepFoot = !foot
	self.m_FootstepTime = CurTime()
	
	if !surface then
		local tr = util.TraceEntity({
			start = self:GetPos(),
			endpos = self:GetPos()-Vector(0,0,5),
			filter = self,
			mask = self:GetSolidMask(),
			collisiongroup = self:GetCollisionGroup(),
		},self)
		
		surface = tr.SurfaceProps
	end
	
	if !surface then return end
	
	local surface = util.GetSurfaceData(surface)
	if !surface then return end
	
	local sound = foot and surface.stepRightSound or surface.stepLeftSound
	
	if sound then
		local pos = self:GetPos()
		
        local signature = {
            "ambient/materials/clang1.wav"
        }
        local randSignature = table.Random( signature )
        local randPitch = math.random( 150, 160 )

		local filter = RecipientFilter()
		filter:AddPAS(pos)
		
		if !self:OnFootstep(pos,foot,sound,volume,filter) then
			self:EmitSound(sound,90,100,1,CHAN_BODY)
		end
	end
end

-- override this to remove path recalculating, we already do that
function ENT:ControlPath(lookatgoal)
	if !self:PathIsValid() then return false end
	
	local path = self:GetPath()
	local pos = self:GetPathPos()
	local options = self.m_PathOptions

	local range = self:GetRangeTo(pos)
	
	if range<options.tolerance or range<self.PathGoalToleranceFinal then
		path:Invalidate()
		return true
	end
	
	if self:MoveAlongPath(lookatgoal) then
		return true
	end
end

function ENT:startFlankPath( flankArea1, flankArea2 )
    if not flankArea1 or not flankArea2 then return end
    if not flankArea1:IsValid() or not flankArea2:IsValid() then return end
    self.HunterIsFlanking = true
    self.FlankAvoidArea1 = flankArea1
    self.FlankAvoidArea2 = flankArea2
end
function ENT:endFlankPath( flankArea )
    self.FlankAvoidArea1 = nil
    self.FlankAvoidArea2 = nil
    self.HunterIsFlanking = nil
    self.FlankAvoidForward = nil
end

function ENT:NavMeshPathCostGenerator(path,area,from,ladder,elevator,len) --do this so we can strictly avoid "avoid" flagged navareas and much more
	if !IsValid(from) then return 0 end
	if !self.loco:IsAreaTraversable(area) then return -1 end
	if !self.CanCrouch and area:HasAttributes(NAV_MESH_CROUCH) then return -1 end
	
    local avoid = nil
	local dist = 0
    local addedCost = 0
	local center = area:GetCenter()
    local costSoFar = from:GetCostSoFar() or 0

	if IsValid(ladder) then
		dist = ladder:GetLength() 
	elseif len>0 then
	    dist = len
	else
		dist = distBetweenTwoAreas( from, area )
	end
	
    if self.HunterIsFlanking then
        local visible1 = self.FlankAvoidArea1:IsPotentiallyVisible( area )
        local visible2 = self.FlankAvoidArea2:IsPotentiallyVisible( area )
        local mul = 1
        if visible2 then
            mul = mul+4
            if visible1 then 
                mul = mul+4
            end
        end
        dist = dist*mul
    end

	if area:HasAttributes(NAV_MESH_CROUCH) then
		dist = dist*5
	end

	if area:HasAttributes(NAV_MESH_JUMP) then
		dist = dist*5
	end
	
	if area:HasAttributes(NAV_MESH_AVOID) then
        avoid = true
		dist = dist*10
	end
    if from then
        local nav1Id = from:GetID()
        local nav2Id = area:GetID()
        if not istable( navExtraDataHunter.nav1Id ) then goto skipShitConnectionDetection end
        if not navExtraDataHunter.nav1Id.shitConnnections then goto skipShitConnectionDetection end
        if navExtraDataHunter.nav1Id.shitConnnections[nav2Id] then
            dist = dist*15
            if not navExtraDataHunter.nav1Id.superShitConnnections then goto skipSuperShitConnectionDetection end
            if navExtraDataHunter.nav1Id.superShitConnnections[nav2Id] then
                addedCost = 9000
            end
            ::skipSuperShitConnectionDetection::
        end
        ::skipShitConnectionDetection::
    end

	if area:HasAttributes(NAV_MESH_TRANSIENT) then
		dist = dist*5
	end

	if area:IsUnderwater() then
		dist = dist*5
	end
    
	local cost = dist+addedCost+costSoFar
	
	local deltaZ = from:ComputeAdjacentConnectionHeightChange(area)
	if deltaZ>=self.loco:GetStepHeight() then
		if deltaZ>=self.loco:GetMaxJumpHeight() or avoid then return -1 end

		cost = cost+dist*6
    elseif deltaZ <- self.loco:GetMaxJumpHeight() then
        if avoid then
            return -1
        else
            cost = cost*2
        end
	elseif deltaZ <- self.loco:GetDeathDropHeight() then
		return -1
	end
	return cost
end

function ENT:ShootBlocker(start,pos,filter)
	local tr = util.TraceHull({
		start = start,
		endpos = pos,
		filter = filter,
		mask = MASK_SHOT,
		mins = Vector(-6,-6,-20),
		maxs = Vector(6,6,20),
	} )
	
	return tr.Hit and tr.Entity
end

function ENT:tryToOpen( blocker )
    local class = blocker:GetClass()
		
    if self:HasWeapon2() and class:StartWith("func_breakable" ) then
        self:WeaponPrimaryAttack()
    elseif class=="prop_door_rotating" and blocker:GetInternalVariable("m_eDoorState" )!=2 and (!self.OpenDoorTime or CurTime()-self.OpenDoorTime>1) then
        self.OpenDoorTime = CurTime()
        blocker:Use(self,self)
    elseif class=="func_door_rotating" and blocker:GetInternalVariable("m_toggle_state" )==1 and (!self.OpenDoorTime or CurTime()-self.OpenDoorTime>1) then
        self.OpenDoorTime = CurTime()
        blocker:Use(self,self)
    elseif class=="func_door" and blocker:GetInternalVariable("m_toggle_state" )==1 and (!self.OpenDoorTime or CurTime()-self.OpenDoorTime>1) then
        self.OpenDoorTime = CurTime()
        blocker:Use(self,self)
    end
end

function ENT:OnContact( contact )
    self:tryToOpen( contact )
end

function ENT:BehaviourThink()
	if self:PathIsValid() and !self:IsControlledByPlayer() and !self:DisableBehaviour() then
		local filter = self:GetChildren()
        table.insert( filter, game.GetWorld() )
		filter[#filter+1] = self
		
		local pos = self:GetShootPos()
		local endpos = pos+self:GetAimVector()*100
		local blocker = self:ShootBlocker(pos,endpos,filter)
		
		self.LastShootBlocker = blocker
		
		if blocker then
			self:tryToOpen( blocker )
		end
	else
		self.LastShootBlocker = false
	end
end

local function flagForTime( Area, Time, Flag )
    if not Area:IsValid() then return end
    if not Area:HasAttributes( Flag ) then
        local OldAtt = Area:GetAttributes()
        local NewAtt = OldAtt + Flag
        Area:SetAttributes( NewAtt )
    end
    local nav1Id = Area:GetID()
    if not istable( navExtraDataHunter.nav1Id ) then
        navExtraDataHunter.nav1Id = {}
    end
    navExtraDataHunter.nav1Id["LastHazardMark"] = CurTime()
    navExtraDataHunter.nav1Id["Flag"] = Flag
    navExtraDataHunter.nav1Id["Id"] = navId
    
    timer.Simple( 120, function()
        local nav = navmesh.GetNavAreaByID( nav1Id )
        if not nav then return end
        if not nav:IsValid() then return end
        if not navExtraDataHunter.nav1Id then return end
        local lastMark = navExtraDataHunter.nav1Id["LastHazardMark"] or 0
        if lastMark + 110 < CurTime() then return end
        if not nav:HasAttributes( Flag ) then return end
        
        local OldAtt = nav:GetAttributes()
        local NewAtt = OldAtt + -Flag
        nav:SetAttributes( NewAtt )
        navExtraDataHunter.nav1Id["LastHazardMark"] = nil
        navExtraDataHunter.nav1Id["Flag"] = nil
        navExtraDataHunter.nav1Id["Id"] = nil
    end )
end

-- make nextbot recognize two nav areas that dont connect in practice
local function flagConnectionAsShit( area1, area2 )
    if not area1:IsValid() then return end
    if not area2:IsValid() then return end
    local superShitConnection = nil
    local nav1Id = area1:GetID()
    local nav2Id = area2:GetID()
    if not istable( navExtraDataHunter.nav1Id ) then navExtraDataHunter.nav1Id = {} end
    if not istable( navExtraDataHunter.nav1Id.shitConnnections ) then navExtraDataHunter.nav1Id.shitConnnections = {} end
    if navExtraDataHunter.nav1Id.shitConnnections[nav2Id] then superShitConnection = true end
    navExtraDataHunter.nav1Id.shitConnnections[nav2Id] = true
    navExtraDataHunter.nav1Id["lastConnectionFlag"] = CurTime()
    timer.Simple( 120, function()
        local nav = navmesh.GetNavAreaByID( nav1Id )
        if not nav then return end
        if not nav:IsValid() then return end
        local lastFlag = navExtraDataHunter.nav1Id["lastConnectionFlag"] or 0
        if lastFlag + 110 < CurTime() then return end
        if not navExtraDataHunter.nav1Id then return end
        if not navExtraDataHunter.nav1Id.shitConnnections then return end
        
        navExtraDataHunter.nav1Id["lastConnectionFlag"] = nil
        navExtraDataHunter.nav1Id.shitConnnections[nav2Id] = nil
    end )

    if not superShitConnection then return end
    if not istable( navExtraDataHunter.nav1Id.superShitConnection ) then navExtraDataHunter.nav1Id.superShitConnection = {} end
    navExtraDataHunter.nav1Id.superShitConnection[nav2Id] = true
    navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] = CurTime()
    timer.Simple( 520, function()
        local nav = navmesh.GetNavAreaByID( nav1Id )
        if not nav then return end
        if not nav:IsValid() then return end
        local lastFlag = navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] or 0
        if lastFlag + 110 < CurTime() then return end
        if not navExtraDataHunter.nav1Id then return end
        if not navExtraDataHunter.nav1Id.superShitConnection then return end
        
        navExtraDataHunter.nav1Id["lastSuperConnectionFlag"] = nil
        navExtraDataHunter.nav1Id.superShitConnection[nav2Id] = nil
    end )
end

local function restoreFlag( data )
    local flag = data.Flag
    local navId = data.Id
    if not flag then return end
    if not navId then return end
    local nav = navmesh.GetNavAreaByID( navId )
    if not nav then return end
    if not nav:IsValid() then return end
    local oldAtt = nav:GetAttributes()
    local newAtt = oldAtt + -flag
    nav:SetAttributes( newAtt )
end

local function restoreAllNavFlags()
    for _, data in pairs( navExtraDataHunter ) do
        restoreFlag( data )
    end
end

hook.Add( "ShutDown", "strawTermHunterRestoreFlags", restoreAllNavFlags )

-- add constraints 

local function FindSpot2( self, Options )
    local pos = Options.Pos
    local SelfPos = self:GetPos()
    local Checked = self.CheckedNavs
    
    local Areas = navmesh.Find( pos, Options.Radius, Options.Stepdown, Options.Stepup )
    if not Areas then return end
    local Count = table.Count( Areas )
    local _ = 0
    local Curr = Areas[1]
    local HidingSpots = {}
    local FinalSpot = nil
    
    while _ < Count do
        _ = _ + 1
        local Curr = Areas[_]
        local Valid = Curr:IsValid()
        if not Valid then return end

        local unReachable = not self:areaIsReachable( Curr )
        local AreaChecked = Checked[ Curr:GetID() ] 
        local UnderWater = Curr:IsUnderwater() and not Options.AllowWet
        local block = unReachable or UnderWater or AreaChecked
        if Valid and not block then
            local ValidSpots = Curr:GetHidingSpots( Options.Type )
            table.Add( HidingSpots, ValidSpots )
        else
            debugoverlay.Cross( Curr:GetCenter(), 2, 10, Color( 255, 0, 0 ), true )
        end
    end
    
    table.sort( HidingSpots, function( a, b ) -- sort hiding spots by distance to me
        local ADist = a:DistToSqr( SelfPos )
        local BDist = b:DistToSqr( SelfPos )
        return ADist < BDist 
    end )

    local _ = 0
    local Done = false
    local Count = table.Count( HidingSpots )
    local Offset = Vector( 0,0,50 )

    while _ < Count and not Done do
        _ = _ + 1
        local CurrSpot = HidingSpots[_]
        local DistSqrToCurr = CurrSpot:DistToSqr( pos )
        if SqrDistGreaterThan( DistSqrToCurr, Options.MinRadius ) then
            if not Options.Visible then 
                if not PosCanSee( pos + Offset, CurrSpot + Offset ) then
                    Done = true
                    FinalSpot = CurrSpot
                else 
                    debugoverlay.Cross( CurrSpot, 2, 10, Color( 255, 0, 0 ), true )
                end
            elseif Options.Visible then
                if PosCanSee( SelfPos + Offset, CurrSpot + Offset ) then
                    Done = true
                    FinalSpot = CurrSpot
                end
            end
        end
        if not Done then
            local currSpotNav = getNearestNav( CurrSpot )
            if currSpotNav then 
                if currSpotNav:IsValid() then
                    table.insert( self.CheckedNavs, currSpotNav:GetID(), true )
                end
            end
        else 
            debugoverlay.Cross( FinalSpot, 20, 10, Color( 255, 255, 255 ), true )
        end
    end
    
    if Done and FinalSpot then return FinalSpot 
    else return nil end
end
local function StartNewMove( self ) -- start new move
    self.LastMovementStart = CurTime()
    self.LastMovementStartPos = self:GetPos()
end

local function CanDoNewPath( self, TargPos )
    if self.BlockNewPaths then return false end
    local NewPathDist = 50
    local Dist = self:GetPath():GetLength() or self.DistToEnemy or 0  
    local PathPos = self.PathPos or Vector( 0,0,0 )
    
    if Dist > 10000 then
        NewPathDist = 3000 -- dont do pathing as often if the target is far away from me!
    elseif Dist > 5000 then
        NewPathDist = 1500
    elseif Dist > 500 then
        NewPathDist = 500
    end

    return SqrDistGreaterThan( TargPos:DistToSqr( PathPos ), NewPathDist ) 
end

function ENT:MakeFeud( enemy )
    if not enemy then return end
    if not enemy:Health() then return end
    if enemy:Health() <= 0 then return end
    local maniacHunter = ( self:GetCreationID() % 15 ) == 1
    if enemy:GetClass() == "sb_advanced_nextbot_terminator_hunter" and not maniacHunter then return end

    local Disp = self:Disposition( enemy )
    if not Disp then return end
    if enemy:IsPlayer() then
        self:AddEntityRelationship( enemy, D_HT, 1 ) -- hate players more than anything else
    else
        self:AddEntityRelationship( enemy, D_HT )
    end

    if not enemy:IsNPC() then return end
    if IsValid( enemy:GetActiveWeapon() ) then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )
    end
    if SqrDistGreaterThan( enemy:GetPos():DistToSqr( self:GetPos() ), 200 ) then
        self:memorizeEntAs( enemy, MEMORY_WEAPONIZEDNPC )
    end
    local Disp = enemy:Disposition( self )
    if not Disp then return end
    if Disp == D_HT then return end
    enemy:AddEntityRelationship( self, D_HT )

end


-- do this so we can store extra stuff about new paths
local function SetupPath2( self, endpos, isUnstuck ) 

    if not isvector( endpos ) then return end
    if self.isUnstucking and not isUnstuck then return end

    local endArea = getNearestPosOnNav( endpos )
    local reachable = self:areaIsReachable( endArea.area )
    if not reachable then return end

    StartNewMove( self )
    self:SetupPath( endpos )
    self.PathPos = endpos
    if self:PathIsValid() then return end
    if not self:OnGround() then return end

    self:rememberAsUnreachable( endArea.area )

    local scoreData = {}
    scoreData.decreasingScores = {}
    scoreData.droppedDownAreas = {}

    local scoreFunction = function( scoreData, area1, area2 )
        local score = scoreData.decreasingScores[area1:GetID()] or 10000
        local droppedDown = scoreData.droppedDownAreas[area1:GetID()]
        local dropToArea = area2:ComputeAdjacentConnectionHeightChange(area1)
        if dropToArea > self.loco:GetMaxJumpHeight() or droppedDown then 
            score = 1
            scoreData.droppedDownAreas[area2:GetID()] = true
        else 
            score = score + -1
            self:rememberAsUnreachable( area2 )
        end
        
        debugoverlay.Text( area2:GetCenter(), tostring( score ), 8 )
        scoreData.decreasingScores[area2:GetID()] = score

        return score

    end
    findValidNavResult( scoreData, endArea.area:GetCenter(), 3000, scoreFunction )
end

local function SetupFlankingPath( self, endpos, endNav, aimNav ) 
    if not isvector( endpos ) then return end
    self:startFlankPath( endNav, aimNav )
    SetupPath2( self, endpos ) 
    self:endFlankPath()
end

function ENT:shootAt( endpos, blockShoot )
    if not endpos then return end
    local out = nil
    local wep = self:GetActiveWeapon()
    local pos = self:GetShootPos()
    local dir = endpos-pos
    dir:Normalize()

    self:SetDesiredEyeAngles(dir:Angle())

    local dot = math.Clamp(self:GetEyeAngles():Forward():Dot(dir),0,1)
    local ang = math.deg(math.acos(dot))
    
    if ang<=25 and not blockShoot then
        local filter = self:GetChildren()
        filter[#filter+1] = self
        filter[#filter+1] = enemy
        self:WeaponPrimaryAttack()
        
    end
    if ang<1 then
        out = true
    end
    return out
end


local function HunterIsStuck( self )
    local lastUnstuck = self.lastUnstuckStart or 0 
    if ( CurTime() + -0.25 ) < lastUnstuck then return end

    if not self.NextStuckCheck then 
        self.NextStuckCheck = 0 
        self.StuckPos3 = Vector(0,0,0)
        self.StuckPos2 = Vector(0,0,0)
        self.StuckPos1 = Vector(0,0,0)
    end
    
    local HasAcceleration = self.loco:GetAcceleration()
    if HasAcceleration <= 0 then return end
    
    local MyPos = self:GetPos()
    local StartPos = self.LastMovementStartPos or Vector( 0,0,0 )
    local NoVel = self:GetVelocity():Length() < 50
    local GoalPos = self.PathPos or Vector( 0,0,0 )
    local NotMoving = Dist2D( MyPos, self.StuckPos3 ) < 20
    local FarFromStart = Dist2D( MyPos, StartPos ) > 15
    local FarFromStartAndNew = FarFromStart or ( self.LastMovementStart + 1 < CurTime() ) 
    local FarFromEnd = Dist2D( MyPos, GoalPos ) > 15
    
    local roundedCur = math.Round( CurTime(), 1 )

    if ( roundedCur % 1 ) == 0 and self.NextStuckCheck < CurTime() then
        self.NextStuckCheck = CurTime() + 0.5
        self.StuckPos3 = self.StuckPos2
        self.StuckPos2 = self.StuckPos1
        self.StuckPos1 = MyPos
    end
    --print(NoVel, FarFromStartAndNew, FarFromEnd, NotMoving)
    return NoVel and FarFromStartAndNew and FarFromEnd and NotMoving
end

--do this so we can override the nextbot's current path
function ENT:ControlPath2( AimMode )
    local result = nil
    local badPathAndStuck = self.isUnstucking and not self:PathIsValid()

    if HunterIsStuck( self ) or badPathAndStuck then -- new unstuck
        self.startUnstuckDestination = self.PathPos -- save where we were going
        self.startUnstuckPos = self:GetPos()
        self.lastUnstuckStart = CurTime()
        local myNav = self:GetCurrentNavArea()
        local scoreData = {}
        
        scoreData.canDoUnderWater = self:isUnderWater()
        scoreData.self = self
        scoreData.dirToEnd = self:GetForward()
        scoreData.bearingPos = self.startUnstuckPos

        if self:PathIsValid() then 
            scoreData.dirToEnd = DirToPos( self:GetPos(), self:GetPath():GetEnd() )
            local goal = self:GetPath():GetCurrentGoal()
            local nextArea = goal.area
            if not nextArea then goto skipTheShitConnectionFlag end
            if not nextArea:IsValid() then goto skipTheShitConnectionFlag end
            debugoverlay.Line( myNav:GetCenter(), nextArea:GetCenter(), 8, Color( 255, 255, 0 ) )
            flagConnectionAsShit( myNav, goal.area )
            ::skipTheShitConnectionFlag::
        end

        local scoreFunction = function( scoreData, area1, area2 ) -- find an area that is at least in the opposite direction of our current path
            local dirToEnd = scoreData.dirToEnd:Angle()
            local bearing = bearingToPos( scoreData.bearingPos, dirToEnd, area2:GetCenter(), dirToEnd )
            local bearing = math.abs( bearing )
            local dropToArea = area1:ComputeAdjacentConnectionHeightChange(area2)
            local score = 5
            if area2:HasAttributes(NAV_MESH_AVOID) then 
                score = 0.1 
            elseif area2:HasAttributes(NAV_MESH_TRANSIENT) then 
                score = 0.1 
            elseif bearing < 45 then
                score = score*15
            elseif bearing < 135 then
                score = score*5
            elseif bearing > 135 then
                score = 0
            else
                local dist = scoreData.bearingPos:DistToSqr( area2:GetCenter() )
                local removed = dist * 0.0001
                score = math.Clamp( 1 - removed, 0, 1 )
            end
            if scoreData.self.walkedAreas[area2:GetID()] then
                score = score*0.9
            end
            if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                score = score * 0.001
            end
            if dropToArea > self.loco:GetMaxJumpHeight() then 
                score = score * 0.01
            end
            
            -- debugoverlay.Text( area2:GetCenter(), tostring( math.Round( bearing ) ), 4 )

            return score

        end

        local escapePos, escapeArea = findValidNavResult( scoreData, self:GetPos(), 800, scoreFunction )
        if not escapeArea then return end
        if not escapeArea:IsValid() then return end
        SetupPath2( self, escapeArea:GetRandomPoint(), true ) 

        if self:PathIsValid() then
            self.initArea = myNav
            self.initAreaId = self.initArea:GetID()
            
            local areaSurfaceArea = self.initArea:GetSizeX() * self.initArea:GetSizeY()
            if areaSurfaceArea < 150000 then
                -- mark this as avoid so we dont make the same mistake again right after!
                flagForTime( self.initArea, 120, NAV_MESH_AVOID )
            else -- if we flag big areas with avoid then lag becomes a huge problem
                flagForTime( self.initArea, 120, NAV_MESH_TRANSIENT )
            end
        end

        self.isUnstucking = true
        self.tryToHitUnstuck = true

    end
    if self.tryToHitUnstuck then
        local done = nil
        if self.hitTimeout then
            if self.hitTimeout < CurTime() then
                done = true
            elseif IsValid( self.entToBeatUp ) then
                local endpos = getBestPos( self.entToBeatUp )
                self:shootAt( endpos, nil )
            end
        elseif IsValid( self.LastShootBlocker ) then
            --print( tostring( self.LastShootBlocker ) .. "a" )
            local caps = self:CapabilitiesGet()
            if bit.band( caps, CAP_INNATE_MELEE_ATTACK1 ) <= 0 then
                self:DropWeapon()
            end
            self.entToBeatUp = self.LastShootBlocker
            self.hitTimeout = CurTime() + 2
        else
            done = true
        end
        if done then
            self.hitTimeout = nil
            self.tryToHitUnstuck = nil
        end
    elseif self.isUnstucking then

        local result = self:ControlPath(AimMode)
        local DistToStart = self:GetPos():Distance( self.startUnstuckPos )
        local FarEnough = DistToStart > 400
        local MyNavArea = self:GetCurrentNavArea()
        local NotStart = self.initAreaId != MyNavArea:GetID()
        
        --print("unstucking" )

        local Escaped = nil
        local Failed = nil
        
        if FarEnough and NotStart then 
            Escaped = true
        elseif result then
            Escaped = true
        elseif result==false then
            Failed = true 
        end
        if Escaped then
            self.isUnstucking = nil
            SetupPath2( self, self.startUnstuckDestination ) 
        end
    else
        local notProgressing = self:GetVelocity():Length() < 10 and self:GetPath():GetLength() > 50
        if notProgressing then 
            AimMode = true
        end 
        result = self:ControlPath(AimMode)
        local path = self:GetPath()
        local currGoal = path:GetCurrentGoal()
        if istable( currGoal ) then
            local goalArea = currGoal.area
            local nextPathSegment = nil
            local segsSinceCurrent = nil
            for _, currSeg in ipairs( path:GetAllSegments() ) do
                if segsSinceCurrent then
                    segsSinceCurrent = segsSinceCurrent + 1
                    if segsSinceCurrent > 4 then
                        nextPathSegment = currSeg
                        break
                    end
                elseif currSeg.area == goalArea then
                    segsSinceCurrent = 1
                end 
            end
            if nextPathSegment then
                local nextPos = nextPathSegment.pos
                local destZ = nextPos[3]
                local canSeeDest = PosCanSee( self:GetPos(), nextPos + Vector( 0,0,10 ) )
                if self:IsJumping() and canSeeDest then
                    local velTowardsDest = ( self:GetPos() - nextPos ):GetNormalized() * 25
                    local myVel = self.loco:GetVelocity()
                    self.loco:SetVelocity( myVel + -velTowardsDest )
                end
            end
        end
    end
    return result
end

function ENT:validSoundHint( minTime )
    if not self.lastHeardSoundHint then return end
    if minTime > ( self.lastHeardSoundTime or 0 ) then return end
    return true

end

-- do this so we can get data about current tasks easily
function ENT:StartTask2( Task, Data )
    print( Task )
    self.InvalidAfterwards = nil
    self.BlockNewPaths = nil -- make sure this never persists between tasks
    Data2 = Data or {}
    Data2.startTime = CurTime()
    self:StartTask( Task, Data2 )
end

function ENT:HasWeapon2()
    local realWeapon = self:GetActiveWeapon():IsValid() and (CLIENT or self:GetActiveLuaWeapon():IsValid())
	if not realWeapon then return false end
    local unarmed = self:GetActiveWeapon():GetClass() == TERM_FISTS
    return realWeapon and not unarmed
end

function ENT:canGetWeapon()
    local armed = self:HasWeapon2()
    if armed then return end
    local nextSearch = self.nextWeapSearch or 0
    if nextSearch < CurTime() then
        self.nextWeapSearch = CurTime() + math.random( 1, 2 )
        self.cachedNewWeapon = self:FindWeapon()
    end
    local newWeap = self.cachedNewWeapon
    return IsValid( newWeap ) 
end

function ENT:enemyBearingToMe()
    local enemy = self:GetEnemy()
    if not enemy then return end
    local myPos = self:GetPos()
    local enemyPos = enemy:GetPos()
    local enemyAngle = enemy:EyeAngles()
    return math.abs( bearingToPos( myPos, enemyAngle, enemyPos, enemyAngle ) ) 
end

function ENT:EnemyAcquired( currentTask )
    if not IsValid( self ) then return end
    if not IsValid( self:GetEnemy() ) then return end
    self:TaskComplete( currentTask )
    local hp = self:Health() 
    local maxHp = self:GetMaxHealth()
    local bearingToMeAbs = self:enemyBearingToMe()
    local distToEnemySqr = self:GetPos():DistToSqr( self:GetEnemy():GetPos() )
    local damaged = hp < ( maxHp * 0.75 )
    local veryDamaged = hp < ( maxHp * 0.5 )
    local enemySeesMe = bearingToMeAbs < 70
    local lowOrRand = ( damaged and math.random( 0, 100 ) > 20 ) or math.random( 0, 100 ) > 70
    local doWatch = hp == maxHp and SqrDistGreaterThan( distToEnemySqr, 1000 ) and not self.boredOfWatching
    --print( bearingToMeAbs, hp == maxHp, SqrDistGreaterThan( distToEnemySqr, 1000 ) )
    local doFlank = lowOrRand and not SqrDistLessThan( distToEnemySqr, 300 )
    if doWatch then
        self:StartTask2( "movement_watch" )
    elseif enemySeesMe and ( lowOrRand or veryDamaged ) then
        self:StartTask2( "movement_stalkenemy" )
    elseif doFlank then 
        self:StartTask2( "movement_flankenemy" )
    else
        self:StartTask2( "movement_followenemy" )
    end
end

function ENT:markAsWalked( area )
    if not IsValid( area ) then return end
    self.walkedAreas[area:GetID()] = true
    timer.Simple( 60, function()
        if not IsValid( self ) then return end
        if not IsValid( area ) then return end
        self.walkedAreas[area:GetID()] = nil

    end ) 
end

function ENT:canDoRun() 
    local area = self:GetCurrentNavArea()
    if not area then return end
    if not area:IsValid() then return end
    if not area:IsFlat() then return end
    if area:HasAttributes( NAV_MESH_AVOID ) then return end
    if area:HasAttributes( NAV_MESH_CLIFF ) then return end
    if area:HasAttributes( NAV_MESH_TRANSIENT ) then return end
    if area:HasAttributes( NAV_MESH_STAIRS ) then return end
    local path = self:GetPath()
    if not path then return true end
    local goal = path:GetCurrentGoal()
    if not goal then return true end
    local nextArea = goal.area
    if not nextArea then return true end
    if not nextArea:IsFlat() then return end
    if not nextArea:IsValid() then return true end
    if nextArea:HasAttributes( NAV_MESH_AVOID ) then return end
    if nextArea:HasAttributes( NAV_MESH_CLIFF ) then return end
    if nextArea:HasAttributes( NAV_MESH_TRANSIENT ) then return end
    if nextArea:HasAttributes( NAV_MESH_STAIRS ) then return end
    return true
end

function ENT:walkArea()
    local walkedArea = self:GetCurrentNavArea()
    local scoreData = {}
    self:rememberAsReachable( walkedArea ) 
    scoreData.visCheckArea = walkedArea
    scoreData.self = self

    local nextFloodMark = self.nextFloodMarkWalkable or 0

    if nextFloodMark > CurTime() then return end

    self.nextFloodMarkWalkable = CurTime() + math.random( 1, 1.5 )

    local scoreFunction = function( scoreData, area1, area2 )
        local score = 0
        if area2:IsCompletelyVisible( scoreData.visCheckArea ) and not scoreData.self.walkedAreas[area2:GetID()] then
            scoreData.self:markAsWalked( area2 )
            score = 25
        end        
        return score

    end

    searchPos = findValidNavResult( scoreData, self:GetPos(), 1000, scoreFunction )
end

function ENT:areaIsReachable( area )
    if not area then return end
    if not IsValid( area ) then return end
    if self.unreachableAreas[area:GetID()] then return end
    return true
end

function ENT:rememberAsUnreachable( area )
    if not area then return end
    if not area:IsValid() then return end
    self.unreachableAreas[area:GetID()] = true
    return true
end

function ENT:rememberAsReachable( area )
    if not area then return end
    if not area:IsValid() then return end
    self.unreachableAreas[area:GetID()] = nil
    return true
end

function ENT:isUnderWater()
    if not self:GetCurrentNavArea() then return false end
    if not self:GetCurrentNavArea():IsValid() then return false end
    return self:GetCurrentNavArea():IsUnderwater()
end

--cool dmage system stuff
ENT.BGrpHealth = {}
ENT.OldBGrpSteps = {}
ENT.BGrpMaxHealth = 150
ENT.MedCal = 4
ENT.HighCal = 80

ENT.BodyGroups = { 
    ["Glasses"] = 0,  
    ["Head"] = 1,
    ["Torso"] = 2,
    ["RArm"] = 3,
    ["LArm"] = 4,
    ["RLeg"] = 5,
    ["LLeg"] = 6,
}
ENT.HitTranslate = {
    [1] = { 0, 1 },
    [2] = { 2 },
    [3] = { 2 },
    [4] = { 4 },
    [5] = { 3 },
    [6] = { 6 },
    [7] = { 5 },
}
ENT.GroupSteps = {
    [0] = { [3] = 1, [2] = 2, [1] = 3 },
    [1] = { [3] = 0, [2] = 1, [1] = 2 },
    [2] = { [3] = 0, [2] = 0, [1] = 1 },
    [3] = { [3] = 0, [2] = 0, [1] = 1 },
    [4] = { [3] = 0, [2] = 0, [1] = 1 },
    [5] = { [3] = 0, [2] = 0, [1] = 1 },
    [6] = { [3] = 0, [2] = 0, [1] = 1 },
    --[1] = { 0, 1, 2 },
}

ENT.Rics = {
    "weapons/fx/rics/ric3.wav",
    "weapons/fx/rics/ric5.wav",
}
ENT.Chunks = {
    "physics/body/body_medium_break2.wav",
    "physics/body/body_medium_break3.wav",
    "physics/body/body_medium_break4.wav",
}
ENT.Whaps = {
    "physics/body/body_medium_impact_hard1.wav",
    "physics/body/body_medium_impact_hard2.wav",
    "physics/body/body_medium_impact_hard3.wav",
}
ENT.Hits = {
    "physics/metal/metal_sheet_impact_hard8.wav",
    "physics/metal/metal_sheet_impact_hard7.wav",
    "physics/metal/metal_sheet_impact_hard6.wav",
    "physics/metal/metal_sheet_impact_hard2.wav",
}
ENT.Creaks = {
    "physics/metal/metal_box_strain1.wav",
    "physics/metal/metal_box_strain2.wav",
    "physics/metal/metal_box_strain3.wav",
    "physics/metal/metal_box_strain4.wav",
}

local function BodyGroupDamageThink( self, Group, Damage, Pos )
    
    if not isnumber( Group ) then return end
    if self:GetModel() ~= ARNOLD_MODEL then return end
    local CurrHSteps = self.GroupSteps[Group]
    if not istable( CurrHSteps ) then return end
    
    if not isnumber( self.BGrpHealth[Group] ) then
        self.BGrpHealth[Group] = self.BGrpMaxHealth
        self.OldBGrpSteps[Group] = 10
    end
    
    self.BGrpHealth[Group] = math.Clamp( self.BGrpHealth[Group] + -Damage, 0, math.huge )
    
    local Steps = table.Count( self.GroupSteps[Group] )
    local CurrStep = math.ceil( ( self.BGrpHealth[Group] / self.BGrpMaxHealth ) * Steps )
    local OldStep = self.OldBGrpSteps[Group]
    self.OldBGrpSteps[Group] = CurrStep
    
    if OldStep <= CurrStep then return end
    if Group ~= 0 then 
        self:EmitSound( table.Random( self.Whaps ), 75, math.random( 85, 90 ) )
        self:EmitSound( table.Random( self.Chunks ), 75, math.random( 115, 120 ) )
        local Data = EffectData()
        Data:SetOrigin( Pos )
        Data:SetColor(0)
        Data:SetScale(1)
        Data:SetRadius(1)
        Data:SetMagnitude(1)
        util.Effect( "BloodImpact", Data )
    end
    if not isnumber( CurrHSteps[CurrStep] ) then return end
    self:SetBodygroup( Group, self.GroupSteps[Group][CurrStep] )
    
end
local function BodyGroupDamage( self, ToBGs, BgDamage, Damage )
    if istable( ToBGs ) then 
        local _ = 0
        local Count = table.Count( ToBGs )
        while _ < Count do
            _ = _ + 1
            local BGroup = ToBGs[_]
            BodyGroupDamageThink( self, BGroup, BgDamage, Damage:GetDamagePosition() )
        end
    end
end
local function MedCalRics( self )
    self:EmitSound( table.Random( self.Rics ), 75, math.random( 92, 100 ), 1, CHAN_AUTO )
end
local function MedDamage( self, Damage )
    self:EmitSound( table.Random( self.Hits ), 85, math.random( 105, 110 ), 1, CHAN_AUTO )
    if Damage:IsBulletDamage() then
        self:EmitSound( table.Random( self.Rics ), 85, math.random( 75, 80 ), 1, CHAN_AUTO )
    end
end
local function CatDamage( self )
    self:EmitSound( table.Random( self.Creaks ), 85, 150, 1, CHAN_AUTO )
    self:EmitSound( table.Random( self.Hits ), 85, 80, 1, CHAN_AUTO )
end
function ENT:takeDamageForce( force )
    local dir = force:GetNormalized() * 0.6 + self:GetUp() * 0.2
    local force = dir * self:GetPhysicsObject():GetMass()
    force = force*3
    self.loco:SetVelocity( force )
end

local function OnDamaged( self, Hitgroup, Damage )

    if self:GetClass() ~= "sb_advanced_nextbot_terminator_hunter" then return end
    self.lastDamagedTime = CurTime()
    local ToBGs = nil
    local BgDmg = false
    local KBack = false
    local BgDamage = 0
    local DamageG = Damage:GetDamage()
    local DmgSound = false
    local DmgType = Damage:GetDamageType()
    
    self:MakeFeud( Damage:GetAttacker() )

    if not Damage:IsExplosionDamage() then 
        if DamageG >= self.HighCal then 
            BgDmg = true
            KBack = true
            BgDamage = Damage:GetDamage()
            Damage:SetDamage( DamageG / 3.5 )
            MedDamage( self, Damage )
        elseif DamageG > self.MedCal then
            BgDmg = true
            BgDamage = Damage:GetDamage() / 4
            Damage:SetDamage( 1 )
            if Damage:IsBulletDamage() then 
                MedCalRics( self )
            end
        else
            BgDmg = true
            BgDamage = Damage:GetDamage() / 16
            Damage:SetDamage( 0 )
        end
    elseif DamageG > 60 then
        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )
        Damage:SetDamage( math.Clamp( DamageG, 0, 100 ) )
        self:takeDamageForce( Damage:GetDamageForce() )
        BgDamage = 40
        CatDamage( self )
    end
    
    if BgDmg then 
        if self:GetModel() ~= ARNOLD_MODEL then return end
        ToBGs = self.HitTranslate[Hitgroup] -- get bodygroups to do stuff to
        
        if not istable( ToBGs ) then return end
        
        local Data = EffectData()
        Data:SetOrigin( Damage:GetDamagePosition() )
        Data:SetScale(1)
        Data:SetRadius(1)
        Data:SetMagnitude(1)
        util.Effect( "Sparks", Data )
    end
    
    BodyGroupDamage( self, ToBGs, BgDamage, Damage )
end

hook.Add( "ScaleNPCDamage", "sb_anb_straw_terminator_damage", OnDamaged )

function ENT:OnTakeDamage( Damage )
    self.lastDamagedTime = CurTime()
    local DmgType = Damage:GetDamageType()
    if DmgType == 131072 then --acid!
        BgDamage = 40
        
        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )
        Damage:ScaleDamage( 0 )
    elseif DmgType == 67108865 then --combine ball!
        Damage:SetDamage( 150 )
        BgDamage = 150
        
        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, table.Count( ToBGs ) ) )
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )
        
        CatDamage( self )
        self:takeDamageForce( Damage:GetDamageForce() )
        self:EmitSound( "weapons/physcannon/energy_disintegrate4.wav", 90, math.random( 90, 100 ), 1, CHAN_AUTO )
    elseif DmgType == 8 or DmgType == 268435464 then -- fire damage!
        Damage:SetDamage( 0 )
        BgDamage = 1
        
        ToBGs = { 0, 1, 2, 3, 4, 5, 6 }
        table.remove( ToBGs, math.random( 0, 6 ) )
        BodyGroupDamage( self, ToBGs, BgDamage, Damage )
    end
end




-- custom values for the nextbot base to use
ENT.JumpHeight = 70 * 2.5
ENT.SpawnHealth = 1000
ENT.AimSpeed = 360
ENT.PathStuckJumpTime = 1
ENT.MoveSpeed = 300
ENT.RunSpeed = 500 -- bit faster than players
ENT.AccelerationSpeed = 1000
ENT.AccelerationSpeed = 3000
ENT.DeathDropHeight = 2000 --not afraid of heights
ENT.CheckedNavs = {} -- add this here even if its hacky
ENT.BadNavAreas = {} -- nav areas that never should be checked
ENT.LastEnemySpotTime = 0

function ENT:Think() -- true hack
    self:walkArea()
    local Mass = 5000
    local Obj = self:GetPhysicsObject()
    if not IsValid( Obj ) then return end
    if Obj:GetMass() ~= Mass then
        self:GetPhysicsObject():SetMass(Mass)
    end
end

function ENT:Initialize()

	BaseClass.Initialize(self)
    self.walkedAreas = {}
    self.unreachableAreas = {}
    self.awarenessMemory = {}
    self.awarenessUnknown = {}
    self.memorizedStates = {}
    
    self:SetCurrentWeaponProficiency( WEAPON_PROFICIENCY_VERY_GOOD )

	self:SetModel(termModel())
    self:SetFriendly(false)

    self:SetClassRelationship( "player", D_HT,1)
	self:SetClassRelationship( "sb_advanced_nextbot_terminator_hunter", D_LI )
	self:SetClassRelationship( "sb_advanced_nextbot_soldier_follower", D_HT )
	self:SetClassRelationship( "sb_advanced_nextbot_soldier_friendly", D_HT )
	self:SetClassRelationship( "sb_advanced_nextbot_soldier_hostile", D_HT )

    self.targetName = "termhunter" .. self:GetCreationID()
    self:SetKeyValue( "targetname", self.targetName )

    self.TaskList = {
        ["shooting_handler"] = {
            OnStart = function(self,data)
                data.PassBlockerTime = CurTime()
            
                data.PassBlocker = function(blocker)
                    local dir = blocker:WorldSpaceCenter()-self:GetPos()
                    dir.z = 0
                    
                    local _,diff = WorldToLocal(vector_origin,dir:Angle(),vector_origin,self:GetDesiredEyeAngles())
                    local side = diff.y>0 and 1 or -1
                    local b1,b2 = self:GetCollisionBounds()
                    
                    self:Approach(self:GetPos()+dir:Angle():Right()*side*10)
                end
            end,
            BehaveUpdate = function(self,data,interval)
                local wep = self:HasWeapon()
                if not wep then
                    self:Give( TERM_FISTS )
                end
                if not self:HasWeapon() then return end
                
                local wep = self:GetActiveWeapon()
                local caps = self:CapabilitiesGet()
                local enemy = self:GetEnemy()
                local doShootingPrevent = nil 
                if self.PreventShooting then
                    doShootingPrevent = true 
                end 

                if IsValid( enemy ) then
                    if bit.band( caps, CAP_WEAPON_RANGE_ATTACK1 ) > 0 then
                        if self.IsSeeEnemy and IsValid(enemy) then
                            local shootableVolatile = self:getShootableVolatiles( enemy )
                            if wep:Clip1()<=0 then
                                self:WeaponReload()
                            elseif shootableVolatile then
                                --print( shootableVolatile )
                                self:shootAt( getBestPos( shootableVolatile ) )    
                            else
                                self:shootAt( self.LastEnemyShootPos, doShootingPrevent )
                            end
                        elseif wep:Clip1()<wep:GetMaxClip1()/2 then
                            self:WeaponReload()
                        end
                    --melee
                    elseif bit.band( caps, CAP_INNATE_MELEE_ATTACK1 ) > 0 then
                        local blockShoot = doShootingPrevent or true
                        if self.DistToEnemy < wep.Range * 2 then
                            blockShoot = nil
                        end
                        self:shootAt( self.LastEnemyShootPos, blockShoot )
                    end
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "shooting_handler" )
            end,
        },
        ["awareness_handler"] = {
            BehaveUpdate = function(self,data,interval)
                local nextAware = data.nextAwareness or 0
                if nextAware < CurTime() then 
                    data.nextAwareness = CurTime() + 1.5
                    self:understandSurroundings()
                end
            end,
        },
        ["reallystuck_handler"] = {
            OnStart = function(self,data)
                data.historicPositions = {}
            end,
            BehaveUpdate = function(self,data)
                local nextCache = data.nextCache or 0
                if nextCache < CurTime() then 
                    local myPos = self:GetPos()
                    data.nextCache = CurTime() + 1
                    table.insert( data.historicPositions, 1, myPos )

                    if #data.historicPositions > 30 then
                        table.remove( data.historicPositions, 31 )
                        table.remove( data.historicPositions, 32 )
                        local stuck = true
                        for _, historicPos in ipairs( data.historicPositions ) do
                            local distSqr = myPos:DistToSqr( historicPos )
                            if SqrDistGreaterThan( distSqr, 15 ) then
                                stuck = nil
                                break
                            end
                        end
                        if stuck then
                            self:OnStuck()
                        end
                    end
                end
            end,
        },
        ["enemy_handler"] = {
            OnStart = function(self,data)
                data.UpdateEnemies = CurTime()
                data.HasEnemy = false
                data.playerCheckIndex = 0
                self.IsSeeEnemy = false
                self.DistToEnemy = 0
                self:SetEnemy(NULL)

                self.UpdateEnemyHandler = function(forceupdateenemies)
                    local prevenemy = self:GetEnemy()
                    local newenemy = prevenemy

                    if forceupdateenemies or !data.UpdateEnemies or CurTime()>data.UpdateEnemies or data.HasEnemy and !IsValid(prevenemy) then
                        data.UpdateEnemies = CurTime()+0.5
                        
                        self:FindEnemies()

                        -- here if the above stuff didnt find an enemy we force it to rotate through all players one by one
                        if not GetConVar( "ai_ignoreplayers" ):GetBool() then
                            local allPlayers = player.GetAll()
                            local pickedPlayer = allPlayers[data.playerCheckIndex]
                            
                            if IsValid( pickedPlayer ) then 
                                local visible = PosCanSee( self:GetShootPos(), self:EntShootPos( pickedPlayer ) )
                                local alive = pickedPlayer:Health() > 0
                                if visible and alive then
                                    self:UpdateEnemyMemory( pickedPlayer, pickedPlayer:GetPos() )

                                end
                            end
                            local new = data.playerCheckIndex + 1
                            if new > table.Count( allPlayers ) then
                                data.playerCheckIndex = 1
                            else
                                data.playerCheckIndex = new
                            end
                        end
                        
                        local enemy = self:FindPriorityEnemy()

                        if IsValid(enemy) then
                            newenemy = enemy
                            local enemyPos = enemy:GetPos()
                            if not self.EnemyLastPos then self.EnemyLastPos = enemyPos end 
                            self.LastEnemySpotTime = CurTime()
                            self.DistToEnemy = self:GetPos():Distance( enemyPos )
                            self.IsSeeEnemy = self:CanSeePosition(enemy)
                            self:MakeFeud(enemy) -- override enemy's relations to me
                            if self.IsSeeEnemy then 
                                self.EnemyLastDir = DirToPos( self.EnemyLastPos, enemyPos )
                                self.LastEnemyForward = enemy:GetForward()
                                self.EnemyLastPos = enemyPos
                                debugoverlay.Line( enemyPos, enemyPos + ( self.EnemyLastDir * 100 ), 5, Color( 255, 255, 255 ), true )
                            end
                            if enemy == self then
                                self:AddEntityRelationship( enemy, D_LI, 0 ) --hardcoded this
                            end
                        end
                    end

                    if IsValid(newenemy) then
                        if !data.HasEnemy then
                            self:RunTask("EnemyFound", newenemy)
                        elseif prevenemy!=newenemy then
                            self:RunTask("EnemyChanged", newenemy,prevenemy)
                        end
                        
                        data.HasEnemy = true
                        
                        if self:CanSeePosition(newenemy) then
                            self.LastEnemyShootPos = self:EntShootPos(newenemy)
                            self:UpdateEnemyMemory(newenemy,newenemy:GetPos())
                        end
                    else
                        if data.HasEnemy then
                            self:RunTask("EnemyLost", prevenemy)
                        end
                        
                        data.HasEnemy = false
                        self.IsSeeEnemy = false
                    end
                    
                    if not data.HasEnemy then
                        if self.notciedChangedEntity then
                            self.EnemyLastHint = self.notciedChangedEntity
                            self.notciedChangedEntity = nil 
                        end
                    end

                    self:SetEnemy(newenemy)
                end
            end,
            BehaveUpdate = function(self,data,interval)
                self.UpdateEnemyHandler()
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "enemy_handler" )
            end,
        },
        ["movement_handler"] = {
            OnStart = function(self,data)
                self:TaskComplete( "movement_handler" )
                
                local task,data2 = "movement_wait"
                local armed = self:HasWeapon2()
                local findwep = not armed and self:FindWeapon()
                
                if not armed and not IsValid(self:GetEnemy()) and findwep then
                    task,data2 = "movement_getweapon", {Wep = findwep, nextTask = data.nextTask}
                else
                    if IsValid(self:GetEnemy()) then
                        self:EnemyAcquired("movement_handler" )
                        task,data2 = nil
                    else
                        if self.awarenessUnknown[1] then
                            task = "movement_understandobject"
                        else
                            task = "movement_inertia"
                            data2 = { Want = math.random( 1, 3 ) }
                        end
                    end
                end
                if task then 
                    self:StartTask2(task,data2)
                end
                
            end,
        },
        ["movement_understandobject"] = {
            OnStart = function(self,data)
                data.object = self.awarenessUnknown[1]
                table.remove( self.awarenessUnknown, 1 )
                data.timeout = CurTime() + 15
                if not IsValid( data.object ) then return end
                data.objectKey = getAwarenessKey( data.object )
                data.objectHealth = data.object:Health() or 0
                data.initToggleState = data.object:GetInternalVariable( "m_toggle_state" )
                if not istable( self.understandAttempts ) then
                    self.understandAttempts = {}
                end
                data.understandAttempts = self.understandAttempts[data.objectKey] or 0
                --print( data.object )
            end,
            BehaveUpdate = function(self,data,interval)
                local definitelyShotAt = ( data.definitelyShotAt or 0 ) < CurTime() and data.shotAt
                local pathLength = self:GetPath():GetLength() or 0
                local internalUnderstandAtt = data.understandAttempts or 0
                local unreachable = internalUnderstandAtt > 2 and SqrDistLessThan( self:GetPos():DistToSqr( data.object ), 400 )
                if self.IsSeeEnemy and self:GetEnemy() then
                    if data.object == self:GetEnemy() then 
                        self:memorizeEntAs( data.object, MEMORY_INERT ) 
                    end
                    data.exit = true
                    self:EnemyAcquired("movement_understandobject" )
                elseif self:canGetWeapon() then 
                    data.exit = true
                    self:TaskFail( "movement_understandobject" )
                    self:StartTask2( "movement_handler" )
                elseif not IsValid( data.object ) then -- we lost the object OR we broke it
                    if not data.trackingBreakable then  
                        data.fail = true
                    else
                        --print("break" )
                        local lastTime = self.lastDamagedTime or 0
                        local lastTimeAdd = lastTime + 1
                        if lastTimeAdd > CurTime() then -- breaking it damaged me!!!!
                            --print("volatile" )
                            self:memorizeEntAs( data.objectKey, MEMORY_VOLATILE )
                            self.lastHeardSoundHint = nil
                        else
                            self:memorizeEntAs( data.objectKey, MEMORY_BREAKABLE )
                        end
                        data.success = true
                    end
                elseif self:validSoundHint( data.startTime ) then
                    data.exit = true
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                elseif self.awarenessMemory[ getAwarenessKey( data.object ) ] ~= MEMORY_MEMORIZING then -- we memorized this already
                    data.fail = true
                elseif data.timeout < CurTime() then -- dont just do this forever
                    if pathLength < 200 or not self:PathIsValid() or data.understandAttempts > 5 or unreachable then
                        self:memorizeEntAs( data.object, MEMORY_INERT )
                    end
                    data.fail = true
                elseif data.checkedUse and definitelyShotAt and not data.entTakingDamage and not data.isButton then -- eliminate if it's inert
                    self:memorizeEntAs( data.object, MEMORY_INERT )
                    data.success = true
                end
                if not data.fail and not data.success and not data.exit then 
                    self.EnemyLastHint = nil -- HACK

                    local objPos = getBestPos( data.object )
                    local _,seeTrace = PosCanSee2( self:GetShootPos(), objPos )
                    debugoverlay.Line( self:GetShootPos(), objPos )
                    local hitTheEnt = seeTrace.HitEntity == data.object
                    local hitPosNear = SqrDistLessThan( seeTrace.HitPos:DistToSqr( objPos ), 5 )
                    local canSeeNear = hitTheEnt or hitPosNear 

                    local weapDist = self:GetActiveLuaWeapon().Range or math.huge
                    local distSqr = self:GetShootPos():DistToSqr( objPos )
                    local canAttack = SqrDistLessThan( distSqr, weapDist )
                    local isNear = SqrDistLessThan( distSqr, 500 )
                    local isClose = SqrDistLessThan( distSqr, 200 )
                    local nearAndFullyVisibile = canSeeNear and isNear and canAttack
                    local closeAndPartiallyVisible = canSeeNear and isClose and canAttack
                    if isClose and self:GetPath():GetLength() < 200 then 
                        if not data.arrived then
                            data.arrived = true
                            data.timeout = CurTime() + 8
                        end
                    end
                    if nearAndFullyVisibile or closeAndPartiallyVisible then
                        if data.object:GetInternalVariable( "m_toggle_state" ) ~= data.initToggleState then 
                            data.isButton = true 
                            self:memorizeEntAs( data.object, MEMORY_INERT )
                            data.success = true
                        end
                        if data.objectHealth then 
                            if data.object:Health() > 300 then 
                                self:memorizeEntAs( data.object, MEMORY_INERT )
                                data.success = true
                            elseif not data.trackingBreakable then
                                data.trackingBreakable = true 
                            end
                            if not data.entTakingDamage and data.object:Health() < data.objectHealth then
                                data.entTakingDamage = true
                                data.timeout = CurTime() + 10
                            end
                        end
                        shotAt = self:shootAt( objPos )
                        if shotAt and canSeeNear and not data.shotAt then 
                            data.definitelyShotAt = CurTime() + 1.5
                            data.shotAt = true
                        end
                        if ( data.nextUse or 0 ) < CurTime() and isClose then
                            data.nextUse = CurTime() + math.random( 0.1, 1 )
                            data.object:Use( self, self )
                            data.checkedUse = true
                        end
                    end
                    if not closeAndPartiallyVisible then
                        local newPath = not self:PathIsValid() or ( self:PathIsValid() and CanDoNewPath( self, objPos ) ) 
                        if newPath then
                            local pathPos = objPos
                            local _,area = getNearestPosOnNav( objPos )
                            if area and not nearAndFullyVisibile then
                                if area:IsValid() then
                                    pathPos = area:GetRandomPoint()
                                end
                            end 
                            SetupPath2( self, pathPos )
                            if not self:PathIsValid() then 
                                self:memorizeEntAs( data.object, MEMORY_INERT )
                                data.fail = true
                            end
                        end
                        local controlPath = self:ControlPath2( true )
                    end
                end
                if data.fail then 
                    self:TaskFail( "movement_understandobject" )
                    self:StartTask2( "movement_handler" )
                end
                if data.success then 
                    self:TaskComplete( "movement_understandobject" )
                    self:StartTask2( "movement_handler" )
                end
            end,
            ShouldRun = function(self,data)
                local length = self:GetPath():GetLength() or 0
                local goodRun = self:canDoRun() 
                return length > 200 and goodRun
            end,
        },
        ["movement_wait"] = {
            OnStart = function(self,data)
                data.Time = CurTime()+(data.Time or math.random(1,2))
            end,
            BehaveUpdate = function(self,data,interval)
                if CurTime()>=data.Time then
                    self:TaskComplete( "movement_wait" )
                    self:StartTask2( "movement_handler" )
                elseif self:validSoundHint( data.startTime ) then
                    self:TaskComplete( "movement_wait" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_wait" )
            end,
        },
        ["playercontrol_handler"] = {
            StopControlByPlayer = function(self,data,ply)
                self:StartTask2( "enemy_handler" )
                self:StartTask2( "movement_wait" )
                self:StartTask2( "shooting_handler" )
            end,
        },
        ["movement_getweapon"] = {
            OnStart = function(self,data)
                if not isstring( data.nextTask ) then
                    data.nextTask = "movement_wait"
                end
                SetupPath2(self, data.Wep:GetPos())
                
                if !self:PathIsValid() then
                    self:TaskFail( "movement_getweapon" )
                    self:StartTask2(data.nextTask)
                end
            end,
            BehaveUpdate = function(self,data)
                if !self:CanPickupWeapon(data.Wep) then
                    self:TaskFail( "movement_getweapon" )
                    self:StartTask2(data.nextTask)
                    
                    return
                end
            
                local result = self:ControlPath2( not self.IsSeeEnemy )
                
                if result then
                    self:TaskComplete( "movement_getweapon" )
                    self:StartTask2(data.nextTask)
                    
                    if self:GetRangeTo(data.Wep)<50 then
                        self:SetupWeapon(data.Wep)
                    end
                elseif result==false then
                    self:TaskFail( "movement_getweapon" )
                    self:StartTask2(data.nextTask)
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_getweapon" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end,
        },
        ["movement_followsound"] = {
            OnStart = function(self,data)
                self:GetPath():Invalidate()
            end,
            BehaveUpdate = function(self,data)
                if not data.Sound then 
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_handler" )
                    return
                end
                local soundPos = self.lastHeardSoundHint or data.Sound
                
                if soundPos then
                    local newPath = not self:PathIsValid() or ( self:PathIsValid() and CanDoNewPath( self, soundPos ) ) 
                    if newPath and not self.isUnstucking then -- HACK
                        local dirFromSoundToMe = DirToPos( soundPos, self:GetPos() )
                        dirFromSoundToMe.z = 0
                        local soundPosOffsetted = soundPos + ( dirFromSoundToMe:GetNormalized() * 500 )
                        local result = getNearestPosOnNav( soundPos )
                        local offsettedResult = getNearestPosOnNav( soundPosOffsetted )
                        if enemyPos and result.area:IsValid() and offsettedResult.area:IsValid() then
                            SetupFlankingPath( self, result.pos, result.area, aimResult.area )
                        end
                        if self:PathIsValid() then 
                            self.PreventShooting = true
                        else
                            SetupPath2( self, result.pos )
                            data.Unreachable = nil
                        end
                        if not self:PathIsValid() then 
                            data.Unreachable = true
                        end
                    end
                end
                local result = self:ControlPath2( !self.IsSeeEnemy )
                local Done = nil
                if self.IsSeeEnemy then
                    Done = true
                    self:EnemyAcquired( "movement_followsound" )
                elseif data.Unreachable then
                    Done = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_searchlastdir" )
                elseif result then
                    Done = true
                    self:TaskComplete( "movement_followsound" )
                    self:StartTask2( "movement_search", { Want = 60, searchCenter = soundPos } )
                elseif result==false then
                    Done = true
                    self:TaskFail( "movement_followsound" )
                    self:StartTask2( "movement_handler" )
                end
                if Done then 
                    self.PreventShooting = nil
                    self.lastHeardSoundHint = nil
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_followenemy" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end
        },
        ["movement_search"] = {
            OnStart = function(self,data)
                if not isnumber( data.Radius ) then 
                    data.Radius = 4000
                end
                if not isnumber( data.Want ) then 
                    data.Want = 100
                end
                if not isnumber( data.Time ) then 
                    data.Time = 0
                end
                --print( "Search!" .. data.Want .. " " .. data.Radius )
                searchCenter = data.searchCenter or self.EnemyLastHint or self:GetPos()
                if self.EnemyLastHint then
                    self.EnemyLastHint = nil
                end
                self.NextForcedSearch = CurTime() + 10
                data.Want = data.Want + -1
                data.Time = CurTime() + data.Time
                local Options = {
                    Type = 1,
                    Pos = searchCenter,
                    Radius = data.Radius,
                    MinRadius = 1,
                    Stepup = 20,
                    Stepdown = 300,
                    AllowWet = self:isUnderWater()
                }
                data.HidingToCheck = FindSpot2( self, Options )
                if data.HidingToCheck == nil then
                    self.InvalidAfterwards = true
                    return 
                end
                local checkNav = getNearestNav( data.HidingToCheck )
                if not checkNav:IsValid() then return end
                data.CheckNavId = checkNav:GetID()
            end,
            BehaveUpdate = function(self,data)
                
                if self.InvalidAfterwards then
                    self:TaskFail( "movement_search" )
                    self:StartTask2( "movement_searchlastdir", {Dir = self:GetForward(), Want = 40} )
                    return
                end

                if data.Time > CurTime() then return end
                
                local MyPos = self:GetPos()
                local HidingToCheck = data.HidingToCheck or Vector()
                local CheckNavId = data.CheckNavId
                local DistToHideSqr = MyPos:DistToSqr( HidingToCheck )

                if isvector( HidingToCheck ) and CanDoNewPath( self, HidingToCheck ) then
                    SetupPath2( self, HidingToCheck )
                end
                
                local result = self:ControlPath2( !self.IsSeeEnemy )
                local Done = false
                local Continue = false
                local BadArea = false
                local WantInternal = data.Want or 0
                
                if WantInternal <= 0 then
                    Done = true
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_handler", {Want = 5} )
                elseif self:canGetWeapon() and not self.IsSeeEnemy then 
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_handler", {nextTask = "movement_search"} )
                elseif self.IsSeeEnemy and self:GetEnemy() then
                    Done = true
                    self:EnemyAcquired( "movement_search" )
                elseif self:validSoundHint( data.startTime ) then
                    self:TaskComplete( "movement_search" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                elseif not result and PosCanSee( MyPos, HidingToCheck ) and SqrDistLessThan( DistToHideSqr, 300 ) then
                    Continue = true
                elseif self.NextForcedSearch < CurTime() then
                    Continue = true
                elseif result then
                    if not PosCanSee( MyPos, HidingToCheck ) or SqrDistLessThan( DistToHideSqr, 300 ) then
                        BadArea = true
                    end
                    Continue = true
                elseif result==false then
                    Continue = true
                    BadArea = true
                end
                
                if Done then 
                    self.CheckedNavs = self.BadNavAreas
                end
                if Continue then
                    if not istable( self.CheckedNavs ) then 
                        self.CheckedNavs = self.BadNavAreas
                    end
                    local searchCenter = self.EnemyLastHint or data.searchCenter
                    self:TaskFail( "movement_search" )
                    if not isnumber( CheckNavId ) then 
                        self:StartTask2( "movement_handler" )
                        return
                    else
                        self:StartTask2( "movement_search", {Want = data.Want, Time = math.random( 0.4, 0.8 ), searchCenter = searchCenter} )
                        table.insert( self.CheckedNavs, CheckNavId, true )
                    end
                end
                if BadArea then
                    table.insert( self.BadNavAreas, CheckNavId, true )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_followtarget" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end,
        },
        ["movement_searchlastdir"] = {
            OnStart = function(self,data)
                data.expiryTime = CurTime() + 10
                if not isnumber( data.Want ) then 
                    data.Want = 10
                end
                data.Want = data.Want + -1
                local Dir = nil
                
                if isvector( data.Dir ) and data.Dir ~= Vector() then
                    Dir = data.Dir
                elseif isvector( self.LastEnemyForward ) then
                    Dir = self.LastEnemyForward
                elseif self.EnemyLastDir ~= Vector() and isvector( self.EnemyLastDir ) then
                    Dir = self.EnemyLastDir
                end
                if Dir == nil or data.Want <= 0 then
                    self.InvalidAfterwards = true
                else
                    local scoreData = {}
                    scoreData.canDoUnderWater = self:isUnderWater()
                    scoreData.self = self
                    scoreData.forward = Dir:Angle()
                    scoreData.bearingCompare = self.EnemyLastPos or self:GetPos()
                    scoreData.visCheckArea = self:GetCurrentNavArea()
    
                    local scoreFunction = function( scoreData, area1, area2 )
                        local ang = scoreData.forward
                        local bearing = bearingToPos( scoreData.bearingCompare, ang, area2:GetCenter(), ang )
                        local bearing = math.abs( bearing )
                        local dropToArea = area1:ComputeAdjacentConnectionHeightChange(area2)
                        local score = math.Rand( 4, 6 )
                        if area2:HasAttributes(NAV_MESH_AVOID) then 
                            score = 0.1 
                        elseif bearing > 135 then
                            score = score*15
                        elseif bearing > 90 then
                            score = score*5
                        else
                            local dist = scoreData.bearingCompare:DistToSqr( area2:GetCenter() )
                            local removed = dist * 0.0001
                            score = math.Clamp( 1 - removed, 0, 1 )
                        end
                        if scoreData.self.walkedAreas[area2:GetID()] then
                            score = score*0.1
                        end
                        if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                            score = score * 0.001
                        end
                        if dropToArea > self.loco:GetMaxJumpHeight() then 
                            score = score * 0.01
                        end
                        
                        -- debugoverlay.Text( area2:GetCenter(), tostring( score ), 8 )
    
                        return score
    
                    end
    
                    searchPos = findValidNavResult( scoreData, self:GetPos(), math.random( 2000, 3500 ), scoreFunction )
                    SetupPath2( self, searchPos )
                    
                    if self:PathIsValid() then return end
                    --nothing worked, fail the task next tick.
                    self.InvalidAfterwards = true
                end
            end,
            BehaveUpdate = function(self,data)
                if self.InvalidAfterwards then
                    self:TaskFail( "movement_searchlastdir" )
                    self:StartTask2( "movement_search", { searchCenter = self.EnemyLastPos or nil} )
                    return
                end
                
                local result = self:ControlPath2( !self.IsSeeEnemy)
                local newSearch = result or data.expiryTime < CurTime()

                if self:canGetWeapon() and not self.IsSeeEnemy then  
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_handler", { nextTask = "movement_searchlastdir"} )
                elseif self.EnemyLastHint then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_search", { Want = 150, Time = 1.5, searchCenter = self.EnemyLastHint } )
                elseif newSearch and data.Want > 0 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want } )
                elseif newSearch and data.Want <= 0 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_search", { Want = 150, Time = 1.5, searchCenter = self.EnemyLastPos or nil } )
                elseif self.IsSeeEnemy then
                    self:EnemyAcquired("movement_searchlastdir" )
                elseif self.awarenessUnknown[1] and data.Want < 2 then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_understandobject" )
                elseif self:validSoundHint( data.startTime ) then
                    self:TaskComplete( "movement_searchlastdir" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                elseif result==false then
                    self:TaskFail( "movement_searchlastdir" )
                    self:StartTask2( "movement_searchlastdir", { Want = data.Want } )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_inertia" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end,
        },
        ["movement_watch"] = {
            OnStart = function(self,data)
                path = self:GetPath()
                path:Invalidate()
                local range1, range2 = 15, 25
                local watchCount = self.watchCount or 0
                if watchCount < 1 then 
                    range1, range2 = 50, 70
                end
                data.giveUpWatchingTime = CurTime() + math.random( range1, range2 )
            end,
            BehaveUpdate = function(self,data)
                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local enemyBearingToMeAbs = math.huge
                local goodEnemy = nil
                if IsValid( enemy ) then
                    data.dirToEnemy = ( self:GetShootPos() - enemy:GetShootPos() ):GetNormalized()
                    goodEnemy = self.IsSeeEnemy
                    enemyBearingToMeAbs = self:enemyBearingToMe()
                end

                local lookingAtBearing = 9

                if goodEnemy and enemyBearingToMeAbs > lookingAtBearing then
                    data.SneakyStaring = true
                    self.PreventShooting = true
                elseif enemyBearingToMeAbs < lookingAtBearing and not data.slinkAway then
                    local min, max = 3, 4
                    local watchCount = self.watchCount or 0
                    if watchCount > 1 then
                        min, max = 1, 2 
                    end 
                    data.slinkAway = CurTime() + math.random( min, max )
                elseif data.SneakyStaring then
                    data.SneakyStaring = nil
                    self.PreventShooting = nil
                end

                local exit = nil

                -- the player looked at us earlier and is still looking
                local slinkAwayTime = data.slinkAway or math.huge
                if slinkAwayTime < CurTime() then
                    if enemyBearingToMeAbs < 15 then
                        -- don't do this forever!
                        local watchCount = self.watchCount or 0
                        self.watchCount = watchCount + 0.2
                        if self.watchCount > 5 then
                            self.boredOfWatching = true
                        end
                        self:TaskComplete( "movement_watch" )
                        self:StartTask2( "movement_stalkenemy" )
                        exit = true
                    else
                        data.slinkAway = nil
                    end
                -- too close bub!
                elseif self.DistToEnemy < 1000 then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_flankenemy" )
                    exit = true
                -- where'd you go...
                elseif not self.IsSeeEnemy then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_approachlastseen", { pos = self.EnemyLastPos } )
                    exit = true
                -- i've been watching long enough
                elseif data.giveUpWatchingTime < CurTime() then
                    local watchCount = self.watchCount or 0
                    self.watchCount = watchCount + 1
                    if self.watchCount > 8 then
                        self.boredOfWatching = true
                    end
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_stalkenemy" )
                    exit = true
                -- you shot me!!
                elseif self:Health() < self:GetMaxHealth() then
                    self:TaskComplete( "movement_watch" )
                    self:StartTask2( "movement_stalkenemy" )
                    exit = true
                end
                if exit then -- just in case !!!!
                    self.PreventShooting = nil
                end 
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_watch" )
            end
        },
        ["movement_stalkenemy"] = {
            OnStart = function(self,data)

                data.want = data.want or 8 

                local myPos = self:GetPos()
                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or data.lastKnownStalkPos or nil
                if not enemyPos then 
                    self.InvalidAfterwards = true 
                    return
                end
                local enemyDir = data.lastKnownStalkDir
                local enemyDis = data.lastKnownStalkDist or enemyPos:Distance( myPos ) or nil
                if IsValid( enemy ) then
                    enemyDir = enemy:GetForward()
                    if self.IsSeeEnemy then 
                        enemyDis = myPos:Distance( enemyPos )
                    end 
                end 
                --print( enemyDis )
                local shootPos = enemyPos + enemyDir * 500 
                if enemy:IsPlayer() then
                    shootPos = enemy:GetShootPos()
                end

                local hp = self:Health()
                local maxHp = self:GetMaxHealth()

                local result = getNearestPosOnNav( enemyPos )
                local aimResult = getNearestPosOnNav( shootPos )

                if enemyPos and result.area:IsValid() and aimResult.area:IsValid() then

                    local scoreData = {}
                    scoreData.hateVisible = hp < maxHp * 0.5
                    scoreData.enemyArea = result.area
                    scoreData.enemyAreaCenter = scoreData.enemyArea:GetCenter() 
                    scoreData.innerBoundary = enemyDis + -100
                    scoreData.outerBoundary = scoreData.innerBoundary + 300
                    scoreData.hardInnerBoundary = enemyDis + -300
                    scoreData.hardOuterBoundary = scoreData.innerBoundary + 1000
                    scoreData.lastStalkFromPos = data.lastStalkFromPos or myPos
                    scoreData.canGoUnderwater = self:isUnderWater()

                    local scoreFunction = function( scoreData, area1, area2 )
                        local area2Center = area2:GetCenter()
                        local distanceTravelled = area2Center:DistToSqr( scoreData.lastStalkFromPos )
                        local score = distanceTravelled
                        local areaDistanceToEnemy2 = area2Center:DistToSqr( scoreData.enemyAreaCenter )
                        local notTooClose = SqrDistGreaterThan( areaDistanceToEnemy2, scoreData.innerBoundary )
                        local notTooFar = SqrDistLessThan( areaDistanceToEnemy2, scoreData.outerBoundary )
                        local inDistanceRing = notTooClose and notTooFar
                        local bigNotTooClose = SqrDistGreaterThan( areaDistanceToEnemy2, scoreData.hardInnerBoundary )
                        local bigNotTooFar = SqrDistLessThan( areaDistanceToEnemy2, scoreData.hardOuterBoundary )
                        local inBiggerDistanceRing = bigNotTooClose and bigNotTooFar
                        local heightChange = math.abs( area2:ComputeAdjacentConnectionHeightChange(area1) )
                        if not area2:IsCompletelyVisible( scoreData.enemyArea ) then
                            score = score * 2
                        elseif scoreData.hateVisible then
                            score = score * 0.005
                        end

                        if self.walkedAreas[area2:GetID()] then 
                            score = score * 0.8
                        end
                        if heightChange > self.loco:GetStepHeight() * 2 then
                            score = score * 0.01
                        end
                        if area2:IsUnderwater() and not scoreData.canGoUnderwater then
                            score = score * 0.0008
                        end
                        if not inBiggerDistanceRing then 
                            score = 0
                        elseif not inDistanceRing then 
                            score = score * 0.5
                        end
                        return score
                
                    end
                    stalkPos = findValidNavResult( scoreData, self:GetPos(), math.Rand( 2500, 3500 ), scoreFunction )
                    if stalkPos then
                        debugoverlay.Cross( stalkPos, 40, 5, Color( 255, 255, 0 ), true )
                        SetupFlankingPath( self, stalkPos, result.area, aimResult.area )
                    end

                end

                if self:PathIsValid() then 
                    self.PreventShooting = true
                    local stalksSinceLastSeen = data.stalksSinceLastSeen or 0 
                    data.stalksSinceLastSeen = stalksSinceLastSeen + 1  
                    data.lastKnownStalkPos = enemyPos
                    data.lastKnownStalkDir = enemyDir
                    data.lastKnownStalkDist = enemyDis
                    data.stalkStartPos = myPos
                    return 
                end
                self.InvalidAfterwards = true
            end,
            BehaveUpdate = function(self,data)
                local exit = nil
                local valid = nil

                if self.InvalidAfterwards then
                    self:TaskFail( "movement_stalkenemy" )
                    if data.want > 0 then
                        local newDat = {}
                        newDat.want = data.want + -1
                        newDat.stalksSinceLastSeen = data.stalksSinceLastSeen 
                        newDat.lastStalkFromPos = data.stalkStartPos
                        newDat.lastKnownStalkDist = data.lastKnownStalkDist
                        newDat.lastKnownStalkDir = data.lastKnownStalkDir
                        newDat.lastKnownStalkPos = data.lastKnownStalkPos
                        self:StartTask2( "movement_stalkenemy",newDat)
                    else
                        self:StartTask2( "movement_handler" )
                    end
                    self.WasHidden = nil
                    self.PreventShooting = nil
                    return
                end
                
                local enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( enemy ) or nil
                local enemyBearingToMeAbs = math.huge
                local maxHealth = self:Health() == self:GetMaxHealth()
                if IsValid( enemy ) then 
                    enemyBearingToMeAbs = self:enemyBearingToMe()
                end
                local exposed = self.IsSeeEnemy and enemyBearingToMeAbs < 15

                if not exposed then
                    self.WasHidden = true
                    self.PreventShooting = true
                else 
                    data.stalksSinceLastSeen = 0
                    self.PreventShooting = nil
                end 

                local enemyNav = getNearestPosOnNav( enemyPos ).area
                local pathEndNav = getNearestPosOnNav( self:GetPath():GetEnd() ).area
                local enemySeesDestination = nil 
                if pathEndNav:IsValid() and enemyNav:IsValid() then
                    enemySeesDestination = PosCanSee( pathEndNav:GetCenter(), enemyPos )
                end
                local watch = enemyBearingToMeAbs > 10 and IsValid( enemy ) and self.IsSeeEnemy and self.WasHidden and not self.boredOfWatching and maxHealth and self.DistToEnemy > 1000
                local ambush = enemyBearingToMeAbs > 100 and IsValid( enemy ) and not exposed
                local tooClose = self.DistToEnemy < 900 and self.IsSeeEnemy and self:areaIsReachable( EnemyNavArea )
                local farTooClose = self.DistToEnemy < 700
                
                local result = self:ControlPath2( not self.IsSeeEnemy and not enemySeesDestination )
                -- weap
                if self:canGetWeapon() and not IsValid( enemy ) then
                    self:TaskFail( "movement_stalkenemy" )
                    self:StartTask2( "movement_handler", {nextTask = "movement_stalkenemy"} )
                    exit = true
                -- we are too close and we just jumped out of somewhere hidden
                elseif tooClose and self.WasHidden then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy" )
                    exit = true
                -- really lame to get close and have it run away
                elseif farTooClose then
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_flankenemy" )
                    exit = true
                -- enemy isnt looking at us so we can observe them
                elseif watch then 
                    self:TaskComplete( "movement_stalkenemy" )
                    self:StartTask2( "movement_watch" )
                    exit = true
                -- we ended up behind the enemy and they haven't seen us yet
                elseif ambush then
                    self:TaskComplete( "movement_stalkenemy" )
                    if maxHealth and not self.boredOfWatching then 
                        self:StartTask2( "movement_watch" )
                    else
                        self:StartTask2( "movement_flankenemy", {Time = 0.2} )
                    end
                    exit = true
                -- we are exposed and we're about to walk even further into the enemy
                elseif exposed and enemySeesDestination then
                    self.WasHidden = false
                    data.stalkStartPos = nil
                    valid = true
                -- we just exited from being hidden, and the enemy sees us
                elseif exposed and self.WasHidden then
                    self.WasHidden = false
                    valid = true
                -- we hit the end of our path, keep stalking
                elseif result then
                    valid = true
                -- invalid path, keep stalking
                elseif result == false then
                    valid = true
                end
                if exit then
                    self.WasHidden = nil
                    self.PreventShooting = nil
                end
                if valid then
                    if data.stalksSinceLastSeen < 15 then
                        local newDat = {}
                        newDat.stalksSinceLastSeen = data.stalksSinceLastSeen 
                        newDat.lastStalkFromPos = data.stalkStartPos
                        newDat.lastKnownStalkDist = data.lastKnownStalkDist
                        newDat.lastKnownStalkDir = data.lastKnownStalkDir
                        newDat.lastKnownStalkPos = data.lastKnownStalkPos
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_stalkenemy", newDat)
                    else
                        self:TaskComplete( "movement_stalkenemy" )
                        self:StartTask2( "movement_approachlastseen", { pos = data.lastKnownStalkPos or self.EnemyLastPos } )
                    end
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_stalkenemy" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() or self.IsSeeEnemy
            end
        },
        ["movement_flankenemy"] = {
            OnStart = function(self,data)
                --find a simple path
                local myPos = self:GetPos()
                local Enemy = self:GetEnemy()
                if not IsValid( Enemy ) then 
                    self.InvalidAfterwards = true
                    return 
                end 
                local enemyPos = self:GetLastEnemyPosition( Enemy ) or nil
                local shootPos = enemyPos + Enemy:GetForward() * 500
                if Enemy:IsPlayer() then
                    shootPos = Enemy:GetShootPos()
                end
                local result = getNearestPosOnNav( enemyPos )
                local aimResult = getNearestPosOnNav( shootPos )
                if enemyPos and result.area:IsValid() and aimResult.area:IsValid() and self:areaIsReachable( result.area ) then
                    SetupFlankingPath( self, enemyPos, result.area, aimResult.area )
                end
                if self:PathIsValid() then 
                    self.PreventShooting = true
                    return 
                end
                self.InvalidAfterwards = true
            end,
            BehaveUpdate = function(self,data)
                
                local exit = nil
                if self.InvalidAfterwards then
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_followenemy" )
                    return
                end
                
                local Enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( Enemy ) or nil
                local enemyBearingToMeAbs = math.huge
                if IsValid( Enemy ) then 
                    enemyBearingToMeAbs = self:enemyBearingToMe()
                end
                local exposed = self.IsSeeEnemy and enemyBearingToMeAbs < 30
                
                if not exposed then
                    self.WasHidden = true
                    self.PreventShooting = true
                else 
                    self.PreventShooting = nil
                end
                
                local result = self:ControlPath2( !self.IsSeeEnemy )
                if self:canGetWeapon() and not IsValid( Enemy ) then
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_handler", { nextTask = "movement_flankenemy"} )
                    exit = true
                elseif self.IsSeeEnemy and self.DistToEnemy < 300 then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_duelenemy_near" )
                    exit = true
                elseif exposed and self.WasHidden then
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_flankenemy" )
                    exit = true
                elseif result then
                    self:TaskComplete( "movement_flankenemy" )
                    self:StartTask2( "movement_searchlastdir", {Want = 10} )
                    exit = true
                elseif result==false then
                    self:TaskFail( "movement_flankenemy" )
                    self:StartTask2( "movement_searchlastdir", {Want = 10} )
                    exit = true
                end
                if exit then
                    self.WasHidden = nil
                    self.PreventShooting = nil
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_flankenemy" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end
        },
        ["movement_approachlastseen"] = {
            OnStart = function(self,data)
                data.approachAfter = CurTime() + 1
                self:GetPath():Invalidate()
            end,
            BehaveUpdate = function(self,data)
                
                local Enemy = self:GetEnemy()
                local approachPos = data.pos or self:GetLastEnemyPosition( Enemy ) or self.EnemyLastPos or nil
                local goodEnemy = self.IsSeeEnemy and IsValid( Enemy )
                local givenItAChance = data.approachAfter < CurTime() -- this schedule didn't JUST start.

                if approachPos then
                    local newPath = not self:PathIsValid() or ( self:PathIsValid() and CanDoNewPath( self, approachPos ) ) 
                    if newPath and not data.Unreachable then -- HACK
                        local result = getNearestPosOnNav( approachPos )
                        local reachable = self:areaIsReachable( result.area )
                        if not reachable then data.Unreachable = true return end
                        local posOnNav = result.pos
                        SetupPath2( self, posOnNav )
                        if not self:PathIsValid() then data.Unreachable = true return end
                    end
                end
                local result = self:ControlPath2( !self.IsSeeEnemy )
                -- get WEAP
                if self:canGetWeapon() then 
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_handler", {nextTask = "movement_approachlastseen"} )
                -- cant get to them
                elseif data.Unreachable and givenItAChance then
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_stalkenemy" )
                -- i see you...
                elseif goodEnemy and givenItAChance then
                    self:EnemyAcquired( "movement_approachlastseen" )
                -- i got there and you're nowhere to be seen
                elseif result and givenItAChance then
                    self:TaskComplete( "movement_approachlastseen" )
                    self:StartTask2( "movement_search", {Want = 10} )
                -- bad path
                elseif result==false and givenItAChance then
                    self:TaskFail( "movement_approachlastseen" )
                    self:StartTask2( "movement_search", {Want = 80} )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_approachlastseen" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end
        },
        ["movement_followenemy"] = {
            BehaveUpdate = function(self,data)
                
                local Enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( Enemy ) or self.EnemyLastPos or nil
                local GoodEnemy = self.IsSeeEnemy and IsValid( Enemy )

                if enemyPos then
                    local newPath = not self:PathIsValid() or ( self:PathIsValid() and CanDoNewPath( self, enemyPos ) ) 
                    if newPath and not self.isUnstucking and not data.Unreachable then -- HACK
                        local result = getNearestPosOnNav( enemyPos )
                        local reachable = self:areaIsReachable( result.area )
                        if not reachable then data.Unreachable = true return end
                        local posOnNav = result.pos
                        SetupPath2( self, posOnNav )
                        if not self:PathIsValid() then data.Unreachable = true return end
                    end
                end
                local result = self:ControlPath2( !self.IsSeeEnemy )
                if self:canGetWeapon() and not GoodEnemy then 
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_handler", {nextTask = "movement_followenemy"} )
                elseif data.Unreachable and GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_stalkenemy" )
                elseif data.Unreachable and not GoodEnemy then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_searchlastdir", {Want = 10} )
                elseif self.IsSeeEnemy and self.DistToEnemy < 800 then
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_duelenemy_near" )
                elseif result then
                    self:TaskComplete( "movement_followenemy" )
                    self:StartTask2( "movement_searchlastdir", {Want = 10} )
                elseif result==false then
                    self:TaskFail( "movement_followenemy" )
                    self:StartTask2( "movement_search", {Want = 80} )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_followenemy" )
            end,
            ShouldRun = function(self,data)
                return self:canDoRun() 
            end
        },
        ["movement_duelenemy_near"] = {
            OnStart = function(self,data)
                data.minNewPathTime = 0
                if not isnumber( self.NextPathAtt ) then
                    self.NextPathAtt = 0
                    self.NextRandPathAtt = 0
                end
            end,
            BehaveUpdate = function(self,data)
                
                local Enemy = self:GetEnemy()
                local enemyPos = self:GetLastEnemyPosition( Enemy ) or nil
                local result = self:ControlPath2( !self.IsSeeEnemy)
                local MaxDuelDist = 800
                local EnemyNavArea = getNearestNav( enemyPos ) or NULL
                
                if not Enemy then
                    self:TaskFail( "movement_duelenemy_near" )
                    self:StartTask2( "movement_followenemy" )
                    --print("noen" )
                elseif not self:areaIsReachable( EnemyNavArea ) and Enemy then
                    self:TaskFail( "movement_duelenemy_near" )
                    self:StartTask2( "movement_stalkenemy" )
                elseif self.DistToEnemy > MaxDuelDist and self:areaIsReachable( EnemyNavArea ) then
                    self:EnemyAcquired("movement_duelenemy_near" )
                    --print("dist" )
                elseif not self.IsSeeEnemy then 
                    if self:areaIsReachable( EnemyNavArea ) then
                        self:EnemyAcquired("movement_duelenemy_near" )
                    else
                        self:TaskComplete( "movement_duelenemy_near" )
                        self:StartTask2( "movement_search" )
                    end
                elseif IsValid( Enemy ) and self.IsSeeEnemy then
                    local MyNavArea = self:GetCurrentNavArea()
                    local GoodPos = nil
                    local canDoNewPath = data.minNewPathTime < CurTime()

                    local FinishedOrInvalid = ( Result == true or not self:PathIsValid() or not PosCanSee( self:EyePos(), Enemy:EyePos() ) ) and canDoNewPath
                    
                    if FinishedOrInvalid or self.NextPathAtt < CurTime() then
                        
                        data.minNewPathTime = CurTime() + 0.3
                        GoodPos = false
                        local caps = self:CapabilitiesGet()
                        -- ranged weap
                        if bit.band( caps, CAP_WEAPON_RANGE_ATTACK1 ) > 0 then
                            local fistiCuffs = self.DistToEnemy < 150
                            if fistiCuffs then
                                self:DropWeapon()
                                goto SkipRemainingCriteria
                            end
                            local AdjAreas = MyNavArea:GetAdjacentAreas()
                            
                            self.NextPathAtt = CurTime() + 3
                            
                            local AdjArea = table.Random( AdjAreas )
                            if not AdjArea then goto SkipRemainingCriteria end
                            if not AdjArea:IsCompletelyVisible( MyNavArea ) then goto SkipRemainingCriteria end -- dont go behind corners!
                            if AdjArea:HasAttributes( NAV_MESH_AVOID ) then goto SkipRemainingCriteria end -- avoid attrib AVOID
                            if AdjArea:HasAttributes( NAV_MESH_JUMP ) then goto SkipRemainingCriteria end -- avoid attrib JUMP
                            local PathPos = AdjArea:GetRandomPoint()
                            if not PosCanSee( PathPos, Enemy:EyePos() ) then goto SkipRemainingCriteria end
                            if SqrDistGreaterThan( self:GetPos():DistToSqr( PathPos ), MaxDuelDist ) then goto SkipRemainingCriteria end
    
                            GoodPos = true
                            SetupPath2( self, PathPos )
                        --melee
                        elseif bit.band( caps, CAP_INNATE_MELEE_ATTACK1 ) > 0 then
                            
                            self.NextPathAtt = CurTime() + math.random( 0.5, 1 )
                            GoodPos = true
                            
                            local shootPos = enemyPos + Enemy:GetForward() * 500
                            if Enemy:IsPlayer() then
                                shootPos = Enemy:GetShootPos()
                            end
                            
                            local Offset = Enemy:GetVelocity():GetNormalized() * math.Clamp( Enemy:GetVelocity():Length() / 2, 0, 400 )
                            local PathPos = enemyPos + Offset
                            local result = getNearestPosOnNav( PathPos )
                            local aimResult = getNearestPosOnNav( shootPos )

                            SetupFlankingPath( self, result.pos, result.area, aimResult.area )
                            if self:PathIsValid() then goto SkipRemainingCriteria end
                            GoodPos = false
                        end
                    end
                    ::SkipRemainingCriteria::
                    if GoodPos == false and self.NextRandPathAtt < CurTime() then
                        self.NextRandPathAtt = CurTime() + math.random( 1, 2 )
                        SetupPath2( self, MyNavArea:GetRandomPoint() )
                    end
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_duelenemy_near" )
            end,
            ShouldRun = function(self,data)
                local caps = self:CapabilitiesGet()
                local ranged = bit.band( caps, CAP_WEAPON_RANGE_ATTACK1 ) > 0
                local isRandomOrIsMelee = ( CurTime() + self:GetCreationID() ) % 10 > 6 or not ranged
                return isRandomOrIsMelee and self:canDoRun() 
            end
        },
        ["movement_inertia"] = {
            OnStart = function(self,data)
                if not isnumber( data.Want ) then 
                    data.Want = 30
                end
                data.PathStart = self:GetPos()
                data.Want = data.Want + -1
                
                local canDoUnderWater = self:isUnderWater()

                --normal path
                local Dir = data.Dir or self:GetForward()
                local scoreData = {}
                scoreData.canDoUnderWater = canDoUnderWater
                scoreData.self = self
                scoreData.forward = Dir:Angle()
                scoreData.startArea = self:GetCurrentNavArea()
                scoreData.startPos = scoreData.startArea:GetCenter()

                local scoreFunction = function( scoreData, area1, area2 )
                    local ang = scoreData.forward
                    local dropToArea = area2:ComputeAdjacentConnectionHeightChange(area1)
                    local score = area2:GetCenter():DistToSqr( scoreData.startPos ) * math.Rand( 0.6, 1.4 )
                    if scoreData.self.walkedAreas[area2:GetID()] then
                        score = score*0.3
                    end
                    if not area2:IsPotentiallyVisible( scoreData.startArea ) then
                        score = score*10
                    end
                    if area2:HasAttributes(NAV_MESH_AVOID) then 
                        score = 0.1
                    end
                    if not scoreData.canDoUnderWater and area2:IsUnderwater() then
                        score = score * 0.01
                    end
                    if dropToArea > self.loco:GetMaxJumpHeight() then 
                        score = score * 0.01
                    end
                    
                    --debugoverlay.Text( area2:GetCenter(), tostring( math.Round( math.sqrt( score ) ) ), 8 )

                    return score

                end

                wanderPos = findValidNavResult( scoreData, self:GetPos(), math.random( 3500 ), scoreFunction )
                
                if wanderPos then
                    SetupPath2( self, wanderPos )
                    
                    if !self:PathIsValid() then
                        self:TaskFail( "movement_inertia" )
                        self:StartTask2( "movement_wait" )
                    end
                else
                    self:TaskFail( "movement_inertia" )
                    self:StartTask2( "movement_wait" )
                end
            end,
            BehaveUpdate = function(self,data)
                local result = self:ControlPath2( !self.IsSeeEnemy)
                if self.IsSeeEnemy then
                    self:EnemyAcquired("movement_inertia" )
                elseif self.EnemyLastHint then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_search", { searchCenter = self.EnemyLastHint } )
                elseif self:validSoundHint( data.startTime ) then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_followsound", { Sound = self.lastHeardSoundHint } )
                elseif self.awarenessUnknown[1] then
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_understandobject" )
                elseif data.Want > 0 then
                    if result == true then
                        self:TaskComplete( "movement_inertia" )
                        self:StartTask2( "movement_inertia", { Want = data.Want, Dir = DirToPos( data.PathStart, self:GetPos() ) } )
                    elseif result == false then
                        self:TaskComplete( "movement_inertia" )
                        self:StartTask2( "movement_inertia", { Want = data.Want, Dir = -self:GetForward() } )
                    end
                else -- no want, end the inertia
                    self:TaskComplete( "movement_inertia" )
                    self:StartTask2( "movement_handler" )
                end
            end,
            StartControlByPlayer = function(self,data,ply)
                self:TaskFail( "movement_inertia" )
            end,
            ShouldRun = function(self,data)
                return true
            end,
        },
        ["inform_handler"] = {
            OnStart = function(self,data)
                data.Inform = function(enemy,pos)
                    for k,v in ipairs(ents.FindByClass(self:GetClass())) do
                        if v==self or v.m_InformGroup!=self.m_InformGroup or self:GetRangeTo(v)>self.InformRadius then continue end
                        
                        v:RunTask("InformReceive",enemy,pos)
                    end
                end
            end,
            BehaveUpdate = function(self,data,interval)
                if IsValid(self.Target) then return end
            
                if self.IsSeeEnemy and (!data.EnemyPosInform or CurTime()>=data.EnemyPosInform) then
                    data.EnemyPosInform = CurTime()+5
                    
                    data.Inform(self:GetEnemy(),self:EntShootPos(self:GetEnemy()))
                end
            end,
            InformReceive = function(self,data,enemy,pos)
                self:SetEntityRelationship(enemy,D_HT,1)
                self:UpdateEnemyMemory(enemy,pos)
                
                if self:IsTaskActive("movement_randomwalk" ) then
                    self:TaskFail( "movement_randomwalk" )
                    
                    self.CustomPosition = pos
                    self:StartTask2( "movement_wait" )
                end
            end,
            OnKilled = function(self,data,dmg)
            end,
        },
    }
end

function ENT:SetupTasks()
	BaseClass.SetupTasks(self)
	
	self:StartTask("enemy_handler" )
	self:StartTask("shooting_handler" )
	self:StartTask("movement_handler" )
	self:StartTask("playercontrol_handler" )
    self:StartTask("awareness_handler" )
    self:StartTask("reallystuck_handler")
end