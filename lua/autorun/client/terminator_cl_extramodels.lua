
-- clientside models stuck onto entities, see ENT.MyExtraModels in terminator_nextbot/shared.lua
-- two ways to use it
-- AttachMyExtraModels, for ents drawn normally. extras get parented to the ent, the engine carries them around and draws them
-- DrawMyExtraModels, for ents you draw by hand, eg a NoDraw copy in a viewmodel. call it every frame, it places and draws the extras itself
-- DropMyExtraModels knocks attached extras off as physics props, eg mid death animation
-- attached extras hide when the ent's dormant or NoDraw. anything that hides an ent its own way, eg cloaking, has to hide its extras too:
--     hook.Add( "ShouldDrawMyExtraModels", "myaddon", function( ent ) if ent.myaddon_Cloaked then return false end end )
-- drawn extras ignore that hook, just don't call DrawMyExtraModels

terminator_Extras = terminator_Extras or {}

local entMeta = FindMetaTable( "Entity" )

local IsValid = IsValid
local LocalToWorld = LocalToWorld
local hook_Run = hook.Run
local vector_origin = Vector( 0, 0, 0 )
local angle_zero = Angle( 0, 0, 0 )

local knownFields = { model = true, pos = true, ang = true, bone = true, attachment = true, scale = true, material = true, color = true, hideWhenDead = true, fallOffOnDeath = true, initialize = true, think = true, thinkInterval = true, draw = true }
local developerVar = GetConVar( "developer" )


-- WARNINGS --

local function warningMessage( ent, index, problem )
    local where = "MyExtraModels"
    if index then
        where = "MyExtraModels entry " .. index

    end
    return "terminator_Extras: " .. ent:GetClass() .. " " .. where .. ", " .. problem .. ". Skipping it.\n"

end

-- a mistake in the entries themselves
local function warn( ent, index, problem )
    ErrorNoHalt( warningMessage( ent, index, problem ) )

end

-- missing models, bones and attachments are usually the player's end, not the dev's. missing content, model replacement addons
-- so it only gets loud with developer on
local function warnMissing( ent, index, problem )
    local msg = warningMessage( ent, index, problem )
    if developerVar:GetInt() > 0 then
        ErrorNoHalt( msg )

    else
        permaPrint( msg )

    end
end


-- MAKING EXTRAS --

-- looks up the entry's bone/attachment onto extra, and makes its prop. returns nil if anything's wrong with the entry
local function makeProp( ent, index, entry, extra )
    local model = entry.model
    if not isstring( model ) then
        warn( ent, index, "missing or non-string model" )
        return

    end

    for field in pairs( entry ) do
        if not knownFields[field] then
            warn( ent, index, "unknown field \"" .. tostring( field ) .. "\", typo?" )
            return

        end
    end

    if entry.material ~= nil and not isstring( entry.material ) then
        warn( ent, index, "non-string material" )
        return

    end
    if entry.color ~= nil and not IsColor( entry.color ) then
        warn( ent, index, "color isn't a Color()" )
        return

    end

    if entry.hideWhenDead and entry.fallOffOnDeath then
        warn( ent, index, "has both hideWhenDead and fallOffOnDeath set, pick one" )
        return

    end

    local bone = entry.bone
    local attachment = entry.attachment
    if bone and attachment then
        warn( ent, index, "has both bone and attachment set, pick one" )
        return

    end

    if bone then
        extra.boneId = ent:LookupBone( bone )
        if not extra.boneId then
            warnMissing( ent, index, "model " .. tostring( ent:GetModel() ) .. " has no bone \"" .. bone .. "\"" )
            return

        end
    elseif attachment then
        extra.attachId = ent:LookupAttachment( attachment )
        if extra.attachId <= 0 then
            warnMissing( ent, index, "model " .. tostring( ent:GetModel() ) .. " has no attachment \"" .. attachment .. "\"" )
            return

        end
    end

    -- not util.IsValidModel, clientside that's false for any model nothing has loaded yet
    if not file.Exists( model, "GAME" ) then
        warnMissing( ent, index, "model " .. model .. " doesn't exist" )
        return

    end

    -- see-through extras have to sort with the translucents, or they draw over/under the wrong things
    local renderGroup = RENDERGROUP_OPAQUE
    if entry.color and entry.color.a < 255 then
        renderGroup = RENDERGROUP_TRANSLUCENT

    end

    local prop = ClientsideModel( model, renderGroup )
    if not IsValid( prop ) then
        warn( ent, index, "ClientsideModel( \"" .. model .. "\" ) failed" )
        return

    end

    return prop

