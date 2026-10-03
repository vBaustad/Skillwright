-- Skillwright - disenchanting: which group an item falls in, and what players actually get out of it.
--
-- The client knows the GROUPS exactly (Data/Disenchant.lua, straight from itemdisenchantloot): an item's
-- class, quality and level band decide the group, with no subclass or skill floor splitting them in any
-- build we have. What falls OUT of a group is server-side and is in none of them, so there is nothing to
-- ship and nothing worth guessing: a hand-made Classic table would be a guess at which materials, a guess
-- at how often, and then multiplied by a price we often do not have.
--
-- So we count. Every disenchant the player does is one observation of its group, and because the group is
-- exact, observations of different items add up correctly - twenty greens in the 16-20 band tell you what
-- the 16-20 band gives. Until there are any, the line says exactly that.
--
-- The records live in SkillwrightDB.de, keyed by group, and nothing outside this file reads their shape:
-- moving the whole thing to another addon later means moving this file and the two lines that call it.
local ADDON, SW = ...
local DE = {}
SW.Disenchant = DE

local ENCHANTING = 333
local DISENCHANT_SPELL = 13262
local LOOT_WINDOW = 4          -- seconds after the cast that loot still counts as coming from it
local TRADE_GOODS, ENCHANTING_REAGENT = 7, 12   -- item class and subclass of dust, essences and shards

local isSecret = issecretvalue or function() return false end

--- Does this character have Enchanting at all? Without it the whole subject is someone else's business.
function DE.Have()
    return SW.Prof.Rank(ENCHANTING) > 0 or (SW.CharDB().profs[ENCHANTING] or {}).has == true
end

--- The disenchant group an item falls in, or nil when it does not disenchant (grey, white, quest items,
--- anything that is not a weapon or a piece of armour, and anything below the lowest band).
--- Needs the item's own facts, which the client hands us: quality, class, subclass and item level.
function DE.Group(id)
    if not id or isSecret(id) or not SW.Data.disenchant then return nil end
    local _, _, quality, ilvl, _, _, _, _, _, _, _, classID, subclassID = C_Item.GetItemInfo(id)
    if not quality or not classID then return nil end          -- still loading: ask again later
    for _, g in ipairs(SW.Data.disenchant) do
        local gid, cls, sub, q, lo, hi = g[1], g[2], g[3], g[4], g[5], g[6]
        if cls == classID and q == quality and (sub == -1 or sub == subclassID)
           and (ilvl or 0) >= lo and (ilvl or 0) <= hi then
            return gid, lo, hi
        end
    end
end

-- ---------------------------------------------------------------------------
-- What we have seen
-- ---------------------------------------------------------------------------
local function Store()
    local db = SW.DB()
    db.de = db.de or {}
    return db.de
end

--- One finished disenchant: `mats` is { [itemID] = count } from that single cast.
function DE.Record(group, mats)
    if not group or not mats or not next(mats) then return end
    local store = Store()
    local g = store[group]
    if not g then
        g = { n = 0, mats = {} }
        store[group] = g
    end
    g.n = g.n + 1
    for id, count in pairs(mats) do
        local m = g.mats[id]
        if not m then
            m = { seen = 0, total = 0, min = count, max = count }
            g.mats[id] = m
        end
        m.seen, m.total = m.seen + 1, m.total + count
        m.min, m.max = math.min(m.min, count), math.max(m.max, count)
    end
    SW.Fire("DISENCHANT_RECORDED")
end

--- How often a material turned up, in words rather than a decimal that pretends to be precise.
local function HowOften(seen, n)
    if seen >= n then return "always" end
    if seen * 2 >= n then return "usually" end
    if seen * 5 >= n then return "often" end
    return "sometimes"
end

local function Amount(m)
    if m.min == m.max then return tostring(m.min) end
    return ("%d-%d"):format(m.min, m.max)
end

