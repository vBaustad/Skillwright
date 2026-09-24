-- Skillwright - prices: auction prices (Auctionator, TSM or our own auction house scan) and vendor prices.
-- The route solver asks SW.Prices.Market(itemID) for a live price; vendor prices go in as facts.
local ADDON, SW = ...
local Pr = {}
SW.Prices = Pr

local KEEP_PRICES = 30 * 86400    -- how long a scanned price is kept at all
local SCAN_PERCENTILE = 0.15      -- price of the cheapest 15% of what's listed: ignores lone bargains
local SCAN_BATCH = 1500           -- replicate rows handled per frame

-- ---------------------------------------------------------------------------
-- Market price sources
-- ---------------------------------------------------------------------------
local function FromAuctionator(id)
    local api = Auctionator and Auctionator.API and Auctionator.API.v1
    if not api or not api.GetAuctionPriceByItemID then return nil end
    local ok, price = pcall(api.GetAuctionPriceByItemID, ADDON, id)
    return ok and price or nil
end

local function FromTSM(id)
    if not TSM_API or not TSM_API.GetCustomPriceValue then return nil end
    local ok, price = pcall(TSM_API.GetCustomPriceValue, "DBMinBuyout", "i:" .. id)
    return ok and price or nil
end

-- Our own scan, as long as it isn't older than the "prices go stale" setting (days).
local function OwnScan(id)
    local e = SW.DB().ah[id]
    if not e then return nil end
    local maxAge = (SW.Settings().maxPriceAge or 3) * 86400
    if e[2] and SW.Now() - e[2] > maxAge then return nil end
    return e[1]
end

-- Which source answers first decides the label shown in the guide.
local SOURCES = {
    { key = "auctionator", label = "Auctionator", fn = FromAuctionator },
    { key = "tsm", label = "TradeSkillMaster", fn = FromTSM },
    { key = "scan", label = "auction scan", fn = OwnScan },
}

function Pr.Market(id)
    for _, s in ipairs(SOURCES) do
        local p = s.fn(id)
        if p and p > 0 then return p, s.key end
    end
end

