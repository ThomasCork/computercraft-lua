local MONITOR_SIDE = "top"
local VAULT_NAME = "create:item_vault_0"
local REFRESH_INTERVAL = 120
local SLOTS_PER_VAULT_BLOCK = 20
local REFRESH_BUTTON = "[REFRESH]"

local theme = {
    header = colors.blue,
    accent = colors.orange,
    panel = colors.gray,
    background = colors.black,
    primary = colors.white,
    muted = colors.lightGray,
    full = colors.lime,
    occupied = colors.green,
    empty = colors.gray,
}

local function formatNumber(amount)
    local formatted = tostring(amount)
    while true do
        local replacements
        formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then return formatted end
    end
end

local function elapsedLabel(lastRefreshAt)
    if not lastRefreshAt then return "Updated: never" end
    local seconds = math.max(0, math.floor((os.epoch("utc") - lastRefreshAt) / 1000))
    return string.format("Updated %dm %02ds ago", math.floor(seconds / 60), seconds % 60)
end

local function sameSnapshot(first, second)
    if not first or first.capacity ~= second.capacity or #first.items ~= #second.items then
        return false
    end
    for i, item in ipairs(first.items) do
        local other = second.items[i]
        if item.slot ~= other.slot or item.name ~= other.name or item.count ~= other.count
            or item.maxCount ~= other.maxCount then
            return false
        end
    end
    return true
end

local function readVault(progress, previousSnapshot, previousStats, stackLimitCache)
    progress.phase = "Reading vault"
    progress.total = 0
    progress.processed = 0

    local vault = peripheral.wrap(VAULT_NAME)
    if not vault then return nil, "Vault not found: " .. VAULT_NAME end
    if type(vault.size) ~= "function" or type(vault.list) ~= "function" then
        return nil, "Vault needs inventory size and list methods"
    end

    local ok, capacity, items = pcall(function()
        return vault.size(), vault.list()
    end)
    if not ok then return nil, "Cannot read vault: " .. tostring(capacity) end
    if type(capacity) ~= "number" or capacity <= 0 or type(items) ~= "table" then
        return nil, "Invalid vault capacity or contents"
    end

    local snapshot = { capacity = capacity, items = {} }
    for slot, item in pairs(items) do
        snapshot.items[#snapshot.items + 1] = {
            slot = slot,
            name = item.name,
            count = item.count,
            maxCount = item.maxCount,
        }
    end
    table.sort(snapshot.items, function(a, b) return a.slot < b.slot end)

    if previousStats and sameSnapshot(previousSnapshot, snapshot) then
        progress.phase = "No changes"
        progress.total = #snapshot.items
        progress.processed = progress.total
        return previousStats, snapshot
    end

    progress.phase = "Updating inventory"
    progress.total = #snapshot.items

    local stats = {
        capacity = capacity,
        used = 0,
        fullSlots = 0,
        fullSlotsKnown = true,
        total = 0,
        types = 0,
        largestStack = 0,
    }
    local itemTypes = {}
    for index, entry in ipairs(snapshot.items) do
        progress.processed = index
        local item = items[entry.slot]
        stats.used = stats.used + 1
        stats.total = stats.total + item.count
        stats.largestStack = math.max(stats.largestStack, item.count)
        itemTypes[item.name] = true

        local stackLimit = stackLimitCache[item.name]
        if stackLimit == nil then
            stackLimit = item.maxCount
            if (type(stackLimit) ~= "number" or stackLimit <= 0)
                and type(vault.getItemDetail) == "function" then
                local okDetail, detail = pcall(vault.getItemDetail, entry.slot)
                if okDetail and detail then stackLimit = detail.maxCount end
            end
            if (type(stackLimit) ~= "number" or stackLimit <= 0)
                and type(vault.getItemLimit) == "function" then
                local okLimit, limit = pcall(vault.getItemLimit, entry.slot)
                if okLimit then stackLimit = limit end
            end
            if type(stackLimit) ~= "number" or stackLimit <= 0 then
                stackLimit = false
            end
            stackLimitCache[item.name] = stackLimit
        end

        if type(stackLimit) == "number" and stackLimit > 0 then
            if item.count >= stackLimit then
                stats.fullSlots = stats.fullSlots + 1
            end
        else
            stats.fullSlotsKnown = false
        end
    end
    for _ in pairs(itemTypes) do
        stats.types = stats.types + 1
    end
    progress.phase = "Finishing"
    return stats, snapshot
end

