-- Skillwright - trainers: read what a profession trainer offers and the skill each recipe needs.
-- The client data has no "skill to learn" for trainer recipes; every trainer visit fills that in
-- (account-wide), and the route solver stops estimating for those recipes.
local ADDON, SW = ...
local T = {}
SW.Trainer = T

-- Lookups built lazily from the recipe data:
--   byItem[itemID] = { { prof, spell }, ... }      what a service's item link points at
--   byName[prof][localized recipe name] = spell   for services without an item (enchants)
local byItem, byName, rowOf

local function Index()
    if byItem then return end
    byItem, byName, rowOf = {}, {}, {}
    for prof, data in pairs(SW.Data.professions) do
        byName[prof] = {}
        for _, r in ipairs(data[2]) do
            rowOf[r[1]] = r
            if r[2] > 0 then
                byItem[r[2]] = byItem[r[2]] or {}
                table.insert(byItem[r[2]], { prof, r[1] })
            end
            local name = C_Spell.GetSpellName(r[1])
            if name and not byName[prof][name] then byName[prof][name] = r[1] end
        end
    end
end

-- Where the trainers are: what we see in game, kept account-wide, so every character is told where the
-- last one was found. The client data has no trainer locations at all, hence remembering our own.
function T.Remember(prof)
    if not prof then return end
    local who = UnitName("npc")
    if not who or who == "" then return end
    local db = SW.DB()
    db.trainers = db.trainers or {}
    local zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or nil
    local spot = GetSubZoneText and GetSubZoneText() or nil
    if spot == "" then spot = nil end
    local x, y
    local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if map and C_Map.GetPlayerMapPosition then
        local pos = C_Map.GetPlayerMapPosition(map, "player")
        if pos and pos.GetXY then
            local px, py = pos:GetXY()
            if px and py and px > 0 and py > 0 then x, y = math.floor(px * 1000) / 10, math.floor(py * 1000) / 10 end
        end
    end
    db.trainers[prof] = { who = who, zone = zone, spot = spot, x = x, y = y,
                          char = UnitName("player"), seen = SW.Now() }
    SW.Fire("TRAINER_PLACES")
end

-- One line about where to find a trainer for this profession, and whether it is something we saw
-- ourselves (true) or Classic knowledge that may be wrong in Forever (false).
function T.WhereIs(prof, tier)
    local seen = SW.DB().trainers and SW.DB().trainers[prof]
    if seen and seen.who then
        local place = seen.spot and seen.zone and ("%s, %s"):format(seen.zone, seen.spot) or seen.zone or "somewhere you have been"
        local at = (seen.x and seen.y) and (" (%.0f, %.0f)"):format(seen.x, seen.y) or ""
        local mine = seen.char == UnitName("player")
        return ("%s - %s%s%s"):format(seen.who, place, at,
            mine and "" or ("  |cff8a8a8a(found by %s)|r"):format(seen.char or "?")), true
    end
    return tier and SW.TrainerHint and SW.TrainerHint(prof, tier) or nil, false
end

local function LinkItem(i)
    if not GetTrainerServiceItemLink then return nil end
    local link = GetTrainerServiceItemLink(i)
    return link and tonumber(link:match("item:(%d+)"))
end

-- Name and kind of a trainer service. The kind is found by VALUE, not by position: we read the third slot
-- for two releases, which in this client is the texture, so "header" never matched and nothing was ever
-- "available" - the Train button simply never appeared, and nothing failed loudly enough to notice.
-- Taking whichever field actually says one of the four kinds cannot make that mistake, and if Blizzard
-- moves the fields again it comes back nil (visible) instead of a texture (silently wrong).
-- Forever returns (name, type, texture, reqLevel, subText). Found by ballzac81.
local KINDS = { available = true, unavailable = true, used = true, header = true }
local function ServiceInfo(i)
    if not GetTrainerServiceInfo then return nil, nil end
    local a, b, c = GetTrainerServiceInfo(i)
    local kind = (type(b) == "string" and KINDS[b] and b)
        or (type(c) == "string" and KINDS[c] and c)
        or nil
    return a, kind
end

