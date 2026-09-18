-- Skillwright - prices: auction prices (Auctionator, TSM or our own auction house scan) and vendor prices.
-- The route solver asks SW.Prices.Market(itemID) for a live price; vendor prices go in as facts.
local ADDON, SW = ...
local Pr = {}
SW.Prices = Pr

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

local function OwnScan(id)
    local e = SW.DB().ah[id]
    return e and e[1] or nil
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

function Pr.HasMarket()
    return Pr.SourceText() ~= nil
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
local scanning, scanStarted = false, 0

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
    scanning, scanStarted = true, GetTime()
    SW.msg("scanning the auction house - this takes a few seconds.")
    C_AuctionHouse.ReplicateItems()
    SW.Fire("SCAN_STATE")
    -- The server refuses a second replicate within 15 minutes and sends nothing back.
    C_Timer.After(60, function()
        if scanning and GetTime() - scanStarted >= 59 then
            scanning = false
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
    SW.DB().ahScanned = now
    scanning = false
    SW.msg("auction scan done: prices for %d materials.", n)
    SW.Fire("SCAN_STATE")
    SW.Fire("PRICES_CHANGED")
end

SW.On("REPLICATE_ITEM_LIST_UPDATE", function()
    if not scanning then return end
    local total = C_AuctionHouse.GetNumReplicateItems()
    local rows, i = {}, 0
    local wanted = SW.Data.items
    local function step()
        local stop = math.min(total, i + SCAN_BATCH)
        for idx = i, stop - 1 do
            local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID = C_AuctionHouse.GetReplicateItemInfo(idx)
            if itemID and wanted[itemID] and buyout and buyout > 0 and count and count > 0 then
                rows[#rows + 1] = { itemID, buyout / count, count }
            end
        end
        i = stop
        if i < total then C_Timer.After(0, step) else Finish(rows) end
    end
    step()
end)

SW.On("AUCTION_HOUSE_CLOSED", function()
    if scanning then
        scanning = false
        SW.Fire("SCAN_STATE")
    end
end)

-- ---------------------------------------------------------------------------
-- Vendor prices, learned from every merchant the player opens
-- ---------------------------------------------------------------------------
Pr.merchant = {}    -- [itemID] = merchant slot, while a merchant is open

local function ScanMerchant()
    wipe(Pr.merchant)
    local vendor = SW.DB().vendor
    local n = GetMerchantNumItems and GetMerchantNumItems() or 0
    for i = 1, n do
        local id = GetMerchantItemID and GetMerchantItemID(i)
        local price, stack, extended
        if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
            local info = C_MerchantFrame.GetItemInfo(i)
            if info then price, stack, extended = info.price, info.stackCount, info.hasExtendedCost end
        elseif GetMerchantItemInfo then
            local _
            _, _, price, stack, _, _, _, extended = GetMerchantItemInfo(i)
        end
        if id and price and price > 0 and not extended then
            Pr.merchant[id] = i
            if SW.Data.items[id] then vendor[id] = price / math.max(1, stack or 1) end
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

function Pr.MerchantOpen()
    return MerchantFrame and MerchantFrame:IsShown() and next(Pr.merchant) ~= nil
end

-- Buy `qty` of an item from the open merchant, in stack-sized chunks.
function Pr.Buy(id, qty)
    local slot = Pr.merchant[id]
    if not slot or qty <= 0 then return 0 end
    local maxStack = (GetMerchantItemMaxStack and GetMerchantItemMaxStack(slot)) or 20
    local stack = 1
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
        local info = C_MerchantFrame.GetItemInfo(slot)
        stack = info and info.stackCount or 1
    end
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

function Pr.PrintStatus()
    local src = Pr.SourceText()
    SW.msg("price sources: %s", src or "|cffff6060none|r - open the auction house and press Scan in the guide")
    local n = 0
    for _ in pairs(SW.DB().vendor) do n = n + 1 end
    SW.msg("vendor prices seen: %d items.", n)
end
