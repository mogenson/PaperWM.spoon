--- === PaperWM ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)

-- install from https://github.com/asmagill/hs._asm.undocumented.spaces
local spaces = require("hs._asm.undocumented.spaces")

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
    stop_events = { { "ctrl", "alt", "cmd", "shift" }, "q" },
    focus_left = { { "ctrl", "alt", "cmd" }, "h" },
    focus_right = { { "ctrl", "alt", "cmd" }, "l" },
    focus_up = { { "ctrl", "alt", "cmd" }, "k" },
    focus_down = { { "ctrl", "alt", "cmd" }, "j" },
    swap_left = { { "ctrl", "alt", "cmd", "shift" }, "h" },
    swap_right = { { "ctrl", "alt", "cmd", "shift" }, "l" },
    swap_up = { { "ctrl", "alt", "cmd", "shift" }, "k" },
    swap_down = { { "ctrl", "alt", "cmd", "shift" }, "j" },
    center_window = { { "ctrl", "alt", "cmd" }, "u" },
    full_width = { { "ctrl", "alt", "cmd" }, "f" },
    cycle_width = { { "ctrl", "alt", "cmd" }, "r" },
    cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in = { { "ctrl", "alt", "cmd" }, "i" },
    barf_out = { { "ctrl", "alt", "cmd" }, "o" },
    switch_space_1 = { { "ctrl", "alt", "cmd" }, "1" },
    switch_space_2 = { { "ctrl", "alt", "cmd" }, "2" },
    switch_space_3 = { { "ctrl", "alt", "cmd" }, "3" },
    switch_space_4 = { { "ctrl", "alt", "cmd" }, "4" },
    switch_space_5 = { { "ctrl", "alt", "cmd" }, "5" },
    switch_space_6 = { { "ctrl", "alt", "cmd" }, "6" },
    switch_space_7 = { { "ctrl", "alt", "cmd" }, "7" },
    switch_space_8 = { { "ctrl", "alt", "cmd" }, "8" },
    switch_space_9 = { { "ctrl", "alt", "cmd" }, "9" },
    move_window_1 = { { "ctrl", "alt", "cmd", "shift" }, "1" },
    move_window_2 = { { "ctrl", "alt", "cmd", "shift" }, "2" },
    move_window_3 = { { "ctrl", "alt", "cmd", "shift" }, "3" },
    move_window_4 = { { "ctrl", "alt", "cmd", "shift" }, "4" },
    move_window_5 = { { "ctrl", "alt", "cmd", "shift" }, "5" },
    move_window_6 = { { "ctrl", "alt", "cmd", "shift" }, "6" },
    move_window_7 = { { "ctrl", "alt", "cmd", "shift" }, "7" },
    move_window_8 = { { "ctrl", "alt", "cmd", "shift" }, "8" },
    move_window_9 = { { "ctrl", "alt", "cmd", "shift" }, "9" },
}

-- filter for windows to manage
obj.window_filter = hs.window.filter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
})

-- number of pixels between windows
obj.window_gap = 8

-- logger
obj.logger = hs.logger.new(obj.name)

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
local window_list = {}
local index_table = {}

local function getSpacesList()
    local spaces_list = {}
    local layout = spaces.layout()
    for _, screen in ipairs(hs.screen.allScreens()) do
        for _, space in ipairs(layout[screen:getUUID()]) do
            table.insert(spaces_list, space)
        end
    end
    return spaces_list
end

local function dumpState()
    obj.logger.df("spaces: %s", hs.inspect(getSpacesList()))

    for space, windows in pairs(window_list) do
        for x, window_column in ipairs(windows) do
            for y, window in ipairs(window_column) do
                local id = window:id()
                obj.logger.df(
                    'window_list[%d][%d][%d] = [%d] "%s" -> %s %s',
                    space,
                    x,
                    y,
                    id,
                    window:title(),
                    window:frame(),
                    hs.inspect(window:spaces())
                )
                local index = index_table[id]
                obj.logger.df(
                    "index_table[%d] = {space=%d, x=%d,y=%d}",
                    id,
                    index.space,
                    index.x,
                    index.y
                )
            end
        end
    end
end