end

-- broken entries still get an extra, with no prop, so they're only warned about once per ent model
local function makeExtra( ent, index, entry )
    local extra = {
        entry = entry,
        -- what the prop was made from, if any of these change it gets remade
        model = entry.model,
        bone = entry.bone,
        attachment = entry.attachment,
    }
    extra.prop = makeProp( ent, index, entry, extra )
    return extra

end

local function needsRemaking( extra, entry, entModelChanged )
    if not extra then return true end
    if extra.prop and not IsValid( extra.prop ) then return true end
    -- new model, new bone and attachment ids. also retries ones that failed on the old model
    if entModelChanged and ( entry.bone or entry.attachment ) then return true end

    return extra.model ~= entry.model or extra.bone ~= entry.bone or extra.attachment ~= entry.attachment

end


-- PLACING EXTRAS --

local function applyScale( extra, scale )
    if extra.appliedScale == scale then return end
    extra.appliedScale = scale
    entMeta.SetModelScale( extra.prop, scale )

end

-- only touches the prop when the entry's value changes, so initialize/think can set their own material or color without it getting stomped
local function applyLooks( extra )
    local entry = extra.entry
    local prop = extra.prop

    local material = entry.material
    if extra.appliedMaterial ~= material then
        extra.appliedMaterial = material
        entMeta.SetMaterial( prop, material or "" )

    end

    local color = entry.color
    if extra.appliedColor ~= color then
        extra.appliedColor = color
        color = color or color_white
        entMeta.SetColor( prop, color )
        -- alpha does nothing in the default render mode
        entMeta.SetRenderMode( prop, color.a < 255 and RENDERMODE_TRANSCOLOR or RENDERMODE_NORMAL )

    end
end

local function scaledOffset( pos, scale )
    if scale == 1 then return pos end
    return pos * scale

end

local function parentExtra( ent, extra )
    local prop = extra.prop
    if extra.boneId then
        prop:FollowBone( ent, extra.boneId )

    elseif extra.attachId then
        prop:SetParent( ent, extra.attachId )

    else
        prop:SetParent( ent )

    end

    -- parenting keeps the world pos, and a fresh prop's is 0,0,0
    -- so without this it'd ride along a whole map away, and only get drawn when the world origin is on screen
    prop:SetLocalPos( vector_origin )
    prop:SetLocalAngles( angle_zero )

end

-- returns false if the ent's bone/attachment isn't there to place it on
local function placeDrawnExtra( ent, extra )
    local basePos
    local baseAng
    if extra.boneId then
        local matrix = entMeta.GetBoneMatrix( ent, extra.boneId )
        if not matrix then return false end
        basePos = matrix:GetTranslation()
        baseAng = matrix:GetAngles()

    elseif extra.attachId then
        local attach = entMeta.GetAttachment( ent, extra.attachId )
        if not attach then return false end
        basePos = attach.Pos
        baseAng = attach.Ang

    else
        basePos = entMeta.GetPos( ent )
        baseAng = entMeta.GetAngles( ent )

    end

    local entry = extra.entry
    local entScale = entMeta.GetModelScale( ent )
    applyScale( extra, ( entry.scale or 1 ) * entScale )

    -- LocalToWorld doesn't know the bone's scale, so bones get scaled here too
    local offset = scaledOffset( entry.pos or vector_origin, entScale )
    local pos, ang = LocalToWorld( offset, entry.ang or angle_zero, basePos, baseAng )

    local prop = extra.prop
    entMeta.SetPos( prop, pos )
    entMeta.SetAngles( prop, ang )
    entMeta.InvalidateBoneCache( prop )
    return true

