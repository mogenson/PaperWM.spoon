local Swipe   = {}
Swipe.__index = Swipe


-- swipe types
Swipe.BEGIN = 1
Swipe.MOVED = 2
Swipe.END   = 3


local Cache = { id = nil, direction = nil, distance = 0, size = 0, touches = {} }

function Cache:clear()
    self.id = nil
    self.direction = nil
    self.distance = 0
    self.size = 0
    self.touches = {}
end

function Cache:set(touches)
    self:clear()
    for i, touch in ipairs(touches) do
        self.touches[touch.identity] = {
            x = touch.normalizedPosition.x,
            y = touch.normalizedPosition.y,
            dx = 0,
            dy = 0,
        }
        self.size = i
    end
    self.id = hs.math.randomFromRange(1, 0xFFFF)
    return self.id
end

function Cache:detect(touches)
    local moved = false
    local delta = { dx = 0, dy = 0 }
    local trackedCount = 0
    local currentTouches = {}
    for _, touch in ipairs(touches) do
        local previous = self.touches[touch.identity]
        local currentX, currentY = touch.normalizedPosition.x, touch.normalizedPosition.y
        if previous then
            delta.dx = delta.dx + currentX - previous.x
            delta.dy = delta.dy + currentY - previous.y
            trackedCount = trackedCount + 1
            moved = moved or touch.phase == "moved"
        end
        currentTouches[touch.identity] = { x = currentX, y = currentY }
    end

    self.touches = currentTouches
    self.size = #touches
    if trackedCount > 0 then
        delta = { dx = delta.dx / trackedCount, dy = delta.dy / trackedCount }
    end

    return moved, delta, self.id
end

-- fingers: number of fingers for swipe (must be at least 2)
-- callback: function(type, distance, id) end
--           id is a unique id across callbacks for the same swipe
--           type is Swipe.type { BEGIN, MOVED, END}
--           dx change in horizontal position between 0.0 and 1.0
--           dy change in vertical position between 0.0 and 1.0
local gesture <const> = hs.eventtap.event.types.gesture
function Swipe:start(fingers, callback)
    assert(fingers > 1)
    assert(callback)
    local function handleEvent(event)
        local type = event:getType(true)
        if type ~= gesture then return end
        local inputTime = event.timestamp and event:timestamp() / 1e9 or nil
        local touches = {}
        for _, touch in ipairs(event:getTouches()) do
            if touch.phase ~= "ended" and touch.phase ~= "cancelled" then
                touches[#touches + 1] = touch
            end
        end
        if not Cache.id then
            if #touches == fingers then
                callback(Cache:set(touches), Swipe.BEGIN, 0, 0, inputTime)
            end
        elseif #touches == 0 then
            local finishedId = Cache.id
            Cache:clear()
            callback(finishedId, Swipe.END, 0, 0, inputTime)
        else
            local moved, delta, id = Cache:detect(touches)
            if moved then
                callback(id, Swipe.MOVED, delta.dx, delta.dy, inputTime)
            end
        end
    end

    self.watcher = hs.eventtap.new({ gesture }, handleEvent)

    Cache:clear()
    self.watcher:start()
end

function Swipe:stop()
    if self.watcher then
        self.watcher:stop()
        self.watcher = nil
    end
end

return Swipe
