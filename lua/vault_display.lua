-- ================= CONFIGURATION =================
local REFRESH_INTERVAL = 120    -- Seconds between inventory scans
local PAGE_INTERVAL = 10        -- Seconds between display pages
-- ===================================================

local VAULT_TYPE = "create:item_vault"
local MONITOR_TYPE = "monitor"
local CONTROLS = "[<][>][REFRESH]"
local SHORT_CONTROLS = "[>][R]"

local vaults = {}
local discoveryProblem
local lastRefreshAt
local monitorError = false
local monitorName
local page = 1
local pageCount = 1
local lastPageAt = 0

local function formatNumber(amount)
    local formatted = tostring(amount)
    while true do
        local replacements
        formatted, replacements = formatted:gsub("^(-?%d+)(%d%d%d)", "%1,%2")
        if replacements == 0 then return formatted end
    end
end

local function readVault(name)
    local vault = peripheral.wrap(name)
    if not vault then return nil, "Vault disconnected" end
    if type(vault.size) ~= "function" or type(vault.list) ~= "function" then
        return nil, "Inventory size or list method unavailable"
    end

    local ok, capacity, items = pcall(function()
        return vault.size(), vault.list()
    end)
    if not ok then return nil, "Cannot read inventory: " .. tostring(capacity) end
    if type(capacity) ~= "number" or capacity <= 0 or capacity % 1 ~= 0
        or type(items) ~= "table" then
        return nil, "Invalid inventory capacity or contents"
    end

    local stats = { capacity = capacity, used = 0, full = 0, fullKnown = true }
    for slot, item in pairs(items) do
        if type(slot) ~= "number" or slot % 1 ~= 0 or slot < 1 or slot > capacity
            or type(item) ~= "table" or type(item.count) ~= "number"
            or item.count <= 0 then
            return nil, "Invalid inventory slot or item count"
        end
        stats.used = stats.used + 1

        local limit = item.maxCount
        if (type(limit) ~= "number" or limit <= 0)
            and type(vault.getItemDetail) == "function" then
            local detailOk, detail = pcall(vault.getItemDetail, slot)
            if detailOk and type(detail) == "table" then limit = detail.maxCount end
        end
        if type(limit) ~= "number" or limit <= 0 then
            stats.fullKnown = false
        elseif item.count >= limit then
            stats.full = stats.full + 1
        end
    end
    return stats
end

