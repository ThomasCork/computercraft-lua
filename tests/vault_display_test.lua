local function check(value, message)
    if not value then error(message, 2) end
end

local function inventory(size, items, details)
    return {
        size = function() return size end,
        list = function() return items end,
        getItemDetail = function(slot)
            local detail = details[slot]
            if detail == false then error("detail unavailable") end
            return detail
        end,
    }
end

local function run(config)
    colors = { white = 1, black = 2, gray = 3, lightGray = 4, yellow = 5,
        red = 6, lime = 7, green = 8 }
    local framesByName = {}
    local width, height = config.width or 40, config.height or 15
    local function newMonitor(name)
        local frames = {}
        framesByName[name] = frames
        local x, y, foreground, background = 1, 1, colors.white, colors.black
        local screen
        local monitor = {}
        function monitor.getSize() return width, height end
        function monitor.setCursorPos(newX, newY) x, y = newX, newY end
        function monitor.setTextColor(color) foreground = color end
        function monitor.setBackgroundColor(color) background = color end
        function monitor.clear()
            screen = {}
            for row = 1, height do
                screen[row] = {}
                for column = 1, width do
                    screen[row][column] = { char = " ", bg = background }
                end
            end
            frames[#frames + 1] = screen
        end
        function monitor.write(value)
            check(y >= 1 and y <= height and x >= 1 and x + #value - 1 <= width,
                "write outside monitor")
            for i = 1, #value do
                screen[y][x] = { char = value:sub(i, i), fg = foreground, bg = background }
                x = x + 1
            end
        end
        return { kind = "monitor", device = monitor }
    end

    local devices = config.devices
    local initialMonitor = config.monitorName or "top"
    if not config.noMonitor then devices[initialMonitor] = newMonitor(initialMonitor) end
    peripheral = {}
    function peripheral.getNames()
        local names = {}
        for name in pairs(devices) do names[#names + 1] = name end
        return names
    end
    function peripheral.hasType(name, kind)
        return devices[name] ~= nil and devices[name].kind == kind
    end
    function peripheral.wrap(name)
        return devices[name] and devices[name].device
    end

    local time, timerId, eventIndex = 0, 0, 0
    os = {
        epoch = function() return time end,
        startTimer = function()
            timerId = timerId + 1
            return timerId
        end,
        cancelTimer = function() end,
        pullEvent = function()
            eventIndex = eventIndex + 1
            local event = config.events and config.events[eventIndex]
            if not event then error("test finished") end
            if event.action then event.action(devices, newMonitor) end
            if event.time then time = event.time end
            return table.unpack(event)
        end,
    }
    local ok, err = pcall(dofile, "lua/vault_display.lua")
    check(not ok and tostring(err):find("test finished", 1, true), tostring(err))
    return framesByName[initialMonitor] or {}, framesByName
end

local function frameText(frame)
    local lines = {}
    for _, row in ipairs(frame) do
        local chars = {}
        for _, cell in ipairs(row) do chars[#chars + 1] = cell.char end
        lines[#lines + 1] = table.concat(chars)
    end
    return table.concat(lines, "\n")
end

local function findFrame(frames, text, start)
    for i = start or 1, #frames do
        if frameText(frames[i]):find(text, 1, true) then return i end
    end
    local displays = {}
    for _, frame in ipairs(frames) do displays[#displays + 1] = frameText(frame) end
    error("display never contained: " .. text .. "\n" .. table.concat(displays, "\n---\n"))
end

local function device(value)
    return { kind = "create:item_vault", device = value }
end

local vaultA = inventory(10, {
    [1] = { count = 64 },
    [2] = { count = 3 },
}, { [1] = { maxCount = 64 }, [2] = { maxCount = 64 } })
local vaultB = inventory(5, { [1] = { count = 1 } }, { [1] = { maxCount = 1 } })
local unknown = inventory(4, { [1] = { count = 1 } }, { [1] = false })
local broken = { size = function() error("offline") end, list = function() return {} end }

local frames = run({
    height = 20,
    devices = {
        ["create:item_vault_9"] = device(vaultA),
        ["create:item_vault_2"] = device(vaultB),
        ["create:item_vault_3"] = device(unknown),
        ["create:item_vault_4"] = device(broken),
        chest = { kind = "minecraft:chest", device = vaultA },
    },
})
local result = frames[findFrame(frames, "Full: 1 Used: 2 Empty: 8")]
local display = frameText(result)
check(display:find("VAULTS: 4", 1, true), "wrong vault count")
check(display:find("Full: 1 Used: 1 Empty: 4", 1, true), "unstackable item not full")
check(display:find("Full: ? Used: 1 Empty: 3", 1, true), "unknown limit not shown")
check(display:find("Cannot read inventory:", 1, true), "vault failure not shown")
check(not display:find("chest", 1, true), "non-vault inventory included")
local foundBar = false
for _, row in ipairs(result) do
    local valid = true
    for column, cell in ipairs(row) do
        local expected = column <= 4 and colors.lime
            or (column <= 8 and colors.green or colors.gray)
        if cell.bg ~= expected then valid = false end
    end
    if valid then foundBar = true end
end
check(foundBar, "full, partial and empty bar segments are incorrect")

local devices = { ["create:item_vault_0"] = device(vaultA) }
frames = run({
    devices = devices,
    events = {
        { "peripheral_detach", "create:item_vault_0", action = function(items)
            items["create:item_vault_0"] = nil
        end },
        { "peripheral", "create:item_vault_12", action = function(items)
            items["create:item_vault_12"] = device(vaultB)
        end },
        { "monitor_touch", "top", 10, 15, action = function(items)
            items["create:item_vault_12"] = device(vaultA)
        end },
    },
})
local removed = findFrame(frames, "No item vaults found")
local added = findFrame(frames, "create:item_vault_12", removed + 1)
findFrame(frames, "Full: 1 Used: 2 Empty: 8", added + 1)

frames = run({
    width = 40, height = 7,
    devices = {
        ["create:item_vault_1"] = device(vaultA),
        ["create:item_vault_2"] = device(vaultB),
    },
    events = {
        { "monitor_touch", "top", 4, 7 },
        { "timer", 2, time = 11000 },
    },
})
local first = findFrame(frames, "create:item_vault_1")
check(frameText(frames[first]):find("Full: 1 Used: 2 Empty: 8", 1, true),
    "vault details split across pages unnecessarily")
local second = findFrame(frames, "create:item_vault_2", first + 1)
findFrame(frames, "create:item_vault_1", second + 1)

run({
    width = 1, height = 1,
    devices = { ["create:item_vault_1"] = device(vaultA) },
    events = { { "timer", 2, time = 11000 } },
})

frames = run({
    monitorName = "monitor_4",
    width = 40, height = 7,
    devices = {
        ["create:item_vault_1"] = device(vaultA),
        ["create:item_vault_2"] = device(vaultB),
    },
    events = {
        { "monitor_touch", "other_monitor", 4, 7 },
        { "monitor_touch", "monitor_4", 4, 7 },
        { "monitor_resize", "monitor_4" },
    },
})
local firstRemote = findFrame(frames, "create:item_vault_1")
local secondRemote = findFrame(frames, "create:item_vault_2", firstRemote + 1)
check(secondRemote == firstRemote + 1, "touch from another monitor affected display")
findFrame(frames, "create:item_vault_2", secondRemote + 1)

local _, monitorFrames = run({
    noMonitor = true,
    devices = { ["create:item_vault_1"] = device(vaultA) },
    events = {
        { "peripheral", "monitor_8", action = function(items, newMonitor)
            items["monitor_8"] = newMonitor("monitor_8")
        end },
        { "peripheral", "monitor_2", action = function(items, newMonitor)
            items["monitor_2"] = newMonitor("monitor_2")
        end },
        { "peripheral_detach", "monitor_8", action = function(items)
            items["monitor_8"] = nil
        end },
        { "peripheral_detach", "monitor_2", action = function(items)
            items["monitor_2"] = nil
        end },
        { "peripheral", "monitor_9", action = function(items, newMonitor)
            items["monitor_9"] = newMonitor("monitor_9")
        end },
    },
})
check(#monitorFrames["monitor_8"] >= 4, "existing monitor should stay selected on attach")
findFrame(monitorFrames["monitor_2"], "create:item_vault_1")
findFrame(monitorFrames["monitor_9"], "create:item_vault_1")

print("vault_display tests passed")
