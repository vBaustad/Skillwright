-- Skillwright - enchanting: pick the item an enchant goes on, craft onto it, and (optionally) accept the
-- "replace the existing enchant?" popup - but only for enchants Skillwright itself just started, and never
-- on gear you are wearing.
local ADDON, SW = ...
local E = {}
SW.Enchant = E

local ARM_SECONDS = 6          -- how long after our own craft (or its last cast) the popup may be auto-accepted

E.choice = {}                  -- [recipeSpell] = itemGUID picked by the player, or false for "no target"
local armedUntil, armedSpell, armedWorn = 0, nil, false

-- Every item in the bags and equipped, by GUID: { location, id, link, equipped, sell }
local function Inventory()
    local byGuid = {}
    local function add(loc, equipped)
        if not loc or not loc:IsValid() then return end
        local guid = C_Item.GetItemGUID(loc)
        if not guid then return end
        local id = C_Item.GetItemID(loc)
        local link = C_Item.GetItemLink(loc)
        local sell = id and select(11, C_Item.GetItemInfo(id)) or 0
        byGuid[guid] = { guid = guid, location = loc, id = id, link = link, equipped = equipped, sell = sell or 0 }
    end
    for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS or 4 do
        for slot = 1, (C_Container.GetContainerNumSlots(bag) or 0) do
            add(ItemLocation:CreateFromBagAndSlot(bag, slot), false)
        end
    end
    for slot = 1, 19 do add(ItemLocation:CreateFromEquipmentSlot(slot), true) end
    return byGuid
end

-- Items this enchant can go on, bag items first, cheapest first. nil when the client can't tell us.
function E.Targets(spell)
    local ok, list = pcall(C_TradeSkillUI.GetEnchantItems, spell)
    if not ok or type(list) ~= "table" then return nil end
    local inv = Inventory()
    local out = {}
    for _, v in ipairs(list) do
        local e
        if type(v) == "string" then
            e = inv[v]
        elseif type(v) == "table" and v.IsValid and v:IsValid() then
            e = inv[C_Item.GetItemGUID(v)]
        end
        if e then out[#out + 1] = e end
    end
    table.sort(out, function(a, b)
        if a.equipped ~= b.equipped then return not a.equipped end
        return a.sell < b.sell
    end)
    return out
end

-- The target the player picked (the slot starts empty, like the profession window's), plus every option.
function E.Target(spell)
    local targets = E.Targets(spell)
    if not targets then return nil, nil end
    local pick = E.choice[spell]
    if pick then
        for _, t in ipairs(targets) do if t.guid == pick then return t, targets end end
    end
    return nil, targets
end

local function Arm(spell, worn)
    armedSpell, armedWorn = spell, worn and true or false
    armedUntil = GetTime() + ARM_SECONDS
end

-- Craft an enchant. Onto a target the game allows one cast per call, and answering its "replace?" popup is a
-- protected action: it only works inside the player's own click. So each click enchants once, and the popup
-- (raised synchronously while the click is still running) is answered right there.
function E.Craft(spell, n)
    local target = E.Target(spell)
    Arm(spell, target and target.equipped)
    E.inClick = true
    local ok, err = pcall(function()
        if target then
            C_TradeSkillUI.CraftEnchant(spell, 1, nil, target.location)
        else
            C_TradeSkillUI.CraftRecipe(spell, n)
        end
    end)
    E.inClick = false
    if not ok then SW.dbg("craft: %s", tostring(err)) end
    SW.RefreshWindow()
end

-- One click per cast when enchanting onto an item.
function E.OneAtATime(spell)
    return E.Target(spell) ~= nil
end

function E.IsEnchant(step)
    return step and step.item == 0 and step.spell ~= nil
end

-- The Craft button (full and minimal view): enchants go through E.Craft, everything else is a plain craft.
function SW.CraftStep(spell, n, isEnchant)
    if not spell or not n or n <= 0 then return end
    if SW.CombatBlocked("craft") then return end
    if isEnchant then
        E.Craft(spell, n)
    else
        C_TradeSkillUI.CraftRecipe(spell, n)
    end
end

SW.On("UNIT_SPELLCAST_START", function(unit, _, spellID)
    if unit == "player" and armedSpell and spellID == armedSpell and GetTime() < armedUntil then Arm(armedSpell, armedWorn) end
end)

-- "Do you want to replace X with Y?" - accept it for our own enchants when the setting is on.
-- The profession window raises REPLACE_TRADESKILL_ENCHANT (answered by C_Item.ReplaceTradeskillEnchant);
-- REPLACE_ENCHANT is the enchant-from-the-bag path.
local function AutoAccept(popup, accept)
    return function()
        if not SW.Settings().autoReplaceEnchant then return end
        if not armedSpell or GetTime() > armedUntil then return end
        -- gear you are wearing always asks: its enchant is probably one you want to keep
        if armedWorn then return end
        -- only while our Craft click is still running: outside a click the game blocks the answer
        if not E.inClick then return end
        accept()
        C_Timer.After(0, function() StaticPopup_Hide(popup) end)
    end
end
SW.On("REPLACE_TRADESKILL_ENCHANT", AutoAccept("REPLACE_TRADESKILL_ENCHANT", C_Item.ReplaceTradeskillEnchant))
SW.On("REPLACE_ENCHANT", AutoAccept("REPLACE_ENCHANT", C_Item.ReplaceEnchant))
SW.On("TRADE_SKILL_CLOSE", function()
    armedSpell, armedUntil, armedWorn = nil, 0, false
end)