local function scanVaults()
    local results = {}
    local problems = {}
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        local ok, isVault = pcall(peripheral.hasType, name, VAULT_TYPE)
        if not ok then
            problems[#problems + 1] = "Cannot identify " .. name .. ": " .. tostring(isVault)
        elseif isVault then
            local scanOk, stats, problem = pcall(readVault, name)
            if not scanOk then
                problem = "Scan failed: " .. tostring(stats)
                stats = nil
            end
            results[#results + 1] = { name = name, stats = stats, problem = problem }
        end
    end
    return results, #problems > 0 and table.concat(problems, "; ") or nil
end

local function layout(height)
    local header = height >= 4 and 1 or 0
    local footer = height >= 4 and 2 or (height >= 2 and 1 or 0)
    return header, height - header - footer, footer
end

local function makePages(width, contentHeight)
    local groups = {}
    local rows

    local function startGroup()
        rows = {}
        groups[#groups + 1] = rows
    end

    local function text(value, color)
        while #value > width do
            local split = value:sub(1, width):match("^.*() ")
            if not split or split == 1 then split = width + 1 end
            rows[#rows + 1] = { text = value:sub(1, split - 1), color = color }
            value = value:sub(split):gsub("^ +", "")
        end
        if #value > 0 then rows[#rows + 1] = { text = value, color = color } end
    end

    if #vaults == 0 and not discoveryProblem then
        startGroup()
        text("No item vaults found. Check the wired connection.", colors.yellow)
    end
    if discoveryProblem then
        startGroup()
        text(discoveryProblem, colors.red)
    end

    for _, vault in ipairs(vaults) do
        startGroup()
        text(vault.name, colors.white)
        local stats = vault.stats
        if not stats then
            text(vault.problem or "Vault scan failed", colors.red)
        else
            local empty = stats.capacity - stats.used
            if stats.fullKnown then
                text("Full: " .. formatNumber(stats.full)
                    .. " Used: " .. formatNumber(stats.used)
                    .. " Empty: " .. formatNumber(empty), colors.lightGray)
            else
                text("Full: ? Used: " .. formatNumber(stats.used)
                    .. " Empty: " .. formatNumber(empty), colors.yellow)
            end
            rows[#rows + 1] = { stats = stats }
        end
    end

    local pages = { {} }
    for _, group in ipairs(groups) do
        local current = pages[#pages]
        if #group <= contentHeight and #current > 0
            and #current + #group > contentHeight then
            current = {}
            pages[#pages + 1] = current
        end
        for _, row in ipairs(group) do
            if #current == contentHeight then
                current = {}
                pages[#pages + 1] = current
            end
            current[#current + 1] = row
        end
    end
    return pages
end

local function draw(monitor, status, footerOnly)
    local width, height = monitor.getSize()
    if width < 1 or height < 1 then return end
    local header, contentHeight, footer = layout(height)
    local pages = makePages(width, contentHeight)
    pageCount = #pages
    page = math.max(1, math.min(page, pageCount))
    local rows = pages[page]

    if not footerOnly then
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.clear()
    end

    local function writeRow(y, value, color, background)
        monitor.setCursorPos(1, y)
        monitor.setTextColor(color or colors.white)
        monitor.setBackgroundColor(background or colors.black)
        value = value:sub(1, width)
        monitor.write(value .. string.rep(" ", width - #value))
    end

    if not footerOnly and header > 0 then
        writeRow(1, "VAULTS: " .. #vaults .. "  Page " .. page .. "/" .. pageCount,
            colors.white, colors.gray)
    end

    for offset = 0, (footerOnly and -1 or contentHeight - 1) do
        local row = rows[offset + 1]
        if row then
            local y = header + offset + 1
            if row.text then
                writeRow(y, row.text, row.color)
            else
                local stats = row.stats
                local full = stats.fullKnown and stats.full or 0
                local fullWidth = math.floor(width * full / stats.capacity)
                local usedWidth = math.floor(width * stats.used / stats.capacity)
                monitor.setCursorPos(1, y)
                monitor.setBackgroundColor(colors.lime)
                monitor.write(string.rep(" ", fullWidth))
                monitor.setBackgroundColor(colors.green)
                monitor.write(string.rep(" ", usedWidth - fullWidth))
                monitor.setBackgroundColor(colors.gray)
                monitor.write(string.rep(" ", width - usedWidth))
            end
        end
    end

    if footer == 2 then
        local message = status
        local color = colors.yellow
        if not message then
            if lastRefreshAt then
                local seconds = math.max(0, math.floor((os.epoch("utc") - lastRefreshAt) / 1000))
                message = string.format("Updated %dm %02ds ago", math.floor(seconds / 60),
                    seconds % 60)
                color = discoveryProblem and colors.red or colors.lightGray
            else
                message = "Waiting for scan"
            end
        end
        writeRow(height - 1, message, color)
    end
    if footer > 0 then
        local controls = width >= #CONTROLS and CONTROLS
            or (width >= #SHORT_CONTROLS and SHORT_CONTROLS or ">")
        writeRow(height, controls, colors.white, colors.gray)
    end
    monitor.setBackgroundColor(colors.black)
end

local function findMonitor()
    if monitorName and peripheral.hasType(monitorName, MONITOR_TYPE) then
        local monitor = peripheral.wrap(monitorName)
        if monitor then return monitor end
    end

    monitorName = nil
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        if peripheral.hasType(name, MONITOR_TYPE) then
            local monitor = peripheral.wrap(name)
            if monitor then
                monitorName = name
                return monitor
            end
        end
    end
end

local function show(status, footerOnly)
    local previousName = monitorName
    local found, monitor = pcall(findMonitor)
    if not found then
        if not monitorError then print("Cannot discover monitor: " .. tostring(monitor)) end
        monitorError = true
        return
    end
    if not monitor then
        if not monitorError then print("No connected monitor found; retrying") end
        monitorError = true
        return
    end
    if monitorError or previousName ~= monitorName then footerOnly = false end
    local ok, problem = pcall(draw, monitor, status, footerOnly)
    if not ok then
        if not monitorError then print("Cannot draw vault display: " .. tostring(problem)) end
        monitorError = true
    else
        monitorError = false
    end
end

local function refresh()
    show("Scanning vaults...")
    local ok, results, problem = pcall(scanVaults)
    if ok then
        vaults = results
        discoveryProblem = problem
        lastRefreshAt = os.epoch("utc")
    else
        discoveryProblem = "Discovery failed: " .. tostring(results)
        print(discoveryProblem)
    end
    page = 1
    lastPageAt = os.epoch("utc")
    show()
end

refresh()
local timer = os.startTimer(REFRESH_INTERVAL)
local clock = os.startTimer(1)
while true do
    local event, value, x, y = os.pullEvent()
    if event == "timer" and value == timer then
        refresh()
        timer = os.startTimer(REFRESH_INTERVAL)
    elseif event == "timer" and value == clock then
        local pageChanged = false
        if pageCount > 1 and os.epoch("utc") - lastPageAt >= PAGE_INTERVAL * 1000 then
            page = page % pageCount + 1
            lastPageAt = os.epoch("utc")
            pageChanged = true
        end
        show(nil, not pageChanged)
        clock = os.startTimer(1)
    elseif event == "peripheral" or event == "peripheral_detach" then
        if event == "peripheral_detach" and value == monitorName then
            monitorName = nil
        end
        os.cancelTimer(timer)
        refresh()
        timer = os.startTimer(REFRESH_INTERVAL)
    elseif event == "monitor_resize" and value == monitorName then
        show()
    elseif event == "monitor_touch" and value == monitorName then
        local monitor = peripheral.wrap(monitorName)
        if monitor then
            local width, height = monitor.getSize()
            local _, _, footer = layout(height)
            if footer > 0 and y == height then
                local refreshPressed = width >= #CONTROLS and x >= 7 and x <= #CONTROLS
                    or (width >= #SHORT_CONTROLS and width < #CONTROLS and x >= 4
                        and x <= #SHORT_CONTROLS)
                if refreshPressed then
                    os.cancelTimer(timer)
                    refresh()
                    timer = os.startTimer(REFRESH_INTERVAL)
                else
                    if width >= #CONTROLS and x <= 3 then
                        page = (page - 2) % pageCount + 1
                    elseif width < #CONTROLS or x <= 6 then
                        page = page % pageCount + 1
                    end
                    lastPageAt = os.epoch("utc")
                    show()
                end
            end
        end
    end
end
