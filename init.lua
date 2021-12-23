--- === PaperWM ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "PaperWM"
obj.version = "0.1"
obj.author = "Michael Mogenson"
obj.homepage = "https://github.com/mogenson/PaperWM.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.default_hotkeys = {
    dump_state = { { "ctrl", "alt", "cmd", "shift" }, "d" },
    stop = { { "ctrl", "alt", "cmd", "shift" }, "q" },
    focus_left = { { "alt", "cmd" }, "h" },
    focus_right = { { "alt", "cmd" }, "l" },
    focus_up = { { "alt", "cmd" }, "k" },
    focus_down = { { "alt", "cmd" }, "j" },
    swap_left = { { "alt", "cmd", "shift" }, "h" },
    swap_right = { { "alt", "cmd", "shift" }, "l" },
    swap_up = { { "alt", "cmd", "shift" }, "k" },
    swap_down = { { "alt", "cmd", "shift" }, "j" },
    center_window = { { "alt", "cmd" }, "u" },
    full_width = { { "alt", "cmd" }, "f" },
    cycle_width = { { "alt", "cmd" }, "r" },
    cycle_height = { { "alt", "cmd", "shift" }, "r" },
    slurp_in = { { "alt", "cmd" }, "i" },
    barf_out = { { "alt", "cmd" }, "o" },
}

-- filter for windows to manage
obj.window_filter = hs.window.filter.new():setOverrideFilter({
    currentSpace = true,
    allowScreens = hs.screen.primaryScreen():id(),
})

-- number of pixels between windows
obj.window_gap = 8

-- logger
obj.logger = hs.logger.new("PaperWM")

-- constants
Direction = {
    ["LEFT"] = -1,
    ["RIGHT"] = 1,
    ["UP"] = -2,
    ["DOWN"] = 2,
    ["WIDTH"] = 3,
    ["HEIGHT"] = 4,
}

-- array of windows sorted from left to right
local window_list = { {} }
local index_table = {}

local function dumpState()
    for x, window_column in ipairs(window_list) do
        for y, window in ipairs(window_column) do
            local id = window:id()
            local title = window:title()
            local frame = window:frame()
            local index = index_table[id]
            obj.logger.df('window_list[%d][%d] = [%d] "%s" -> %s', x, y, id, title, frame)
            obj.logger.df("index_table[%d] = {x=%d,y=%d}", id, index.x, index.y)
        end
    end
end

local function getWorkArea(screen)
    local screen_frame = screen:frame()
    return hs.geometry.rect(
        screen_frame.x + obj.window_gap,
        screen:fullFrame().h - screen_frame.h + obj.window_gap,
        screen_frame.w - (2 * obj.window_gap),
        screen_frame.h - (2 * obj.window_gap)
    )
end

