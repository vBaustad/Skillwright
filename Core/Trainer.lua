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
    local link = GetTrainerServiceItemLink and GetTrainerServiceItemLink(i)
    return link and tonumber(link:match("item:(%d+)"))
end

-- GetTrainerServiceInfo's returns moved in the current Forever trainer UI.
--   now:    name, serviceType, texture, reqLevel
--   before: name, subText, serviceType, texture, reqLevel
-- serviceType is "available" / "unavailable" / "used" / "header". Reading a fixed
-- slot made every row look like a texture, so nothing counted as trainable.
local KINDS = { available = true, unavailable = true, used = true, header = true }
local function ServiceInfo(i)
    if not GetTrainerServiceInfo then return nil, nil end
    local name, a, b = GetTrainerServiceInfo(i)
    if KINDS[a] then return name, a end
    if KINDS[b] then return name, b end
    return name, nil
end

-- The trainer window hides services by default ("available" only), and the hidden ones are exactly the
-- interesting ones: a recipe the character can't train yet still states the skill it needs. So every
-- filter is turned on for one read and the player's own filters are put back straight after.
--
-- That read used to rescan on the TRAINER_UPDATE it had just caused, which turned the filters on and
-- off again. The current trainer frame rebuilds every row (Hide + Show) on each of those updates, so
-- the whole window strobed for as long as it stayed open. Our own updates are ignored, and the frame
-- redraw is held back until the filters are already back where the player left them.
local FILTERS = { "available", "unavailable", "used" }
local saved, restoring, quiet, suppressVisual
local generation = 0
local fullDone = false
local updateWrappedFor

local function HookTrainerUpdate()
    if type(ClassTrainerFrame_Update) ~= "function" then return end
    if ClassTrainerFrame_Update == updateWrappedFor then return end
    local orig = ClassTrainerFrame_Update
    local function wrapped(...)
        if suppressVisual then return end
        return orig(...)
    end
    updateWrappedFor = wrapped
    ClassTrainerFrame_Update = wrapped
end

local function OpenAllFilters()
    if not (GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter) then return false end
    -- Only the first pass remembers the player's own filters: the read that follows sees them all on.
    local first = saved == nil
    if first then saved = {} end
    local changed = false
    for _, f in ipairs(FILTERS) do
        local on = GetTrainerServiceTypeFilter(f)
        if first then saved[f] = not not on end
        if not on then
            changed = true
            SetTrainerServiceTypeFilter(f, true)
        end
    end
    return changed
end

local function RestoreFilters()
    if not saved then return end
    local mine = saved
    saved = nil
    restoring = true
    for _, f in ipairs(FILTERS) do
        if not mine[f] then SetTrainerServiceTypeFilter(f, false) end
    end
    restoring = false
end

-- Hold the redraw across the filter changes and the update event they post.
local function EndQuiet()
    local gen = generation
    -- Long enough for the filter's TRAINER_UPDATE to be delivered and dropped.
    C_Timer.After(0.15, function()
        if gen ~= generation then return end
        suppressVisual = false
        quiet = false
    end)
end

T.services = {}     -- [spell] = { index, type, spell } for the open trainer
T.prof = nil        -- profession of the open trainer

local function SpellFor(prof, i, name)
    local spell
    local id = LinkItem(i)
    if prof and id and byItem[id] then
        for _, hit in ipairs(byItem[id]) do
            if hit[1] == prof then spell = hit[2] break end
        end
    end
    if not spell and not id and prof and name and byName[prof] then spell = byName[prof][name] end
    return spell
end

-- Match every service to a recipe. Recipe names aren't unique (two "Faction Banner"s, two "Dark Leather
-- Boots"), so the item a service makes decides first - within the trainer's own profession - and the
-- name is only used for services that make no item.
-- recordFacts: write the skill each recipe needs (only useful while hidden rows are visible).
-- recordServices: publish the rows the player can click. Do this on the filtered list, after the
-- player's own filters are back, or the indices point at the wrong service.
local function Ingest(recordFacts, recordServices)
    Index()
    local n = GetNumTrainerServices and GetNumTrainerServices() or 0
    if recordServices then wipe(T.services) end

    local profCount = {}
    for i = 1, n do
        local _, kind = ServiceInfo(i)
        local id = kind ~= "header" and LinkItem(i)
        for _, hit in ipairs(id and byItem[id] or {}) do profCount[hit[1]] = (profCount[hit[1]] or 0) + 1 end
    end
    local prof, bestN = T.prof, 0
    if recordFacts or not prof then
        prof, bestN = nil, 0
        for p, c in pairs(profCount) do if c > bestN then prof, bestN = p, c end end
        if not prof then
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
        if prof then
            if T.prof ~= prof then T.Remember(prof) end
            T.prof = prof
        end
    end

    local learned = 0
    local db = SW.DB()
    for i = 1, (prof and n or 0) do
        local name, kind = ServiceInfo(i)
        if name and kind ~= "header" then
            local spell = SpellFor(prof, i, name)
            if spell then
                if recordServices then
                    T.services[spell] = { index = i, type = kind, prof = prof, spell = spell }
                end
                if recordFacts then
                    db.trainerSeen[spell] = true
                    local _, rank = GetTrainerServiceSkillReq(i)
                    rank = tonumber(rank)
                    local cost = GetTrainerServiceCost and tonumber(GetTrainerServiceCost(i))
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
                    local cp = SW.CharProf(prof)
                    for j = 1, (GetTrainerServiceNumAbilityReq and GetTrainerServiceNumAbilityReq(i) or 0) do
                        local ability, has = GetTrainerServiceAbilityReq(i, j)
                        if ability and ability ~= SW.ProfName(prof) then
                            db.specReq[spell] = ability
                            if has then cp.specName = ability end
                        end
                    end
                end
            end
        end
    end
    return learned, n