local function paint(monitor, x, y, text, foreground, background, width)
    local screenWidth, screenHeight = monitor.getSize()
    if y < 1 or y > screenHeight or x < 1 or x > screenWidth then return end
    width = math.min(width or #text, screenWidth - x + 1)
    if width <= 0 then return end
    text = text:sub(1, width)
    monitor.setCursorPos(x, y)
    monitor.setTextColor(foreground or theme.primary)
    monitor.setBackgroundColor(background or theme.background)
    monitor.write(text .. string.rep(" ", width - #text))
end

local function fill(monitor, x, y, width, color)
    if width <= 0 then return end
    monitor.setCursorPos(x, y)
    monitor.setBackgroundColor(color)
    monitor.write(string.rep(" ", width))
end

local function drawHeader(monitor, width)
    fill(monitor, 1, 1, width, theme.header)
    paint(monitor, 2, 1, "NETSUITE", theme.primary, theme.header)
    paint(monitor, 12, 1, "| INVENTORY", colors.white, theme.header)

    fill(monitor, 1, 2, width, theme.panel)
    paint(monitor, 2, 2, "Inventory", theme.primary, theme.panel)
    paint(monitor, 14, 2, " /  Item Vault", theme.muted, theme.panel)
end

local function drawSidebar(monitor, height, width)
    local sidebarWidth = 16
    for y = 3, height do
        fill(monitor, 1, y, sidebarWidth, theme.panel)
    end
    paint(monitor, 2, 4, "DASHBOARD", theme.muted, theme.panel)
    paint(monitor, 2, 6, "Overview", theme.primary, theme.header, sidebarWidth - 2)
    paint(monitor, 2, 8, "INVENTORY", theme.muted, theme.panel)
    paint(monitor, 2, 10, "Item Vault", theme.accent, theme.panel)
    paint(monitor, 2, 12, "CAPACITY", theme.muted, theme.panel)
    paint(monitor, 2, 14, "Slot usage", theme.primary, theme.panel)
    fill(monitor, sidebarWidth + 1, 3, 1, theme.accent)
    return sidebarWidth + 3, width - sidebarWidth - 3
end

local function drawCard(monitor, x, y, width, label, value, accent)
    if width < 9 then return end
    fill(monitor, x, y, width, theme.panel)
    fill(monitor, x, y, width, accent)
    paint(monitor, x + 1, y + 1, label, theme.muted, theme.panel, width - 2)
    paint(monitor, x + 1, y + 2, value, theme.primary, theme.panel, width - 2)
    paint(monitor, x + 1, y + 3, "CURRENT", theme.muted, theme.panel, width - 2)
end

local function drawProgressBar(monitor, x, y, width, stats)
    local fullSlots = stats.fullSlotsKnown and stats.fullSlots or 0
    local partialSlots = stats.fullSlotsKnown and stats.used - fullSlots or stats.used
    local fullWidth = math.min(width, math.floor(width * fullSlots / stats.capacity + 0.5))
    local occupiedWidth = math.min(width - fullWidth,
        math.floor(width * partialSlots / stats.capacity + 0.5))
    local emptyWidth = width - fullWidth - occupiedWidth
    for row = y, y + 1 do
        local column = x
        fill(monitor, column, row, fullWidth, theme.full)
        column = column + fullWidth
        fill(monitor, column, row, occupiedWidth, theme.occupied)
        column = column + occupiedWidth
        fill(monitor, column, row, emptyWidth, theme.empty)
    end
end

local function drawFooter(monitor, progress, lastRefreshAt, frame)
    local width, height = monitor.getSize()
    if height < 1 then return end

    local buttonWidth = width >= 24 and #REFRESH_BUTTON or 0
    local barWidth = width - buttonWidth
    local text, foreground
    if progress.problem then
        text, foreground = "Refresh failed", colors.red
    elseif progress.done then
        text, foreground = elapsedLabel(lastRefreshAt), theme.muted
    elseif progress.total > 0 then
        local percent = math.floor(progress.processed / progress.total * 100)
        text = string.format("Updating %d%%  %s/%s slots",
            percent, formatNumber(progress.processed), formatNumber(progress.total))
        foreground = colors.yellow
    else
        local spinner = { "|", "/", "-", "\\" }
        text = "Checking vault " .. spinner[frame % #spinner + 1]
        foreground = colors.yellow
    end
    paint(monitor, 1, height - 1, text, foreground, theme.background, width)

    if height >= 2 then
        local filled = 0
        if progress.total > 0 and not progress.done then
            filled = math.floor(barWidth * progress.processed / progress.total)
        elseif progress.done and not progress.problem and lastRefreshAt then
            filled = barWidth
        end
        fill(monitor, 1, height, filled, theme.accent)
        fill(monitor, filled + 1, height, barWidth - filled, theme.panel)
        if buttonWidth > 0 then
            paint(monitor, barWidth + 1, height, REFRESH_BUTTON,
                theme.primary, theme.header, buttonWidth)
        end
    end
end

local function drawFirstScan(monitor, progress, frame)
    local width, height = monitor.getSize()
    fill(monitor, 1, 1, width, theme.header)
    paint(monitor, 2, 1, "NETSUITE  |  INVENTORY", theme.primary, theme.header)
    fill(monitor, 1, 2, width, theme.panel)
    paint(monitor, 2, 2, "Inventory / Item Vault", theme.primary, theme.panel)

    local spinner = { "|", "/", "-", "\\" }
    local centerX, centerY = math.floor(width / 2), math.floor((height - 2) / 2)
    paint(monitor, centerX - 2, centerY, "[" .. spinner[frame % #spinner + 1] .. "]",
        theme.accent, theme.background)
    paint(monitor, math.max(1, centerX - 12), centerY + 2,
        "Loading inventory data", theme.primary, theme.background)
    drawFooter(monitor, progress, nil, frame)
end

local function drawDashboard(monitor, stats, problem, progress, lastRefreshAt, frame)
    local width, height = monitor.getSize()
    monitor.setBackgroundColor(theme.background)
    monitor.setTextColor(theme.primary)
    monitor.clear()

    drawHeader(monitor, width)
    local contentTop, contentWidth = 4, width
    if width >= 78 then
        contentTop, contentWidth = drawSidebar(monitor, height - 2, width)
    end

    if not stats then
        if problem then
            paint(monitor, contentTop, 5, "VAULT CONNECTION", theme.accent, theme.background)
            paint(monitor, contentTop, 7, problem, colors.red, theme.background, contentWidth)
            paint(monitor, contentTop, 8, "Check the peripheral and try again.",
                theme.muted, theme.background, contentWidth)
        else
            drawFirstScan(monitor, progress, frame)
        end
        drawFooter(monitor, progress, lastRefreshAt, frame)
        return
    end

    paint(monitor, contentTop, 4, "VAULT OVERVIEW", theme.primary, theme.background)
    paint(monitor, contentTop, 5, "Live inventory snapshot", theme.muted, theme.background)

    local used = formatNumber(stats.used)
    local total = formatNumber(stats.total)
    local types = formatNumber(stats.types)
    local cardY = 7
    if contentWidth >= 42 then
        local gap = 1
        local cardWidth = math.floor((contentWidth - gap * 2) / 3)
        drawCard(monitor, contentTop, cardY, cardWidth, "OCCUPIED SLOTS",
            used .. " / " .. formatNumber(stats.capacity), theme.accent)
        drawCard(monitor, contentTop + cardWidth + gap, cardY, cardWidth,
            "TOTAL ITEMS", total, colors.yellow)
        drawCard(monitor, contentTop + (cardWidth + gap) * 2, cardY, cardWidth,
            "ITEM TYPES", types, colors.cyan)
    else
        paint(monitor, contentTop, cardY, "Occupied slots  " .. used .. " / "
            .. formatNumber(stats.capacity), theme.primary, theme.background, contentWidth)
        paint(monitor, contentTop, cardY + 1, "Total items  " .. total,
            colors.yellow, theme.background, contentWidth)
        paint(monitor, contentTop, cardY + 2, "Item types  " .. types,
            colors.cyan, theme.background, contentWidth)
    end

    local sectionY = cardY + 6
    paint(monitor, contentTop, sectionY, "STORAGE CAPACITY", theme.primary, theme.background)
    local occupancy = math.min(100, stats.used / stats.capacity * 100)
    paint(monitor, contentTop, sectionY + 1,
        string.format("%.1f%% of slots occupied", occupancy), theme.muted, theme.background)
    local barWidth = math.max(1, contentWidth - 2)
    drawProgressBar(monitor, contentTop, sectionY + 2, barWidth, stats)

    local fullSlots = stats.fullSlotsKnown and stats.fullSlots or 0
    local partialSlots = stats.fullSlotsKnown and stats.used - fullSlots or stats.used
    local emptySlots = math.max(0, stats.capacity - stats.used)
    local legendY = sectionY + 5
    paint(monitor, contentTop, legendY, "FULL " .. formatNumber(fullSlots),
        theme.full, theme.background)
    paint(monitor, contentTop + 17, legendY,
        "OCCUPIED " .. (stats.fullSlotsKnown and formatNumber(partialSlots) or "?"),
        theme.occupied, theme.background)
    paint(monitor, contentTop + 38, legendY, "EMPTY " .. formatNumber(emptySlots),
        theme.muted, theme.background)

    local detailsY = sectionY + 7
    paint(monitor, contentTop, detailsY, "INVENTORY DETAILS", theme.primary, theme.background)
    if stats.fullSlotsKnown then
        local fullBlocks = math.floor(stats.fullSlots / SLOTS_PER_VAULT_BLOCK)
        paint(monitor, contentTop, detailsY + 1,
            "Full stacks: " .. formatNumber(stats.fullSlots) .. " / " .. used,
            theme.full, theme.background, contentWidth)
        paint(monitor, contentTop, detailsY + 2,
            "Full block equivalents: " .. formatNumber(fullBlocks),
            theme.muted, theme.background, contentWidth)
    else
        paint(monitor, contentTop, detailsY + 1,
            "Full stack count unavailable", theme.muted, theme.background, contentWidth)
    end
    paint(monitor, contentTop, detailsY + 3,
        "Average stack: " .. string.format("%.1f", stats.used > 0
            and stats.total / stats.used or 0), theme.muted, theme.background, contentWidth)
    paint(monitor, contentTop, detailsY + 4,
        "Largest stack: " .. formatNumber(stats.largestStack),
        theme.muted, theme.background, contentWidth)

    drawFooter(monitor, progress, lastRefreshAt, frame)
end

local cachedStats
local cachedSnapshot
local stackLimitCache = {}
local lastRefreshAt
local lastProblem
local lastMonitorError
local displayProgress = { done = true }

local function scanWithProgress(monitor, progress)
    progress.phase = "Reading vault"
    progress.processed = 0
    progress.total = 0
    progress.done = false
    progress.problem = nil
    displayProgress = progress

    local stats, snapshot
    local function scan()
        local ok, result, newSnapshot = pcall(readVault, progress, cachedSnapshot,
            cachedStats, stackLimitCache)
        if ok then
            if result then
                stats, snapshot = result, newSnapshot
            else
                progress.problem = newSnapshot
            end
        else
            progress.problem = "Vault scan failed: " .. tostring(result)
        end
        progress.done = true
    end

    local function showProgress()
        local frame = 0
        while not progress.done do
            pcall(drawFooter, monitor, progress, lastRefreshAt, frame)
            if not cachedStats then
                pcall(drawFirstScan, monitor, progress, frame)
            end
            frame = frame + 1
            sleep(0.25)
        end
    end

    parallel.waitForAny(scan, showProgress)
    if progress.problem then return nil, nil, progress.problem end
    return stats, snapshot
end

local function refresh(monitor)
    monitor = monitor or peripheral.wrap(MONITOR_SIDE)
    if not monitor then
        if not lastMonitorError then
            print("Monitor not found: " .. MONITOR_SIDE .. "; retrying")
        end
        lastMonitorError = true
        return
    end

    local progress = { phase = "Reading vault", processed = 0, total = 0, done = false }
    if not cachedStats then
        drawDashboard(monitor, nil, nil, progress, lastRefreshAt, 0)
    end

    local stats, snapshot, problem = scanWithProgress(monitor, progress)
    if stats then
        cachedStats = stats
        cachedSnapshot = snapshot
        lastRefreshAt = os.epoch("utc")
    end
    lastProblem = problem
    progress.done = true
    progress.problem = problem

    if stats and progress.phase == "No changes" then
        drawFooter(monitor, progress, lastRefreshAt, 0)
    else
        drawDashboard(monitor, cachedStats, problem, progress, lastRefreshAt, 0)
    end
    lastMonitorError = false
end

refresh()
local timer = os.startTimer(REFRESH_INTERVAL)
local ageTimer = os.startTimer(1)
while true do
    local event, side, x, y = os.pullEvent()
    if event == "timer" and side == timer then
        refresh()
        timer = os.startTimer(REFRESH_INTERVAL)
        ageTimer = os.startTimer(1)
    elseif event == "timer" and side == ageTimer then
        local monitor = peripheral.wrap(MONITOR_SIDE)
        if monitor then
            drawFooter(monitor, displayProgress, lastRefreshAt, 0)
        end
        ageTimer = os.startTimer(1)
    elseif event == "monitor_touch" and side == MONITOR_SIDE then
        local monitor = peripheral.wrap(MONITOR_SIDE)
        if monitor then
            local width, height = monitor.getSize()
            local buttonX = width - #REFRESH_BUTTON + 1
            if width >= 24 and y == height and x >= buttonX then
                os.cancelTimer(timer)
                refresh(monitor)
                timer = os.startTimer(REFRESH_INTERVAL)
                ageTimer = os.startTimer(1)
            end
        end
    elseif event == "monitor_resize" and side == MONITOR_SIDE then
        local monitor = peripheral.wrap(MONITOR_SIDE)
        if monitor then
            drawDashboard(monitor, cachedStats, lastProblem, displayProgress,
                lastRefreshAt, 0)
        end
    end
end
