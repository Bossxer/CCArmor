-- Armor Delivery UI System
-- Features: scrollable UI, GitHub JSON fetching, armor set caching, redstone + ME Bridge delivery, and return tracking

-- CONFIG -------------------------------
local sets = {}
local enableCaching = true
local preloadAllArmorSets = true
local armorCache = {}
local usedSets = {}
local scrollOffset = 0
local selectedSet = nil

local baseURL = "https://raw.githubusercontent.com/Bossxer/CCArmor/refs/heads/main/main/"
local setListURL = baseURL .. "ArmorSets.json"

-- PERIPHERALS --------------------------
local monitor = peripheral.find("monitor")
local speaker = peripheral.find("speaker")
local me = peripheral.find("meBridge")
local returnChest = peripheral.wrap("minecraft:chest_0")
local outputName = "top"

if not monitor then error("No monitor attached") end
if not speaker then error("No speaker attached") end
if not me then error("No ME Bridge connected") end
if not returnChest then error("No return chest connected") end

-- UTILITIES ----------------------------
local function center(text, width)
  local pad = math.floor((width - #text) / 2)
  return string.rep(" ", pad) .. text
end

local function fetchArmorSets()

if preloadAllArmorSets and enableCaching then
  print("📦 Preloading armor sets...")
  for _, set in ipairs(sets) do
    print("⏳ Caching: " .. set.name)
    fetchSetDetails(set.id)
  end
  print("✅ All sets preloaded.")
end
  print("🔄 Fetching armor set list...")
  local response = http.get(setListURL)
  if not response then
    error("❌ Failed to fetch ArmorSets.json from GitHub")
  end
  local content = response.readAll()
  response.close()
  local parsed = textutils.unserializeJSON(content)
  sets = parsed or {}
end

local function fetchSetDetails(setID)
  if enableCaching and armorCache[setID] then
    return armorCache[setID]
  end
  local url = baseURL .. setID .. ".json"
  local response = http.get(url)
  if not response then
    error("❌ Failed to fetch set details: " .. url)
  end
  local data = textutils.unserializeJSON(response.readAll())
  response.close()
  if enableCaching then
    armorCache[setID] = data
  end
  return data
end

local function playDeliverySound()
  speaker.playNote("pling", 1.0, 12)
  sleep(0.1)
  speaker.playNote("pling", 1.0, 16)
end

local function triggerRedstonePulse()
  redstone.setOutput("front", true)
  sleep(1)
  redstone.setOutput("front", false)
end

local function drawUI(selected)
  monitor.clear()
  monitor.setCursorPos(1, 1)
  local w, h = monitor.getSize()
  monitor.setTextScale(1)
  monitor.setTextColor(colors.white)
  monitor.setBackgroundColor(colors.black)

  monitor.setCursorPos(1, 1)
  monitor.write(center("Select Armor Set", w))

  local maxVisible = h - 5
  for i = 1, math.min(#sets - scrollOffset, maxVisible) do
    local index = i + scrollOffset
    local set = sets[index]
    monitor.setCursorPos(2, i + 1)
    if selected == index then
      monitor.setTextColor(colors.yellow)
    elseif usedSets[index] then
      monitor.setTextColor(colors.gray)
    else
      monitor.setTextColor(colors.white)
    end
    monitor.write(index .. ". " .. set.name)
  end

  monitor.setTextColor(colors.lime)
  monitor.setCursorPos(2, h - 2)
  monitor.write("[ Refresh Armor Sets ]")

  monitor.setTextColor(colors.orange)
  monitor.setCursorPos(2, h - 1)
  monitor.write("[ Return Armor to AE ]")

  monitor.setTextColor(colors.lightBlue)
  monitor.setCursorPos(w - 10, h)
  monitor.write("[ Scroll Up ]")
  monitor.setCursorPos(2, h)
  monitor.write("[ Scroll Down ]")
end

local function returnItemsToAE()
  local chestItems = returnChest.list()
  local namesInChest = {}

  for slot, item in pairs(chestItems) do
    table.insert(namesInChest, item.name)
    me.importItem({ name = item.name }, "south", item.count)
    print("🔁 Returned: " .. item.name .. " x" .. item.count)
  end

  for i, set in ipairs(sets) do
    local armor = fetchSetDetails(set.id)
    local needed = {
      armor.helmet,
      armor.chestplate,
      armor.leggings,
      armor.boots
    }

    local allFound = true
    for _, piece in ipairs(needed) do
      local found = false
      for _, name in ipairs(namesInChest) do
        if piece == name then
          found = true
          break
        end
      end
      if not found then
        allFound = false
        break
      end
    end

    if allFound then
      usedSets[i] = nil
      print("♻ " .. set.name .. " is now available again.")
    end
  end

  playDeliverySound()
end

-- MAIN ------------------------------
fetchArmorSets()

while true do
  drawUI(selectedSet)
  local event, side, x, y = os.pullEvent("monitor_touch")
  local w, h = monitor.getSize()
  local maxVisible = h - 5

  if y == h - 2 then
    fetchArmorSets()
    playDeliverySound()
    selectedSet = nil
  elseif y == h - 1 then
    returnItemsToAE()
    selectedSet = nil
  elseif y == h and x <= 16 then
    if scrollOffset + maxVisible < #sets then
      scrollOffset = scrollOffset + 1
    end
  elseif y == h and x > w - 11 then
    if scrollOffset > 0 then
      scrollOffset = scrollOffset - 1
    end
  else
    for i = 1, math.min(#sets - scrollOffset, maxVisible) do
      if y == i + 1 then
        local index = i + scrollOffset
        if usedSets[index] then
          print("⚠ " .. sets[index].name .. " already requested.")
        else
          selectedSet = index
          local chosenMeta = sets[index]
          drawUI(selectedSet)
          print("Delivering: " .. chosenMeta.name)
          local chosen = fetchSetDetails(chosenMeta.id)
          for _, itemName in ipairs({chosen.helmet, chosen.chestplate, chosen.leggings, chosen.boots}) do
            local pulled = me.exportItem({ name = itemName }, outputName, 1)
            if pulled > 0 then
              print("✔ Exported: " .. itemName)
            else
              print("❌ Failed to export: " .. itemName)
            end
          end
          playDeliverySound()
          triggerRedstonePulse()
          usedSets[index] = true
          sleep(1.5)
          selectedSet = nil
        end
      end
    end
  end
end