function obj:bindHotkeys(mapping)
    local spec = {
        dump_state = dumpState,
        stop = hs.fnutils.partial(self.stop, self),
        focus_left = hs.fnutils.partial(self.focusWindow, self, Direction.LEFT),
        focus_right = hs.fnutils.partial(self.focusWindow, self, Direction.RIGHT),
        focus_up = hs.fnutils.partial(self.focusWindow, self, Direction.UP),
        focus_down = hs.fnutils.partial(self.focusWindow, self, Direction.DOWN),
        swap_left = hs.fnutils.partial(self.swapWindows, self, Direction.LEFT),
        swap_right = hs.fnutils.partial(self.swapWindows, self, Direction.RIGHT),
        swap_up = hs.fnutils.partial(self.swapWindows, self, Direction.UP),
        swap_down = hs.fnutils.partial(self.swapWindows, self, Direction.DOWN),
        center_window = hs.fnutils.partial(self.centerWindow, self),
        full_width = hs.fnutils.partial(self.setWindowFullWidth, self),
        cycle_width = hs.fnutils.partial(self.cycleWindowSize, self, Direction.WIDTH),
        cycle_height = hs.fnutils.partial(self.cycleWindowSize, self, Direction.HEIGHT),
        slurp_in = hs.fnutils.partial(self.slurpWindow, self),
        barf_out = hs.fnutils.partial(self.barfWindow, self),
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

function obj:start()
    -- clear state
    window_list = { {} }
    index_table = {}

    -- sort windows from left to right
    local windows = self.window_filter:getWindows()
    table.sort(windows, function(first_window, second_window)
        return first_window:frame().x < second_window:frame().x
    end)

    -- create window list and index table
    local y = 1
    for x, window in ipairs(windows) do
        window_list[x] = { window }
        index_table[window:id()] = { x = x, y = y }
    end

    -- set initial layout
    self:tileWindows()

    -- listen for window events

    self.window_filter:subscribe(
        { hs.window.filter.windowFocused, hs.window.filter.windowMoved },
        function(window, app, event)
            self.logger.d(event .. " for " .. window:title())
            self:tileWindows()
        end
    )

    self.window_filter:subscribe(hs.window.filter.windowAllowed, function(window, app, event)
        self.logger.d(event .. " for " .. window:title())
        self:addWindow(window)
    end)

    self.window_filter:subscribe({
        hs.window.filter.windowDestroyed,
        hs.window.filter.windowFullscreened,
        hs.window.filter.windowHidden,
        hs.window.filter.windowMinimized,
        hs.window.filter.windowNotInCurrentSpace,
        hs.window.filter.windowNotOnScreen,
        hs.window.filter.windowNotVisible,
    }, function(window, app, event)
        self.logger.d(event)
        self.logger.d(event .. " for " .. window:title())
        self:removeWindow(window)
    end)

    return self
end

function obj:stop()
    -- stop events
    self.window_filter:unsubscribeAll()

    return self
end

function obj:tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    for _, window in ipairs(windows) do
        frame = window:frame()
        w = w or frame.w -- take given width or width of first window
        -- set either left or right x coord
        if bounds.x then
            frame.x = bounds.x
        elseif bounds.x2 then
            frame.x = bounds.x2 - w
        end
        -- set height if given
        if h then
            if id and h4id and window:id() == id then
                frame.h = h4id -- use this height for window with id
            else
                frame.h = h -- use this height for all other windows
            end
        end
        frame.y = bounds.y
        frame.w = w
        frame.y2 = math.min(frame.y2, bounds.y2) -- don't overflow bottom of bounds
        window:setFrame(frame)
        bounds.y = math.min(frame.y2 + self.window_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        last_window:setFrame(frame)
    end
    return w -- return width of column
end

function obj:tileWindows()
    -- find anchor window to tile from
    local anchor_window = hs.window.focusedWindow() or window_list[1][1]
    if not anchor_window then
        self.logger.d("anchor window not found")
        return -- bail
    end

    -- find anchor window index
    local anchor_index = index_table[anchor_window:id()]
    if not anchor_index then
        self.logger.d("anchor index not found")
        return -- bail
    end

    -- MacOS doesn't allow windows to be moved off screen
    -- stack windows in a visible margin on either side
    local screen_margin = 40

    -- get some global coordinates
    local screen = anchor_window:screen()
    local screen_frame = screen:frame()
    local left_margin = screen_frame.x + screen_margin
    local right_margin = screen_frame.x2 - screen_margin
    local work_area = getWorkArea(screen)

    -- adjust anchor window
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, work_area.x)
    anchor_frame.w = math.min(anchor_frame.w, work_area.w)
    anchor_frame.h = math.min(anchor_frame.h, work_area.h)
    if anchor_frame.x2 > work_area.x2 then
        anchor_frame.x = work_area.x2 - anchor_frame.w
    end

    -- TODO: need a min window height
    -- adjust anchor window column
    local column = window_list[anchor_index.x]
    if #column == 1 then
        anchor_frame.y, anchor_frame.h = work_area.y, work_area.h
        anchor_window:setFrame(anchor_frame)
    else
        local n = #column - 1 -- number of other windows in column
        local target_h = math.max(0, work_area.h - anchor_frame.h - (n * self.window_gap)) / n
        local bounds = { x = anchor_frame.x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
        self:tileColumn(
            column,
            bounds,
            target_h,
            anchor_frame.w,
            anchor_window:id(),
            anchor_frame.h
        )
    end

    -- tile windows from anchor right
    local target_x = math.min(anchor_frame.x2 + self.window_gap, right_margin)
    for x = anchor_index.x + 1, #window_list do
        local bounds = { x = target_x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
        local column_width = self:tileColumn(window_list[x], bounds)
        target_x = math.min(target_x + column_width + self.window_gap, right_margin)
    end

    -- tile windows from anchor left
    local target_x2 = math.max(anchor_frame.x - self.window_gap, left_margin)
    for x = anchor_index.x - 1, 1, -1 do
        local bounds = { x = nil, x2 = target_x2, y = work_area.y, y2 = work_area.y2 }
        local column_width = self:tileColumn(window_list[x], bounds)
        target_x2 = math.max(target_x2 - column_width - self.window_gap, left_margin)
    end

    hs.timer.doAfter(1.5 * hs.window.animationDuration, function()
        for window, _ in pairs(self.window_filter.windows) do
            if window.movedDelayed then
                self.logger.d("cancelled windowMoved for " .. window.title)
                window.movedDelayed:stop()
                window.movedDelayed = nil
            end
        end
    end)
end

function obj:addWindow(add_window)
    -- check if window is already in window list
    if index_table[add_window:id()] then
        return
    end

    -- find where to insert window
    local add_x = add_window:frame().center.x
    local add_index = 1
    for index, column in ipairs(window_list) do
        if add_x < column[1]:frame().center.x then
            add_index = index
            break
        end
    end

    -- add window
    table.insert(window_list, add_index, { add_window })

    -- update index table
    for x = add_index, #window_list do
        for y, window in ipairs(window_list[x]) do
            index_table[window:id()] = { x = x, y = y }
        end
    end

    -- update layout
    self:tileWindows()
end

function obj:removeWindow(remove_window)
    -- get index of window
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        self.logger.d("remove index not found")
        return
    end

    -- remove window
    table.remove(window_list[remove_index.x], remove_index.y)
    if #window_list[remove_index.x] == 0 then
        table.remove(window_list, remove_index.x)
    end

    -- update index table
    index_table[remove_window:id()] = nil
    for x = remove_index.x, #window_list do
        for y, window in ipairs(window_list[x]) do
            index_table[window:id()] = { x = x, y = y }
        end
    end

    -- update layout
    self:tileWindows()
end

function obj:focusWindow(direction)
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.d("focused index not found")
        return
    end

    -- get new focused window
    local new_focused_window
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        local column = window_list[focused_index.x + direction]
        if column then
            for y = focused_index.y, 1, -1 do
                new_focused_window = column[y]
                if new_focused_window then
                    break
                end
            end
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window = window_list[focused_index.x][focused_index.y + (direction / 2)]
    end

    if not new_focused_window then
        self.logger.d("new focused window not found")
        return
    end

    -- focus new window, windowFocused event will be emited immediately
    new_focused_window:focus()
end

function obj:swapWindows(direction)
    -- use focused window as source window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.d("focused index not found")
        return
    end

    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- get target windows
        local target_index = { x = focused_index.x + direction }
        local target_column = window_list[target_index.x]
        if not target_column then
            self.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = window_list[focused_index.x]
        window_list[target_index.x] = focused_column
        window_list[focused_index.x] = target_column

        -- update index table
        for y, window in ipairs(target_column) do
            index_table[window:id()] = { x = focused_index.x, y = y }
        end
        for y, window in ipairs(focused_column) do
            index_table[window:id()] = { x = target_index.x, y = y }
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1]:frame()
        if direction == Direction.LEFT then
            focused_frame.x = target_frame.x
            target_frame.x = focused_frame.x2 + self.window_gap
        else -- Direction.RIGHT
            target_frame.x = focused_frame.x
            focused_frame.x = target_frame.x2 + self.window_gap
        end
        for y, window in ipairs(target_column) do
            local frame = window:frame()
            frame.x = target_frame.x
            window:setFrame(frame)
        end
        for y, window in ipairs(focused_column) do
            local frame = window:frame()
            frame.x = focused_frame.x
            window:setFrame(frame)
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        -- get target window
        local target_index = { x = focused_index.x, y = focused_index.y + (direction / 2) }
        local target_window = window_list[target_index.x][target_index.y]
        if not target_window then
            self.logger.d("target window not found")
            return
        end

        -- swap places in window list
        window_list[target_index.x][target_index.y] = focused_window
        window_list[focused_index.x][focused_index.y] = target_window

        -- update index table
        index_table[target_window:id()] = focused_index
        index_table[focused_window:id()] = target_index

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_window:frame()
        if direction == Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + self.window_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + self.window_gap
        end
        focused_window:setFrame(focused_frame)
        target_window:setFrame(target_frame)
    end

    -- update layout
    self:tileWindows()
end

function obj:centerWindow()
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- get global coordinates
    local focused_frame = focused_window:frame()
    local screen_frame = focused_window:screen():frame()

    -- center window
    focused_frame.x = screen_frame.x + (screen_frame.w / 2) - (focused_frame.w / 2)
    focused_window:setFrame(focused_frame)

    -- update layout
    self:tileWindows()
end

function obj:setWindowFullWidth()
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- fullscreen window width
    local work_area = getWorkArea(focused_window:screen())
    local focused_frame = focused_window:frame()
    focused_frame.x, focused_frame.w = work_area.x, work_area.w
    focused_window:setFrame(focused_frame)

    -- update layout
    self:tileWindows()
end

function obj:cycleWindowSize(direction)
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    function findNewSize(area_size, frame_size)
        -- calculate pixel widths from ratios
        local sizes = { 0.38195, 0.5, 0.61804 }
        for index, size in ipairs(sizes) do
            sizes[index] = size * area_size
        end

        -- find new size
        local new_size = sizes[1]
        for _, size in ipairs(sizes) do
            if size > frame_size + 10 then
                new_size = size
                break
            end
        end

        return new_size
    end

    local work_area = getWorkArea(focused_window:screen())
    local focused_frame = focused_window:frame()

    if direction == Direction.WIDTH then
        local new_width = findNewSize(work_area.w, focused_frame.w)
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_width) / 2)
        focused_frame.w = new_width
    elseif direction == Direction.HEIGHT then
        local new_height = findNewSize(work_area.h, focused_frame.h)
        focused_frame.y = math.max(
            work_area.y,
            focused_frame.y + ((focused_frame.h - new_height) / 2)
        )
        focused_frame.h = new_height
        focused_frame.y = focused_frame.y - math.max(0, focused_frame.y2 - work_area.y2)
    end

    -- apply new size
    focused_window:setFrame(focused_frame)

    -- update layout
    self:tileWindows()
