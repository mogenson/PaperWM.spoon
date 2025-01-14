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

function Cache:none(touches)
    local absent = true
    for _, touch in ipairs(touches) do
        absent = absent and (self.touches[touch.identity] == nil)
    end
    return absent
end

function Cache:all(touches)
    local present = true
    for _, touch in ipairs(touches) do
        present = present and (self.touches[touch.identity] ~= nil)
    end
    return present
end

function Cache:any(touches)
    for _, touch in ipairs(touches) do
        if self.touches[touch.identity] then return true end
    end
    return false
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
    local moved = true
    local delta = { dx = 0, dy = 0 }
    local size = 0
    for i, touch in ipairs(touches) do
        local id = touch.identity
        local x, y = touch.normalizedPosition.x, touch.normalizedPosition.y
        local dx, dy = x - assert(self.touches[id]).x, y - assert(self.touches[id]).y

        moved = moved and (touch.phase == "moved")
        delta = { dx = delta.dx + dx, dy = delta.dy + dy }
        self.touches[id] = { x = x, y = y, dx = dx, dy = dy }
        size = i
    end

    assert(self.size == size)
    delta = { dx = delta.dx / size, dy = delta.dy / size }

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

    self.watcher = hs.eventtap.new({ gesture }, function(event)
        local type = event:getType(true)
        if type ~= gesture then return end
        local touches = event:getTouches()

        if #touches ~= fingers then
            if Cache.id and Cache:any(touches) then
                callback(Cache.id, Swipe.END, 0, 0)
                Cache:clear()
            end
        elseif Cache:none(touches) then
            callback(Cache:set(touches), Swipe.BEGIN, 0, 0)
        elseif Cache:all(touches) then
            local moved, delta, id = Cache:detect(touches)
            if moved then
                callback(id, Swipe.MOVED, delta.dx, delta.dy)
            end
        end
    end)

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
