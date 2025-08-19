local entMeta = FindMetaTable("Entity")

-- Motion Type Enums
TERMINATOR_NEXTBOT_MOTIONTYPE_IDLE = 0
TERMINATOR_NEXTBOT_MOTIONTYPE_MOVE = 1
TERMINATOR_NEXTBOT_MOTIONTYPE_RUN = 2
TERMINATOR_NEXTBOT_MOTIONTYPE_WALK = 3
TERMINATOR_NEXTBOT_MOTIONTYPE_CROUCH = 4
TERMINATOR_NEXTBOT_MOTIONTYPE_CROUCHWALK = 5
TERMINATOR_NEXTBOT_MOTIONTYPE_JUMPING = 6
TERMINATOR_NEXTBOT_MOTIONTYPE_SWIMMING = 7

-- Default movetype acts can be changed
ENT.MotionTypeActivities = {
	[TERMINATOR_NEXTBOT_MOTIONTYPE_IDLE] = ACT_MP_STAND_IDLE,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_MOVE] = ACT_MP_RUN,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_RUN] = ACT_MP_RUN,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_WALK] = ACT_MP_WALK,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_CROUCH] = ACT_MP_CROUCH_IDLE,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_CROUCHWALK] = ACT_MP_CROUCHWALK,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_JUMPING] = ACT_MP_JUMP,
	[TERMINATOR_NEXTBOT_MOTIONTYPE_SWIMMING] = ACT_MP_SWIM,
}

--[[------------------------------------
	Name: NEXTBOT:SetMotionType
	Desc: (INTERNAL) Sets bot motion type.
	Arg1: number | type | Motion Type. See TERMINATOR_NEXTBOT_MOTIONTYPE_ Enums
	Ret1:
--]]------------------------------------
function ENT:SetMotionType(type)
	self.m_MotionType = type
end

--[[------------------------------------
	Name: NEXTBOT:GetMotionType
	Desc: (INTERNAL) Returns bot motion type.
	Arg1: 
	Ret1: number | Motion Type. See TERMINATOR_NEXTBOT_MOTIONTYPE_ Enums
--]]------------------------------------
function ENT:GetMotionType()
	return self.m_MotionType or TERMINATOR_NEXTBOT_MOTIONTYPE_IDLE
end

--[[------------------------------------
	Name: NEXTBOT:GetCurrentSpeed
	Desc: Returns bot current motion speed.
	Arg1: 
	Ret1: number | Motion speed.
--]]------------------------------------
function ENT:GetCurrentSpeed()
	local cached = self.term_CachedCurrentSpeed
	if cached then return cached end
	cached = self.loco:GetVelocity():Length2D()
	self.term_CachedCurrentSpeed = cached

	timer.Simple( 0.01, function()
		if not IsValid( self ) then return end
		self.term_CachedCurrentSpeed = nil

	end )

	return cached
end

--[[------------------------------------
	Name: NEXTBOT:GetCurrentSpeedSqr
	Desc: Returns bot current motion speed, squared.
	Arg1: 
	Ret1: number | Motion speed.
--]]------------------------------------
function ENT:GetCurrentSpeedSqr()
	local cached = self.term_CachedCurrentSpeedSqr
	if cached then return cached end
	cached = self.loco:GetVelocity():Length2DSqr()
	self.term_CachedCurrentSpeedSqr = cached

	timer.Simple( 0, function()
		self.term_CachedCurrentSpeedSqr = nil

	end )

	return cached
end

--[[------------------------------------
	Name: NEXTBOT:GetDesiredSpeed()
	Desc: Returns bots Locomotion desired speed.
	Arg1: 
	Ret1: number | Motion speed.
--]]------------------------------------
function ENT:GetDesiredSpeed()
	return self.m_Speed or 0
end

--[[------------------------------------
	Name: NEXTBOT:GetPathPos
	Desc: Returns goal of path.
	Arg1: 
	Ret1: Vector | Goal position
--]]------------------------------------
function ENT:GetPathPos()
	return self.m_PathPos
end

--[[------------------------------------
	Name: NEXTBOT:IsMoving()
	Desc: Returns bot is moving or not.
	Arg1: 
	Ret1: bool | Bot is moving.
--]]------------------------------------
function ENT:IsMoving()
	return self:GetCurrentSpeed()>0.1
