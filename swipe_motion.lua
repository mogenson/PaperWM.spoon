local Motion = {}
Motion.__index = Motion

local function now()
    return hs.timer.absoluteTime() / 1e9
end

local function sampleTime(inputTime, timestamp)
    return inputTime and inputTime > 0 and inputTime <= timestamp and inputTime or timestamp
end

function Motion.curve(distance, velocity)
    if distance == 0 then return 0, 0, function() return 0 end end
    local direction = distance > 0 and 1 or -1
    local speed = math.max(0, velocity * direction)
    local duration = speed > 1 and 2 * math.abs(distance) / speed or 0.22
    duration = math.max(0.12, math.min(0.35, duration))
    local initial = direction * math.min(speed, 3 * math.abs(distance) / duration)
    return duration, initial, function(elapsed)
        local progress = math.max(0, math.min(1, elapsed / duration))
        return distance * (3 * progress ^ 2 - 2 * progress ^ 3)
            + initial * duration * (progress ^ 3 - 2 * progress ^ 2 + progress)
    end
end

function Motion.new(paperwm)
    return setmetatable({ paperwm = paperwm }, Motion)
end

function Motion:cancel()
    local session = self.session
    if not session then return end
    self.session = nil
    if session.timer then session.timer:stop() end
    for _, item in ipairs(session.windows) do
        pcall(self.paperwm.state.uiWatcherStart, item.id)
    end
end

function Motion:run(method, ...)
    local ok, message = xpcall(method, debug.traceback, self, ...)
    if not ok then
        self:cancel()
        self.paperwm.logger.e(message)
    end
end

