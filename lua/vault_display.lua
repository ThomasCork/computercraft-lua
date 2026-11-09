-- ================= CONFIGURATION =================
local MONITOR_SIDE = "top"               -- Your monitor peripheral name/side
local VAULT_NAME = "create:item_vault_0" -- Your exact vault peripheral name
local STACK_SIZE = 64                    -- Standard max stack size
-- ===================================================

local args = { ... }
local VAULT_BLOCKS = tonumber(args[1]) or 1

local monitor = peripheral.wrap(MONITOR_SIDE)
local vault = peripheral.wrap(VAULT_NAME)

if not monitor then
    print("Error: Monitor not found on '" .. MONITOR_SIDE .. "'!")
    return
end

if not vault then
    print("Error: Vault not found at '" .. VAULT_NAME .. "'!")
    return
end

-- Helper function to format numbers with commas
local function formatNumber(amount)
    local formatted = tostring(amount)
    while true do  
        local k
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if (k == 0) then break end
    end
    return formatted
end

-- Helper function to draw a dual-colored progress bar (Green used / Red unused)
local function drawSplitProgressBar(x, y, width, fillPercent)
    if width < 5 then return end
    
    local filledChars = math.floor((width * fillPercent) / 100)
    local emptyChars = width - filledChars
    
    monitor.setCursorPos(x, y)
    
    if filledChars > 0 then
        monitor.setBackgroundColor(colors.green)
        monitor.write(string.rep(" ", filledChars))
    end
    
    if emptyChars > 0 then
        monitor.setBackgroundColor(colors.red)
        monitor.write(string.rep(" ", emptyChars))
    end
    
    monitor.setBackgroundColor(colors.black)
end

while true do
    monitor.clear()
    
    -- Dynamically grab current screen width and height on every loop
    local screenWidth, screenHeight = monitor.getSize()
    local maxCapacityItems = VAULT_BLOCKS * 20 * STACK_SIZE
    
    -- Scan vault contents
    local items = vault.list()
    local totalItems = 0
    local uniqueTypes = 0
    
    for slot, item in pairs(items) do
        totalItems = totalItems + item.count
        uniqueTypes = uniqueTypes + 1
    end
    
    if totalItems > maxCapacityItems then
        totalItems = maxCapacityItems
    end
    
    local freeSpace = maxCapacityItems - totalItems
    local fillPercent = math.min(100, (totalItems / maxCapacityItems) * 100)
    local fillPercentRounded = math.floor(fillPercent + 0.5)
    local avgStackSize = uniqueTypes > 0 and math.floor(totalItems / uniqueTypes) or 0
    
    -- --- HEADER ---
    local title = "=== CREATE STORAGE VAULT ==="
    local titleX = math.max(1, math.floor((screenWidth - string.len(title)) / 2) + 1)
    monitor.setCursorPos(titleX, 1)
    monitor.setTextColor(colors.cyan)
    monitor.write(title)
    
    monitor.setCursorPos(2, 2)
    monitor.setTextColor(colors.lightGray)
    monitor.write(string.rep("-", screenWidth - 2))
    
    local leftMargin = 3
    
    -- --- CORE STATS (Always Shown) ---
    monitor.setCursorPos(leftMargin, 4)
    monitor.setTextColor(colors.white)
    monitor.write("Status:      ")
    if fillPercentRounded >= 95 then
        monitor.setTextColor(colors.red)
        monitor.write("CRITICAL (" .. fillPercentRounded .. "%)")
    elseif fillPercentRounded >= 80 then
        monitor.setTextColor(colors.orange)
        monitor.write("WARNING (" .. fillPercentRounded .. "%)")
    else
        monitor.setTextColor(colors.lime)
        monitor.write("OPTIMAL (" .. fillPercentRounded .. "%)")
    end
    
    -- Green (Used) / Red (Unused) Capacity Request
    monitor.setCursorPos(leftMargin, 5)
    monitor.setTextColor(colors.white)
    monitor.write("Capacity:    ")
    monitor.setTextColor(colors.green)
    monitor.write(formatNumber(totalItems))
    monitor.setTextColor(colors.lightGray)
    monitor.write(" / ")
    monitor.setTextColor(colors.red)
    monitor.write(formatNumber(maxCapacityItems))
    
    monitor.setCursorPos(leftMargin, 6)
    monitor.setTextColor(colors.white)
    monitor.write("Unique Types: ")
    monitor.setTextColor(colors.yellow)
    monitor.write(formatNumber(uniqueTypes) .. " items")
    
    -- --- EXPANDED STATS (Unlocks automatically on taller/larger monitors like 4x3) ---
    if screenHeight >= 11 then
        monitor.setCursorPos(leftMargin, 8)
        monitor.setTextColor(colors.lightGray)
        monitor.write("--- EXTENDED ANALYTICS ---")
        
        monitor.setCursorPos(leftMargin, 9)
        monitor.setTextColor(colors.white)
        monitor.write("Free Space:   ")
        monitor.setTextColor(colors.lime)
        monitor.write(formatNumber(freeSpace) .. " items")
        
        monitor.setCursorPos(leftMargin, 10)
        monitor.setTextColor(colors.white)
        monitor.write("Avg Stack:    ")
        monitor.setTextColor(colors.cyan)
        monitor.write(formatNumber(avgStackSize) .. " / stack")
        
        monitor.setCursorPos(leftMargin, 11)
        monitor.setTextColor(colors.white)
        monitor.write("Vault Size:   ")
        monitor.setTextColor(colors.lightGray)
        monitor.write(VAULT_BLOCKS .. " blocks")
        
        -- Progress Bar position for larger screens
        local barWidth = screenWidth - 6
        if screenHeight >= 14 and barWidth > 5 then
            drawSplitProgressBar(3, 13, barWidth, fillPercent)
            
            monitor.setCursorPos(leftMargin, 14)
            monitor.setTextColor(colors.lightGray)
            monitor.write("0%")
            monitor.setCursorPos(screenWidth - 4, 14)
            monitor.write("100%")
        end
    else
        -- Compact progress bar for smaller screens
        local barWidth = screenWidth - 6
        if screenHeight >= 9 and barWidth > 5 then
            drawSplitProgressBar(3, 9, barWidth, fillPercent)
        end
    end
    
    monitor.setTextColor(colors.white)
    sleep(2)
end