end

local function Finish(learned)
    if learned > 0 then
        local d = SW.DB().drift
        SW.dbg("trainer: learned the required skill of %d recipes%s", learned,
            d and d.n > 0 and (" (estimate off by %.1f on average over %d, worst %+d)"):format(d.sum / d.n, d.n, d.worst) or "")
        SW.Fire("TRAINER_FACTS")
    end
    SW.Fire("TRAINER_CHANGED")
end

-- One full read per open window: every filter on, record what the hidden rows need, filters back,
-- then the indices the Train button can actually buy. Retries if the list is still empty.
local function FullRead(attempt)
    local gen = generation
    quiet = true
    suppressVisual = true
    HookTrainerUpdate()
    local learned, n = 0, 0
    local ok, err = pcall(function()
        OpenAllFilters()
        learned, n = Ingest(true, false)
        RestoreFilters()
        if n > 0 then Ingest(false, true) end
    end)
    if not ok then
        pcall(RestoreFilters)
        SW.dbg("trainer: %s", tostring(err))
        EndQuiet()
        return
    end
    if n == 0 and attempt < 4 then
        pcall(RestoreFilters)
        -- Stay quiet until the retry. EndQuiet here would let TRAINER_UPDATE start a second read.
        C_Timer.After(0.25, function()
            if gen ~= generation or fullDone then
                if gen == generation then
                    suppressVisual = false
                    quiet = false
                end
                return
            end
            FullRead(attempt + 1)
        end)
        return
    end
    fullDone = n > 0
    EndQuiet()
    Finish(learned)
end

local function Scan()
    if quiet or restoring then return end
    if not fullDone then
        FullRead(1)
        return
    end
    -- A later update (a recipe just learned, the player changed a filter): refresh the visible rows only.
    local ok, err = pcall(function() Ingest(false, true) end)
    if not ok then SW.dbg("trainer: %s", tostring(err)) return end
    Finish(0)
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
    -- Indices belong to the list on screen right now. Learning a row, or a filter, shifts the rest,
    -- so resolve each recipe again and buy from the bottom.
    Index()
    local want = {}
    for _, svc in ipairs(list or {}) do
        if svc.spell then want[svc.spell] = true end
    end
    local found = {}
    local prof = T.prof
    local n = GetNumTrainerServices and GetNumTrainerServices() or 0
    for i = 1, n do
        local name, kind = ServiceInfo(i)
        local spell = kind ~= "header" and SpellFor(prof, i, name)
        if spell and want[spell] and kind == "available" then found[#found + 1] = i end
    end
    table.sort(found, function(a, b) return a > b end)
    for _, i in ipairs(found) do BuyTrainerService(i) end
end

local function Schedule(delay)
    local gen = generation
    SW.Debounce("trainer", delay, function()
        if gen ~= generation or quiet or restoring then return end
        Scan()
    end)
end

SW.On("TRAINER_SHOW", function()
    generation = generation + 1
    fullDone = false
    quiet = false
    suppressVisual = false
    wipe(T.services)
    T.prof = nil
    HookTrainerUpdate()
    Schedule(0.2)
end)
SW.On("TRAINER_UPDATE", function()
    -- The updates posted by our own filter changes are what made the window strobe.
    if quiet or restoring or suppressVisual then return end
    Schedule(0.35)
end)
SW.On("TRAINER_CLOSED", function()
    generation = generation + 1
    fullDone = false
    quiet = true
    suppressVisual = true
    pcall(RestoreFilters)
    suppressVisual = false
    quiet = false
    wipe(T.services)
    T.prof = nil
    SW.Fire("TRAINER_CHANGED")
end)