-- The trainer window hides services by default ("available" only), and the hidden ones are exactly the
-- interesting ones: a recipe the character can't train yet still states the skill it needs. So every
-- filter is turned on for the read and the player's own filters are put back straight after.
local FILTERS = { "available", "unavailable", "used" }
local saved       -- the player's own filters while we have ours on
local busy        -- true while WE are changing filters: every event in that window is ours, so ignore it
local deepDone    -- the one deep read of this trainer window has been done

-- Blizzard's trainer frame redraws its rows on TRAINER_UPDATE, so our own filter change makes the list
-- visibly rebuild twice, whatever we do about our own scanning. While our filters are moving we hold that
-- redraw, then put the frame's own function back and let it draw once with the player's filters.
-- Held for two frames at most, and only when the window is open; if anything else has replaced the
-- function in the meantime we leave it alone rather than clobber it.
local heldUpdate
local function HoldRedraw()
    if heldUpdate or type(_G.ClassTrainerFrame_Update) ~= "function" then return end
    heldUpdate = _G.ClassTrainerFrame_Update
    _G.ClassTrainerFrame_Update = function(...)
        if busy then return end
        return heldUpdate(...)
    end
end

local function ReleaseRedraw()
    if not heldUpdate then return end
    local mine = _G.ClassTrainerFrame_Update
    local original = heldUpdate
    heldUpdate = nil
    if type(mine) == "function" then _G.ClassTrainerFrame_Update = original end
    -- one honest redraw, with the player's own filters back in place
    if ClassTrainerFrame and ClassTrainerFrame:IsShown() then pcall(original, true) end
end

-- Turning a filter on rebuilds the list and fires TRAINER_UPDATE. Reacting to that event would set the
-- filters again, and the list would flicker for as long as the window is open (seen in beta4). So the
-- deep read happens once per trainer window and every event it causes is ignored.
local function OpenAllFilters()
    if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return false end
    local mine, changed = {}, false
    for _, f in ipairs(FILTERS) do
        local on = not not GetTrainerServiceTypeFilter(f)
        mine[f] = on
        if not on then changed = true end
    end
    if not changed then return false end       -- everything is already visible: nothing to do, no blink
    saved = mine
    busy = true
    HoldRedraw()
    for _, f in ipairs(FILTERS) do
        if not mine[f] then SetTrainerServiceTypeFilter(f, true) end
    end
    return true
end

local function RestoreFilters()
    if not saved then
        busy = false
        ReleaseRedraw()
        return
    end
    local mine = saved
    saved = nil
    for _, f in ipairs(FILTERS) do
        if not mine[f] then SetTrainerServiceTypeFilter(f, false) end
    end
    -- the events from putting them back arrive next frame: stay deaf until they have passed
    C_Timer.After(0, function()
        busy = false
        ReleaseRedraw()
    end)
end


T.services = {}     -- [spell] = { index, type } for the open trainer
T.prof = nil        -- profession of the open trainer