end

function obj:slurpWindow()
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.d("focused index not found")
        return
    end

    -- get column to left
    local column = window_list[focused_index.x - 1]
    if not column then
        self.logger.d("column not found")
        return
    end

    -- remove window
    table.remove(window_list[focused_index.x], focused_index.y)
    if #window_list[focused_index.x] == 0 then
        table.remove(window_list, focused_index.x)
    end

    -- append to end of column
    table.insert(column, focused_window)

    -- update index table
    local num_windows = #column
    index_table[focused_window:id()] = { x = focused_index.x - 1, y = num_windows }
    for x = focused_index.x, #window_list do
        for y, window in ipairs(window_list[x]) do
            index_table[window:id()] = { x = x, y = y }
        end
    end

    -- adjust window frames
    local work_area = getWorkArea(focused_window:screen())
    local bounds = { x = column[1]:frame().x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
    local target_h = math.max(0, work_area.h - ((num_windows - 1) * self.window_gap)) / num_windows
    self:tileColumn(column, bounds, target_h)

    -- update layout
    self:tileWindows()
end

function obj:barfWindow()
    -- get current focused window
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.d("focused index not found")
        return
    end

    -- get column
    local column = window_list[focused_index.x]
    if #column == 1 then
        self.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.y)
    table.insert(window_list, focused_index.x + 1, { focused_window })

    -- update index table
    for x = focused_index.x, #window_list do
        for y, window in ipairs(window_list[x]) do
            index_table[window:id()] = { x = x, y = y }
        end
    end

    -- adjust window frames
    local num_windows = #column
    local work_area = getWorkArea(focused_window:screen())
    local focused_frame = focused_window:frame()
    local bounds = { x = focused_frame.x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
    local target_h = math.max(0, work_area.h - ((num_windows - 1) * self.window_gap)) / num_windows
    focused_frame.y = work_area.y
    focused_frame.x = focused_frame.x2 + self.window_gap
    focused_frame.h = work_area.h
    focused_window:setFrame(focused_frame)
    self:tileColumn(column, bounds, target_h)

    -- update layout
    self:tileWindows()
end

return obj