end


-- DRAWING EXTRAS --

local function drawExtra( ent, prop, realEnt, entry, flags )
    if entry.draw then
        entry.draw( ent, prop, realEnt, flags )

    else
        entMeta.DrawModel( prop, flags )

    end
end

-- the .RenderOverride, that gets applied on the created extra prop
local function makeAttachedOverride( ent, extra )
    return function( prop, flags )
        -- :Remove() lands next tick, so a removed ent's extras can still get drawn in between
        if not IsValid( ent ) then return end
        if entMeta.IsDormant( ent ) or entMeta.GetNoDraw( ent ) then return end
        if hook_Run( "ShouldDrawMyExtraModels", ent ) == false then return end

        if entMeta.GetParent( prop ) ~= ent then
            parentExtra( ent, extra )

        end

        local entry = extra.entry
        local entScale = entMeta.GetModelScale( ent )
        applyScale( extra, ( entry.scale or 1 ) * entScale )

        local pos = entry.pos or vector_origin
        -- bone matrices already carry the ent's scale, the origin and attachments don't
        if not extra.boneId then
            pos = scaledOffset( pos, entScale )

        end
        entMeta.SetLocalPos( prop, pos )
        entMeta.SetLocalAngles( prop, entry.ang or angle_zero )

        drawExtra( ent, prop, ent, entry, flags )

    end
end


-- THINKING --

local defaultThinkInterval = 0.03 -- bit less than every other frame at 66ticks

local function startThinking( ent, extra )
    local entry = extra.entry
    if not entry.think then return end

    -- not EntIndex, every clientside ent's is -1
    local timerName = "terminator_ExtraModels_" .. tostring( extra )
    extra.timerName = timerName

    extra.thinkInterval = entry.thinkInterval or defaultThinkInterval

    timer.Create( timerName, extra.thinkInterval, 0, function()
        local prop = extra.prop
        if not IsValid( ent ) or not IsValid( prop ) then
            timer.Remove( timerName )
            return

        end

        -- read every time, so autorefresh can change them
        local thinkInterval = extra.entry.thinkInterval or defaultThinkInterval
        if thinkInterval ~= extra.thinkInterval then
            extra.thinkInterval = thinkInterval
            timer.Adjust( timerName, thinkInterval )

        end

        if ent:IsDormant() then return end

        local think = extra.entry.think
        if think then think( ent, prop, extra.realEnt ) end

    end )
end


-- KEEPING EXTRAS IN SYNC WITH THE ENTRIES --

-- ent -> its attached state, watched for model changes. nothing calls AttachMyExtraModels again when an ent's model changes
terminator_Extras.attachedExtrasEnts = terminator_Extras.attachedExtrasEnts or {}
local attachedEnts = terminator_Extras.attachedExtrasEnts

local function removeExtra( extra )
    SafeRemoveEntity( extra.prop )
    if extra.timerName then
        timer.Remove( extra.timerName )

    end
end

-- makes extras for new entries, remakes changed ones, removes ones past the end of the entries
local function syncExtras( ent, state, realEnt )
    local entModel = entMeta.GetModel( ent ) or ""
    local entModelChanged = state.entModel ~= entModel
    -- recorded even when empty, or manageAttachedExtras would see a change and resync every frame
    state.entModel = entModel

    -- client Initialize can run before the ent's model arrives, no bones to look up yet
    if entModel == "" then return end

    local entries = state.entries
    local extras = state.extras
    local count = #entries

    for index = #extras, count + 1, -1 do
        removeExtra( extras[index] )
        extras[index] = nil

    end

    for index = 1, count do
        local entry = entries[index]
        local extra = extras[index]
        if needsRemaking( extra, entry, entModelChanged ) then
            if extra then
                removeExtra( extra )

            end

            extra = makeExtra( ent, index, entry )
            extra.realEnt = realEnt
            extras[index] = extra

            local prop = extra.prop
            if prop then
                applyLooks( extra )
                -- AttachMyExtraModels, parented once, let the engine move and draw it
                if state.isAttached then
                    parentExtra( ent, extra )
                    prop.RenderOverride = makeAttachedOverride( ent, extra )

                -- DrawMyExtraModels inside a :Draw(),
                -- NoDraw so the engine doesn't draw it. we draw it ourselves
                else
                    prop:SetNoDraw( true )

                end

                if entry.initialize then entry.initialize( ent, prop, realEnt ) end
                startThinking( ent, extra )

            end
        end

        -- the entries table itself can be swapped out, eg autorefresh
        extra.entry = entry
        extra.realEnt = realEnt
        if extra.prop then
            applyLooks( extra )

        end
    end
