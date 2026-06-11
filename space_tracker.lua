local HsSpaces <const> = hs.spaces

local Tracker = {}
 
Tracker.__index = Tracker

local recentSpaces = { nil, nil }     -- [1] = current, [2] = previous

---to track space changes
---@param spaceID space id on changed
function Tracker.trackSpaces(spaceID)
    if spaceID == -1 then
        spaceID = HsSpaces.focusedSpace()
    end

    -- Ignore error spaceID and current space swiching.
    if spaceID == nil or recentSpaces[1] == spaceID then
        return
    end
    -- Set recent spaces
    recentSpaces[2] = recentSpaces[1]
    recentSpaces[1] = spaceID
end

local function initSpaceTracker()
    local currentSpace = HsSpaces.focusedSpace()
    if currentSpace then
        recentSpaces[1] = currentSpace
    end
end

---Get a recent space
---@return Space | nil
function Tracker.getRecentSpace()
    local prev = recentSpaces[2]
    local current = recentSpaces[1]
    if prev and prev ~= current then
        return prev
    end
    
    return nil
end

initSpaceTracker()

return Tracker