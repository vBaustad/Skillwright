-- Cooking 1-300 craft path (WoW Classic Era).
-- Factual craft data from public leveling guides; item IDs best-effort (spot-check in-game).
local ADDON, SW = ...

-- mat entry = { name, totalForStep, itemId }
SW.RegisterPath("Cooking", {
    { from = 1,   to = 50,  qty = 55, recipe = "Charred Wolf Meat", item = 2679, note = "Cooking is a secondary skill, so no separate Journeyman/Expert trainer rank gates you the way a primary profession does; you simply learn higher tiers and recipes from trainers and recipe vendors. Cooking pairs naturally with Fishing, which supplies most of the raw fish below. Learn Apprentice Cooking and this recipe from any Cooking trainer (requires character level 5). Swap in any same-tier recipe if you have more of another meat or fish.",
        mats = { { "Stringy Wolf Meat", 55, 2672 } } },
    { from = 50,  to = 100, qty = 55, recipe = "Boiled Clams", item = 5525, note = "Learn the next recipes from your Cooking trainer (requires Cooking 50). Refreshing Spring Water and Clam Meat are easy to gather or buy. Fished mud snappers (Raw Longjaw Mud Snapper) also work well here.",
        mats = { { "Clam Meat", 55, 5503 }, { "Refreshing Spring Water", 55, 159 } } },
    { from = 100, to = 130, qty = 40, recipe = "Crab Cake", item = 2683, note = "Crab Cake is a trainer recipe; Crawler Meat drops from crabs along most coastlines.",
        mats = { { "Crawler Meat", 40, 2675 } } },
    { from = 130, to = 175, qty = 50, recipe = "Curiously Tasty Omelet", item = 3665, note = "At skill 125 learn Expert Cooking by buying the Expert Cookbook (recipe vendor): Wulan in Desolace (Horde) or Shandrina in Ashenvale (Alliance). The Curiously Tasty Omelet recipe is sold by a vendor (Kendor Kabonka in Stormwind / Keena in Hillsbrad); vendorPattern = true. Raptor Eggs come from raptors in the Barrens / Arathi.",
        vendorPattern = true,
        mats = { { "Raptor Egg", 50, 3685 } } },
    { from = 175, to = 225, qty = 50, recipe = "Roast Raptor", item = 12210, note = "Roast Raptor recipe is sold by a vendor (Hammon Karwn / Keena, Arathi Highlands); vendorPattern = true. Raptor Flesh drops from higher-level raptors. Soothing Turtle Bisque (Turtle Meat) is a solid alternative if you have a stack of turtle meat.",
        vendorPattern = true,
        mats = { { "Raptor Flesh", 50, 12184 } } },
    { from = 225, to = 275, qty = 65, recipe = "Spotted Yellowtail", item = 6887, note = "At skill 225 learn Artisan Cooking by completing the quest 'Clamlette Surprise' from Dirge Quikcleave in Gadgetzan, Tanaris (requires character level ~35; turn-in needs 1 Giant Clam Scorcher made from Big-mouth Clam, plus other quest items). The Spotted Yellowtail recipe is sold by Gikkix in Tanaris; vendorPattern = true. Fish Raw Spotted Yellowtail off the coast.",
        vendorPattern = true,
        mats = { { "Raw Spotted Yellowtail", 65, 4603 } } },
    { from = 275, to = 300, qty = 35, recipe = "Nightfin Soup", item = 13931, note = "Nightfin Soup recipe is sold by Gikkix in Tanaris; vendorPattern = true. Raw Nightfin Snapper is fished at night in high-level zones. Poached Sunscale Salmon (Raw Sunscale Salmon) is an equivalent finisher.",
        vendorPattern = true,
        mats = { { "Raw Nightfin Snapper", 35, 13759 } } },
})
