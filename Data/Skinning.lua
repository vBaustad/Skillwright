-- Skinning leveling routes (WoW Classic Era).
local ADDON, SW = ...

-- segment = { from, to, faction?, zones = {...}, note? }   faction = "Horde"/"Alliance"/nil(both)
SW.RegisterRoute("Skinning", {
    { from = 1, to = 75, faction = "Horde", zones = { "Durotar", "Mulgore", "The Barrens" }, note = "Skin beasts for Light Leather. You can also skin mobs other players kill." },
    { from = 1, to = 75, faction = "Alliance", zones = { "Dun Morogh", "Elwynn Forest", "Loch Modan" }, note = "Skin low-level beasts for Light Leather. Carry a Skinning Knife in your bags." },
    { from = 75, to = 125, faction = "Horde", zones = { "The Barrens", "Stonetalon Mountains" }, note = "Keep skinning beasts toward Camp Taurajo. Mostly Light Leather with the first Medium Leather appearing." },
    { from = 75, to = 125, faction = "Alliance", zones = { "Loch Modan", "Wetlands" }, note = "Work the river paths and grasslands for Light and Medium Leather." },
    { from = 125, to = 175, zones = { "Thousand Needles", "Arathi Highlands", "Hillsbrad Foothills" }, note = "Medium Leather from mid-level beasts. Learn Expert Skinning around this point." },
    { from = 175, to = 205, zones = { "Arathi Highlands", "Desolace", "Stranglethorn Vale" }, note = "Higher-level beasts now give Heavy Leather. Learn Artisan Skinning at 205." },
    { from = 205, to = 260, zones = { "Feralas", "Tanaris", "The Hinterlands" }, note = "Skin yetis and other beasts near Camp Mojache for Thick Leather." },
    { from = 260, to = 300, zones = { "Un'Goro Crater", "Winterspring", "Western Plaguelands" }, note = "High-level beasts drop Rugged Leather. Devilsaurs and thunder lizards skin well to reach 300." },
})
