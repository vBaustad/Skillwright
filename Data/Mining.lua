-- Mining leveling routes (WoW Classic Era).
local ADDON, SW = ...

-- segment = { from, to, faction?, zones = {...}, note? }   faction = "Horde"/"Alliance"/nil(both)
SW.RegisterRoute("Mining", {
    { from = 1, to = 65, faction = "Horde", zones = { "Durotar", "Mulgore", "Tirisfal Glades" }, note = "Copper Ore. Smelt it into Copper Bars at any forge as you go." },
    { from = 1, to = 65, faction = "Alliance", zones = { "Dun Morogh", "Elwynn Forest", "Darkshore" }, note = "Copper Ore. Night Elves have no copper at home, so start in Darkshore." },
    { from = 65, to = 125, zones = { "Hillsbrad Foothills", "Redridge Mountains", "Ashenvale", "The Barrens" }, note = "Mostly Tin Ore plus some Copper; mine Silver Veins when seen. Learn to smelt Silver at skill 75." },
    { from = 125, to = 175, zones = { "Arathi Highlands", "Desolace", "Thousand Needles" }, note = "Iron Ore with some Tin; grab Gold Veins on the way. Smelt Iron Bars to round out the range." },
    { from = 175, to = 245, zones = { "The Hinterlands", "Tanaris" }, note = "Mithril Ore plus Truesilver Veins. Learn Artisan Mining at 225 from a Master trainer." },
    { from = 245, to = 275, zones = { "Un'Goro Crater", "Blasted Lands", "Felwood" }, note = "Mithril and Truesilver, with early Thorium starting to appear." },
    { from = 275, to = 300, zones = { "Un'Goro Crater", "Eastern Plaguelands", "Winterspring", "Burning Steppes" }, note = "Thorium Ore, including Rich Thorium Veins. Smelt Thorium Bars to finish." },
})
