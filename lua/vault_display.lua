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

local function drawFooter(monitor, progress, frame)
    local width, height = monitor.getSize()
    if height < 1 then return end

    local text
    local foreground = colors.lightGray
    if progress.problem then
        text = "Update failed: " .. progress.problem
        foreground = colors.red
    elseif progress.done then
        text = "Up to date"
        foreground = colors.lime
    elseif progress.total > 0 then
        local percent = math.floor(progress.processed / progress.total * 100)
        text = string.format("%s %d%%  %s/%s slots", progress.phase, percent,
            formatNumber(progress.processed), formatNumber(progress.total))
        foreground = colors.yellow
    else
        local spinner = { "|", "/", "-", "\\" }
        text = "Checking vault " .. spinner[frame % #spinner + 1]
        foreground = colors.yellow
    end

    local textRow = height >= 2 and height - 1 or height
    monitor.setCursorPos(1, textRow)
    monitor.setTextColor(foreground)
    monitor.setBackgroundColor(colors.black)
    text = text:sub(1, width)
    monitor.write(text .. string.rep(" ", width - #text))
    if height >= 2 then
        local filled = 0
        if progress.total > 0 and not progress.done then
            filled = math.floor(width * progress.processed / progress.total)
        elseif progress.done and not progress.problem then
            filled = width
        end
        monitor.setCursorPos(1, height)
        monitor.setBackgroundColor(colors.lime)
        monitor.write(string.rep(" ", filled))
        monitor.setBackgroundColor(colors.gray)
        monitor.write(string.rep(" ", width - filled))
    end
    monitor.setBackgroundColor(colors.black)
end

local function drawFirstScanSpinner(monitor, frame)
    local width, height = monitor.getSize()
    local contentHeight = math.max(0, height - 2)
    if width < 1 or contentHeight < 1 then return end

    local spinner = { "|", "/", "-", "\\" }
    local message = "Waiting for first inventory scan [" .. spinner[frame % #spinner + 1] .. "]"
    local messageY = math.min(3, contentHeight)
    local messageX = math.max(1, math.floor((width - #message) / 2) + 1)
    monitor.setCursorPos(1, messageY)
    monitor.setTextColor(colors.yellow)
    monitor.setBackgroundColor(colors.black)
    monitor.write(string.rep(" ", width))
    monitor.setCursorPos(messageX, messageY)
    monitor.write(message:sub(1, width - messageX + 1))

    local centerX = math.floor((width + 1) / 2)
    local centerY = math.floor((contentHeight + 1) / 2)
    local positions = {
        { -2, -1 }, { 0, -1 }, { 2, -1 }, { 2, 0 },
        { 2, 1 }, { 0, 1 }, { -2, 1 }, { -2, 0 },
    }

    if width >= 5 and contentHeight >= 3 then
        for i, position in ipairs(positions) do
            local x, y = centerX + position[1], centerY + position[2]
            monitor.setCursorPos(x, y)
            monitor.setTextColor(i == frame % #positions + 1 and colors.lime or colors.gray)
            monitor.write(i == frame % #positions + 1 and "*" or ".")
        end
        monitor.setCursorPos(centerX, centerY)
        monitor.setTextColor(colors.yellow)
        monitor.write("+")
    else
        monitor.setCursorPos(centerX, centerY)
        monitor.setTextColor(colors.lime)
        monitor.write(spinner[frame % #spinner + 1])
    end

    monitor.setBackgroundColor(colors.black)
end

local function draw(monitor, stats, problem, progress)
    local width, height = monitor.getSize()
    local contentHeight = math.max(0, height - 2)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    local function row(y, text, foreground, background)
        if y < 1 or y > contentHeight then return end
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
    if problem and not stats then
        wrapped(3, problem, colors.red)
        wrapped(4, "Check connection; retrying", colors.lightGray)
        drawFooter(monitor, progress, 0)
        return
    elseif not stats then
        drawFirstScanSpinner(monitor, progress.frame or 0)
        drawFooter(monitor, progress, 0)
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

    if y <= contentHeight then
        drawBarRow(y)
        if y + 1 <= contentHeight then drawBarRow(y + 1) end
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
    drawFooter(monitor, progress, 0)
end

local lastMonitorError
local cachedStats
local cachedSnapshot
local stackLimitCache = {}

local function scanWithProgress(monitor, progress)
    progress.phase = "Reading vault"
    progress.processed = 0
    progress.total = 0
    progress.done = false
    progress.problem = nil

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
            if monitor then
                if not cachedStats then
                    progress.frame = frame
                    pcall(drawFirstScanSpinner, monitor, frame)
                end
                pcall(drawFooter, monitor, progress, frame)
            end
            frame = frame + 1
            sleep(0.25)
        end
    end

    drawFooter(monitor, progress, 0)
    parallel.waitForAny(scan, showProgress)
    if progress.problem then return nil, nil, progress.problem end
    return stats, snapshot
end

local function refresh()
    local monitor = peripheral.wrap(MONITOR_SIDE)
    if not monitor then
        if not lastMonitorError then print("Monitor not found: " .. MONITOR_SIDE .. "; retrying") end
        lastMonitorError = true
        return
    end
    local progress = { phase = "Reading vault", processed = 0, total = 0, done = false }
    local ok, drawError = pcall(draw, monitor, cachedStats, nil, progress)
    if not ok then
        if not lastMonitorError then
            print("Cannot draw vault display: " .. tostring(drawError))
        end
        lastMonitorError = true
    end

    local stats, snapshot, problem = scanWithProgress(monitor, progress)
    if stats then
        cachedStats = stats
        cachedSnapshot = snapshot
    end
    progress.done = true
    progress.problem = problem
    local drawOk, err = pcall(draw, monitor, cachedStats, problem, progress)
    if not drawOk then
        if not lastMonitorError then print("Cannot draw to monitor: " .. tostring(err)) end
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
