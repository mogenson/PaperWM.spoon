local Fnutils <const> = hs.fnutils
local Geometry <const> = hs.geometry
local LeftMouseDown <const> = hs.eventtap.event.types.leftMouseDown
local LeftMouseDragged <const> = hs.eventtap.event.types.leftMouseDragged
local LeftMouseUp <const> = hs.eventtap.event.types.leftMouseUp
local MouseEventDeltaX <const> = hs.eventtap.event.properties.mouseEventDeltaX
local MouseEventDeltaY <const> = hs.eventtap.event.properties.mouseEventDeltaY
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Timer <const> = hs.timer
local Window <const> = hs.window
local WindowFilter <const> = hs.window.filter

local Events = {}
Events.__index = Events

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Events.init(paperwm)
    Events.PaperWM = paperwm
    Events.Swipe = dofile(hs.spoons.resourcePath("swipe.lua"))
end

---refresh window layout on screen change
local screen_watcher = Screen.watcher.new((function()
    local pending_timer = nil
    return function()
        if not pending_timer then
            pending_timer = Timer.doAfter(Window.animationDuration, function()
                pending_timer = nil
                Events.PaperWM.logger.d("refreshing window layout on screen change")
                Events.PaperWM.windows.refreshWindows()
            end)
        end
    end
end)())

---callback for window events
---@param window Window
---@param event string name of the event
---@param self PaperWM
function Events.windowEventHandler(window, event, self)
    if not window["id"] then
        self.logger.ef("no id method for window %s in windowEventHandler", window)
        return
    end

    self.logger.df("%s for [%s] id: %d", event, window:title(), window:id())
    local space = nil

    --[[ When a new window is created, We first get a windowVisible event but
    without a Space. Next we receive a windowFocused event for the window, but
    this also sometimes lacks a Space. Our approach is to store the window
    pending a Space in the pending_window variable and set a timer to try to add
    the window again later. Also schedule the windowFocused handler to run later
    after the window was added ]]
    --

    if self.floating.isFloating(window) then
        -- this event is only meaningful for floating windows
        if event == "windowDestroyed" then
            self.floating.removeFloating(window)
        end
        -- no other events are meaningful for floating windows
        return
    end

    if event == "windowFocused" then
        if self.state.pending_window and window == self.state.pending_window then
            Timer.doAfter(Window.animationDuration,
                function()
                    self.logger.vf("pending window timer for %s", window)
                    Events.windowEventHandler(window, event, self)
                end)
            return
        end
        self.state.prev_focused_window = window -- for addWindow()
        space = Spaces.windowSpaces(window)[1]
    elseif event == "windowVisible" or event == "windowUnfullscreened" then
        space = self.windows.addWindow(window)
        if self.state.pending_window and window == self.state.pending_window then
            self.state.pending_window = nil -- tried to add window for the second time
        elseif not space then
            self.state.pending_window = window
            Timer.doAfter(Window.animationDuration,
                function()
                    Events.windowEventHandler(window, event, self)
                end)
            return
        end
    elseif event == "windowNotVisible" then
        space = self.windows.removeWindow(window)
    elseif event == "windowFullscreened" then
        space = self.windows.removeWindow(window, true) -- don't focus new window if fullscreened
    elseif event == "AXWindowMoved" or event == "AXWindowResized" then
        space = Spaces.windowSpaces(window)[1]
    end

    if space then self:tileSpace(space) end
end