local function getWorkArea(screen)
    local screen_frame = screen:frame()
    return hs.geometry.rect(
        screen_frame.x + obj.window_gap,
        screen_frame.y + obj.window_gap,
        screen_frame.w - (2 * obj.window_gap),
        screen_frame.h - (2 * obj.window_gap)
    )
end

local function doAfterAnimation(fn)
    hs.timer.doAfter(1.5 * hs.window.animationDuration, fn)
end

local function cancelPendingMoveEvents()
    for window, _ in pairs(obj.window_filter.windows) do
        if window.movedDelayed then
            obj.logger.d("cancelled windowMoved for " .. window.title)
            window.movedDelayed:stop()
            window.movedDelayed = nil
        end
    end
end

function obj:bindHotkeys(mapping)
    local spec = {
        dump_state = dumpState,
        stop_events = hs.fnutils.partial(self.stop, self),
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
        switch_space_1 = hs.fnutils.partial(self.switchToSpace, self, 1),
        switch_space_2 = hs.fnutils.partial(self.switchToSpace, self, 2),
        switch_space_3 = hs.fnutils.partial(self.switchToSpace, self, 3),
        switch_space_4 = hs.fnutils.partial(self.switchToSpace, self, 4),
        switch_space_5 = hs.fnutils.partial(self.switchToSpace, self, 5),
        switch_space_6 = hs.fnutils.partial(self.switchToSpace, self, 6),
        switch_space_7 = hs.fnutils.partial(self.switchToSpace, self, 7),
        switch_space_8 = hs.fnutils.partial(self.switchToSpace, self, 8),
        switch_space_9 = hs.fnutils.partial(self.switchToSpace, self, 9),
        move_window_1 = hs.fnutils.partial(self.moveWindowToSpace, self, 1),
        move_window_2 = hs.fnutils.partial(self.moveWindowToSpace, self, 2),
        move_window_3 = hs.fnutils.partial(self.moveWindowToSpace, self, 3),
        move_window_4 = hs.fnutils.partial(self.moveWindowToSpace, self, 4),
        move_window_5 = hs.fnutils.partial(self.moveWindowToSpace, self, 5),
        move_window_6 = hs.fnutils.partial(self.moveWindowToSpace, self, 6),
        move_window_7 = hs.fnutils.partial(self.moveWindowToSpace, self, 7),
        move_window_8 = hs.fnutils.partial(self.moveWindowToSpace, self, 8),
        move_window_9 = hs.fnutils.partial(self.moveWindowToSpace, self, 9),
    }
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

function obj:start()
    -- clear state
    window_list = {}
    index_table = {}

    -- populate window list and index table
    self:refreshWindows()

    -- set initial layout
    self:tileWindows()

    -- listen for window events
    self.window_filter:subscribe(
        { hs.window.filter.windowFocused, hs.window.filter.windowMoved },
        function(window, app, event)
            self.logger.d(event .. " for " .. window:title() or app)
            self:tileWindows(window)
        end
    )

    self.window_filter:subscribe(hs.window.filter.windowAllowed, function(window, app, event)
        self.logger.d(event .. " for " .. window:title() or app)
        if self:addWindow(window) then
            self:tileWindows()
        end
    end)

    self.window_filter:subscribe(
        { hs.window.filter.windowNotVisible, hs.window.filter.windowFullscreened },
        function(window, app, event)
            self.logger.d(event .. " for " .. window:title() or app)
            if self:removeWindow(window) then
                self:tileWindows()
            end
        end
    )

    self.window_filter:subscribe(
        { hs.window.filter.windowNotInCurrentSpace, hs.window.filter.windowInCurrentSpace },
        function(window, app, event)
            self.logger.d(event .. " for " .. window:title() or app)
            if self:refreshWindows() then
                self:tileWindows()
            end
        end
    )

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