end

local function removeExtras( state )
    for _, extra in ipairs( state.extras ) do
        removeExtra( extra )

    end
    -- entries stay, so the extras can be remade if the ent comes back, eg after a full update
    state.extras = {}

end

local function onEntRemoved( ent )
    attachedEnts[ent] = nil
    if ent.term_AttachedExtras then
        removeExtras( ent.term_AttachedExtras )

    end
    if ent.term_DrawnExtras then
        removeExtras( ent.term_DrawnExtras )

    end
end

local function getState( ent, key, entries, isAttached )
    local state = ent[key]
    if state and state.entries == entries then return state end

    if not istable( entries ) then
        warn( ent, nil, "isn't a table" )
        return

    end
    if entries.BaseClass then
        warn( ent, nil, "was merged into its base class's list by SENT inheritance, pass scripted_ents.GetMember( class, key ) instead" )
        return

    end
    -- MyExtraModels = { model = ... } has no list part, so it would silently make nothing
    if #entries == 0 and next( entries ) ~= nil then
        warn( ent, nil, "isn't a list, wrap each entry in its own { }" )

    end

    if not state then
        -- isAttached, Attach or Draw. see syncExtras
        state = { extras = {}, isAttached = isAttached }
        ent[key] = state
        ent:CallOnRemove( "terminator_ExtraModels", onEntRemoved )

    end
    state.entries = entries
    return state

end


-- PUBLIC --

-- call again whenever entries changes, extras made from unchanged entries are kept
function terminator_Extras.AttachMyExtraModels( ent, entries )
    local state = getState( ent, "term_AttachedExtras", entries, true )
    if not state then return end

    if next( attachedEnts ) == nil then
        hook.Add( "Think", "terminator_ExtraModels", function()
            local returned = terminator_Extras.manageAttachedExtras()
            if returned == false then
                hook.Remove( "Think", "terminator_ExtraModels" )

            end
        end )
    end
    attachedEnts[ent] = state
    syncExtras( ent, state, ent )

    for _, extra in ipairs( state.extras ) do
        local prop = extra.prop
        if prop and prop:GetParent() ~= ent then
            parentExtra( ent, extra )

        end
    end
end

-- call every frame, right after drawing ent
-- realEnt is what the entry callbacks get as their 3rd arg. when ent is a stand-in copy, pass the entity it's standing in for
function terminator_Extras.DrawMyExtraModels( ent, entries, flags, realEnt )
    realEnt = realEnt or ent
    local state = getState( ent, "term_DrawnExtras", entries, false )
    if not state then return end

    syncExtras( ent, state, realEnt )

    for _, extra in ipairs( state.extras ) do
        local prop = extra.prop
        if prop and placeDrawnExtra( ent, extra ) then
            drawExtra( ent, prop, realEnt, extra.entry, flags )

        end
    end
end

-- re-parents extras that lost their parent while the ent was out of the PVS, an off screen extra never runs its RenderOverride to fix itself
-- also remakes extras removed by a full update, those fire the ent's CallOnRemove without removing the ent
hook.Add( "NotifyShouldTransmit", "terminator_ExtraModels", function( ent, shouldTransmit )
    if not shouldTransmit then return end
    local entTbl = entMeta.GetTable( ent )
    local state = entTbl and entTbl.term_AttachedExtras
    if not state then return end

    terminator_Extras.AttachMyExtraModels( ent, state.entries )

end )

