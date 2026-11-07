-- Soldier squads, soldiers on the same side who stick together.
--
--  local term_Squads = terminator_Extras.term_Squads
--  local squad = term_Squads.Found( soldier ) -- soldier leads it
--  term_Squads.Merge( bigSquad, smallSquad ) -- smallSquad is gone after
--  term_Squads.Join( squad, otherSoldier )
--  term_Squads.Leave( otherSoldier )
--
-- A soldier on their own is a squad of 1, so joining is just merging that in.
-- Soldiers decide what merges with what, see shared.lua.
-- This keeps the books, and the toughest member always leads.

terminator_Extras = terminator_Extras or {}
terminator_Extras.term_Squads = terminator_Extras.term_Squads or {}

local term_Squads = terminator_Extras.term_Squads
term_Squads.All = term_Squads.All or {} -- squad -> true

local IsValid = IsValid
local entMeta = FindMetaTable( "Entity" )

-- toughest member leads, so elites take over from regular soldiers
-- ties keep the leader we have, so equals don't swap back and forth
local function electLeader( squad )
    local best = squad.leader
    local bestHealth = IsValid( best ) and entMeta.GetMaxHealth( best ) or -math.huge
    for _, member in ipairs( squad.members ) do
        local maxHealth = entMeta.GetMaxHealth( member )
        if maxHealth > bestHealth then
            best = member
            bestHealth = maxHealth

        end
    end
    squad.leader = best

end

function term_Squads.Get( ent )
    local entsTbl = entMeta.GetTable( ent )
    return entsTbl and entsTbl.term_Squad

end

-- safe to call on someone in no squad
function term_Squads.Leave( ent )
    local entsTbl = entMeta.GetTable( ent )
    local squad = entsTbl and entsTbl.term_Squad
    if not squad then return end

    entsTbl.term_Squad = nil
    table.RemoveByValue( squad.members, ent )
    if squad.pushWanted then
        squad.pushWanted[ent] = nil -- or they'd still be voting if they come back

    end

    if #squad.members <= 0 then
        term_Squads.All[squad] = nil
        return

    end
    if squad.leader == ent then
        squad.leader = nil
        electLeader( squad )

    end
end

