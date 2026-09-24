-- Skillwright - plan: runs the route solver for a character's profession and keeps the result
-- until something that changes the answer happens (mode, learned recipes, prices, trainer facts).
local ADDON, SW = ...
local Plan = {}
SW.Plan = Plan

local cache = {}    -- [prof][mode] = route: both modes are kept, so the guide can say what the choice costs
local jobs = {}     -- ["prof:mode"] = { prof, mode, co = coroutine, rank = the rank it was started from }

local function Cached(prof, mode)
    local byMode = cache[prof]
    return byMode and byMode[mode or SW.Settings().mode]
end

local function Keep(prof, mode, route)
    cache[prof] = cache[prof] or {}
    cache[prof][mode] = route
end
local runner        -- the frame that drives the background solving
local Stop          -- takes that frame's OnUpdate away again (defined below)
local SLICE_MS = 6  -- time per frame given to solving: enough to be quick, small enough not to be seen
local SYNC_SPAN = 20 -- ranks still to go that are quick enough (about 8 ms) to work out on the spot

function Plan.Count(id, withBank)
    return C_Item.GetItemCount(id, withBank) or 0
end

function Plan.Invalidate(prof)
    Plan.ForgetShopping(prof)
    Plan.ForgetOrange(prof)
    if prof then
        cache[prof] = nil
        for key, job in pairs(jobs) do
            if job.prof == prof then jobs[key] = nil end
        end
    else
        wipe(cache)
        wipe(jobs)
    end
    if not next(jobs) then Stop() end
    SW.Fire("PLAN_CHANGED", prof)
end

-- True while a route is still being worked out (the guide says so instead of showing nothing).
function Plan.Solving(prof, mode)
    if prof then return jobs[("%d:%s"):format(prof, mode or SW.Settings().mode)] ~= nil end
    return next(jobs) ~= nil
end

-- Runs the solving coroutines a few milliseconds per frame. Nothing to solve: the handler goes away again.
function Stop()
    if runner then
        runner:SetScript("OnUpdate", nil)
        runner:Hide()
    end
end

local function Drive()
    if not next(jobs) then return Stop() end
    local started = debugprofilestop and debugprofilestop()
    for key, job in pairs(jobs) do
        local prof, mode = job.prof, job.mode
        while true do
            local ok, res = coroutine.resume(job.co)
            if not ok then
                SW.dbg("route for %s failed: %s", SW.ProfName(prof), tostring(res))
                jobs[key] = nil
                break
            end
            if coroutine.status(job.co) == "dead" then
                jobs[key] = nil
                if res then
                    Keep(prof, mode, res)
                    if job.t then SW.dbg("solved %s (%s) from %d in %.0f ms", SW.ProfName(prof), mode, job.rank,
                        debugprofilestop() - job.t) end
                end
                SW.Fire("PLAN_CHANGED", prof)
                break
            end
            if not started or debugprofilestop() - started >= SLICE_MS then return end
        end
        if not started or debugprofilestop() - started >= SLICE_MS then return end
    end
    if not next(jobs) then Stop() end
end

local function StartJob(prof, rank, mode)
    mode = mode or SW.Settings().mode
    local key = ("%d:%s"):format(prof, mode)
    if jobs[key] then return end
    local opts = Plan.Options(prof, rank)
    opts.mode = mode
    opts.yield = coroutine.yield
    jobs[key] = {
        prof = prof, mode = mode, rank = rank,
        t = debugprofilestop and debugprofilestop(),
        co = coroutine.create(function() return SW.Solver.Solve(prof, opts) end),
    }
    if not runner then runner = CreateFrame("Frame") end
    runner:SetScript("OnUpdate", Drive)
    runner:Show()
end

function SW.SetMode(mode)
    if mode ~= "cheap" and mode ~= "fast" then return end
    if SW.Settings().mode == mode then return end
    SW.Settings().mode = mode
    -- both routes stay cached, so switching back and forth is instant and nothing is re-solved
    Plan.ForgetShopping()
    SW.Fire("PLAN_CHANGED")
    SW.msg("route mode: %s", mode == "cheap" and "|cffffd100cheapest|r" or "|cffffd100fastest|r")
