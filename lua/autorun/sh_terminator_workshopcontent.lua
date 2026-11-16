
-- shared so both halves of the workshop content system read the same convar, see autorun/server/terminator_workshopcontent.lua
-- off by default, ENT.MyWorkshopContentIds get resource.AddWorkshop'd
-- replicated, clients check it before getting a bot's content on demand
CreateConVar( "terminator_myworkshopcontentids_ondemand", 0, { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Should clients download terminator nextbots' ENT.MyWorkshopContentIds when they first see one, instead of at join? For dedicated servers that don't want everyone downloading everything. Needs a map change.", 0, 1 )
