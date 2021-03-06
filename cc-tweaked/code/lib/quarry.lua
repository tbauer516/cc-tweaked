local m = {}

--## Variables to track state ##--
m.t = nil -- placeholder for "t" module to go

m.quarryLength = 1
m.quarryWidth = 1

m.junkSlot = 15
m.junkLimit = 10

m.blacklist = {}

m.continueMining = 1

m.blocksMined = 0

m.initialLoc = nil

--## Helper Functions ##--

m.setQuarrySize = function(self, length, width)
  self.quarryLength = length
  self.quarryWidth = width
end

m.checkForBlacklist = function(self, blacklistName)
  local blistPath = "blacklist/"
  if (fs.exists("disk/")) then
    blistPath = "disk/" .. blistPath
  end
  if (blacklistName ~= nil) then
    if (fs.exists(blistPath .. blacklistName .. ".blist")) then
      local handle = fs.open(blistPath .. blacklistName .. ".blist", "r")
      local blacklistText = handle.readAll()
      self.blacklist = textutils.unserialize(blacklistText)
      handle.close()
    end
  else
    if (fs.exists(blistPath .. "default.blist")) then
      local handle = fs.open(blistPath .. "default.blist", "r")
      local blacklistText = handle.readAll()
      self.blacklist = textutils.unserialize(blacklistText)
      handle.close()
    end
  end
end

m.scanHelper = function(self, detectFunc, inspectFunc)
  if (detectFunc()) then
    local success, data = inspectFunc()
    for i = 1, #self.blacklist do
      if (self.blacklist[i] == data["name"]) then
        return false
      end
    end
    return true
  end
end

--## Public Functions ##--

m.scanU = function(self)
  if (self:scanHelper(turtle.detectUp, turtle.inspectUp)) then
    turtle.digUp()
    return true
  end
  return false
end
m.scanD = function(self)
  if (self:scanHelper(turtle.detectDown, turtle.inspectDown)) then
    turtle.digDown()
    return true
  end
  return false
end

m.burrow = function(self)
  self.t:mineD()
  self.t:mineD()
  turtle.select(self.junkSlot)
  turtle.placeUp()
  turtle.select(self.junkSlot)
  self.t:mineD()
  self:scanD()
end

m.returnToSurface = function(self)
  self.t:setStatus("Returning to surface")
  turtle.select(self.junkSlot)
  self.t.maxLoc = self.t:getLoc()
  local vertical = self.t:getLoc()
  vertical.y = self.initialLoc.y
  self.t:checkFuel(vertical)
  
  self.t:moveTo(vertical)
  turtle.select(self.junkSlot)
  turtle.placeDown()
  turtle.select(self.junkSlot)
  
  self.t:setStatus("Moving to home")
  self.t:cruiseTo(self.t.homeLoc)
end

m.returnToMine = function(self)
  self.t:setStatus("Returning to mine location")
  local vertical = self.t:copyLoc(self.t.maxLoc)
  vertical.y = self.initialLoc.y
  self.t:cruiseTo(vertical)
  self.t:checkFuel(self.t.maxLoc)
  turtle.select(self.junkSlot)
  self.t:mineD()
  self.t:mineD()
  turtle.select(self.junkSlot)
  turtle.placeUp()

  self.t:setStatus("Tunneling to previous location")
  self.t:moveTo(self.t.maxLoc)
  self.t:setStatus("Mining")
end

m.consolidate = function(self)
  for i = 1, self.junkSlot - 1 do
    local details = turtle.getItemDetail(i)
    if (details ~= nil) then
      for j = 1, #self.blacklist do
        if (details["name"] == self.blacklist[j]) then
          turtle.select(i)
          turtle.dropDown()
        end
      end
      if (turtle.getItemCount(i) > 0) then
        turtle.transferTo(self.t.fuelSlot)
      end
    end
  end
  local count = turtle.getItemCount(self.junkSlot)
  if (count > self.junkLimit) then
    turtle.select(self.junkSlot)
    turtle.dropDown(count - self.junkLimit)
  end
  turtle.select(self.junkSlot)