end

-- The specialization key the data uses ("Dragonscale", "Goblin" ...) for a character's profession.
function Plan.Spec(prof)
    local cp = SW.CharProf(prof)
    if cp.spec then return cp.spec end
    local specs = SW.PROFESSIONS[prof] and SW.PROFESSIONS[prof].specs
    if specs and cp.specName then
        for _, key in ipairs(specs) do
            if cp.specName:find(key, 1, true) then return key end
        end
    end
end

function Plan.Options(prof, from)
    local db, cp = SW.DB(), SW.CharProf(prof)
    local s = SW.Settings()
    -- Never plan past the rank cap: at 37/75 the route ends at 75 and the guide says to train the next
    -- rank first. Planning to 300 there put steps like "skill 37 to 78" in front of the player.
    local cap = SW.MAX_RANK
    if cp.has and (cp.max or 0) > 0 then cap = math.min(cap, cp.max) end
    return {
        from = math.max(1, from or cp.rank or 1),
        to = cap,
        colors = db.colors,
        mode = s.mode,
        known = cp.known,
        learnRanks = db.learnRanks,
        vendorPrices = db.vendor,
        market = SW.Prices.Market,
        allowCamp = false,       -- recipes that need a camp station (Tanning Rack, Master Forge ...) stay out
        preferVendor = s.preferVendor,
        owned = Plan.OwnedTools(),
        haveMats = s.useOwned ~= false and Plan.HaveMats(prof) or nil,
        spec = Plan.Spec(prof),
        prefer = SW.CharProf(prof).prefer,
        faction = UnitFactionGroup and UnitFactionGroup("player") or nil,
    }
end

-- Materials this profession's recipes use, worked out once per profession.
local matsOf = {}
local function ProfessionMats(prof)
    local set = matsOf[prof]
    if set then return set end
    set = {}
    for _, r in ipairs(SW.Data.professions[prof][2]) do
        local mats = r[10]
        for i = 1, #mats, 2 do set[mats[i]] = true end
    end
    matsOf[prof] = set
    return set
end

-- Materials you already have enough of to be worth using: at least MIN_HAVE in the bags or bank, and not
-- something you'd regret burning - nothing worth more than HAVE_MAX_VALUE each, nothing rare or better.
local MIN_HAVE = 10
local HAVE_MAX_VALUE = 10000     -- 1g per unit
local haveSig = {}

