-- Skillwright - trainers: read what a profession trainer offers and the skill each recipe needs.
-- The client data has no "skill to learn" for trainer recipes; every trainer visit fills that in
-- (account-wide), and the route solver stops estimating for those recipes.
local ADDON, SW = ...
local T = {}
SW.Trainer = T

-- [localized recipe name] = { prof, spell }, built lazily from the recipe data.
local byName

local function NameIndex()
    if byName then return byName end
    byName = {}
    local getName = C_Spell and C_Spell.GetSpellName or GetSpellInfo
    for prof, data in pairs(SW.Data.professions) do
        for _, r in ipairs(data[2]) do
            local name = getName(r[1])
            if name and not byName[name] then byName[name] = { prof, r[1] } end
        end
    end
    return byName
end

local function ByItemLink(link, prof)
    local id = link and tonumber(link:match("item:(%d+)"))
    if not id then return nil end
    for p, data in pairs(SW.Data.professions) do
        if not prof or p == prof then
            for _, r in ipairs(data[2]) do
                if r[2] == id then return p, r[1] end
            end
        end
    end
end

T.services = {}     -- [spell] = { index, type } for the open trainer
T.prof = nil        -- profession of the open trainer

local function Scan()
    if not GetNumTrainerServices then return end
    wipe(T.services)
    T.prof = nil
    local db = SW.DB()
    local names = NameIndex()
    local profCount = {}
    local n = GetNumTrainerServices() or 0
    local learned = 0
    for i = 1, n do
        local name, _, kind = GetTrainerServiceInfo(i)
        if name and kind ~= "header" then
            local hit = names[name]
            local prof, spell
            if hit then
                prof, spell = hit[1], hit[2]
            else
                prof, spell = ByItemLink(GetTrainerServiceItemLink and GetTrainerServiceItemLink(i))
            end
            if spell then
                profCount[prof] = (profCount[prof] or 0) + 1
                T.services[spell] = { index = i, type = kind, prof = prof }
                db.trainerSeen[spell] = true
                local _, rank = GetTrainerServiceSkillReq(i)
                if rank and rank > 0 and db.learnRanks[spell] ~= rank then
                    db.learnRanks[spell] = rank
                    learned = learned + 1
                end
                -- Abilities it asks for beyond the profession itself = a specialization.
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
    local best, bestN = nil, 0
    for p, c in pairs(profCount) do if c > bestN then best, bestN = p, c end end
    T.prof = best
    if learned > 0 then
        SW.dbg("trainer: learned the required skill of %d recipes", learned)
        SW.Fire("TRAINER_FACTS")
    end
    SW.Fire("TRAINER_CHANGED")
end

function T.IsOpen()
    return T.prof ~= nil and ((ClassTrainerFrame and ClassTrainerFrame:IsShown()) or next(T.services) ~= nil)
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