---coroutine to slide all windows in a space by dx
---@param self PaperWM
---@param space Space
---@param screen_frame Frame
local function slide_windows(self, space, screen_frame)
    local left_margin  = screen_frame.x + self.screen_margin
    local right_margin = screen_frame.x2 - self.screen_margin

    -- cache windows, frame, and virtual x positions because window lookup is expensive
    -- stop window watchers
    local windows      = {}
    for id, x in pairs(self.state.xPositions(space)) do
        local window = Window.get(id)
        if window then
            self.state.uiWatcherStop(id)
            local frame = window:frame()
            table.insert(windows, { window = window, frame = frame, x = x })
        end
    end

    local update_window_frames = function(dx)
        if dx ~= 0 then
            for _, item in ipairs(windows) do
                item.x = item.x + dx                               -- scroll left or right
                item.frame.x = dx > 0 and math.min(item.x, right_margin) or math.max(item.x, left_margin - item.frame.w)
                item.window:setTopLeft(item.frame.x, item.frame.y) -- avoid the animationDuration
            end
        end
    end

    local dx_queue = {}
    while true do
        local dx = coroutine.yield()
        if not dx then break end

        table.insert(dx_queue, { timestamp=Timer.secondsSinceEpoch(), dx=dx })
        if #dx_queue > 5 then
            table.remove(dx_queue, 1)
        end

        update_window_frames(dx)
    end

    local slide_windows_cleanup = function()
        -- start window watchers
        for _, item in ipairs(windows) do self.state.uiWatcherStart(item.window:id()) end
        windows = nil -- force collection

        -- ensure a focused window is on screen
        local focused_window = Window.focusedWindow()
        if focused_window then
            local frame = focused_window:frame()
            local visible_window = (function()
                if frame.x < screen_frame.x then
                    return self.windows.getFirstVisibleWindow(space, screen_frame,
                        self.windows.Direction.LEFT)
                elseif frame.x2 > screen_frame.x2 then
                    return self.windows.getFirstVisibleWindow(space, screen_frame,
                        self.windows.Direction.RIGHT)
                end
            end)()
            if visible_window then
                visible_window:focus()
            else
                self:tileSpace(space)
            end
        else
            self.logger.e("no focused window at end of swipe")
        end
    end

    -- Apply inertia if enabled
    if #dx_queue > 1 and self.swipe_inertia_max_duration > 0 then
        local current_time = Timer.secondsSinceEpoch()
        local swipe_end_time = current_time + self.swipe_inertia_max_duration

        local total_dx = 0
        for i, dx_info in ipairs(dx_queue) do
            total_dx = total_dx + dx_info.dx
        end

        local last_time = dx_queue[#dx_queue].timestamp
        local elapsed = last_time - dx_queue[1].timestamp
        local velocity = total_dx / elapsed

        -- Apply inertia for a short duration
        local inertia_timer
        local target_fps = self.swipe_inertia_fps
        if target_fps <= 0 then
            target_fps = 60
            self.logger.ef("swipe_inertia_fps <= 0, using %f instead", target_fps)
        end

        inertia_timer = Timer.new(1 / target_fps,
            function()
                local current_time = Timer.secondsSinceEpoch()
                if current_time > swipe_end_time then
                    slide_windows_cleanup()
                    inertia_timer:stop()
                    return
                end

                -- Apply velocity with exponential decay
                velocity = velocity * self.swipe_inertia_decay
                if math.abs(velocity) < 0.1 then
                    -- Stop when velocity is very small
                    slide_windows_cleanup()
                    inertia_timer:stop()
                    return
                end

                local time_delta = current_time - last_time
                update_window_frames(velocity * time_delta)
                last_time = current_time
            end

        )
        inertia_timer:start()
    else
        slide_windows_cleanup()
    end

    while true do
        self.logger.ef("resumed finished slide_windows coroutine with: %s", coroutine.yield())
    end
end


---generate callback function for touchpad swipe gesture event
---@param self PaperWM
function Events.swipeHandler(self)
    -- saved upvalues between callback function calls
    local swipe_coro, screen_frame = nil, nil

    ---callback for touchpad swipe gesture event
    ---@param id number unique id across callbacks for the same swipe
    ---@param type number one of Swipe.BEGIN, Swipe.MOVED, Swipe.END
    ---@param dx number change in horizonal position since last callback: between 0 and 1
    ---@param dy number change in vertical position since last callback: between 0 and 1
    return function(id, type, dx, dy)
        if type == Events.Swipe.BEGIN then
            self.logger.df("new swipe: %d", id)

            -- use focused window for space to scroll windows
            local focused_window = Window.focusedWindow()
            if not focused_window then
                self.logger.d("focused window not found")
                return
            end

            local focused_index = self.state.windowIndex(focused_window)
            if not focused_index then
                self.logger.e("focused index not found")
                return
            end

            local screen = Screen(Spaces.spaceDisplay(focused_index.space))
            if not screen then
                self.logger.e("no screen for space")
                return
            end

            -- cache upvalues
            screen_frame = screen:frame()
            swipe_coro = coroutine.wrap(slide_windows)
            swipe_coro(self, focused_index.space, screen_frame)
        elseif swipe_coro and type == Events.Swipe.END then
            self.logger.df("swipe end: %d", id)
            swipe_coro(nil)
            swipe_coro = nil
        elseif swipe_coro and screen_frame and type == Events.Swipe.MOVED then
            if math.abs(dy) >= math.abs(dx) then return end -- horizontal swipes only
            dx = math.floor(self.swipe_gain * dx * screen_frame.w)
            swipe_coro(dx)
        end
    end
end

---generate callback function for mouse events
---@param self PaperWM
function Events.mouseHandler(self)
    local lift_window, drag_coro = nil, nil

    ---find a Window under the mouse cursor
    ---@param event userdata
    ---@return Window|nil
    local function windowUnderCursor(event)
        local cursor = Geometry.new(event:location())
        local screen = Fnutils.find(Screen.allScreens(), function(screen) return cursor:inside(screen:frame()) end)
        if not screen then return end
        local space = Spaces.activeSpaceOnScreen(screen)
        if not space then return end
        for id, _ in pairs(self.state.xPositions(space)) do
            local window = Window.get(id)
            if window and cursor:inside(window:frame()) then return window end
        end
    end

    ---callback for mouse event
    ---@param event userdata
    ---@return boolean delete or propagate event
    return function(event)
        local delete_event = false
        local type = event:getType()
        if type == LeftMouseDown then
            local flags = event:getFlags()
            if self.drag_window and flags:containExactly(self.drag_window) then
                local drag_window = windowUnderCursor(event)
                if drag_window then
                    local index = self.state.windowIndex(drag_window)
                    if not index then
                        self.logger.e("drag window index not found")
                        return delete_event
                    end
                    local screen = Screen(Spaces.spaceDisplay(index.space))
                    if not screen then
                        self.logger.e("no screen for space")
                        return delete_event
                    end
                    drag_coro = coroutine.wrap(slide_windows)
                    drag_coro(self, index.space, screen:frame())
                    self.logger.df("drag window start for: %s", drag_window)
                    delete_event = true
                end
            elseif self.lift_window and flags:containExactly(self.lift_window) then
                -- get window from cursor location, set window to floating, tile
                lift_window = windowUnderCursor(event)
                if lift_window then self.floating.toggleFloating(lift_window) end
                self.logger.df("lift window start for: %s", lift_window)
                delete_event = true
            end
        elseif type == LeftMouseDragged then
            if drag_coro then
                drag_coro(event:getProperty(MouseEventDeltaX))
                delete_event = true
            elseif lift_window then
                local frame = lift_window:frame()
                lift_window:setTopLeft(
                    frame.x + event:getProperty(MouseEventDeltaX),
                    frame.y + event:getProperty(MouseEventDeltaY)
                )
                delete_event = true
            end
        elseif type == LeftMouseUp then
            if drag_coro then
                self.logger.df("drag window stop")
                drag_coro(nil)
                drag_coro = nil
                delete_event = true
            elseif lift_window then
                -- set window to not floating, tile
                self.logger.df("lift window stop")
                self.floating.toggleFloating(lift_window)
                lift_window = nil
                delete_event = true
            end
        end
        return delete_event
    end
end

---start monitoring for window events
function Events.start()
    -- listen for window events
    Events.PaperWM.window_filter:subscribe({
        WindowFilter.windowFocused, WindowFilter.windowVisible,
        WindowFilter.windowNotVisible, WindowFilter.windowFullscreened,
        WindowFilter.windowUnfullscreened, WindowFilter.windowDestroyed,
    }, function(window, _, event) Events.windowEventHandler(window, event, Events.PaperWM) end)

    -- watch for external monitor plug / unplug
    screen_watcher:start()

    -- recognize horizontal touchpad swipe gestures
    if Events.PaperWM.swipe_fingers > 1 then
        Events.Swipe:start(Events.PaperWM.swipe_fingers, Events.swipeHandler(Events.PaperWM))
    end

    -- register a mouse event watcher if the drag window or lift window hotkeys are set
    if Events.PaperWM.drag_window or Events.PaperWM.lift_window then
        Events.mouse_watcher = hs.eventtap.new({ LeftMouseDown, LeftMouseDragged, LeftMouseUp },
            Events.mouseHandler(Events.PaperWM)):start()
    end
end

---stop monitoring for window events
function Events.stop()
    -- stop events
    Events.PaperWM.window_filter:unsubscribeAll()
    Events.PaperWM.state.uiWatcherStopAll()
    screen_watcher:stop()

    -- stop listening for touchpad swipes
    Events.Swipe:stop()

    -- stop listening for mouse events
    if Events.mouse_watcher then Events.mouse_watcher:stop() end
end

return Events
