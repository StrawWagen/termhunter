--[[ 
ENT.IsWraith = true -- set to true on any bot to enable this file's logic
ENT.NotSolidWhenCloaked = true -- if we're a wraith, we become non-solid when cloaked

ENT.FlickerBarelyVisibleMat = "effects/combineshield/comshieldwall3"
ENT.FlickerInvisibleMat = "effects/combineshield/comshieldwall"

function self:PlayHideFX()
    self:EmitSound( "ambient/levels/citadel/pod_open1.wav", 74, math.random( 115, 125 ) )

end

function self:PlayUnhideFX()
    self:EmitSound( "ambient/levels/citadel/pod_close1.wav", 74, math.random( 115, 125 ) )

end

ENT.wraithTerm_IsCloaked = false -- are we currently cloaked?

ENT.wraithTerm_CloakDecidingTask = function( self, data ) end -- override the default cloaking deciding func 

--]]

function ENT:InitializeWraith( myTbl )
    self.wraithTerm_NextHidingSwap = 0
    self.wraithTerm_NextAttack = 0
    self.wraithTerm_IsCloaked = false

    self.MySpecialActions = self.MySpecialActions or {}
    self.MySpecialActions["wraithcloaking"] = {
        inBind = IN_SPEED, -- combo
        commandName = "+reload", -- sprint and reload combo
        name = "Cloak/Uncloak",
        drawHint = true,
        syncCommand = true, -- instruct server to inform client that yes this exists

        svAction = function( _drive, _driver, bot )
            bot:DoHiding( not bot.wraithTerm_IsCloaked )

        end,
    }

    -- so every wraith can have different logic for hiding
    local cloakDecidingFunc = self.wraithTerm_CloakDecidingTask or function( self, data )
        local speedSqr = self:GetCurrentSpeedSqr()
        local enem = self:GetEnemy()
        local doHide = IsValid( enem ) or speedSqr > 80^2
        local enemDist = self.DistToEnemy
        if doHide and speedSqr < 85^1 then
            doHide = false

        elseif doHide and IsValid( enem ) and enemDist < 120 then
            doHide = false
            self:ReallyAnger( 90 ) -- ANGRY

        end

        self:DoHiding( doHide )

        if self.wraithTerm_IsCloaked and math.Rand( 0, 100 ) < 0.5 then
            self:CloakedMatFlicker()

        end
    end

    self.MyClassTask = self.MyClassTask or {}
    -- BehaveUpdatePriority doesn't run when being driven by ply
    self.MyClassTask["BehaveUpdatePriority"] = cloakDecidingFunc

    if self.NotSolidWhenCloaked == nil then self.NotSolidWhenCloaked = true end
    self.FlickerBarelyVisibleMat = myTbl.FlickerBarelyVisibleMat or "effects/combineshield/comshieldwall3"
    self.FlickerInvisibleMat = myTbl.FlickerInvisibleMat or "effects/combineshield/comshieldwall"

    function self:CloakedMatFlicker()
        local toApply = { self }
        table.Add( toApply, self:GetChildren() )

        for _, ent in pairs( toApply ) do
            if not IsValid( ent ) then continue end
            local entsParent = ent:GetParent()
            if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

            if IsValid( ent ) then
                ent:SetMaterial( self.FlickerBarelyVisibleMat )

            end
        end
        timer.Simple( math.Rand( 0.65, 0.75 ), function()
            if not IsValid( self ) then return end
            if self:IsSolid() then return end
            toApply = { self }
            table.Add( toApply, self:GetChildren() )

            for _, ent in pairs( toApply ) do
                if not IsValid( ent ) then continue end
                local entsParent = ent:GetParent()
                if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end

                if IsValid( ent ) then
                    ent:SetMaterial( self.FlickerInvisibleMat )

                end
            end
        end )
    end

    function self:CanWeaponPrimaryAttack()
        if self.wraithTerm_IsCloaked then return false end
        local nextAttack = self.wraithTerm_NextAttack or 0
        if nextAttack > CurTime() then return end
        return self:GetTable().BaseClass.CanWeaponPrimaryAttack( self )

    end

    function self:DoHiding( hide )
        local oldHide = self.wraithTerm_IsCloaked
        if hide == oldHide then return end
        local nextSwap = self.wraithTerm_NextHidingSwap or 0
        if nextSwap > CurTime() then return end

        if hide then
            if self.NotSolidWhenCloaked then
                self:SetCollisionGroup( COLLISION_GROUP_DEBRIS )
                self:SetSolidMask( MASK_NPCSOLID_BRUSHONLY )

            end
            self:SetRenderMode( RENDERMODE_TRANSALPHA ) -- CFC JI compat
            self:AddFlags( FL_NOTARGET )
            self.wraithTerm_NextHidingSwap = CurTime() + math.Rand( 0.25, 0.75 )

            self:PlayHideFX()

            self:CloakedMatFlicker()
            self:RemoveAllDecals()

            local toApply = { self }
            table.Add( toApply, self:GetChildren() )
            for _, ent in pairs( toApply ) do
                if not IsValid( ent ) then continue end
                local entsParent = ent:GetParent()
                if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end
                ent:DrawShadow( false )
                if self.NotSolidWhenCloaked then
                    ent:SetNotSolid( true )

                end
            end

            self.wraithTerm_IsCloaked = true

        else -- unhide
            self.wraithTerm_NextHidingSwap = CurTime() + math.Rand( 2.5, 3.5 )

            self:PlayUnhideFX()
            self:CloakedMatFlicker()
            timer.Simple( 0.25, function()
                if not IsValid( self ) then return end
                self.wraithTerm_NextAttack = CurTime() + 0.25
                self:EmitSound( "buttons/combine_button_locked.wav", 76, 50 )
                self:SetCollisionGroup( COLLISION_GROUP_NPC )
                self:SetSolidMask( MASK_NPCSOLID )

                self:RemoveFlags( FL_NOTARGET )
                self:SetRenderMode( RENDERMODE_NORMAL ) -- CFC JI compat

                self:OnStuck()

                local toApply = { self }
                table.Add( toApply, self:GetChildren() )
                for _, ent in pairs( toApply ) do
                    if not IsValid( ent ) then continue end
                    local entsParent = ent:GetParent()
                    if ent ~= self and ( not IsValid( entsParent ) or entsParent ~= self ) then continue end
                    ent:DrawShadow( true )
                    ent:SetMaterial( "" )
                    if self.NotSolidWhenCloaked then
                        ent:SetNotSolid( false )

                    end

                end
            end )

            self.wraithTerm_IsCloaked = false

        end
    end
end