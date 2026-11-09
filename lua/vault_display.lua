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

    row(1, (" VAULT MONITOR " .. string.rep(" ", width)):sub(1, width),
        colors.yellow, colors.gray)
    if problem then
        row(3, problem, colors.red)
        row(4, "Check connection; retrying", colors.lightGray)
        return
    end

    local occupiedPercent = math.min(100, stats.used / stats.capacity * 100)
    local statusColor = colors.lime
    if occupiedPercent >= 95 then
        statusColor = colors.red
    elseif occupiedPercent >= 80 then
        statusColor = colors.orange
    end
    local statusText = string.format(" SLOTS OCCUPIED  %.1f%%", occupiedPercent)
    if #statusText > width then statusText = string.format("%.1f%% slots used", occupiedPercent) end
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
    local slotsText = " Occupied slots: " .. used .. " / " .. capacity
    if #slotsText > width then slotsText = used .. " of " .. capacity .. " slots" end
    row(4, slotsText)
    local freeText = " Empty slots: " .. free
    if #freeText > width then freeText = free .. " empty" end
    row(5, freeText, colors.lightGray)
    row(6, " Items stored: " .. total, colors.yellow)
    local typesText = " Item types: " .. types
    if #typesText > width then typesText = types .. " types" end
    row(7, typesText, colors.cyan)

    local averageStack = stats.used > 0 and stats.total / stats.used or 0
    if height >= 8 then
        row(8, "Bar shows occupied slots, not item capacity", colors.gray)
    end
    if height >= 9 then
        row(9, string.format(" Avg stack: %.1f items", averageStack), colors.lightGray)
    end
    if height >= 10 then
        row(10, " Largest stack: " .. formatNumber(stats.largestStack), colors.lightGray)
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
