-- First Aid 1-300 craft path (WoW Classic Era).
-- Factual craft data from public leveling guides; item IDs best-effort (spot-check in-game).
local ADDON, SW = ...

-- mat entry = { name, totalForStep, itemId }
SW.RegisterPath("First Aid", {
    { from = 1,   to = 40,  qty = 50, recipe = "Linen Bandage", item = 1251, note = "First Aid is a secondary profession. Learn it from any First Aid trainer, then buy cloth or loot it from humanoids.",
        mats = { { "Linen Cloth", 50, 2589 } } },
    { from = 40,  to = 75,  qty = 45, recipe = "Heavy Linen Bandage", item = 2581, note = "Heavy bandages use 2 cloth each.",
        mats = { { "Linen Cloth", 90, 2589 } } },
    { from = 75,  to = 80,  qty = 15, recipe = "Heavy Linen Bandage", item = 2581,
        mats = { { "Linen Cloth", 30, 2589 } } },
    { from = 80,  to = 115, qty = 60, recipe = "Wool Bandage", item = 3530,
        mats = { { "Wool Cloth", 60, 2592 } } },
    { from = 115, to = 150, qty = 60, recipe = "Heavy Wool Bandage", item = 3531, note = "Heavy bandages use 2 cloth each.",
        mats = { { "Wool Cloth", 120, 2592 } } },
    { from = 150, to = 180, qty = 50, recipe = "Silk Bandage", item = 6450, note = "At skill 125 you must learn Expert First Aid from the book 'Expert First Aid - Under Wraps'. Buy it from Deneb Walker in Stromgarde Keep, Arathi Highlands (Alliance) or Balai Lok'Wein in Theramore, Dustwallow Marsh (Horde).",
        mats = { { "Silk Cloth", 50, 4306 } } },
    { from = 180, to = 210, qty = 50, recipe = "Heavy Silk Bandage", item = 6451, note = "Heavy bandages use 2 cloth each.",
        mats = { { "Silk Cloth", 100, 4306 } } },
    { from = 210, to = 225, qty = 30, recipe = "Mageweave Bandage", item = 8544,
        mats = { { "Mageweave Cloth", 30, 4338 } } },
    { from = 225, to = 240, qty = 30, recipe = "Mageweave Bandage", item = 8544, note = "At skill 225 you must learn Artisan First Aid. Complete the triage quest from Doctor Gustaf VanHowzen in Theramore, Dustwallow Marsh (the book comes from Balai Lok'Wein / Deneb Walker chain). This unlocks Runecloth Bandages.",
        mats = { { "Mageweave Cloth", 30, 4338 } } },
    { from = 240, to = 260, qty = 30, recipe = "Heavy Mageweave Bandage", item = 8545, note = "Heavy bandages use 2 cloth each.",
        mats = { { "Mageweave Cloth", 60, 4338 } } },
    { from = 260, to = 290, qty = 50, recipe = "Runecloth Bandage", item = 14529,
        mats = { { "Runecloth", 50, 14047 } } },
    { from = 290, to = 300, qty = 15, recipe = "Heavy Runecloth Bandage", item = 14530, note = "Heavy bandages use 2 cloth each.",
        mats = { { "Runecloth", 30, 14047 } } },
})