local defaultDropLifetime = 30

-- makes a physics prop where the extra's prop is, looking how it does, removed after about lifetime seconds
-- give or take 10%, so a pile of them doesn't all vanish on the same frame
local function dropExtra( ent, extra, lifetime )
    local old = extra.prop
    local prop = ents.CreateClientProp( old:GetModel() )
    if not IsValid( prop ) then return end

    prop:SetPos( old:GetPos() )
    prop:SetAngles( old:GetAngles() )
    prop:SetModelScale( old:GetModelScale() ) -- visual only, the physics stays model sized
    prop:SetSkin( old:GetSkin() )
    for _, group in ipairs( old:GetBodyGroups() ) do
        prop:SetBodygroup( group.id, old:GetBodygroup( group.id ) )

    end
    terminator_Extras.copyMatsOver( old, prop )
    prop:SetColor( old:GetColor() )
    prop:SetRenderMode( old:GetRenderMode() )
    prop:Spawn()

    local phys = prop:GetPhysicsObject()
    if IsValid( phys ) then
        phys:SetVelocity( ent:GetVelocity() )

    end

    lifetime = lifetime or defaultDropLifetime
    SafeRemoveEntityDelayed( prop, lifetime * math.Rand( 0.9, 1.1 ) )

    return prop

end

-- cloaked and the like, a prop popping out of nowhere would give it away
local function extrasVisible( ent )
    return hook_Run( "ShouldDrawMyExtraModels", ent ) ~= false

end

-- drops ent's attached extras off as physics props, eg at the start of a death animation
-- the ent stops having extras, so they won't come back, or carry onto its ragdoll
-- returns the props, they get removed after about lifetime seconds
function terminator_Extras.DropMyExtraModels( ent, lifetime )
    local state = ent.term_AttachedExtras
    if not state then return {} end

    local dropped = {}
    if not entMeta.IsDormant( ent ) and not entMeta.GetNoDraw( ent ) and extrasVisible( ent ) then
        for _, extra in ipairs( state.extras ) do
            if IsValid( extra.prop ) then
                dropped[#dropped + 1] = dropExtra( ent, extra, lifetime )

            end
        end
    end

    attachedEnts[ent] = nil
    removeExtras( state )
    ent.term_AttachedExtras = nil

    return dropped

end

-- attached extras move onto the ent's clientside death ragdoll, minus hideWhenDead ones. fallOffOnDeath ones drop off as props instead
-- the ragdoll's a fresh ent, so they're made anew, initialize and all, and their callbacks get the ragdoll, not the dead ent
hook.Add( "CreateClientsideRagdoll", "terminator_ExtraModels", function( died, ragdoll )
    local state = died.term_AttachedExtras
    if not state then return end

    local visible = extrasVisible( died )

    local carried = {}
    for index, entry in ipairs( state.entries ) do
        if entry.fallOffOnDeath then
            local extra = state.extras[index]
            if visible and extra and IsValid( extra.prop ) then
                local prop = dropExtra( died, extra )
                -- or sooner, if the ragdoll goes first, eg a cleanup
                if prop then
                    ragdoll:CallOnRemove( "terminator_ExtraModels_" .. tostring( prop ), function() SafeRemoveEntity( prop ) end )

                end
            end
        elseif not entry.hideWhenDead then
            carried[#carried + 1] = entry

        end
    end
    if #carried == 0 then return end

    terminator_Extras.AttachMyExtraModels( ragdoll, carried )

end )

-- the Think hook AttachMyExtraModels adds, returns false once there's no ents left to watch
-- DrawMyExtraModels needs none of this, it syncs every frame anyway
function terminator_Extras.manageAttachedExtras()
    for ent, state in pairs( attachedEnts ) do
        if not IsValid( ent ) then
            attachedEnts[ent] = nil

        elseif ( entMeta.GetModel( ent ) or "" ) ~= state.entModel then
            terminator_Extras.AttachMyExtraModels( ent, state.entries )

        end
    end

    if next( attachedEnts ) == nil then return false end

end
