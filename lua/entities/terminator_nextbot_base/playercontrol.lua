
local entMeta = FindMetaTable("Entity")
local plyMeta = FindMetaTable("Player")
local IsValid = IsValid

--[[------------------------------------
    Name: NEXTBOT:IsControlledByPlayer
    Desc: Returns true if bot currently controlled by player.
    Arg1: 
    Ret1: bool | Is bot controlled by player or not
--]]------------------------------------
function ENT:IsControlledByPlayer( myTbl )
    myTbl = myTbl or entMeta.GetTable( self )

    local ply = myTbl.GetControlPlayer( self )
    if ply == NULL then return false end
    if not IsValid( ply ) then myTbl.SetControlPlayer( self, NULL ) return false end

    if plyMeta.GetDrivingEntity( ply ) ~= self then
        self:StopControlByPlayer()
        return false

    end

    return true
end

--[[------------------------------------
    Name: NEXTBOT:StartControlByPlayer
    Desc: Starts bot control by player.
    Arg1: Player | ply | Who will control bot
    Ret1: 
--]]------------------------------------
function ENT:StartControlByPlayer(ply)
    self:SetControlPlayer(ply)
    self.m_ControlPlayerOldButtons = 0
    self.m_ControlPlayerButtons = 0
    self:ReloadWeaponData()

    self:RunTask( "StartControlByPlayer", ply )

    -- kill all movement tasks
    self:KillAllTasksWith( "movement" )

    local tasks = self.TaskList
    for name, data in pairs( tasks ) do
        if not data.StopsWhenPlayerControlled then continue end
        self:TaskComplete( name )

    end
end

--[[------------------------------------
    Name: NEXTBOT:StopControlByPlayer
    Desc: Stops bot control by player.
    Arg1: 
    Ret1: 
--]]------------------------------------
function ENT:StopControlByPlayer()
    local ply = self:GetControlPlayer()
    self:SetControlPlayer(NULL)

    self:RunTask("StopControlByPlayer",ply)

    local tasks = self.TaskList
    for name, data in pairs( tasks ) do
        if not data.StopsWhenPlayerControlled then continue end
        self:StartTask( name, "StopsWhenPlayerControlled" )

    end
end

--[[------------------------------------
    Name: NEXTBOT:ControlPlayerKeyDown
    Desc: Returns true if key of player who controls bot is downed.
    Arg1: number | key | Key. See IN_ Enums
    Ret1: bool | Key is downed
--]]------------------------------------
function ENT:ControlPlayerKeyDown(key)
    return bit.band(self.m_ControlPlayerButtons,key)==key
end

--[[------------------------------------
    Name: NEXTBOT:ControlPlayerKeyPressed
    Desc: Returns true if player who controls bot has pressed given key at this bot behaviour tick.
    Arg1: number | key | Key. See IN_ Enums
    Ret1: bool | Key is pressed
--]]------------------------------------
function ENT:ControlPlayerKeyPressed(key)
    return self:ControlPlayerKeyDown(key) and bit.band(self.m_ControlPlayerOldButtons,key)~=key
end


--[[------------------------------------
    Name: NEXTBOT:BehaviourPlayerControlThink
    Desc: Override this function to control bot with player.
    Arg1: Player | ply | Player who controls bot
    Ret1: 
--]]------------------------------------
function ENT:BehaviourPlayerControlThink(ply)
    local myTbl = self:GetTable()
    local eyeang = ply:EyeAngles()
    local f = self:ControlPlayerKeyDown( IN_FORWARD ) and 1 or self:ControlPlayerKeyDown( IN_BACK ) and -1 or 0
    local r = self:ControlPlayerKeyDown( IN_MOVELEFT ) and 1 or self:ControlPlayerKeyDown( IN_MOVERIGHT ) and -1 or 0

    if f ~= 0 or r ~= 0 then
        eyeang.p = 0
        eyeang.r = 0
        local movedir = eyeang:Forward() * f - eyeang:Right() * r

        if self:OnGround() then
            self:Approach( self:GetPos() + movedir * 100 )

        else
            local div = self:ControlPlayerKeyDown( IN_SPEED ) and 5 or 10

            -- Horizontal acceleration we intend to add this tick (movedir is planar: eyeang pitch was zeroed)
            local accel2D = movedir * ( self.MoveSpeed / div )

            local velCur = self.loco:GetVelocity()
            local v2      = Vector( velCur.x, velCur.y, 0 )
            local v2Len   = v2:Length()
            local prop2   = v2 + accel2D
            local propLen = prop2:Length()

            -- Hotspot: enforce run speed cap in air.
            -- WHY: We don't want to add any horizontal accel that would increase speed above self.RunSpeed,
            -- but we must always allow changes that reduce speed (even if the result remains > cap).
            local useProp2 = not ( propLen > self.RunSpeed and propLen > v2Len )
            if useProp2 then
                v2 = prop2
            end

            -- Vertical decel when crouching without jump; allowed regardless of horizontal cap decision.
            local newZ = velCur.z
            if self:ControlPlayerKeyDown( IN_DUCK ) and not self:ControlPlayerKeyDown( IN_JUMP ) then
                newZ = newZ - ( self.MoveSpeed / div )
            end

            self.loco:SetVelocity( Vector( v2.x, v2.y, newZ ) )

        end
    end

    if self:OnGround() and self:ControlPlayerKeyPressed( IN_JUMP ) then
        if self:ControlPlayerKeyDown( IN_DUCK ) then
            self:Jump( self.JumpHeight / 4 )

        else
            self:Jump( self.JumpHeight )

        end
    end

    if self:HasWeapon() then
        local wep = self:GetActiveLuaWeapon()

        if self:ControlPlayerKeyPressed( IN_ATTACK ) then
            self:RunTask( "OnMightStartAttacking" )

        end

        local wantsToPriAttack = self[wep.Primary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self,IN_ATTACK)
        local canPriAttack = wantsToPriAttack and myTbl.CanWeaponPrimaryAttack( self, myTbl, wep )

        --print( canPriAttack, wantsToPriAttack, myTbl.CanWeaponPrimaryAttack( self, myTbl, wep ) )

        if wantsToPriAttack and not canPriAttack and wep:Clip1() <= 0 and wep:GetMaxClip1() > 0 then
            self:WeaponReload()

        elseif canPriAttack then
            self:WeaponPrimaryAttack()
            --local wasGood, attackType = self:WeaponPrimaryAttack()
            --print( "Attacked!", wasGood, attackType )

        end

        local wantsToSecAttack = self[wep.Secondary.Automatic and "ControlPlayerKeyDown" or "ControlPlayerKeyPressed"](self,IN_ATTACK2)
        local canSecAttack = wantsToSecAttack and myTbl.CanWeaponSecondaryAttack( self, myTbl, wep )

        if canSecAttack then
            self:WeaponSecondaryAttack()

        end

        if self:ControlPlayerKeyPressed(IN_RELOAD) then
            self:WeaponReload()

        end
    elseif self.TERM_FISTS and self:ControlPlayerKeyDown(IN_ATTACK) then
        self:DoFists()

    end
end