
function ENT:GetHolsteredWeapons()
    local weaps = self.m_HolsteredWeapons or {}
    local slots = self.m_HolsteringSlots or {}

    return weaps, slots

end

function ENT:IsHolsteredWeap( wep )
    if not IsValid( wep ) then return end
    local holsteredWeaps = self.m_HolsteredWeapons or {}
    if holsteredWeaps[ wep ] then return true end

end

function ENT:CanHolsterWeap( wep )
    if self:IsHolsteredWeap( wep ) then return false end
    if wep:GetClass() == self.TERM_FISTS then return false end

    local holsteredWeps, holsteredSlots = self:GetHolsteredWeapons()

    -- validate slots
    for check, _ in pairs( holsteredWeps ) do
        if not IsValid( check ) then
            holsteredWeps[check] = nil

        end
    end
    for slot, check in pairs( holsteredSlots ) do
        if not IsValid( check ) then
            holsteredSlots[ slot ] = nil

        end
    end

    local data = self:GetHolsterData( wep )
    local slot = data.slot

    local hasBoneForSlot = self:HasHolsterBone( slot )
    if not hasBoneForSlot then return false end

    if holsteredSlots[ slot ] then return false end

    return true, data

end

local HOLSTER_BACK = 1
local HOLSTER_SIDEARM = 2

local bonesForSlots = {
    [ HOLSTER_BACK ] = "ValveBiped.Bip01_Spine1",
    [ HOLSTER_SIDEARM ] = "ValveBiped.Bip01_Spine",

}

function ENT:HasHolsterBone( slot )
    local boneId = self:LookupBone( bonesForSlots[ slot ] )
    if not boneId then return end
    return true, boneId

end


local angZero = Angle( 0, 0, 0 )
local vector_back = Vector( 0, -1, 0 )
local vector_leftSide = Vector( 0, 0, 1 )
local vector_localUp = Vector( 1, 0, 0 )

local sidearmOffset = vector_leftSide * 8
sidearmOffset = sidearmOffset + -vector_back * 3
sidearmOffset = sidearmOffset + -vector_localUp * 6

local offsetsForSlots = {
    [ HOLSTER_BACK ] = { pos = ( vector_back * 3.5 ) + ( vector_localUp * 8 ), angOffset = Angle( 0, 7, 0 ) },
    [ HOLSTER_SIDEARM ] = { pos = sidearmOffset, angOffset = Angle( 0, 180, 90 ) },

}

local rotationsForSizes = {
    xx = Angle( 0, 90, 0 ),
    xy = Angle( 90, 0, 0 ), -- done
    xz = Angle( 0, 90, 0 ),
    yy = Angle( 0, 0, 90 ),
    yx = Angle( 0, 0, 0 ), -- done
    yz = Angle( 0, 90, 90 ), -- done
    zy = Angle( 0, 0, 90 ),
    zx = Angle( 0, 0, 90 ), -- done
    zz = Angle( 0, 0, 90 ),

}

function ENT:GetHolsterData( wep )

    local data = wep.terminator_HolsterData

    if data then return data end

    local biggestIndex = nil
    local thinnestIndex = nil
    local biggestSize = 0
    local thinnestSize = math.huge

    local mins = wep:OBBMins()
    local maxs = wep:OBBMaxs()

    local sizes = {
        x = math.abs( mins.x - maxs.x ),
        y = math.abs( mins.y - maxs.y ),
        z = math.abs( mins.z - maxs.z ),

    }

    for index, currSize in pairs( sizes ) do
        local currSizesSize = currSize
        if currSizesSize > biggestSize then
            biggestSize = currSizesSize
            biggestIndex = index

        end
        if currSizesSize < thinnestSize then
            thinnestSize = currSize
            thinnestIndex = index

        end
    end

    local holsterDat = {}

    if biggestSize <= 25 then -- sidearm
        holsterDat.slot = HOLSTER_SIDEARM

    elseif biggestSize <= 150 then
        holsterDat.slot = HOLSTER_BACK

    end

    if not holsterDat.slot then return end

    local rotInd = thinnestIndex .. biggestIndex

    local rotation = rotationsForSizes[ rotInd ]
    local offsets = offsetsForSlots[ holsterDat.slot ]

    --print( rotInd, thinnestSize, biggestSize, wep:GetClass() )

    if offsets.angOffset then
        rotation = rotation + offsets.angOffset

    end

    holsterDat.biggestSize = biggestSize
    holsterDat.thinnestSize = thinnestSize
    holsterDat.rotation = rotation
    holsterDat.posOffset = offsets.pos

    wep.terminator_HolsterData = holsterDat

    return holsterDat

end

function ENT:HolsterWeap( wep )
    local canHolster, holsterDat = self:CanHolsterWeap( wep )
    if not canHolster then return end

    local boneExists, boneId = self:HasHolsterBone( holsterDat.slot )
    if not boneExists then return end

    self:SetActiveWeapon( NULL )

    wep:SetOwner( nil )
    wep:SetVelocity( vector_origin )
    wep:RemoveSolidFlags( FSOLID_TRIGGER )
    wep:RemoveEffects( EF_ITEM_BLINK )
    wep:PhysicsDestroy()

    wep:SetTransmitWithParent( true )
    wep:AddSolidFlags( FSOLID_NOT_SOLID )

    wep:FollowBone( self, boneId )
    wep:SetLocalAngles( holsterDat.rotation )

    wep:SetLocalPos( holsterDat.posOffset )
    wep:SetPos( wep:LocalToWorld( -wep:OBBCenter() ) )

    --debugoverlay.Cross( wep:GetPos(), 5, 10, color_white, true )
    --debugoverlay.Cross( wep:LocalToWorld( -wep:OBBCenter() ), 20, 10, color_white, true )

    if not self.m_HolsteredWeapons then
        self.m_HolsteredWeapons = {}

    end
    self.m_HolsteredWeapons[ wep ] = true

    if not self.m_HolsteringSlots then
        self.m_HolsteringSlots = {}

    end
    self.m_HolsteringSlots[ holsterDat.slot ] = wep

    -- 'equip' sound
    self:EmitSound( "Flesh.Strain", 80, 120, 0.8 )

end

function ENT:UnHolsterWeap( wep )
    local holsterDat = self:GetHolsterData( wep )
    self.m_HolsteredWeapons[ wep ] = nil
    self.m_HolsteringSlots[ holsterDat.slot ] = nil

end