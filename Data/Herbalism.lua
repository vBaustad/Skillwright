-- Herbalism leveling routes (WoW Classic Era).
local ADDON, SW = ...

-- segment = { from, to, faction?, zones = {...}, note? }   faction = "Horde"/"Alliance"/nil(both)
SW.RegisterRoute("Herbalism", {
    { from = 1, to = 70, faction = "Horde", zones = { "Durotar", "Mulgore", "Tirisfal Glades" }, note = "Loop the starting zones picking Peacebloom and Silverleaf; grab Earthroot from rockier ground." },
    { from = 1, to = 70, faction = "Alliance", zones = { "Elwynn Forest", "Teldrassil", "Dun Morogh" }, note = "Loop the starting zones picking Peacebloom and Silverleaf; grab Earthroot from rockier ground." },
    { from = 70, to = 115, zones = { "The Barrens", "Silverpine Forest", "Loch Modan", "Darkshore" }, note = "Learn Journeyman Herbalism first. Pick Mageroyal and Briarthorn; Stranglekelp near water once you hit 85." },
    { from = 115, to = 170, zones = { "Hillsbrad Foothills", "Wetlands", "Stonetalon Mountains" }, note = "Train again at 150. Gather Bruiseweed, Wild Steelbloom and Kingsblood; Liferoot near water from 150." },
    { from = 170, to = 205, zones = { "Stranglethorn Vale", "Arathi Highlands" }, note = "Pick Kingsblood, Liferoot, Fadeleaf and Goldthorn; Khadgar's Whisker becomes available from 185." },
    { from = 205, to = 230, zones = { "Tanaris", "Searing Gorge" }, note = "Learn Artisan Herbalism. Farm Purple Lotus and Firebloom around the open desert and gorge." },
    { from = 230, to = 270, zones = { "The Hinterlands" }, note = "Loop for Sungrass and Purple Lotus, plus Golden Sansam; Ghost Mushroom in caves from 245." },
    { from = 270, to = 300, zones = { "Felwood" }, note = "Run the roads for Dreamfoil, Gromsblood, Mountain Silversage, Plaguebloom and Golden Sansam." },
})