local function addMember( squad, ent )
    squad.members[#squad.members + 1] = ent
    entMeta.GetTable( ent ).term_Squad = squad
    ent:CallOnRemove( "term_Squads_Leave", term_Squads.Leave )

end

-- everyone in from moves to into, from goes away
-- push and fallback state isn't carried over, only merge calm squads
function term_Squads.Merge( into, from )
    if ( from.contactTime or -math.huge ) > ( into.contactTime or -math.huge ) then
        into.contactPos = from.contactPos
        into.contactArea = from.contactArea
        into.contactTime = from.contactTime

    end
    if ( from.investigateTime or -math.huge ) > ( into.investigateTime or -math.huge ) then
        into.investigatePos = from.investigatePos
        into.investigateArea = from.investigateArea
        into.investigateTime = from.investigateTime

    end
    for _, member in ipairs( from.members ) do
        addMember( into, member )

    end
    from.members = {}
    term_Squads.All[from] = nil
    electLeader( into )

end

-- leaves their old squad first
function term_Squads.Found( leader )
    term_Squads.Leave( leader )
    local squad = {
        leader = leader,
        members = {},
        faction = leader.isTerminatorHunterChummy,
    }
    term_Squads.All[squad] = true
    addMember( squad, leader )
    return squad

end

-- leaves their old squad first
function term_Squads.Join( squad, ent )
    term_Squads.Merge( squad, term_Squads.Found( ent ) )

end

-- how many members are in the fight, how many of those want to push, and since when
function term_Squads.PushVotes( squad )
    local wanted = squad.pushWanted or {}
    local canPush = 0
    local wanting = 0
    local since = math.huge
    for _, member in ipairs( squad.members ) do
        if not member:TermSoldier_CanPush() then continue end
        canPush = canPush + 1
        local wantedAt = wanted[member]
        if wantedAt then
            wanting = wanting + 1
            since = math.min( since, wantedAt )

        end
    end
    return canPush, wanting, since

end

-- the soldiers do the actual thinking, see TermSoldier_SquadThink
timer.Create( "terminator_squad_think", 1, 0, function()
    for squad in pairs( term_Squads.All ) do
        local leader = squad.leader
        if not IsValid( leader ) or not leader.TermSoldier_SquadThink then continue end
        ProtectedCall( function() leader:TermSoldier_SquadThink() end )

    end
end )

local DEBUG_INTERVAL = 0.5
local squadTextOffset = Vector( 0, 0, 60 )
local taskTextOffset = Vector( 0, 0, 45 )
local lineColor = Color( 0, 200, 255 )
local contactColor = Color( 255, 80, 0 )
local investigateColor = Color( 255, 220, 0 )

local function movementTaskOf( member )
    for task in pairs( entMeta.GetTable( member ).m_ActiveTasks or {} ) do
        if string.sub( task, 1, 9 ) == "movement_" then return string.sub( task, 10 ) end

    end
    return "no movement task"

end

local function squadText( squad )
    local text = "squad of " .. #squad.members
    local cur = CurTime()
    if ( squad.fallbackUntil or 0 ) > cur then
        return text .. ", FALLING BACK " .. math.ceil( squad.fallbackUntil - cur ) .. "s left"

    end
    if ( squad.pushUntil or 0 ) > cur then
        return text .. ", PUSHING " .. math.ceil( squad.pushUntil - cur ) .. "s left"

    end

    if not squad.pushWanted then return text end

    local canPush, wanting, since = term_Squads.PushVotes( squad )
    if wanting <= 0 then return text end
    return text .. ", " .. wanting .. "/" .. canPush .. " engaged want push, " .. math.Round( cur - since ) .. "s"

end

function term_Squads.DebugDraw()
    for squad in pairs( term_Squads.All ) do
        local leader = squad.leader
        if not IsValid( leader ) then continue end

        local leaderPos = leader:WorldSpaceCenter()
        debugoverlay.Text( leader:GetPos() + squadTextOffset, squadText( squad ), DEBUG_INTERVAL, false )
        if squad.contactPos then
            debugoverlay.Cross( squad.contactPos, 20, DEBUG_INTERVAL, contactColor, true )
            debugoverlay.Text( squad.contactPos, "contact " .. math.Round( CurTime() - squad.contactTime ) .. "s ago", DEBUG_INTERVAL, false )

        end
        if squad.investigatePos then
            debugoverlay.Cross( squad.investigatePos, 20, DEBUG_INTERVAL, investigateColor, true )
            debugoverlay.Text( squad.investigatePos, "heard " .. math.Round( CurTime() - squad.investigateTime ) .. "s ago", DEBUG_INTERVAL, false )

        end
        for _, member in ipairs( squad.members ) do
            if not IsValid( member ) then continue end
            debugoverlay.Text( member:GetPos() + taskTextOffset, movementTaskOf( member ), DEBUG_INTERVAL, false )
            if member ~= leader then
                debugoverlay.Line( member:WorldSpaceCenter(), leaderPos, DEBUG_INTERVAL, lineColor, true )

            end
        end
    end
end

-- the timer only exists while debugging
-- it looks DebugDraw up each time, so autorefresh swaps in the new one without restarting the timer
local function setDebugging( on )
    if on then
        timer.Create( "terminator_debug_soldiersquad", DEBUG_INTERVAL, 0, function() term_Squads.DebugDraw() end )

    else
        timer.Remove( "terminator_debug_soldiersquad" )

    end
end

local debuggingVar = CreateConVar( "terminator_debug_soldiersquad", 0, FCVAR_NONE, "Draw soldier squads and what each soldier is doing, needs developer 1.", 0, 1 )
setDebugging( debuggingVar:GetBool() )
cvars.AddChangeCallback( "terminator_debug_soldiersquad", function( _, _, new )
    setDebugging( tobool( new ) )

end, "updatedebugging" )