function obj:tileSpace(anchor_window, column_index, space)
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
    local column = window_list[space][column_index]
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
    for x = column_index + 1, #window_list[space] do
        local bounds = { x = target_x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
        local column_width = self:tileColumn(window_list[space][x], bounds)
        target_x = math.min(target_x + column_width + self.window_gap, right_margin)
    end

    -- tile windows from anchor left
    local target_x2 = math.max(anchor_frame.x - self.window_gap, left_margin)
    for x = column_index - 1, 1, -1 do
        local bounds = { x = nil, x2 = target_x2, y = work_area.y, y2 = work_area.y2 }
        local column_width = self:tileColumn(window_list[space][x], bounds)
        target_x2 = math.max(target_x2 - column_width - self.window_gap, left_margin)
    end
end

function obj:tileWindows(anchor_window)
    if anchor_window then
        local space = anchor_window:spaces()[1]
        if not space then
            self.logger.d("anchor window does not have space")
            return
        end

        if spaces.spaceType(space) ~= spaces.types.user then
            self.logger.d("current space invalid")
            return -- bail
        end

        -- TODO: seems finicky
        -- if space ~= spaces.currentSpace() then
        --     self.logger.d("window not in current space")
        --     return
        -- end

        -- find anchor window index
        local anchor_index = index_table[anchor_window:id()]
        if not anchor_index then
            self.logger.d("anchor index not found")
            return -- bail
        end

        self:tileSpace(anchor_window, anchor_index.x, space)
    else
        for space, windows in pairs(window_list) do
            anchor_window = windows[1][1]
            local space = anchor_window:spaces()[1]
            self:tileSpace(anchor_window, 1, space)
        end
    end

    if self.window_filter.pending then
        self.logger.d("cancelled pending events")
        self.window_filter.pending = {}
    end

    doAfterAnimation(cancelPendingMoveEvents)
end

function obj:refreshWindows()
    -- get all windows across spaces
    local all_windows = self.window_filter:getWindows()

    local refresh_needed = false
    for _, window in ipairs(all_windows) do
        local index = index_table[window:id()]
        if not index then
            -- add window
            self:addWindow(window)
            refresh_needed = true
        elseif index.space ~= window:spaces()[1] then
            -- move to window list in new space
            self:removeWindow(window)
            self:addWindow(window)
            refresh_needed = true
        end
    end

    return refresh_needed
end

function obj:addWindow(add_window)
    -- check if window is already in window list
    if index_table[add_window:id()] then
        return false
    end

    local space = add_window:spaces()[1]
    if not space then
        self.logger.d("add window does not have a space")
        return false
    end

    -- find where to insert window
    if not window_list[space] then
        window_list[space] = {}
    end
    local add_x = add_window:frame().center.x
    local add_index = 1
    for index, column in ipairs(window_list[space]) do
        if add_x < column[1]:frame().center.x then
            add_index = index
            break
        end
    end

    -- add window
    table.insert(window_list[space], add_index, { add_window })

    -- update index table
    for x = add_index, #window_list[space] do
        for y, window in ipairs(window_list[space][x]) do
            index_table[window:id()] = { space = space, x = x, y = y }
        end
    end

    return true
end

function obj:removeWindow(remove_window)
    -- get index of window
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        self.logger.d("remove index not found")
        return false
    end

    -- remove window
    table.remove(window_list[remove_index.space][remove_index.x], remove_index.y)
    if #window_list[remove_index.space][remove_index.x] == 0 then
        table.remove(window_list[remove_index.space], remove_index.x)
    end

    -- update index table
    index_table[remove_window:id()] = nil
    for x = remove_index.x, #window_list[remove_index.space] do
        for y, window in ipairs(window_list[remove_index.space][x]) do
            index_table[window:id()] = { space = remove_index.space, x = x, y = y }
        end
    end

    -- remove if space is empty
    if #window_list[remove_index.space] == 0 then
        window_list[remove_index.space] = nil
    end

    return true
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
        local column = window_list[focused_index.space][focused_index.x + direction]
        if column then
            for y = focused_index.y, 1, -1 do
                new_focused_window = column[y]
                if new_focused_window then
                    break
                end
            end
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window =
            window_list[focused_index.space][focused_index.x][focused_index.y + (direction / 2)]
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
        local target_column = window_list[focused_index.space][target_index.x]
        if not target_column then
            self.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = window_list[focused_index.space][focused_index.x]
        window_list[focused_index.space][target_index.x] = focused_column
        window_list[focused_index.space][focused_index.x] = target_column

        -- update index table
        for y, window in ipairs(target_column) do
            index_table[window:id()] = { space = focused_index.space, x = focused_index.x, y = y }
        end
        for y, window in ipairs(focused_column) do
            index_table[window:id()] = { space = focused_index.space, x = target_index.x, y = y }
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
        local target_index = {
            space = focused_index.space,
            x = focused_index.x,
            y = focused_index.y + (direction / 2),
        }
        local target_window = window_list[target_index.space][target_index.x][target_index.y]
        if not target_window then
            self.logger.d("target window not found")
            return
        end

        -- swap places in window list
        window_list[target_index.space][target_index.x][target_index.y] = focused_window
        window_list[focused_index.space][focused_index.x][focused_index.y] = target_window

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
    self:tileWindows(focused_window)
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
    self:tileWindows(focused_window)
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
    self:tileWindows(focused_window)
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
    self:tileWindows(focused_window)
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
    local column = window_list[focused_index.space][focused_index.x - 1]
    if not column then
        self.logger.d("column not found")
        return
    end

    -- remove window
    table.remove(window_list[focused_index.space][focused_index.x], focused_index.y)
    if #window_list[focused_index.space][focused_index.x] == 0 then
        table.remove(window_list[focused_index.space], focused_index.x)
    end

    -- append to end of column
    table.insert(column, focused_window)

    -- update index table
    local num_windows = #column
    index_table[focused_window:id()] = {
        space = focused_index.space,
        x = focused_index.x - 1,
        y = num_windows,
    }
    for x = focused_index.x, #window_list[focused_index.space] do
        for y, window in ipairs(window_list[focused_index.space][x]) do
            index_table[window:id()] = { space = focused_index.space, x = x, y = y }
        end
    end

    -- adjust window frames
    local work_area = getWorkArea(focused_window:screen())
    local bounds = { x = column[1]:frame().x, x2 = nil, y = work_area.y, y2 = work_area.y2 }
    local target_h = math.max(0, work_area.h - ((num_windows - 1) * self.window_gap)) / num_windows
    self:tileColumn(column, bounds, target_h)

    -- update layout
    self:tileWindows(focused_window)
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
    local column = window_list[focused_index.space][focused_index.x]
    if #column == 1 then
        self.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.y)
    table.insert(window_list[focused_index.space], focused_index.x + 1, { focused_window })

    -- update index table
    for x = focused_index.x, #window_list[focused_index.space] do
        for y, window in ipairs(window_list[focused_index.space][x]) do
            index_table[window:id()] = { space = focused_index.space, x = x, y = y }
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
    self:tileWindows(focused_window)
