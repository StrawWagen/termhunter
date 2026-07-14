
local hasInitialized = terminator_Extras.hasInitPostEntitied
local registerQueue = terminator_Extras.registerNPCQueue or {}

local function thatOrMember( toGet, class, that )
    return that[toGet] or scripted_ents.GetMember( class, toGet )

end

local function actuallyRegister( class, rawENTTbl, overrides )
    local listMember = {
        Name = thatOrMember( "PrintName", class, rawENTTbl ),
        Class = class,
        Category = thatOrMember( "Category", class, rawENTTbl ),
        SubCategory = thatOrMember( "SubCategory", class, rawENTTbl ),
    }
    if overrides then
        table.Merge( listMember, overrides, true )

    end
    list.Set( "NPC", class, listMember )

    if CLIENT then
        language.Add( class, listMember.Name )

    end
end

-- register delayed so the .Category and .SubCategory can be inherited from .Base class tree
-- register off InitPostEntity cause that is totally gonna get errored by some broke addon 
timer.Simple( 0, function()
    hasInitialized = true
    terminator_Extras.hasInitPostEntitied = hasInitialized
    while #registerQueue > 0 do
        local member = table.remove( registerQueue, 1 )
        actuallyRegister( member.class, member.rawENTTbl, member.overrides )

    end
end )


--[[------------------------------------
    Name: terminator_Extras.RegisterNPC
    Desc: Puts your entity in the spawnmenu's NPC tab.
        Call on load, see usage of it in this repo for examples
        Exists so that .SubCategory, etc, can propogate down the BaseClass tree
        Means you just have to change .Category, .SubCategory, in one npc and all it's children will follow
    Arg1: string | class | Your entity's class.
    Arg2: table | rawENTTbl | Your ENT table. Its PrintName/Category/SubCategory ( or its .Base's ) fill the spawn icon.
    Arg3: table | overrides | Override the rawENTTbl values, or add other things that the "NPC" list accepts, like .Weapons
    Ret1:
--]]------------------------------------
terminator_Extras.RegisterNPC = function( class, rawENTTbl, overrides )
    if hasInitialized then -- auto re fresh, make sure to call spawnmenu_reload!
        actuallyRegister( class, rawENTTbl, overrides )
        return

    end
    table.insert( registerQueue, { class = class, rawENTTbl = rawENTTbl, overrides = overrides } )

end