-- A one-line summary of where prices come from right now.
function Pr.SourceText()
    local parts = {}
    if Auctionator and Auctionator.API then parts[#parts + 1] = "Auctionator" end
    if TSM_API then parts[#parts + 1] = "TSM" end
    local t = SW.DB().ahScanned or 0
    if t > 0 then
        parts[#parts + 1] = ("auction scan %s"):format(Pr.Ago(t))
    end
    if #parts == 0 then return nil end
    return table.concat(parts, ", ")
end

-- Whether the guide has real auction prices: "addon" (Auctionator/TSM), "scan" (our own, fresh enough),
-- "stale" (our scan is older than the "prices go stale" setting) or "none".
function Pr.Status()
    if (Auctionator and Auctionator.API) or TSM_API then return "addon" end
    local t = SW.DB().ahScanned or 0
    if t <= 0 then return "none" end
    if SW.Now() - t > (SW.Settings().maxPriceAge or 3) * 86400 then return "stale" end
    return "scan"
end

function Pr.Ago(t)
    local d = SW.Now() - t
    if d < 3600 then return ("%dm ago"):format(math.max(1, d / 60)) end
    if d < 86400 then return ("%dh ago"):format(d / 3600) end
    return ("%dd ago"):format(d / 86400)
end

-- ---------------------------------------------------------------------------
-- Our own auction house scan (C_AuctionHouse.ReplicateItems: the whole house, once per 15 minutes)
-- ---------------------------------------------------------------------------
local scanning = false
local scanToken = 0          -- bumped by every start and every stop; a reading chain only finishes its own scan
local reading = false        -- a REPLICATE_ITEM_LIST_UPDATE is being read in batches right now

function Pr.CanScan()
    return C_AuctionHouse and C_AuctionHouse.ReplicateItems and AuctionHouseFrame and AuctionHouseFrame:IsShown()
end

function Pr.Scanning() return scanning end

function Pr.StartScan()
    if scanning then return end
    if not Pr.CanScan() then
        SW.msg("open the auction house first.")
        return
    end
    scanning = true
    scanToken = scanToken + 1
    local token = scanToken
    SW.msg("scanning the auction house - this takes a few seconds.")
    C_AuctionHouse.ReplicateItems()
    SW.Fire("SCAN_STATE")
    -- The server refuses a second replicate within 15 minutes and sends nothing back.
    C_Timer.After(60, function()
        if scanning and scanToken == token and not reading then
            scanning = false
            scanToken = scanToken + 1
            SW.msg("|cffff6060the auction house didn't answer.|r It allows one full scan every 15 minutes.")
            SW.Fire("SCAN_STATE")
        end
    end)
end

local function Finish(rows)
    local wanted = SW.Data.items
    local byItem = {}
    for _, r in ipairs(rows) do
        local list = byItem[r[1]]
        if not list then list = {}; byItem[r[1]] = list end
        list[#list + 1] = r
    end
    local now, n = SW.Now(), 0
    local ah = SW.DB().ah
    for id, list in pairs(byItem) do
        if wanted[id] then
            table.sort(list, function(a, b) return a[2] < b[2] end)
            local total = 0
            for _, r in ipairs(list) do total = total + r[3] end
            local target, acc, price = math.max(1, total * SCAN_PERCENTILE), 0, list[1][2]
            for _, r in ipairs(list) do
                acc = acc + r[3]
                price = r[2]
                if acc >= target then break end
            end
            ah[id] = { math.floor(price + 0.5), now }
            n = n + 1
        end
    end
    -- Prices older than a month are never used again (the setting caps them at days): drop them so the
    -- saved table can't grow for ever.
    local cutoff = now - KEEP_PRICES
    for id, e in pairs(SW.dataLost and {} or ah) do
        if type(e) ~= "table" or not e[2] or e[2] < cutoff then ah[id] = nil end
    end
    SW.DB().ahScanned = now
    scanning = false
    SW.msg("auction scan done: prices for %d materials.", n)
    SW.Fire("SCAN_STATE")
    SW.Fire("PRICES_CHANGED")
end

SW.On("REPLICATE_ITEM_LIST_UPDATE", function()
    -- only for a scan we started, and only once: the event can come twice
    if not scanning or reading then return end
    reading = true
    local token = scanToken
    local total = C_AuctionHouse.GetNumReplicateItems()
    local rows, i = {}, 0
    local wanted = SW.Data.items
    local function step()
        if token ~= scanToken or not scanning then
            reading = false      -- stopped (auction house closed): keep nothing from a half-read list
            return
        end
        local stop = math.min(total, i + SCAN_BATCH)
        for idx = i, stop - 1 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
            if itemID and wanted[itemID] and buyout and buyout > 0 and count and count > 0 then
                rows[#rows + 1] = { itemID, buyout / count, count }
            end
        end
        i = stop
        if i < total then
            C_Timer.After(0, step)
        else
            reading = false
            Finish(rows)
        end
    end
    step()
end)

SW.On("AUCTION_HOUSE_CLOSED", function()
    if scanning then
        scanning = false
        scanToken = scanToken + 1
        SW.Fire("SCAN_STATE")
    end
end)

-- ---------------------------------------------------------------------------
-- Vendor prices, learned from every merchant the player opens
-- ---------------------------------------------------------------------------
Pr.merchant = {}    -- [itemID] = merchant slot, while a merchant is open

-- Where this merchant is, for the "sold by" line. The player's own position is readable; nothing else is.
local function Here()
    local zone = GetRealZoneText and GetRealZoneText() or (GetZoneText and GetZoneText()) or nil
    local spot = GetSubZoneText and GetSubZoneText() or nil
    if spot == "" then spot = nil end
    return zone, spot
end

local function ScanMerchant()
    wipe(Pr.merchant)
    local db = SW.DB()
    local vendor = db.vendor
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    local who = UnitName("npc")
    local zone, spot = Here()
    for i = 1, n do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, extended, available
        local info = C_MerchantFrame.GetItemInfo(i)
        if info then
            price, stack, extended = info.price, info.stackCount, info.hasExtendedCost
            available = info.numAvailable
        end
        if id and price and price > 0 and not extended then
            Pr.merchant[id] = i
            if SW.Data.items[id] then vendor[id] = price / math.max(1, stack or 1) end
        end
        -- A recipe on sale: the client data has no vendor sources at all, so this is worth keeping.
        -- Quietly: a merchant is opened for other reasons and nobody wants chat about it.
        local recipe = id and SW.RecipeByItem(id)
        if recipe and who and who ~= "" then
            db.sources = db.sources or {}
            db.sources[recipe.spell] = {
                kind = "vendor", item = id, who = who, zone = zone, spot = spot,
                price = price, limited = (available and available >= 0) and available or nil,
                char = UnitName("player"), seen = SW.Now(),
            }
        end
    end
    SW.Fire("MERCHANT_CHANGED")
end

SW.On("MERCHANT_SHOW", function() SW.Debounce("merchant", 0.2, ScanMerchant) end)
SW.On("MERCHANT_UPDATE", function() SW.Debounce("merchant", 0.5, ScanMerchant) end)
SW.On("MERCHANT_CLOSED", function()
    wipe(Pr.merchant)
    SW.Fire("MERCHANT_CHANGED")
end)

-- Buy `qty` of an item from the open merchant, in stack-sized chunks.
function Pr.Buy(id, qty)
    local slot = Pr.merchant[id]
    if not slot or qty <= 0 then return 0 end
    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(slot)) or 20
    local info = C_MerchantFrame.GetItemInfo(slot)
    local stack = info and info.stackCount or 1
    if stack > 1 then
        -- sold in bundles (e.g. 5 water): one call per bundle
        local bundles = math.ceil(qty / stack)
        for _ = 1, bundles do BuyMerchantItem(slot) end
        return bundles * stack
    end
    local left = qty
    while left > 0 do
        local n = math.min(left, math.max(1, maxStack))
        BuyMerchantItem(slot, n)
        left = left - n
    end
    return qty
end

-- Add `qty` of an item to a buy list, if the open merchant sells it (merges repeats).
function Pr.AddToBuy(list, id, qty, unit)
    if not Pr.merchant[id] or qty <= 0 then return end
    for _, e in ipairs(list) do
        if e.id == id then e.qty = e.qty + qty return end
    end
    list[#list + 1] = { id = id, qty = qty, unit = unit or 0 }
end

local function BuyTotal(list)
    local total = 0
    for _, m in ipairs(list or {}) do total = total + m.qty * (m.unit or 0) end
    return total
end

local function ItemLabel(id)
    return (SW.ItemName(id)) or ("item " .. id)
end

function Pr.BuyTooltip(owner, list)
    if not list or #list == 0 then return end
    GameTooltip:SetOwner(owner, "ANCHOR_TOP")
    GameTooltip:AddLine("Buy from this merchant", 1, 0.82, 0.3)
    for _, m in ipairs(list) do
        GameTooltip:AddDoubleLine(("%d x %s"):format(m.qty, ItemLabel(m.id)), SW.MoneyShort(m.qty * (m.unit or 0)), 1, 1, 1, 1, 1, 1)
    end
    local total = BuyTotal(list)
    GameTooltip:AddDoubleLine("Total", SW.MoneyShort(total), 1, 0.82, 0.3, 1, 1, 1)
    if total > GetMoney() then GameTooltip:AddLine("You don't have enough money.", 1, 0.4, 0.4) end
    GameTooltip:Show()
end

StaticPopupDialogs["SKILLWRIGHT_CONFIRM_BUY"] = {
    text = "Buy %s from this merchant for %s?",
    button1 = YES,
    button2 = NO,
    OnAccept = function(_, data)
        if SW.CombatBlocked("buy") then return end
        for _, m in ipairs(data or {}) do Pr.Buy(m.id, m.qty) end
    end,
    timeout = 0,
    whileDead = false,
    hideOnEscape = true,
    preferredIndex = 3,
}

-- Ask before spending: the number of things, the total, and a stop when the money isn't there.
function Pr.ConfirmBuy(list)
    if not list or #list == 0 then return end
    if SW.CombatBlocked("buy") then return end
    local total = BuyTotal(list)
    if total > GetMoney() then
        SW.msg("|cffff6060not enough money|r - that costs %s.", SW.Money(total))
        return
    end
    local count = 0
    for _, m in ipairs(list) do count = count + m.qty end
    local what = #list == 1 and ("%d %s"):format(list[1].qty, ItemLabel(list[1].id))
        or ("%d items (%d kinds)"):format(count, #list)
    StaticPopup_Show("SKILLWRIGHT_CONFIRM_BUY", what, SW.Money(total), list)
end

function Pr.PrintStatus()
    local src = Pr.SourceText()
    SW.msg("price sources: %s", src or "|cffff6060none|r - open the auction house and press Scan in the guide")
    local n = 0
    for _ in pairs(SW.DB().vendor) do n = n + 1 end
    SW.msg("vendor prices seen: %d items.", n)
end
