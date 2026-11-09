-- ================= CONFIGURATION =================
local MONITOR_SIDE = "top"               -- Monitor peripheral name/side
local VAULT_NAME = "create:item_vault_0" -- Inventory peripheral name
local REFRESH_INTERVAL = 5                -- Seconds between inventory scans
local SLOTS_PER_VAULT_BLOCK = 20
-- ===================================================

local function formatNumber(amount)
    local formatted = tostring(amount)
    while true do
        local replacements
        formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then return formatted end
    end
end

local function readVault(progress)
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

    local itemCount = 0
    for _ in pairs(items) do
        itemCount = itemCount + 1
    end
    progress.phase = "Checking stack limits"
    progress.total = itemCount

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
    local stackLimits = {}
    for slot, item in pairs(items) do
        stats.used = stats.used + 1
        stats.total = stats.total + item.count
        stats.largestStack = math.max(stats.largestStack, item.count)
        itemTypes[item.name] = true

        local stackLimit = stackLimits[item.name]
        if stackLimit == nil then
            stackLimit = item.maxCount
            if (type(stackLimit) ~= "number" or stackLimit <= 0)
                and type(vault.getItemDetail) == "function" then
                local okDetail, detail = pcall(vault.getItemDetail, slot)
                if okDetail and detail then stackLimit = detail.maxCount end
            end
            if type(stackLimit) ~= "number" or stackLimit <= 0 then
                stackLimit = false
            end
            stackLimits[item.name] = stackLimit
        end

        if stackLimit == false and type(vault.getItemLimit) == "function" then
            local okLimit, limit = pcall(vault.getItemLimit, slot)
            if okLimit then stackLimit = limit end
        end
        if type(stackLimit) == "number" and stackLimit > 0 then
            if item.count >= stackLimit then
                stats.fullSlots = stats.fullSlots + 1
            end
        else
            stats.fullSlotsKnown = false
        end
        progress.processed = progress.processed + 1
    end
    for _ in pairs(itemTypes) do
        stats.types = stats.types + 1
    end
    progress.phase = "Finishing"
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

    local function wrapped(y, text, foreground)
        local line = ""
        local function emit()
            if line ~= "" then
                row(y, line, foreground)
                y = y + 1
                line = ""
            end
        end

        for word in text:gmatch("%S+") do
            while #word > width do
                emit()
                line = word:sub(1, width)
                emit()
                word = word:sub(width + 1)
            end
            if line == "" then
                line = word
            elseif #line + #word + 1 <= width then
                line = line .. " " .. word
            else
                emit()
                line = word
            end
        end
        emit()
        return y
    end

    local function section(y, text)
        if width < 2 then
            text = ""
        elseif width <= 5 then
            text = ({
                ["ITEM VAULT"] = "V",
                INVENTORY = "I",
                ["STACK DETAILS"] = "S",
            })[text]
        elseif #text + 1 > width then
            text = ({
                ["ITEM VAULT"] = "VAULT",
                INVENTORY = "ITEMS",
                ["STACK DETAILS"] = width == 6 and "STACK" or "STACKS",
            })[text] or text
        end
        local label = " " .. text
        if #label > width then label = label:sub(1, width) end
        row(y, label .. string.rep(" ", width - #label), colors.white, colors.gray)
        return y + 1
    end

    local function metric(y, label, value, foreground)
        return wrapped(y, label .. ": " .. value, foreground)
    end

    section(1, "ITEM VAULT")
    if problem then
        wrapped(3, problem, colors.red)
        wrapped(4, "Check connection; retrying", colors.lightGray)
        return
    end

    local occupiedPercent = math.min(100, stats.used / stats.capacity * 100)
    local roomStatus = "SPACE AVAILABLE"
    local statusColor = colors.lime
    if occupiedPercent >= 95 then
        roomStatus = "NEARLY FULL"
        statusColor = colors.red
    elseif occupiedPercent >= 80 then
        roomStatus = "LOW SPACE"
        statusColor = colors.orange
    end
    local y = wrapped(2,
        string.format("%s - %.1f%% slots used", roomStatus, occupiedPercent), statusColor)

    local fullSlots = stats.fullSlotsKnown and stats.fullSlots or 0
    local partialSlots = stats.used - fullSlots
    local fullWidth = math.min(width,
        math.floor(width * fullSlots / stats.capacity + 0.5))
    local partialWidth = math.min(width - fullWidth,
        math.floor(width * partialSlots / stats.capacity + 0.5))
    local emptyWidth = width - fullWidth - partialWidth
    local function drawBarRow(row)
        local x = 1
        local function segment(color, cells)
            if cells > 0 then
                monitor.setCursorPos(x, row)
                monitor.setBackgroundColor(color)
                monitor.write(string.rep(" ", cells))
                x = x + cells
            end
        end
        segment(colors.lime, fullWidth)
        segment(colors.green, partialWidth)
        segment(colors.gray, emptyWidth)
    end

    if y <= height then
        drawBarRow(y)
        if y + 1 <= height then drawBarRow(y + 1) end
        monitor.setBackgroundColor(colors.black)
        y = y + 2
    end

    local used, capacity = formatNumber(stats.used), formatNumber(stats.capacity)
    local free, total, types = formatNumber(math.max(0, stats.capacity - stats.used)),
        formatNumber(stats.total), formatNumber(stats.types)
    y = math.max(y, 4)
    y = metric(y, "Occupied slots", used .. " / " .. capacity)
    y = metric(y, "Empty slots", free, colors.lightGray)
    if stats.fullSlotsKnown then
        y = metric(y, "Full stacks", formatNumber(stats.fullSlots) .. " / " .. used,
            colors.lime)
        y = metric(y, "Occupied, not full",
            formatNumber(math.max(0, stats.used - stats.fullSlots)), colors.green)
        local fullBlocks = math.floor(stats.fullSlots / SLOTS_PER_VAULT_BLOCK)
        local totalBlocks = math.ceil(stats.capacity / SLOTS_PER_VAULT_BLOCK)
        y = metric(y, "Full block equivalents",
            formatNumber(fullBlocks) .. " / " .. formatNumber(totalBlocks)
                .. " (20 full stacks each)", colors.lime)
    else
        y = metric(y, "Full stacks", "Unknown (stack limits unavailable)", colors.lime)
        y = metric(y, "Occupied, not full", "Unknown", colors.green)
        y = metric(y, "Full block equivalents", "Unavailable", colors.orange)
    end

    y = section(y, "INVENTORY")
    y = metric(y, "Total items stored", total, colors.yellow)
    y = metric(y, "Item types", types, colors.cyan)
    y = section(y, "STACK DETAILS")
    local averageStack = stats.used > 0 and stats.total / stats.used or 0
    y = metric(y, "Average items per occupied slot", string.format("%.1f", averageStack),
        colors.lightGray)
    metric(y, "Largest stack", formatNumber(stats.largestStack), colors.lightGray)
end

local function drawCalculating(monitor, progress, frame)
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

    local title = (" VAULT MONITOR "):sub(1, width)
    row(1, title .. string.rep(" ", width - #title), colors.yellow, colors.gray)
    row(3, "Calculating inventory...", colors.yellow)
    row(4, progress.phase, colors.lightGray)

    if progress.total > 0 then
        local percent = math.floor(progress.processed / progress.total * 100)
        row(5, string.format("%d%%  %s / %s slots", percent,
            formatNumber(progress.processed), formatNumber(progress.total)), colors.white)
        local filled = math.floor(width * progress.processed / progress.total)
        monitor.setCursorPos(1, 7)
        monitor.setBackgroundColor(colors.lime)
        monitor.write(string.rep(" ", filled))
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", width - filled))
    else
        row(5, "Waiting for vault data", colors.lightGray)
        local segmentWidth = math.max(1, math.floor(width / 5))
        local travel = math.max(1, width - segmentWidth + 1)
        local start = frame % travel + 1
        monitor.setCursorPos(1, 7)
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", width))
        monitor.setCursorPos(start, 7)
        monitor.setBackgroundColor(colors.lime)
        monitor.write(string.rep(" ", segmentWidth))
    end
    monitor.setBackgroundColor(colors.black)
end

local lastMonitorError

local function scanWithProgress(monitor)
    local progress = {
        phase = "Reading vault",
        processed = 0,
        total = 0,
        done = false,
    }
    local stats, problem

    local function scan()
        local ok, result, errorMessage = pcall(readVault, progress)
        if ok then
            stats, problem = result, errorMessage
        else
            problem = "Vault scan failed: " .. tostring(result)
        end
        progress.done = true
    end

    local function showProgress()
        local frame = 0
        local reportedDrawError = false
        while not progress.done do
            if monitor then
                local ok, err = pcall(drawCalculating, monitor, progress, frame)
                if not ok and not reportedDrawError then
                    print("Cannot draw calculation progress: " .. tostring(err))
                    reportedDrawError = true
                end
            end
            frame = frame + 1
            sleep(0.25)
        end
    end

    parallel.waitForAny(scan, showProgress)
    return stats, problem
end

local function refresh()
    local monitor = peripheral.wrap(MONITOR_SIDE)
    if not monitor then
        if not lastMonitorError then print("Monitor not found: " .. MONITOR_SIDE .. "; retrying") end
        lastMonitorError = true
        return
    end
    local stats, problem = scanWithProgress(monitor)
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
        refresh()
        timer = os.startTimer(REFRESH_INTERVAL)
    elseif event == "monitor_resize" and value == MONITOR_SIDE
        or event == "peripheral" or event == "peripheral_detach" then
        refresh()
    end
end
