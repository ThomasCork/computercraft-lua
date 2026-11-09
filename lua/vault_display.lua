-- ================= CONFIGURATION =================
local MONITOR_SIDE = "top"               -- Your monitor peripheral name/side
local VAULT_NAME = "create:item_vault_0" -- Your exact vault peripheral name
-- ===================================================

local args = { ... }
-- Defaults to 54 blocks based on your setup, or change via command line (e.g. "vault 54")
local VAULT_BLOCKS = tonumber(args[1]) or 54 

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

-- Helper function to draw a chunky, 2-line tall split progress bar (Green used / Red unused)
local function drawTallProgressBar(x, startY, width, fillPercent)
    if width < 5 then return end
    
    local filledChars = math.floor((width * fillPercent) / 100)
    local emptyChars = width - filledChars
    
    -- Draw top row of the thick bar
    monitor.setCursorPos(x, startY)
    if filledChars > 0 then
        monitor.setBackgroundColor(colors.green)
        monitor.write(string.rep(" ", filledChars))
    end
    if emptyChars > 0 then
        monitor.setBackgroundColor(colors.red)
        monitor.write(string.rep(" ", emptyChars))
    end
    
    -- Draw bottom row of the thick bar
    monitor.setCursorPos(x, startY + 1)
    if filledChars > 0 then
        monitor.setBackgroundColor(colors.lime)
        monitor.write(string.rep(" ", filledChars))
    end
    if emptyChars > 0 then
        monitor.setBackgroundColor(colors.brown) -- Darker red/brown hue for depth
        monitor.write(string.rep(" ", emptyChars))
    end
    
    monitor.setBackgroundColor(colors.black)
end

while true do
    monitor.clear()
    
    local screenWidth, screenHeight = monitor.getSize()
    local maxCapacitySlots = VAULT_BLOCKS * 20
    
    -- Scan vault contents
    local items = vault.list()
    local usedSlots = 0
    local totalIndividualItems = 0
    local uniqueTypes = 0
    
    for slot, item in pairs(items) do
        usedSlots = usedSlots + 1
        totalIndividualItems = totalIndividualItems + item.count
        uniqueTypes = uniqueTypes + 1
    end
    
    if usedSlots > maxCapacitySlots then
        usedSlots = maxCapacitySlots
    end
    
    local freeSlots = maxCapacitySlots - usedSlots
    local fillPercent = math.min(100, (usedSlots / maxCapacitySlots) * 100)
    local fillPercentRounded = math.floor(fillPercent + 0.5)
    
    -- ================= UI RENDERING =================
    
    -- 1. Distinct Header Section (Solid Background Banner)
    monitor.setBackgroundColor(colors.gray)
    monitor.setCursorPos(1, 1)
    monitor.write(string.rep(" ", screenWidth))
    monitor.setCursorPos(1, 2)
    monitor.write(string.rep(" ", screenWidth))
    
    local title = "CREATE STORAGE VAULT"
    local titleX = math.floor((screenWidth - string.len(title)) / 2) + 1
    monitor.setCursorPos(titleX, 1)
    monitor.setTextColor(colors.yellow)
    monitor.write(title)
    
    local subTitle = "SYSTEM MONITOR"
    local subX = math.floor((screenWidth - string.len(subTitle)) / 2) + 1
    monitor.setCursorPos(subX, 2)
    monitor.setTextColor(colors.lightGray)
    monitor.write(subTitle)
    
    monitor.setBackgroundColor(colors.black)
    
    -- 2. Core Stats Section
    local leftMargin = 3
    
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
    
    -- Green (Used Slots) / Red (Total Max Slots)
    monitor.setCursorPos(leftMargin, 5)
    monitor.setTextColor(colors.white)
    monitor.write("Capacity:    ")
    monitor.setTextColor(colors.green)
    monitor.write(formatNumber(usedSlots) .. " stacks")
    monitor.setTextColor(colors.lightGray)
    monitor.write(" / ")
    monitor.setTextColor(colors.red)
    monitor.write(formatNumber(maxCapacitySlots) .. " max")
    
    monitor.setCursorPos(leftMargin, 6)
    monitor.setTextColor(colors.white)
    monitor.write("Total Items: ")
    monitor.setTextColor(colors.yellow)
    monitor.write(formatNumber(totalIndividualItems) .. " items")
    
    monitor.setCursorPos(leftMargin, 7)
    monitor.setTextColor(colors.white)
    monitor.write("Unique Types:")
    monitor.setTextColor(colors.cyan)
    monitor.write(" " .. formatNumber(uniqueTypes) .. " types")
    
    -- 3. Extended Analytics Section
    monitor.setCursorPos(leftMargin, 9)
    monitor.setTextColor(colors.lightGray)
    monitor.write("--- EXTENDED ANALYTICS ---")
    
    monitor.setCursorPos(leftMargin, 10)
    monitor.setTextColor(colors.white)
    monitor.write("Free Space:   ")
    monitor.setTextColor(colors.lime)
    monitor.write(formatNumber(freeSlots) .. " stacks")
    
    monitor.setCursorPos(leftMargin, 11)
    monitor.setTextColor(colors.white)
    monitor.write("Vault Size:   ")
    monitor.setTextColor(colors.lightGray)
    monitor.write(VAULT_BLOCKS .. " blocks")
    
    -- 4. Thick 2-Line Progress Bar at the bottom
    local barWidth = screenWidth - 6
    if screenHeight >= 15 and barWidth > 5 then
        drawTallProgressBar(3, 13, barWidth, fillPercent)
        
        -- Percentage indicators underneath the chunky bar
        monitor.setCursorPos(3, 16)
        monitor.setTextColor(colors.green)
        monitor.write("0%")
        
        local pText = fillPercentRounded .. "% Full"
        monitor.setCursorPos(math.floor((screenWidth - string.len(pText)) / 2) + 1, 16)
        monitor.setTextColor(colors.white)
        monitor.write(pText)
        
        monitor.setCursorPos(screenWidth - 3, 16)
        monitor.setTextColor(colors
