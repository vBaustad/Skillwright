-- Leatherworking 1-300 craft path (WoW Classic Era).
-- Factual craft data: skill range, quantity, recipe, and the TOTAL materials for that
-- step. Item IDs are best-effort and should be spot-checked in-game (used later for the
-- "still need" counts). Optimal route referenced from public leveling guides.
local ADDON, SW = ...

-- mat entry = { name, totalForStep, itemId }
SW.RegisterPath("Leatherworking", {
    { from = 1,   to = 20,  qty = 19, recipe = "Light Leather", item = 2318, note = "Tip: buy thread, dye, and salt from the Leatherworking supplier near your trainer. Leatherworking pairs well with Skinning for a steady leather supply.",
        mats = { { "Ruined Leather Scraps", 57, 2934 } } },
    { from = 20,  to = 45,  qty = 40, recipe = "Light Armor Kit", item = 2304,
        mats = { { "Light Leather", 40, 2318 } } },
    { from = 45,  to = 55,  qty = 20, recipe = "Handstitched Leather Cloak", item = 7276,
        mats = { { "Light Leather", 40, 2318 }, { "Coarse Thread", 20, 2320 } } },
    { from = 55,  to = 100, qty = 50, recipe = "Embossed Leather Gloves", item = 4239, note = "At skill 75 you must learn Journeyman Leatherworking (requires character level 10) from an Expert trainer before you can keep leveling.",
        mats = { { "Light Leather", 150, 2318 }, { "Coarse Thread", 100, 2320 } } },
    { from = 100, to = 125, qty = 40, recipe = "Fine Leather Belt", item = 4246,
        mats = { { "Light Leather", 240, 2318 }, { "Coarse Thread", 80, 2320 } } },
    { from = 125, to = 137, qty = 15, recipe = "Dark Leather Boots", item = 2315, note = "At skill 125 you must learn Expert Leatherworking (requires character level 20). Trainers: Telonis in Darnassus (Alliance) or Una in Thunder Bluff (Horde).",
        mats = { { "Medium Leather", 60, 2319 }, { "Fine Thread", 30, 2321 }, { "Gray Dye", 15, 2604 } } },
    { from = 137, to = 150, qty = 20, recipe = "Dark Leather Pants", item = 5961,
        mats = { { "Medium Leather", 240, 2319 }, { "Gray Dye", 20, 2604 }, { "Fine Thread", 20, 2321 } } },
    { from = 150, to = 155, qty = 7,  recipe = "Heavy Leather", item = 4234,
        mats = { { "Medium Leather", 35, 2319 } } },
    { from = 155, to = 165, qty = 20, recipe = "Cured Heavy Hide", item = 4236,
        mats = { { "Heavy Hide", 20, 4235 }, { "Salt", 60, 2692 } } },
    { from = 165, to = 180, qty = 15, recipe = "Heavy Armor Kit", item = 4265,
        mats = { { "Heavy Leather", 75, 4234 }, { "Fine Thread", 15, 2321 } } },
    { from = 180, to = 190, qty = 10, recipe = "Barbaric Shoulders", item = 5964,
        mats = { { "Heavy Leather", 80, 4234 }, { "Cured Heavy Hide", 10, 4233 }, { "Fine Thread", 20, 2321 } } },
    { from = 190, to = 200, qty = 10, recipe = "Guardian Gloves", item = 5966,
        mats = { { "Heavy Leather", 40, 4234 }, { "Cured Heavy Hide", 10, 4233 }, { "Silken Thread", 10, 4291 } } },
    { from = 200, to = 205, qty = 5,  recipe = "Thick Armor Kit", item = 8173, note = "At skill 200 you must learn Artisan Leatherworking (requires character level 35). Trainers: Drakk Stonehand in the Hinterlands (Alliance) or Hahrana Ironhide in Feralas (Horde). You can choose a specialization at 225.",
        mats = { { "Thick Leather", 25, 4304 }, { "Silken Thread", 5, 4291 } } },
    { from = 205, to = 235, qty = 40, recipe = "Nightscape Headband", item = 8176,
        mats = { { "Thick Leather", 200, 4304 }, { "Silken Thread", 80, 4291 } } },
    { from = 235, to = 250, qty = 15, recipe = "Nightscape Pants", item = 8193,
        mats = { { "Thick Leather", 210, 4304 }, { "Silken Thread", 60, 4291 } } },
    { from = 250, to = 260, qty = 13, recipe = "Nightscape Boots", item = 8197,
        mats = { { "Thick Leather", 208, 4304 }, { "Heavy Silken Thread", 26, 8343 } } },
    { from = 260, to = 290, qty = 33, recipe = "Wicked Leather Gauntlets", item = 15083, vendorPattern = true,
        note = "You'll need this recipe's pattern first. It is sold (limited supply) by Leonard Porter in Western Plaguelands and Werg Thickblade in Tirisfal Glades, so check the Auction House too. Alternative: Wicked Leather Bracers, whose pattern drops from Legashi Rogue in Azshara.",
        mats = { { "Rugged Leather", 264, 8170 }, { "Black Dye", 33, 2871 }, { "Rune Thread", 33, 14341 } } },
    { from = 290, to = 300, qty = 10, recipe = "Runic Leather Headband", item = 15094, vendorPattern = true,
        note = "You'll need this recipe's pattern first. It is sold (limited supply) by Jase Farlane in Eastern Plaguelands, so check the Auction House too. Alternative: Wicked Leather Headband, whose pattern drops from Jadefire Tricksters in Felwood.",
        mats = { { "Rugged Leather", 140, 8170 }, { "Runecloth", 100, 14047 }, { "Rune Thread", 10, 14341 } } },
})