--- What this group has given this character so far: a sentence, or nil when nothing has been recorded.
--- Never an average dressed up as a promise - the counts are what they are, and the number of
--- disenchants behind them is part of the sentence.
function DE.Summary(group)
    local g = Store()[group]
    if not g or g.n == 0 then return nil end
    local order = {}
    for id, m in pairs(g.mats) do order[#order + 1] = { id = id, m = m } end
    table.sort(order, function(a, b) return a.m.seen > b.m.seen end)
    local parts = {}
    for _, e in ipairs(order) do
        parts[#parts + 1] = ("%s %s %s"):format(HowOften(e.m.seen, g.n), Amount(e.m), SW.ItemName(e.id)
            or ("item " .. e.id))
    end
    return table.concat(parts, ", "), g.n
end

--- The tooltip line for an item, or nil when there should be no line at all.
--- No Enchanting, no line: the subject does not exist for that character. Enchanting but nothing seen
--- yet is a different thing, and says so - an empty answer to a real question.
function DE.Line(id)
    if not SW.Settings().tooltipDisenchant then return nil end
    if not DE.Have() then return nil end
    local group = DE.Group(id)
    if not group then return nil end
    local text, n = DE.Summary(group)
    -- "Nothing yet" stays. UI/Tooltip.lua's rule - an empty unknown is worse than silence - is why
    -- this line is now opt-in; once you HAVE asked for it, silence would read as a broken counter.
    if not text then
        return "|cff8a8a8aDisenchant: nothing recorded yet for items like this|r"
    end
    return ("|cffffd100Disenchant|r |cff8a8a8a(from %d like this):|r %s"):format(n, text)
end

--- /skw de - what has been recorded so far. The first thing to look at after disenchanting a few
--- items: if the counting never sees anything, this is where that shows.
function DE.Print()
    if not DE.Have() then
        SW.msg("this character is not an enchanter, so nothing is recorded.")
        return
    end
    local store, groups = Store(), 0
    for group, g in pairs(store) do
        groups = groups + 1
        local text = DE.Summary(group)
        SW.msg("group %d, %d disenchant%s: %s", group, g.n, g.n == 1 and "" or "s", text or "nothing")
    end
    if groups == 0 then
        SW.msg("nothing recorded yet. Disenchant something and look again.")
    end
end

-- ---------------------------------------------------------------------------
-- Watching a disenchant happen
-- ---------------------------------------------------------------------------
-- The cast names the item it is aimed at, the loot arrives a moment later in chat. Both halves have to
-- be sure of themselves: an item we cannot identify records nothing, and loot that is not an enchanting
-- reagent is somebody else's - a corpse looted in the same second must not become a disenchant.
local pending      -- { group = id, expires = time, mats = { [itemID] = count } }

--- The item a cast is aimed at is given by name. Find it in the bags, and only accept an answer when
--- every match agrees on the group: two different items with the same name would otherwise be a coin toss.
local function GroupOfCarriedItem(name)
    if not name or name == "" then return nil end
    local found
    for bag = 0, 4 do
        for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            local id = info and info.itemID
            if id and not isSecret(id) and SW.ItemName(id) == name then
                local group = DE.Group(id)
                if not group then return nil end
                if found and found ~= group then return nil end
                found = found or group
            end
        end
    end
    return found
end

local function Commit()
    if not pending then return end
    local p = pending
    pending = nil
    DE.Record(p.group, p.mats)
end

SW.On("UNIT_SPELLCAST_SENT", function(unit, target, _, spellID)
    if unit ~= "player" or spellID ~= DISENCHANT_SPELL then return end
    local group = GroupOfCarriedItem(target)
    pending = group and { group = group, expires = GetTime() + LOOT_WINDOW, mats = {} } or nil
end)

SW.On("UNIT_SPELLCAST_SUCCEEDED", function(unit, _, spellID)
    if unit ~= "player" or spellID ~= DISENCHANT_SPELL or not pending then return end
    pending.expires = GetTime() + LOOT_WINDOW
    -- Loot arrives in a burst; write the observation once the burst is over.
    SW.Debounce("disenchantLoot", 2, Commit)
end)

SW.On("CHAT_MSG_LOOT", function(msg)
    if not pending or GetTime() > pending.expires then return end
    local link, count = msg:match("(|c.-|Hitem:.-|h.-|h|r)%s*x?(%d*)")
    if not link then return end
    local id, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(link)
    if not id or isSecret(id) then return end
    if classID ~= TRADE_GOODS or subclassID ~= ENCHANTING_REAGENT then return end
    pending.mats[id] = (pending.mats[id] or 0) + math.max(1, tonumber(count) or 1)
    SW.Debounce("disenchantLoot", 2, Commit)
end)