end

--[[------------------------------------
	Name: NEXTBOT:IsJumping
	Desc: Bot is not on ground because he jump.
	Arg1: 
	Ret1: bool | Bot is jumped
--]]------------------------------------
function ENT:IsJumping( myTbl )
	return myTbl.m_Jumping or false
end

--[[------------------------------------
	Name: NEXTBOT:SetDesiredEyeAngles
	Desc: Sets direction where bot want aim. You should use this in behaviour.
	Arg1: Angle | ang | Desired direction.
	Ret1:
--]]------------------------------------
function ENT:SetDesiredEyeAngles(ang)
	self.m_DesiredEyeAngles = ang
end

--[[------------------------------------
	Name: NEXTBOT:GetDesiredEyeAngles
	Desc: Returns direction where bot want aim.
	Arg1: 
	Ret1: Angle | Desired direction.
--]]------------------------------------
function ENT:GetDesiredEyeAngles()
	return self.m_DesiredEyeAngles or angle_zero
end

--[[------------------------------------
	Name: NEXTBOT:ViewPunch
	Desc: Performs simple view punch.
	Arg1: Angle | ang | view punch angles.
	Ret1: 
--]]------------------------------------
function ENT:ViewPunch(ang)
	self:SetViewPunchTime(CurTime())
	self:SetViewPunchAngle(ang)
end

