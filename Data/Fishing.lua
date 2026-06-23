-- Fishing leveling routes (WoW Classic Era).
local ADDON, SW = ...

-- segment = { from, to, faction?, zones = {...}, note? }   faction = "Horde"/"Alliance"/nil(both)
SW.RegisterRoute("Fishing", {
    { from = 1, to = 75, faction = "Horde", zones = { "Durotar", "Mulgore", "Tirisfal Glades" }, note = "Learn Fishing at character level 5. Buy a Fishing Pole and a few Shiny Baubles from a trade or fishing supplier; apply a Bauble before casting. Fish any nearby water in a starting zone." },
    { from = 1, to = 75, faction = "Alliance", zones = { "Elwynn Forest", "Dun Morogh", "Teldrassil" }, note = "Learn Fishing at character level 5. Buy a Fishing Pole and Shiny Baubles from a supplier and apply a Bauble. Any starting-zone water works for early skill ups." },
    { from = 75, to = 150, zones = { "The Barrens", "Westfall", "Loch Modan", "Silverpine Forest", "Darkshore" }, note = "Train Journeyman Fishing first. Capital-city water (Orgrimmar, Stormwind, etc.) also works. Keep a Shiny Bauble on the pole to reduce escapes." },
    { from = 150, to = 225, zones = { "Dustwallow Marsh", "Stranglethorn Vale", "Arathi Highlands", "Desolace", "Thousand Needles" }, note = "Buy the Expert Fishing book from Old Man Heming in Booty Bay (Stranglethorn) and grab Bright Baubles there. Apply Bright Baubles; Dustwallow Marsh is a fast pick." },
    { from = 225, to = 300, zones = { "Tanaris", "Feralas", "Un'Goro Crater", "The Hinterlands", "Felwood", "Western Plaguelands" }, note = "Train Artisan past 225 by finishing Nat Pagle's quest in Dustwallow Marsh (catch the four quest fish). Keep Bright Baubles on the pole so high-level fish do not get away." },
})