function Motion:begin(id, inputTime)
    local started = now()
    local interrupted = self.session
    local focused = interrupted and interrupted.phase == "snap" and interrupted.selected
        or hs.window.focusedWindow()
    self:cancel()
    local index = focused and self.paperwm.state.windowIndex(focused)
    if not index then return end
    local screen = hs.screen(hs.spaces.spaceDisplay(index.space))
    if not screen then return end
    local session = { id = id, space = index.space, frame = screen:frame(),
        windows = {}, offset = 0, pendingOffset = 0, requested = 0, samples = {}, phase = "drag" }
    self.session = session
    local items = {}
    local columns = self.paperwm.state.windowList(index.space)
    local positions = self.paperwm.state.xPositions(index.space)
    local contentLeft, contentRight = math.huge, -math.huge
    for _, column in ipairs(columns) do
        for _, window in ipairs(column) do
            local windowId = window:id()
            local frame = window:frame()
            local position = positions[windowId] or frame.x
            session.windows[#session.windows + 1] = {
                id = windowId, window = window, frame = frame, origin = position, lastX = frame.x,
            }
            items[windowId] = session.windows[#session.windows]
            contentLeft = math.min(contentLeft, position)
            contentRight = math.max(contentRight, position + frame.w)
            self.paperwm.state.uiWatcherStop(windowId)
        end
    end
    local canvas = self.paperwm.windows.getCanvas(screen)
    local maximum = canvas.x - contentLeft
    local minimum = math.min(maximum, canvas.x2 - contentRight)
    local function destination(window)
        local item = window and items[window:id()]
        if not item then return nil end
        return { window = window,
            offset = math.max(minimum, math.min(canvas.x - item.origin, maximum)) }
    end
    session.home = destination(focused)
    if not session.home then self:cancel(); return end
    session.previous = destination(columns[index.col - 1] and columns[index.col - 1][1])
    session.next = destination(columns[index.col + 1] and columns[index.col + 1][1])
    session.minimum = math.max(minimum, math.min(0, session.home.offset,
        session.previous and session.previous.offset or session.home.offset,
        session.next and session.next.offset or session.home.offset))
    session.maximum = math.min(maximum, math.max(0, session.home.offset,
        session.previous and session.previous.offset or session.home.offset,
        session.next and session.next.offset or session.home.offset))
    session.samples[1] = { time = sampleTime(inputTime, started), position = 0 }
end

function Motion:apply(offset)
    local session = self.session
    offset = math.max(session.minimum, math.min(offset, session.maximum))
    session.offset = offset
    local positions = self.paperwm.state.xPositions(session.space)
    local left = session.frame.x + self.paperwm.screen_margin
    local right = session.frame.x2 - self.paperwm.screen_margin
    for _, item in ipairs(session.windows) do
        local position = item.origin + offset
        local visible = math.floor(math.max(left - item.frame.w, math.min(position, right)) + 0.5)
        if visible ~= item.lastX then
            item.window:setTopLeft(visible, item.frame.y)
            item.lastX = visible
        end
        positions[item.id] = position
    end
end

function Motion:move(id, dx, dy, inputTime)
    local session = self.session
    if not session or session.id ~= id or session.phase ~= "drag" then return end
    local timestamp = now()
    local pixels = math.abs(dx) > math.abs(dy) and dx * session.frame.w * self.paperwm.swipe_gain or 0
    session.requested = math.max(math.min(session.minimum, -20),
        math.min(session.requested + pixels, math.max(session.maximum, 20)))
    local offset = math.max(session.minimum, math.min(session.pendingOffset + pixels, session.maximum))
    session.pendingOffset = offset
    session.pending = true
    local sampledAt = sampleTime(inputTime, timestamp)
    local samples = session.samples
    samples[#samples + 1] = { time = sampledAt, position = offset }
    while #samples > 2 and samples[2].time < sampledAt - 0.1 do table.remove(samples, 1) end
    if not session.timer then
        session.timer = hs.timer.doEvery(1 / 60, function()
            if self.session ~= session or session.phase ~= "drag" or not session.pending then return end
            self:run(function(controller)
                controller:apply(session.pendingOffset)
                session.pending = false
            end)
        end)
    end
end

function Motion:velocity(timestamp)
    local session = self.session
    local samples = session.samples
    local last = samples[#samples]
    if not last or timestamp - last.time >= 0.08 then return 0 end
    local first = samples[1]
    for _, sample in ipairs(samples) do
        if sample.time >= timestamp - 0.1 then first = sample; break end
    end
    local duration = timestamp - first.time
    if duration < 0.008 then return 0 end
    local velocity = (session.pendingOffset - first.position) / duration
    local limit = session.frame.w * 4
    return math.max(-limit, math.min(limit, velocity))
end

function Motion:complete()
    local session = self.session
    if session.timer then session.timer:stop() end
    self.session = nil
    for _, item in ipairs(session.windows) do
        pcall(self.paperwm.state.uiWatcherStart, item.id)
    end
    if session.selected then
        self.paperwm.state.prev_focused_window = session.selected
        session.selected:focus()
        local index = self.paperwm.state.windowIndex(session.selected)
        if index and self.paperwm.state.isStacked(session.space, index.col)
            and self.paperwm.state.activeRow(session.space, index.col) ~= index.row then
            self.paperwm:tileSpace(session.space, session.selected)
        end
    end
end

function Motion:finish(id, inputTime)
    local session = self.session
    if not session or session.id ~= id or session.phase ~= "drag" then return end
    local timestamp = now()
    if session.timer then session.timer:stop(); session.timer = nil end
    local velocity = self:velocity(sampleTime(inputTime, timestamp))
    local focused = hs.window.focusedWindow()
    local index = focused and self.paperwm.state.windowIndex(focused)
    if not index or index.space ~= session.space then self:cancel(); return end
    local home = assert(session.home)
    local destination = home
    if session.requested <= -12 then
        destination = session.next or home
    elseif session.requested >= 12 then
        destination = session.previous or home
    end
    local selected = destination.window
    local distance = destination.offset - session.offset
    session.selected = selected
    if math.abs(distance) < 0.5 then
        self:complete()
        return
    end
    local duration, _, evaluate = Motion.curve(distance, velocity)
    local origin = session.offset
    local startTime = now()
    session.phase = "snap"
    session.timer = hs.timer.doEvery(1 / 60, function()
        if self.session ~= session then return end
        self:run(function(controller)
            local elapsed = now() - startTime
            controller:apply(origin + evaluate(elapsed))
            if elapsed >= duration then controller:complete() end
        end)
    end)
end

return Motion