--[[------------------------------------
	Name: NEXTBOT:SetupActivity
	Desc: (INTERNAL) Sets right activity to bot.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:SetupActivity()
	local curact = self:GetActivity()
	local act = self:RunTask("GetDesiredActivity")
	
	if !act then
		act = self.MotionTypeActivities[self:GetMotionType()]
		act = self:TranslateActivity(act)
	end
	
	if act and curact != act then
		self:StartActivity(act)
	end
end

--[[------------------------------------
	Name: NEXTBOT:DoGesture
	Desc: Creates gesture animation (e.g. reload animation). Removes previous gesture.
	Arg1: number | act | Animation to run. See ACT_* Enums.
	Arg2: (optional) number | speed | Playback rate.
	Arg3: (optional) bool | wait | Should behaviour be stopped while gesture active (like DoPosture).
	Ret1: 
--]]------------------------------------
function ENT:DoGesture(act,speed,wait)
	self.m_DoGesture = {act,speed or 1,wait}
end

--[[------------------------------------
	Name: NEXTBOT:DoPosture
	Desc: Creates posture animation (e.g. reload animation). Removes previous posture. NOTE: While posture active behaviour will be disabled and activities will not be updated.
	Arg1: number | act | Animation to run. See ACT_* Enums. If `issequence` is true, sequence id (also can be string).
	Arg2: (optional) bool | issequence | If set, creates sequence with `act` argument id, otherwise gest random weighted sequence to `act` activity.
	Arg3: (optional) number | speed | Playback rate.
	Arg4: (optional) bool | noautokill | If set, disables autokill when sequence has finished.
	Ret1: number | Length of created sequence.
--]]------------------------------------
function ENT:DoPosture(act,issequence,speed,noautokill)
	local seq = issequence and act or self:SelectWeightedSequence(act)
	
	self.m_DoPosture = {seq,speed or 1,!noautokill}
	
	if issequence and isstring(seq) then
		local seqid,len = self:LookupSequence(seq)
		
		return len
	end
	
	return self:SequenceDuration(seq)
end

--[[------------------------------------
	Name: NEXTBOT:StopGesture
	Desc: Removes current gesture. Does nothing if gesture not active.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:StopGesture()
	if self.m_CurGesture then
		self:RemoveGesture(self.m_CurGesture[1])
		self.m_CurGesture = nil
	end
end

--[[------------------------------------
	Name: NEXTBOT:StopPosture
	Desc: Removes current posture. Does nothing if posture not active.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:StopPosture()
	if self.m_CurPosture then
		self.m_CurPosture = nil
		
		self:ResetSequenceInfo()
		self:StartActivity(self:GetActivity())
	end
end

--[[------------------------------------
	Name: NEXTBOT:IsGestureActive
	Desc: Returns whenever we currently playing a gesture or not.
	Arg1: (optional) bool | wait | If true, function will return true only if behaviour should be stopped while gesture active.
	Ret1: bool | Gesture active or not.
--]]------------------------------------
function ENT:IsGestureActive(wait)
	return self.m_CurGesture and CurTime()<self.m_CurGesture[2] and (!wait or self.m_CurGesture[3]) or false
end

--[[------------------------------------
	Name: NEXTBOT:IsPostureActive
	Desc: Returns whenever we currently playing a posture or not.
	Arg1: 
	Ret1: bool | Posture active or not.
--]]------------------------------------
function ENT:IsPostureActive()
	return self.m_CurPosture and (!self.m_CurPosture[2] or CurTime()<self.m_CurPosture[1]) or false
end

--[[------------------------------------
	Name: NEXTBOT:SetupGesturePosture
	Desc: (INTERNAL) Setups gestures and postures. DoGesture and DoPosture not actually creates animations, because for correctly work it should be done in BehaveUpdate. SetupGesturePosture will called in BehaveUpdate.
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:SetupGesturePosture()
	if self.m_DoGesture then
		local act = self.m_DoGesture[1]
		local spd = self.m_DoGesture[2]
		local wait = self.m_DoGesture[3]
		self.m_DoGesture = nil

		self:StopGesture()

		local layer

		if isstring( act ) then
			act = self:LookupSequence( act )
			layer = self:AddGestureSequence( act )

		else
			layer = self:AddGesture( act )

		end
		self:SetLayerPlaybackRate(layer,spd)
		self:SetLayerBlendIn(layer,0.2)
		self:SetLayerBlendOut(layer,0.2)

		self.m_CurGesture = { act, CurTime() + self:GetLayerDuration( layer ), wait }
		self.term_CachedCurrentSpeed = nil
	end
	
	if self.m_DoPosture then
		local seq = self.m_DoPosture[1]
		local spd = self.m_DoPosture[2]
		local autokill = self.m_DoPosture[3]
		self.m_DoPosture = nil
		
		self:StopPosture()
		
		local len = self:SetSequence(seq)
		self:ResetSequenceInfo()
		self:SetCycle(0)
		self:SetPlaybackRate( math.Clamp( spd, 0, 12 ) )
		
		self.m_CurPosture = {CurTime()+len/spd,autokill}
	end
	
	if self.m_CurPosture and self.m_CurPosture[2] and CurTime()>self.m_CurPosture[1] then
		self:StopPosture()
	end
end

--[[------------------------------------
	NEXTBOT:BodyUpdate
	Updating animations and activities.
--]]------------------------------------
function ENT:BodyUpdate()
	if !self:IsPostureActive() then
		self:SetupActivity()
	end

	if self:IsMoving() then
		self:BodyMoveXY()
	else
		self:FrameAdvance(0)
	end

	self:RunTask("BodyUpdate")
end

--[[------------------------------------
	Name: NEXTBOT:SetupCollisionBounds
	Desc: (INTERNAL) Sets collision bounds сonsidering crouch status. Also recreating physics object using new bounds
	Arg1: 
	Ret1: 
--]]------------------------------------
function ENT:SetupCollisionBounds()
	local data = self:IsCrouching() and self.CrouchCollisionBounds or self.CollisionBounds
	
	self:SetCollisionBounds(data[1],data[2])
	
	if self:PhysicsInitShadow(false,false) then
		self:GetPhysicsObject():SetMass(self.MyPhysicsMass)
	end
end

--[[------------------------------------
	Name: NEXTBOT:UpdatePhysicsObject
	Desc: (INTERNAL) Updates physics object position and angles.
	Arg1: 
	Ret1: 
--]]------------------------------------

local ang_zero = Angle( 0, 0 ,0 ) -- maybe fix bugs with the shadow :(

function ENT:UpdatePhysicsObject()
	local phys = self:GetPhysicsObject()

	if IsValid(phys) then
		phys:SetAngles(ang_zero)

		if self:GetModelScale() ~= 1 then -- HACK, to fix the horrible blowing up collision bounds bug
			local data = self:IsCrouching() and self.CrouchCollisionBounds or self.CollisionBounds
			self:SetCollisionBounds( data[1], data[2] )

		end

		phys:UpdateShadow( self:GetPos(), ang_zero, self.BehaveInterval )

		phys:SetPos(self:GetPos())
	end
end

--[[------------------------------------
	Name: NEXTBOT:PhysicsObjectCollide
	Desc: Called when physics object collides something. Works like ENT:PhysicsCollide.
	Arg1: table | data | The collision data.
	Ret1: 
--]]------------------------------------
function ENT:PhysicsObjectCollide(data)
end

--[[------------------------------------
	Name: NEXTBOT:OnContact
	Desc: (INTERNAL) Used to call NEXTBOT:OnTouch when there is a actual contact.
	Arg1: Entity | ent | Entity the nextbot came contact with.
	Ret1: 
--]]------------------------------------
function ENT:OnContact(ent)
	local trace = self:GetTouchTrace()

	if trace.Hit then
		self:OnTouch(ent,trace)
	end
end

--[[------------------------------------
	Name: NEXTBOT:OnTouch
	Desc: Called when bot touches something.
	Arg1: Entity | ent | Entity that bot touches.
	Arg2: table | trace | TraceResult touch data.
	Ret1: 
--]]------------------------------------
function ENT:OnTouch(ent,trace)
end

--[[------------------------------------
	Name: NEXTBOT:GetCurrentNavArea
	Desc: Returns current nav area where bot is.
	Arg1: 
	Ret1: NavArea | Current nav area
--]]------------------------------------
function ENT:GetCurrentNavArea( myTbl )
	myTbl = myTbl or entMeta.GetTable( self )
	return myTbl.m_NavArea
end

--[[------------------------------------
	Name: NEXTBOT:GetPath
	Desc: Returns last PathFollower object used for path finding.
	Arg1: 
	Ret1: PathFollower | PathFollower object
--]]------------------------------------
function ENT:GetPath( myTbl )
	myTbl = myTbl or entMeta.GetTable( self )
	return myTbl.m_Path
end

--[[------------------------------------
	Name: NEXTBOT:PathIsValid
	Desc: Returns whenever PathFollower object is valid or not.
	Arg1: 
	Ret1: bool | PathFollower object is valid or not
--]]------------------------------------
function ENT:PathIsValid( path )
	path = path or self:GetPath()
	return path:IsValid()
end

--[[------------------------------------
	NEXTBOT:OnNavAreaChanged
	Saving new area as current. Also stops bot if area has NAV_MESH_STOP attribute.
--]]------------------------------------
function ENT:OnNavAreaChanged(old,new)

	-- detect modified navmesh!
	if not new then return end

	self.m_NavArea = new
	
	if new:HasAttributes(NAV_MESH_STOP) and self.loco:IsOnGround() then
		local vel = self.loco:GetVelocity()
		vel.x = 0
		vel.y = 0
		
		self.loco:SetVelocity(vel)
	end
end

--[[------------------------------------
	Name: NEXTBOT:SetHullType
	Desc: Sets hull type for bot.
	Arg1: number | type | Hull type. See HULL_* Enums
	Ret1: 
--]]------------------------------------
function ENT:SetHullType(type)
	self.m_HullType = type
end

--[[------------------------------------
	Name: NEXTBOT:GetHullType
	Desc: Returns hull type for bot.
	Arg1: 
	Ret1: number | Hull type. See HULL_* Enums
--]]------------------------------------
function ENT:GetHullType()
	return self.m_HullType
end

--[[------------------------------------
	Name: NEXTBOT:SetDuckHullType
	Desc: Sets duck hull type for bot.
	Arg1: number | type | Hull type. See HULL_* Enums
	Ret1: 
--]]------------------------------------
function ENT:SetDuckHullType(type)
	self.m_DuckHullType = type
end

--[[------------------------------------
	Name: NEXTBOT:GetDuckHullType
	Desc: Returns hull type for bot.
	Arg1: 
	Ret1: number | Hull type. See HULL_* Enums
--]]------------------------------------
function ENT:GetDuckHullType()
	return self.m_DuckHullType
end