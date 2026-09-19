-- Skillwright - trainers: read what a profession trainer offers and the skill each recipe needs.
-- The client data has no "skill to learn" for trainer recipes; every trainer visit fills that in
-- (account-wide), and the route solver stops estimating for those recipes.
local ADDON, SW = ...
local T = {}
SW.Trainer = T

-- Lookups built lazily from the recipe data:
--   byItem[itemID] = { { prof, spell }, ... }      what a service's item link points at
--   byName[prof][localized recipe name] = spell   for services without an item (enchants)
local byItem, byName

local function Index()
    if byItem then return end
    byItem, byName = {}, {}
    for prof, data in pairs(SW.Data.professions) do
        byName[prof] = {}
        for _, r in ipairs(data[2]) do
            if r[2] > 0 then
                byItem[r[2]] = byItem[r[2]] or {}
                table.insert(byItem[r[2]], { prof, r[1] })
            end
            local name = C_Spell.GetSpellName(r[1])
            if name and not byName[prof][name] then byName[prof][name] = r[1] end
        end
    end
end

local function LinkItem(i)
    local link = GetTrainerServiceItemLink(i)
    return link and tonumber(link:match("item:(%d+)"))
end

T.services = {}     -- [spell] = { index, type } for the open trainer
T.prof = nil        -- profession of the open trainer

-- Match every service to a recipe. Recipe names aren't unique (two "Faction Banner"s, two "Dark Leather
-- Boots"), so the item a service makes decides first - within the trainer's own profession - and the
-- name is only used for services that make no item.
local function Scan()
    wipe(T.services)
    T.prof = nil
    Index()
    local db = SW.DB()
    local n = GetNumTrainerServices() or 0

    -- 1. which profession is this trainer for? The one most of its item links belong to.
    local profCount = {}
    for i = 1, n do
        local _, _, kind = GetTrainerServiceInfo(i)
        local id = kind ~= "header" and LinkItem(i)
        for _, hit in ipairs(id and byItem[id] or {}) do profCount[hit[1]] = (profCount[hit[1]] or 0) + 1 end
    end
    local prof, bestN = nil, 0
    for p, c in pairs(profCount) do if c > bestN then prof, bestN = p, c end end
    if not prof then
        -- an enchanting trainer's services make no items: fall back to names
        local nameCount = {}
        for i = 1, n do
            local name, _, kind = GetTrainerServiceInfo(i)
            if name and kind ~= "header" then
                for p, names in pairs(byName) do
                    if names[name] then nameCount[p] = (nameCount[p] or 0) + 1 end
                end
            end
        end
        for p, c in pairs(nameCount) do if c > bestN then prof, bestN = p, c end end
    end
    T.prof = prof

    -- 2. each service -> its recipe in that profession
    local learned = 0
    for i = 1, (prof and n or 0) do
        local name, _, kind = GetTrainerServiceInfo(i)
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
                if rank and rank > 0 and db.learnRanks[spell] ~= rank then
                    db.learnRanks[spell] = rank
                    learned = learned + 1
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
        SW.dbg("trainer: learned the required skill of %d recipes", learned)
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

SW.On("TRAINER_SHOW", function() SW.Debounce("trainer", 0.2, Scan) end)
SW.On("TRAINER_UPDATE", function() SW.Debounce("trainer", 0.3, Scan) end)
SW.On("TRAINER_CLOSED", function()
    wipe(T.services)
    T.prof = nil
    SW.Fire("TRAINER_CHANGED")
end)
