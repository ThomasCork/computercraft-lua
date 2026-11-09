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

    local stats = { capacity = capacity, used = 0, total = 0, types = 0, top = {} }
    local counts = {}
    for _, item in pairs(items) do
        stats.used = stats.used + 1
        stats.total = stats.total + item.count
        counts[item.name] = (counts[item.name] or 0) + item.count
    end
    for name, count in pairs(counts) do
        stats.types = stats.types + 1
        stats.top[#stats.top + 1] = { name = name, count = count }
    end
    table.sort(stats.top, function(a, b)
        if a.count == b.count then return a.name < b.name end
        return a.count > b.count
    end)
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

    local percent = math.min(100, stats.used / stats.capacity * 100)
    local status, statusColor = "HEALTHY", colors.lime
    if percent >= 95 then
        status, statusColor = "CRITICAL", colors.red
    elseif percent >= 80 then
        status, statusColor = "WARNING", colors.orange
    end
    row(2, string.format(" %s  %.1f%% full", status, percent), statusColor)

    if height >= 3 then
        local filled = math.floor(width * percent / 100 + 0.5)
        monitor.setCursorPos(1, 3)
        monitor.setBackgroundColor(statusColor)
        monitor.write(string.rep(" ", filled))
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", width - filled))
        monitor.setBackgroundColor(colors.black)
    end

    row(4, " Slots: " .. formatNumber(stats.used) .. " / " .. formatNumber(stats.capacity))
    row(5, " Free slots: " .. formatNumber(math.max(0, stats.capacity - stats.used)), colors.lightGray)
    row(6, " Items: " .. formatNumber(stats.total), colors.yellow)
    row(7, " Item types: " .. formatNumber(stats.types), colors.cyan)

    if height >= 9 then
        row(9, (" TOP ITEMS " .. string.rep(" ", width)):sub(1, width),
            colors.white, colors.gray)
        if #stats.top == 0 then
            row(10, " Vault is empty", colors.lightGray)
        else
            for i = 1, math.min(#stats.top, height - 9) do
                local item = stats.top[i]
                local count = formatNumber(item.count)
                local prefix = " " .. i .. ". "
                local available = width - #prefix - #count - 1
                if available > 0 then
                    local name = item.name
                    if #name > available then
                        name = available > 1 and name:sub(1, available - 1) .. "~" or "~"
                    end
                    row(9 + i, prefix .. name .. string.rep(" ", available - #name + 1) .. count)
                else
                    row(9 + i, count .. " " .. item.name)
                end
            end
        end
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