end

function obj:switchToSpace(index)
    local space = getSpacesList()[index]
    if not space then
        self.logger.d("space not found")
        return
    end

    self.window_filter:pause()
    spaces.changeToSpace(space)
    doAfterAnimation(function()
        self.window_filter:resume()
    end)
end

function obj:moveWindowToSpace(index)
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.d("focused index not found")
        return
    end

    local space = getSpacesList()[index]
    if not space then
        self.logger.d("space not found")
        return
    end

    if spaces.spaceType(space) ~= spaces.types.user then
        self.logger.d("space is invalid")
        return
    end

    local screen = hs.screen.find(spaces.spaceScreenUUID(space))
    if not screen then
        self.logger.d("screen not found")
        return
    end

    self.window_filter:pause()
    self:removeWindow(focused_window)
    focused_window:spacesMoveTo(space)
    spaces.changeToSpace(space)

    -- center window
    local work_area = getWorkArea(screen) -- use new screen
    local focused_frame = focused_window:frame()
    focused_frame.w = math.min(focused_frame.w, work_area.w)
    focused_frame.x = work_area.x + (work_area.w / 2) - (focused_frame.w / 2)
    focused_frame.y, focused_frame.h = work_area.y, work_area.h
    focused_window:setFrame(focused_frame)

    -- update layout in old space
    local windows = window_list[focused_index.space]
    if windows then -- grab first window in old space
        self:tileSpace(windows[1][1], 1, focused_index.space)
    end

    -- tile windows in new space
    doAfterAnimation(function()
        if windows then
            cancelPendingMoveEvents()
        end
        self:addWindow(focused_window)
        self:tileWindows(focused_window)
        self.window_filter:resume()
    end)
end

return obj
