-- ================= CONFIGURATION =================
local MONITOR_SIDE = "top"               -- Monitor peripheral name/side
local VAULT_NAME = "create:item_vault_0" -- Inventory peripheral name
local REFRESH_INTERVAL = 5                -- Seconds between inventory scans
-- ===================================================

local function formatNumber(amount)
    local formatted = tostring(amount)
    while true do
        local replacements
        formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then return formatted end
    end
end

local function readVault()
    local vault = peripheral.wrap(VAULT_NAME)
    if not vault then return nil, "Vault not found: " .. VAULT_NAME end
    if type(vault.size) ~= "function" or type(vault.list) ~= "function" then
        return nil, "Vault needs inventory size and list methods"
    end

    local ok, capacity, items = pcall(function()
        return vault.size(), vault.list()
    end)
    if not ok then return nil, "Cannot read vault; retrying" end
    if type(capacity) ~= "number" or capacity <= 0 or type(items) ~= "table" then
        return nil, "Invalid vault capacity or contents"
    end

    local stats = {
        capacity = capacity,
        used = 0,
        total = 0,
        types = 0,
        largestStack = 0,
    }
    local itemTypes = {}
    for _, item in pairs(items) do
        stats.used = stats.used + 1
        stats.total = stats.total + item.count
        stats.largestStack = math.max(stats.largestStack, item.count)
        itemTypes[item.name] = true
    end
    for _ in pairs(itemTypes) do
        stats.types = stats.types + 1
    end
    return stats
end

local function draw(monitor, stats, problem)
    local width, height = monitor.getSize()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    local function row(y, text, foreground, background)
        if y < 1 or y > height then return end
        monitor.setCursorPos(1, y)
        monitor.setTextColor(foreground or colors.white)
        monitor.setBackgroundColor(background or colors.black)
        monitor.write(text:sub(1, width))
    end

    local function section(y, text)
        row(y, (" " .. text .. string.rep(" ", width)):sub(1, width),
            colors.white, colors.gray)
    end

    local function metric(y, label, value, foreground, compactLabel)
        local text = " " .. label .. ": " .. value
        if #text > width and compactLabel then
            text = " " .. compactLabel .. ": " .. value
        end
        row(y, text, foreground)
    end

    row(1, (" ITEM VAULT " .. string.rep(" ", width)):sub(1, width),
        colors.yellow, colors.gray)
    if problem then
        row(3, problem, colors.red)
        row(4, "Check connection; retrying", colors.lightGray)
        return
    end

    local occupiedPercent = math.min(100, stats.used / stats.capacity * 100)
    local roomStatus = "ROOM AVAILABLE"
    local statusColor = colors.lime
    if occupiedPercent >= 95 then
        roomStatus = "ALMOST FULL"
        statusColor = colors.red
    elseif occupiedPercent >= 80 then
        roomStatus = "LOW SPACE"
        statusColor = colors.orange
    end
    local statusText = string.format(" %s  %.1f%% slots used", roomStatus, occupiedPercent)
    if #statusText > width then
        statusText = string.format("%.1f%% used", occupiedPercent)
    end
    row(2, statusText, statusColor)

    if height >= 3 then
        local filled = math.floor(width * occupiedPercent / 100 + 0.5)
        monitor.setCursorPos(1, 3)
        monitor.setBackgroundColor(statusColor)
        monitor.write(string.rep(" ", filled))
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", width - filled))
        monitor.setBackgroundColor(colors.black)
    end

    local used, capacity = formatNumber(stats.used), formatNumber(stats.capacity)
    local free, total, types = formatNumber(math.max(0, stats.capacity - stats.used)),
        formatNumber(stats.total), formatNumber(stats.types)
    metric(4, "Occupied slots", used .. "/" .. capacity, nil, "Slots")
    metric(5, "Empty slots", free, colors.lightGray, "Empty")
    if height >= 6 then
        section(6, "INVENTORY")
    end
    metric(7, "Items stored", total, colors.yellow, "Items")
    metric(8, "Item types", types, colors.cyan, "Types")

    if height >= 11 then
        section(10, "STACK DETAILS")
    end
    if height >= 11 then
        local averageStack = stats.used > 0 and stats.total / stats.used or 0
        metric(11, "Avg items per occupied slot", string.format("%.1f", averageStack),
            colors.lightGray, "Avg/slot")
    end
    if height >= 12 then
        metric(12, "Largest stack", formatNumber(stats.largestStack), colors.lightGray, "Largest")
    end
end

local lastMonitorError
local function refresh()
    local monitor = peripheral.wrap(MONITOR_SIDE)
    if not monitor then
        if not lastMonitorError then print("Monitor not found: " .. MONITOR_SIDE .. "; retrying") end
        lastMonitorError = true
        return
    end
    local stats, problem = readVault()
    local ok = pcall(draw, monitor, stats, problem)
    if not ok then
        if not lastMonitorError then print("Cannot draw to monitor; retrying") end
        lastMonitorError = true
    else
        lastMonitorError = false
    end
end

refresh()
local timer = os.startTimer(REFRESH_INTERVAL)
while true do
    local event, value = os.pullEvent()
    if event == "timer" and value == timer then
        timer = os.startTimer(REFRESH_INTERVAL)
        refresh()
    elseif event == "monitor_resize" and value == MONITOR_SIDE
        or event == "peripheral" or event == "peripheral_detach" then
        refresh()
    end
end