end

m.dumpItems = function(self)
  self:consolidate()
  for i = 1, self.junkSlot - 1 do
    turtle.select(i)
    self.blocksMined = self.blocksMined + turtle.getItemCount()
    turtle.drop()
  end
  turtle.select(self.junkSlot)
end

m.storageFull = function(self)
  return turtle.getItemCount(self.junkSlot - 1) > 0
end

m.checkStorage = function(self)
  if (self:storageFull()) then
    self:returnToSurface()
    self:dumpItems()
    self:returnToMine()
  end
end

--## Runtime Logic ##--

m.start = function(self)
  self.t:setStatus("Mining")
  self.continueMining = 1
  local starttime = os.clock()
  local quarrysuccess, quarryvalue = pcall(function()

    self.t:checkFuel(self.t:calcLocD(4))
    self:burrow()
  
    local targetW = nil
    local initialD = self.t:getLoc().d
    local wDir = nil
    if (initialD == 0) then
      targetW = 1
      wDir = "z"
    elseif (initialD == 2) then
      targetW = -1
      wDir = "z"
    elseif (initialD == 1) then
      targetW = -1
      wDir = "x"
    elseif (initialD == 3) then
      targetW = 1
      wDir = "x"
    end

    while (self.continueMining >= 0) do -- inside this loop == done once per level
  
      for j = 1, self.quarryWidth do -- inside this loop == done once per row
        self:consolidate()
  
        for i = 1, self.quarryLength - 1 do -- inside this loop == done once per cell
          self.t:mineF()
          self:scanU()
          self:scanD()
          self.t:checkFuel(self.t.homeLoc)
          turtle.select(self.junkSlot)
          self:checkStorage()
        end
  
        if (j < self.quarryWidth) then -- on every row but the last, turn around on the new row
          local target = self.t:getLoc()
          target["d"] = (target["d"] + 2) % 4
          target[wDir] = target[wDir] + targetW
          self.t:moveTo(target)
          self:scanU()
          self:scanD()
          self.t:checkFuel(self.t.homeLoc)
        end
      end
  
      -- check if on last level
      if (self.continueMining <= 0) then
        break
      end
      
      -- move down a level
      self.t:moveR()
      self.t:moveR()
      local downsuccess, downvalue = pcall(function()
        local targetLoc = self.t:getLoc()
        targetLoc["y"] = targetLoc["y"] - 3
        self.t:checkFuel(targetLoc)
        self.t:mineD()
        self.t:mineD()
        self.t:mineD()
      end)
      self:scanD()
      targetW = targetW * -1
  
      self.continueMining = self.continueMining - 1
      if (downsuccess) then
        self.continueMining = 1
      end
    end
  end)
  
  if (quarrysuccess) then
    print("Mining completed!")
  else
    print("Could not continue mining!")
    print(quarryvalue)
  end
  
  self:returnToSurface()
  self:dumpItems()
  -- self.t:moveR()
  -- self.t:moveR()
  local endtime = os.clock()
  local mins = math.floor((endtime - starttime) / 60)
  local seconds = math.floor((endtime - starttime) % 60)
  local runtime = mins .. "m " .. seconds .. "s"
  print("Blocks Mined: " .. self.blocksMined)
  print("Runtime: " .. runtime)
  local size = self.quarryLength .. "x" .. self.quarryWidth
  local sizepadded = size
  for i = 1, 7 - #size do
    sizepadded = sizepadded .. " "
  end
  local blockspadded = tostring(self.blocksMined)
  for i = 1, 5 - #tostring(self.blocksMined) do
    blockspadded = blockspadded .. " "
  end
  local h = fs.open("runlog", "a")
  h.writeLine(sizepadded .. blockspadded .. runtime)
  h.close()
end

--## Constructor Method ##--

m.new = function(self, t, l, w, bl)
  local o = {}
  setmetatable(o, self)
  self.__index = self
  self.t = t
  self:setQuarrySize(l, w)
  self:checkForBlacklist(bl)
  self.initialLoc = self.t:getLoc()
  return o
end

return m