-- Match every service to a recipe. Recipe names aren't unique (two "Faction Banner"s, two "Dark Leather
-- Boots"), so the item a service makes decides first - within the trainer's own profession - and the
-- name is only used for services that make no item.
local function Read()
    wipe(T.services)
    T.prof = nil
    Index()
    local db = SW.DB()
    local n = GetNumTrainerServices() or 0

    -- 1. which profession is this trainer for? The one most of its item links belong to.
    local profCount = {}
    for i = 1, n do
        local _, kind = ServiceInfo(i)
        local id = kind ~= "header" and LinkItem(i)
        for _, hit in ipairs(id and byItem[id] or {}) do profCount[hit[1]] = (profCount[hit[1]] or 0) + 1 end
    end
    local prof, bestN = nil, 0
    for p, c in pairs(profCount) do if c > bestN then prof, bestN = p, c end end
    if not prof then
        -- an enchanting trainer's services make no items: fall back to names
        local nameCount = {}
        for i = 1, n do
            local name, kind = ServiceInfo(i)
            if name and kind ~= "header" then
                for p, names in pairs(byName) do
                    if names[name] then nameCount[p] = (nameCount[p] or 0) + 1 end
                end
            end
        end
        for p, c in pairs(nameCount) do if c > bestN then prof, bestN = p, c end end
    end
    T.prof = prof
    T.Remember(prof)

    -- 2. each service -> its recipe in that profession
    local learned = 0
    for i = 1, (prof and n or 0) do
        local name, kind = ServiceInfo(i)
        if name and kind ~= "header" then
            local spell
            local id = LinkItem(i)
            for _, hit in ipairs(id and byItem[id] or {}) do
                if hit[1] == prof then spell = hit[2] break end
            end
            if not spell and not id then spell = byName[prof][name] end
            if spell then
                T.services[spell] = { index = i, type = kind, prof = prof }
                db.trainerSeen[spell] = true
                local _, rank = GetTrainerServiceSkillReq(i)
                local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
                if rank and rank > 0 and db.learnRanks[spell] ~= rank then
                    -- How far our estimate was from the game's own number: a measure of how much Forever
                    -- moved away from what the recipe data implies.
                    local row = rowOf[spell]
                    if row and (row[4] or 0) == 0 then
                        local guess = math.max(1, (row[5] or 1) - 10)
                        local d = db.drift or { n = 0, sum = 0, worst = 0 }
                        d.n, d.sum = d.n + 1, d.sum + math.abs(rank - guess)
                        if math.abs(rank - guess) > math.abs(d.worst) then
                            d.worst, d.worstSpell = rank - guess, spell
                        end
                        db.drift = d
                    end
                    db.learnRanks[spell] = rank
                    learned = learned + 1
                end
                if cost and cost > 0 then
                    db.trainerCost = db.trainerCost or {}
                    db.trainerCost[spell] = cost
                end
                -- Abilities it asks for beyond the profession itself = a specialization.
                local cp = SW.CharProf(prof)
                for j = 1, GetTrainerServiceNumAbilityReq(i) or 0 do
                    local ability, has = GetTrainerServiceAbilityReq(i, j)
                    if ability and ability ~= SW.ProfName(prof) then
                        db.specReq[spell] = ability
                        if has then cp.specName = ability end
                    end
                end
            end
        end
    end
    if learned > 0 then
        local d = db.drift
        SW.dbg("trainer: learned the required skill of %d recipes%s", learned,
            d and d.n > 0 and (" (estimate off by %.1f on average over %d, worst %+d)"):format(d.sum / d.n, d.n, d.worst) or "")
        SW.Fire("TRAINER_FACTS")
    end
    SW.Fire("TRAINER_CHANGED")
end

-- Services at the open trainer that the current route uses and can be learned now.
function T.RouteServices(prof, route)
    local list = {}
    if not route or T.prof ~= prof then return list end
    local seen = {}
    for _, s in ipairs(route.steps) do
        local svc = T.services[s.spell]
        if svc and svc.type == "available" and not seen[s.spell] then
            seen[s.spell] = true
            list[#list + 1] = svc
        end
    end
    return list
end

function T.Train(list)
    if SW.CombatBlocked("train") then return end
    -- Highest index first: learning a service can shift the ones after it.
    table.sort(list, function(a, b) return a.index > b.index end)
    for _, svc in ipairs(list) do BuyTrainerService(svc.index) end
end

-- Read what the player's own filters show. Once per trainer window, and only if they asked for it,
-- also read the hidden services: filters on, read, filters back, done - one blink, never a loop.
local function Scan()
    if busy then return end
    Read()
    if deepDone or SW.Settings().deepTrainerScan == false then return end
    deepDone = true
    if not OpenAllFilters() then return end       -- already all visible: the read above was the deep one
    C_Timer.After(0.05, function()
        Read()
        RestoreFilters()
        SW.Fire("TRAINER_CHANGED")
    end)
end

SW.On("TRAINER_SHOW", function()
    deepDone = false
    SW.Debounce("trainer", 0.2, Scan)
end)
SW.On("TRAINER_UPDATE", function()
    if busy then return end                        -- our own filter change: not a reason to scan again
    SW.Debounce("trainer", 0.3, Scan)
end)
SW.On("TRAINER_CLOSED", function()
    RestoreFilters()
    deepDone = false
    wipe(T.services)
    T.prof = nil
    SW.Fire("TRAINER_CHANGED")
end)