local haveCache = {}
function Plan.HaveMats(prof)
    -- One client call per material of the whole profession: far too heavy to repeat per redraw, and the
    -- answer only changes when the bags do.
    local c = haveCache[prof]
    if c and c.bags == (Plan.bagSig or 0) then
        haveSig[prof] = c.sig
        return c.have
    end
    local have, sig = {}, {}
    for id in pairs(ProfessionMats(prof)) do
        local count = Plan.Count(id, true)
        if count >= MIN_HAVE then
            local quality = C_Item.GetItemQualityByID(id)
            local facts = SW.Data.items[id]
            local unit = SW.Prices.Market(id)
                or (facts and facts[1] > 0 and facts[1])
                or (facts and facts[2] * 4)
                or 0
            if (not quality or quality < 3) and unit <= HAVE_MAX_VALUE then
                have[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    haveSig[prof] = table.concat(sig, ",")
    haveCache[prof] = { bags = Plan.bagSig or 0, have = have, sig = haveSig[prof] }
    return have
end

-- Tools the character has (bags or bank): rods, hammers, spanners ...
local ownedSig
local ownedCache
function Plan.OwnedTools()
    -- Counting every tool in the bags is a client call per item, and this runs several times per redraw:
    -- the answer only changes when the bags do.
    if ownedCache and ownedCache.bags == (Plan.bagSig or 0) then return ownedCache.owned, ownedCache.sig end
    local owned, sig = {}, {}
    for _, t in pairs(SW.Data.tools or {}) do
        for _, id in ipairs(t[3]) do
            if Plan.Count(id, true) > 0 then
                owned[id] = true
                sig[#sig + 1] = id
            end
        end
    end
    table.sort(sig)
    local text = table.concat(sig, ",")
    ownedCache = { bags = Plan.bagSig or 0, owned = owned, sig = text }
    return owned, text
end

-- The first tool a step still needs, live (it disappears the moment the tool is in your bags).
function Plan.PendingTool(step, owned)
    owned = owned or Plan.OwnedTools()
    for _, t in ipairs(step.prereqs or {}) do
        if not SW.Solver.HasTool(t.category, owned) then return t end
    end
end

-- The route for a profession from the character's current rank. Solved from rank 1 for professions
-- the character doesn't have (preview). Re-solved when the rank leaves the cached route.
function Plan.Route(prof, mode)
    mode = mode or SW.Settings().mode
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then
        Plan.WantOther(prof, rank, mode)
        return r
    end
    if r and rank >= r.to and not r.gapAt and r.to >= SW.MAX_RANK then return r end
    -- The last stretch is short enough to work out on the spot, so the guide stays instant where it is
    -- used most. A longer route takes tens of milliseconds - a visible stutter - so that one is solved in
    -- the background, a few milliseconds per frame, while the guide says it is working.
    if SW.MAX_RANK - rank <= SYNC_SPAN then return Plan.RouteNow(prof, mode) end
    StartJob(prof, rank, mode)
    return nil
end

-- With the shown route ready, the other mode is worked out in the background too, so the guide can say
-- what the choice costs instead of asking the player to guess.
function Plan.WantOther(prof, rank, mode)
    local other = mode == "fast" and "cheap" or "fast"
    local r = Cached(prof, other)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return end
    -- Not while the player is crafting: the profession window is the one place where a spare solve is
    -- felt. It is only needed for the "what would the other mode cost" line.
    if SW.Prof.IsOpen(prof) or (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
    if next(jobs) then return end                     -- one route at a time
    SW.Debounce("wantOther", 2, function()
        if SW.Prof.IsOpen(prof) or (ProfessionsFrame and ProfessionsFrame:IsShown()) then return end
        StartJob(prof, rank, other)
    end)
end

-- What switching would cost, in one line: nil while the other route is still being worked out.
-- "cheap" is the route with the lower gold cost, "fast" the one with fewer crafts - which is not always
-- how they come out, so the wording follows the numbers rather than the names.
function Plan.TradeOff(prof)
    local cheap, fast = Plan.Compare(prof)
    if not (cheap and fast) then return nil end
    local mode = SW.Settings().mode
    local here, there = (mode == "fast") and fast or cheap, (mode == "fast") and cheap or fast
    local crafts, cost = here.crafts - there.crafts, there.cost - here.cost
    if crafts == 0 and math.abs(cost) < 100 then
        return "Both routes come out the same from here."
    end
    local other = (mode == "fast") and "Cheapest" or "Fastest"
    local parts = {}
    if crafts > 0 then
        parts[#parts + 1] = ("%d fewer crafts"):format(crafts)
    elseif crafts < 0 then
        parts[#parts + 1] = ("%d more crafts"):format(-crafts)
    end
    if cost > 0 then
        parts[#parts + 1] = ("%s more"):format(SW.MoneyShort(cost))
    elseif cost < 0 then
        parts[#parts + 1] = ("%s less"):format(SW.MoneyShort(-cost))
    end
    return ("%s: %s"):format(other, table.concat(parts, ", "))
end

-- Crafts and cost still to go in each mode, once they are known. Returns cheap, fast (either may be nil).
function Plan.Compare(prof)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local function totals(mode)
        local r = Cached(prof, mode)
        -- the same freshness rule the guide uses: a route solved from an older rank describes a different
        -- journey, and a number that doesn't start where the player stands is worse than no number
        if not (r and (r.from == rank or (rank >= r.from and rank < r.to))) then return nil end
        local crafts, cost = 0, 0
        for _, s in ipairs(r.steps) do
            if s.to > rank then
                local n = Plan.CraftsLeft(s, rank)
                crafts = crafts + n
                cost = cost + n * (s.costEach or 0)
            end
        end
        return { crafts = crafts, cost = cost, to = r.to }
    end
    return totals("cheap"), totals("fast")
end

-- The route we already have, or nil. Never starts a solve: for callers that are only asking a question,
-- such as another addon wondering whether an item matters.
function Plan.RouteIfReady(prof, mode)
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode or SW.Settings().mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return r end
    return nil
end

-- The route, solved here and now (no waiting). Used by anything that can't come back for the answer.
function Plan.RouteNow(prof, mode)
    mode = mode or SW.Settings().mode
    local rank = math.max(1, SW.Prof.Rank(prof))
    local r = Cached(prof, mode)
    if r and (r.from == rank or (rank >= r.from and rank < r.to)) then return r end
    local opts = Plan.Options(prof, rank)
    opts.mode = mode
    r = SW.Solver.Solve(prof, opts)
    if r then Keep(prof, mode, r) end
    return r
end

-- Which of several interchangeable recipes the player would rather make. Remembered per character and
-- profession; nil means "whichever is cheapest".
function Plan.Prefer(prof, spell)
    local cp = SW.CharProf(prof)
    cp.prefer = cp.prefer or {}
    wipe(cp.prefer)                      -- one choice per group, and groups can't overlap
    if spell then cp.prefer[spell] = true end
    -- and it becomes the step being followed, until it goes grey or its target is reached
    if spell then
        local route = Cached(prof, SW.Settings().mode)
        local rank = math.max(1, SW.Prof.Rank(prof))
        local to
        for _, st in ipairs(route and route.steps or {}) do
            if rank < st.to then to = st.to break end
        end
        Plan.SetActive(prof, spell, to)
    else
        Plan.SetActive(prof, nil)
    end
    Plan.Invalidate(prof)
end

function Plan.Preferred(prof, spell)
    local cp = SW.CharProf(prof)
    return cp.prefer ~= nil and cp.prefer[spell] == true
end

-- Of several recipes that all give a guaranteed skill-up, the one that costs least to FINISH from here:
-- materials already in the bags or bank are paid for, so only what is still missing counts. That is the
-- user's rule - "number of materials against cost to craft, lowest wins" - and it falls out naturally:
-- a recipe you have the materials for costs nothing more, however dear it would be to buy.
local orangeCache = {}

function Plan.ForgetOrange(prof)
    if prof then orangeCache[prof] = nil else wipe(orangeCache) end
end

-- crafts you could do right now from what you hold, and what the rest would cost to buy
local function Affordability(opt, crafts)
    local canMake, missing = nil, 0
    for i = 1, #opt.mats, 2 do
        local id, per = opt.mats[i], opt.mats[i + 1]
        local have = Plan.Count(id, true)
        local possible = math.floor(have / math.max(1, per))
        canMake = (canMake == nil or possible < canMake) and possible or canMake
        local short = math.max(0, per * crafts - have)
        if short > 0 then
            local unit = SW.Prices.Market(id) or (SW.DB().vendor[id] or 0)
            missing = missing + short * unit
        end
    end
    return canMake or 0, missing
end

-- The alternatives for the step the player is on, best first. Worked out once per profession, rank and
-- bag state, so it can't shuffle while they craft.
function Plan.Orange(prof, rank, to)
    local sig = ("%d:%d"):format(rank, to)
    local cached = orangeCache[prof]
    if cached and cached.sig == sig and cached.bags == Plan.bagSig then return cached.list end
    local opts = Plan.Options(prof, rank)
    local list = SW.Solver.Interchangeable(prof, rank, opts)
    for _, o in ipairs(list) do
        -- what THIS recipe would take to carry the player to the same skill: an orange one needs fewer
        -- crafts than a yellow one, which is half of why the choice matters
        o.crafts = math.max(1, Plan.CraftsLeft({ from = rank, to = to, yellow = o.yellow, grey = o.grey }, rank))
        o.canMake, o.missing = Affordability(o, o.crafts)
        o.total = o.cost * o.crafts
        o.chosen = Plan.Preferred(prof, o.spell) or nil
    end
    table.sort(list, function(a, b)
        if (a.chosen or false) ~= (b.chosen or false) then return a.chosen end
        if a.missing ~= b.missing then return a.missing < b.missing end   -- cheapest to finish from here
        if a.cost ~= b.cost then return a.cost < b.cost end               -- then cheapest outright
        return a.spell < b.spell
    end)
    orangeCache[prof] = { sig = sig, bags = Plan.bagSig, list = list }
    return list
end

-- The step the player is following, remembered per character and profession (so it survives a /reload).
-- A guide that changes its mind while you follow it is worse than one that is slightly suboptimal, so a
-- step is only given up when it stops giving skill, when it is finished, or when the player says so.
-- Running out of materials is NOT a reason: the guide says what is missing instead.
function Plan.Active(prof)
    return SW.CharProf(prof).active
end

function Plan.SetActive(prof, spell, to)
    local cp = SW.CharProf(prof)
    if not spell then
        cp.active = nil
        return
    end
    local a = cp.active
    if a and a.spell == spell and a.to == to then return end
    cp.active = { spell = spell, to = to }
end

-- Is the recipe we are following still worth following at this skill?
local function StillGood(prof, spell, rank)
    local data = SW.Data.professions[prof]
    if not data then return nil end
    local cp = SW.CharProf(prof)
    if not (cp.known and cp.known[spell]) then return nil end
    for _, r in ipairs(data[2]) do
        if r[1] == spell then
            local colors = SW.DB().colors and SW.DB().colors[spell]
            local yellow = (colors and colors.yellow) or r[5]
            local grey = (colors and colors.grey) or r[6]
            if SW.Solver.Chance(yellow, grey, rank) <= 0 then return nil end   -- grey: no skill left in it
            return r, yellow, grey
        end
    end
end

-- Index of the step the rank falls in (#steps + 1 when past the route).
function Plan.StepIndex(route, rank)
    for i, s in ipairs(route.steps) do
        if rank < s.to then return i end
    end
    return #route.steps + 1
end

local Count = function(...) return Plan.Count(...) end

-- Expected crafts left in a step from `rank` (the solver's numbers, re-summed from where you are now).
function Plan.CraftsLeft(step, rank)
    local sum, r = 0, math.max(rank, step.from)
    local ups = 1
    while r < step.to do
        local p = SW.Solver.Chance(step.yellow, step.grey, r)
        if p <= 0 then break end
        sum = sum + 1 / p
        r = r + ups
    end
    return math.ceil(sum - 1e-6)
end

-- Everything the guide shows about the step you're on.
function Plan.Current(prof)
    local route = Plan.Route(prof)
    if not route then return nil end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local idx = Plan.StepIndex(route, rank)
    -- The recipe being followed wins wherever this route also uses it here: that is what keeps the guide
    -- still across a mode switch, a re-plan, or a reload.
    local active = Plan.Active(prof)
    if active then
        for i, s in ipairs(route.steps) do
            if s.spell == active.spell and rank >= s.from and rank < s.to then idx = i break end
        end
    end
    local step = route.steps[idx]
    if not step then return { route = route, done = true, rank = rank } end
    local left = math.max(1, Plan.CraftsLeft(step, rank))

    -- Several known recipes can be orange at once (four Cooking recipes at skill 39, say). They all give
    -- a guaranteed skill-up, so the one to SUGGEST is the one that costs least to finish from here, with
    -- what is already in the bags counting as paid for. Once one is being followed it stays: only losing
    -- its skill-ups, reaching its target, or the player choosing changes it.
    local alts, swapped = nil, nil
    do
        alts = Plan.Orange(prof, rank, step.to)
        local active = Plan.Active(prof)
        if active and (rank >= (active.to or step.to) or not StillGood(prof, active.spell, rank)) then
            Plan.SetActive(prof, nil)                 -- finished, or it has gone grey
            active = nil
        end
        local pick
        if active then
            for _, o in ipairs(alts) do
                if o.spell == active.spell then pick = o break end
            end
            -- it may be out of the "orange" list only because we have no price for it: keep it anyway
            if not pick and StillGood(prof, active.spell, rank) then pick = { spell = active.spell } end
        elseif #alts > 0 then
            -- The planned recipe keeps the benefit of the doubt: another one only takes over when it
            -- costs strictly less to finish from here, which is what holding the materials does.
            local planned
            for _, o in ipairs(alts) do
                if o.spell == step.spell then planned = o break end
            end
            local best = alts[1]
            if planned and planned.missing <= best.missing then best = planned end
            pick = best
            Plan.SetActive(prof, pick.spell, step.to)
        end
        if pick and pick.spell ~= step.spell then
            if not pick.mats then                     -- kept without a price: fill it in from the data
                for _, o in ipairs(Plan.Orange(prof, rank, left)) do
                    if o.spell == pick.spell then pick = o break end
                end
            end
            if pick.mats then
                -- a copy: the route itself is left alone, only what the guide shows changes
                local copy = {}
                for k, v in pairs(step) do copy[k] = v end
                copy.spell, copy.item, copy.qty = pick.spell, pick.item, pick.qty
                copy.costEach, copy.yellow, copy.grey = pick.cost, pick.yellow, pick.grey
                -- the alternatives carry per-craft prices; a step's materials also need `count`
                copy.mats = {}
                for _, m in ipairs(pick.priced or {}) do
                    copy.mats[#copy.mats + 1] = { id = m.id, per = m.per, count = m.per * left,
                                                  unit = m.unit, priceSource = m.priceSource }
                end
                copy.vendorOnly, copy.haveMats = pick.vendorOnly, pick.haveMats
                copy.alts, copy.chosenByPlayer = nil, Plan.Preferred(prof, pick.spell) or nil
                step, swapped = copy, true
                left = math.max(1, Plan.CraftsLeft(step, rank))
            end
        end
    end
    -- A tool still to make (or buy) comes first: the step can't be crafted without it.
    local tool = Plan.PendingTool(step)
    local srcMats = step.mats
    if tool then
        left = 1
        srcMats = tool.mats
    end
    local mats, craftable = {}, nil
    for _, m in ipairs(srcMats) do
        local need = m.per * left
        local have = Count(m.id, true)
        local bags = Count(m.id, false)
        mats[#mats + 1] = { id = m.id, per = m.per, need = need, have = have, bank = math.max(0, have - bags),
                            short = math.max(0, need - have), unit = m.unit, priceSource = m.priceSource }
        local can = math.floor(bags / m.per)
        craftable = craftable and math.min(craftable, can) or can
    end
    local craftSpell = tool and tool.spell or step.spell
    return {
        route = route, idx = idx, step = step, rank = rank, left = left, mats = mats, tool = tool,
        orange = alts, swapped = swapped,
        craftable = math.min(craftable or (tool and 1 or 0), left),
        known = craftSpell and SW.Prof.Knows(prof, craftSpell) or false,
        color = tool and tool.yellow and SW.Solver.Color(tool.yellow, tool.grey, rank)
            or SW.Solver.Color(step.yellow, step.grey, rank),
    }
end

-- Materials for the rest of the route, grouped by trainer tier. Current step counted from the rank.
-- The answer only changes with the route, the rank or what's in the bags, so it is kept until then.
local shopCache = {}
function Plan.ForgetShopping(prof)
    if prof then shopCache[prof] = nil else wipe(shopCache) end
end

-- What you have of each material is read fresh every time, cached list or not.
local function CountThem(groups)
    for _, g in ipairs(groups) do
        for _, e in ipairs(g.order) do
            e.have = Count(e.id, true)
            e.short = math.max(0, e.need - e.have)
        end
    end
    return groups
end

function Plan.Shopping(prof)
    local route = Plan.Route(prof)
    if not route then return {} end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local cached = shopCache[prof]
    if cached and cached.route == route and cached.rank == rank then return CountThem(cached.groups) end
    local owned = Plan.OwnedTools()
    local groups, byTier = {}, {}
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local tier
            for _, t in ipairs(SW.TIERS) do
                if s.from < t.cap then tier = t break end
            end
            tier = tier or SW.TIERS[#SW.TIERS]
            local g = byTier[tier.cap]
            if not g then
                g = { tier = tier, mats = {}, order = {}, cost = 0 }
                byTier[tier.cap] = g
                groups[#groups + 1] = g
            end
            local crafts = rank > s.from and Plan.CraftsLeft(s, rank) or s.crafts
            local function add(id, qty, unit, src)
                local e = g.mats[id]
                if not e then
                    e = { id = id, need = 0, unit = unit, priceSource = src }
                    g.mats[id] = e
                    g.order[#g.order + 1] = e
                end
                e.need = e.need + qty
                g.cost = g.cost + qty * unit
            end
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then
                    if t.buy then
                        add(t.item, 1, t.cost or 0, "vendor")
                    else
                        for _, m in ipairs(t.mats) do add(m.id, m.per, m.unit, m.priceSource) end
                    end
                end
            end
            for _, m in ipairs(s.mats) do add(m.id, m.per * crafts, m.unit, m.priceSource) end
        end
    end
    shopCache[prof] = { route = route, rank = rank, groups = groups }
    return CountThem(groups)
end

-- Totals for the rest of the route: crafts and gold still to spend.
function Plan.Remaining(prof)
    local route = Plan.Route(prof)
    if not route then return 0, 0 end
    local rank = math.max(1, SW.Prof.Rank(prof))
    local owned = Plan.OwnedTools()
    local crafts, cost = 0, 0
    for _, s in ipairs(route.steps) do
        if rank < s.to then
            local n = rank > s.from and Plan.CraftsLeft(s, rank) or s.crafts
            crafts = crafts + n
            cost = cost + n * s.costEach
            for _, t in ipairs(s.prereqs or {}) do
                if not SW.Solver.HasTool(t.category, owned) then cost = cost + (t.cost or 0) end
            end
        end
    end
    return crafts, cost
end

-- The next trainer tier to learn, when the rank is close to (or at) the current cap.
function Plan.TrainingDue(prof)
    local cp = SW.CharProf(prof)
    local rank, max = cp.rank or 0, cp.max or 0
    if max <= 0 or max >= SW.MAX_RANK then return nil end
    for _, t in ipairs(SW.TIERS) do
        if t.cap > max then
            if rank >= t.need and rank >= max - 10 then return t end
            return nil
        end
    end
end

for _, ev in ipairs({ "RECIPES_CHANGED", "TRAINER_FACTS", "PRICES_CHANGED", "COLORS_CHANGED" }) do
    SW.Listen(ev, function(prof)
        if type(prof) == "number" then Plan.Invalidate(prof) else Plan.Invalidate() end
    end)
end
-- A tool arriving in (or leaving) the bags changes which recipes are possible.
-- Picking things up shouldn't re-plan constantly: only when the set of tools, or of materials we have
-- enough of, actually changes - and then at most once every few seconds.
SW.On("BAG_UPDATE_DELAYED", function()
    SW.Coalesce("bagsChanged", 3, function()
        -- what is in the bags decides which guaranteed recipe is cheapest to finish: let that list go
        -- stale on a timer, never mid-craft
        Plan.bagSig = (Plan.bagSig or 0) + 1
        Plan.ForgetOrange()
        wipe(haveCache)
        local _, sig = Plan.OwnedTools()
        local changed = ownedSig and sig ~= ownedSig
        ownedSig = sig
        if SW.Settings().useOwned ~= false then
            for prof in pairs(cache) do
                local before = haveSig[prof]
                Plan.HaveMats(prof)
                if before and haveSig[prof] ~= before then changed = true end
            end
        end
        if changed then Plan.Invalidate() end
    end)
end)
-- Vendor prices change the plan only a little; re-plan when the merchant closes.
SW.Listen("MERCHANT_CHANGED", function()
    if not (MerchantFrame and MerchantFrame:IsShown()) then SW.Debounce("replanVendor", 1, function() Plan.Invalidate() end) end
end)
