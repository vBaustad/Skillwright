-- Alchemy 1-300 craft path (WoW Classic Era).
-- Factual craft data from public leveling guides; item IDs best-effort (spot-check in-game).
local ADDON, SW = ...

-- mat entry = { name, totalForStep, itemId }
SW.RegisterPath("Alchemy", {
    { from = 1, to = 60, qty = 65, recipe = "Minor Healing Potion", item = 118, note = "Tip: Alchemy pairs well with Herbalism for a steady herb supply. Buy Empty Vials from a Trade Goods or Alchemy supplier vendor.",
        mats = { { "Peacebloom", 65, 2447 }, { "Silverleaf", 65, 765 }, { "Empty Vial", 65, 3372 } } },
    { from = 60, to = 110, qty = 65, recipe = "Lesser Healing Potion", item = 858, note = "At skill 75 you must learn Journeyman Alchemy (requires character level 10) from an Alchemy trainer before you can keep leveling. This step reuses the Minor Healing Potions you made earlier.",
        mats = { { "Minor Healing Potion", 65, 118 }, { "Briarthorn", 65, 2450 } } },
    { from = 110, to = 140, qty = 35, recipe = "Healing Potion", item = 929,
        mats = { { "Bruiseweed", 35, 2453 }, { "Briarthorn", 35, 2450 }, { "Leaded Vial", 35, 3371 } } },
    { from = 140, to = 155, qty = 20, recipe = "Lesser Mana Potion", item = 3385, note = "At skill 150 you must learn Expert Alchemy (requires character level 20) from an Expert Alchemy trainer. If Stranglekelp is hard to find, Fire Oil is an alternative for this range.",
        mats = { { "Mageroyal", 20, 785 }, { "Stranglekelp", 20, 3820 }, { "Empty Vial", 20, 3372 } } },
    { from = 155, to = 185, qty = 35, recipe = "Greater Healing Potion", item = 1710,
        mats = { { "Liferoot", 35, 3357 }, { "Kingsblood", 35, 3356 }, { "Leaded Vial", 35, 3371 } } },
    { from = 185, to = 210, qty = 30, recipe = "Elixir of Agility", item = 8949, note = "If Goldthorn is scarce, Mana Potion or Nature Protection Potion are alternatives for this range.",
        mats = { { "Stranglekelp", 30, 3820 }, { "Goldthorn", 30, 3821 }, { "Leaded Vial", 30, 3371 } } },
    { from = 210, to = 215, qty = 5, recipe = "Elixir of Greater Defense", item = 8951,
        mats = { { "Wild Steelbloom", 5, 3818 }, { "Goldthorn", 5, 3821 }, { "Leaded Vial", 5, 3371 } } },
    { from = 215, to = 230, qty = 15, recipe = "Superior Healing Potion", item = 3928, note = "At skill 200 you must learn Artisan Alchemy (requires character level 35) from an Artisan Alchemy trainer.",
        mats = { { "Sungrass", 15, 8838 }, { "Khadgar's Whisker", 15, 3358 }, { "Crystal Vial", 15, 8925 } } },
    { from = 230, to = 265, qty = 45, recipe = "Elixir of Detect Undead", item = 9154,
        mats = { { "Arthas' Tears", 45, 8836 }, { "Crystal Vial", 45, 8925 } } },
    { from = 265, to = 285, qty = 30, recipe = "Superior Mana Potion", item = 13443, vendorPattern = true,
        note = "You'll need this recipe first. It is sold by Ulthir in Darnassus (Alliance) or Algernon in the Undercity (Horde).",
        mats = { { "Sungrass", 60, 8838 }, { "Blindweed", 60, 8839 }, { "Crystal Vial", 30, 8925 } } },
    { from = 285, to = 300, qty = 20, recipe = "Major Healing Potion", item = 13446, vendorPattern = true,
        note = "You'll need this recipe first. It is sold by Evie Whirlbrew in Everlook, Winterspring.",
        mats = { { "Golden Sansam", 40, 13464 }, { "Mountain Silversage", 20, 13465 }, { "Crystal Vial", 20, 8925 } } },
})
