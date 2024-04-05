--- === PaperWM.spoon ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- # Usage
---
--- `PaperWM:start()` will begin automatically tiling new and existing windows.
--- `PaperWM:stop()` will release control over windows.
---
--- Set `PaperWM.window_gap` to the number of pixels to space between windows and
--- the top and bottom screen edges.
---
--- Overwrite `PaperWM.window_filter` to ignore specific applications. For example:
---
--- ```
--- PaperWM.window_filter = PaperWM.window_filter:setAppFilter("Finder", false)
--- PaperWM:start() -- restart for new window filter to take effect
--- ```
---
--- # Limitations
---
--- MacOS does not allow a window to be moved fully off-screen. Windows that would
--- be tiled off-screen are placed in a margin on the left and right edge of the
--- screen. They are still visible and clickable.
---
--- It's difficult to detect when a window is dragged from one space or screen to
--- another. Use the move_window_N commands to move windows between spaces and
--- screens.
---
--- Arrange screens vertically to prevent windows from bleeding into other screens.
---
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)
local Mouse <const> = hs.mouse
local Rect <const> = hs.geometry.rect
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Timer <const> = hs.timer
local Watcher <const> = hs.uielement.watcher
local Window <const> = hs.window
local WindowFilter <const> = hs.window.filter
local leftClick <const> = hs.eventtap.leftClick
local partial <const> = hs.fnutils.partial
local rectMidPoint <const> = hs.geometry.rectMidPoint

local PaperWM = {}
PaperWM.__index = PaperWM

-- Metadata
PaperWM.name = "PaperWM"
PaperWM.version = "0.4"
PaperWM.author = "Michael Mogenson"
PaperWM.homepage = "https://github.com/mogenson/PaperWM.spoon"
PaperWM.license = "MIT - https://opensource.org/licenses/MIT"

PaperWM.default_hotkeys = {
    stop_events          = { { "alt", "cmd", "shift" }, "q" },
    refresh_windows      = { { "alt", "cmd", "shift" }, "r" },
    focus_left           = { { "alt", "cmd" }, "left" },
    focus_right          = { { "alt", "cmd" }, "right" },
    focus_up             = { { "alt", "cmd" }, "up" },
    focus_down           = { { "alt", "cmd" }, "down" },
    swap_left            = { { "alt", "cmd", "shift" }, "left" },
    swap_right           = { { "alt", "cmd", "shift" }, "right" },
    swap_up              = { { "alt", "cmd", "shift" }, "up" },
    swap_down            = { { "alt", "cmd", "shift" }, "down" },
    center_window        = { { "alt", "cmd" }, "c" },
    full_width           = { { "alt", "cmd" }, "f" },
    cycle_width          = { { "alt", "cmd" }, "r" },
    cycle_height         = { { "alt", "cmd", "shift" }, "r" },
    reverse_cycle_width  = { { "ctrl", "alt", "cmd" }, "r" },
    reverse_cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in             = { { "alt", "cmd" }, "i" },
    barf_out             = { { "alt", "cmd" }, "o" },
    switch_space_l       = { { "alt", "cmd" }, "," },
    switch_space_r       = { { "alt", "cmd" }, "." },
    switch_space_1       = { { "alt", "cmd" }, "1" },
    switch_space_2       = { { "alt", "cmd" }, "2" },
    switch_space_3       = { { "alt", "cmd" }, "3" },
    switch_space_4       = { { "alt", "cmd" }, "4" },
    switch_space_5       = { { "alt", "cmd" }, "5" },
    switch_space_6       = { { "alt", "cmd" }, "6" },
    switch_space_7       = { { "alt", "cmd" }, "7" },
    switch_space_8       = { { "alt", "cmd" }, "8" },
    switch_space_9       = { { "alt", "cmd" }, "9" },
    move_window_1        = { { "alt", "cmd", "shift" }, "1" },
    move_window_2        = { { "alt", "cmd", "shift" }, "2" },
    move_window_3        = { { "alt", "cmd", "shift" }, "3" },
    move_window_4        = { { "alt", "cmd", "shift" }, "4" },
    move_window_5        = { { "alt", "cmd", "shift" }, "5" },
    move_window_6        = { { "alt", "cmd", "shift" }, "6" },
    move_window_7        = { { "alt", "cmd", "shift" }, "7" },
    move_window_8        = { { "alt", "cmd", "shift" }, "8" },
    move_window_9        = { { "alt", "cmd", "shift" }, "9" }
}

-- filter for windows to manage
PaperWM.window_filter = WindowFilter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    hasTitlebar = true,
    allowRoles = "AXStandardWindow"
})

-- number of pixels between windows
PaperWM.window_gap = 8

-- ratios to use when cycling widths and heights, golden ratio by default
PaperWM.window_ratios = { 0.23607, 0.38195, 0.61804 }

-- size of the on-screen margin to place off-screen windows
PaperWM.screen_margin = 1

-- logger
PaperWM.logger = hs.logger.new(PaperWM.name)

-- constants
local Direction <const> = {
    LEFT = -1,
    RIGHT = 1,
    UP = -2,
    DOWN = 2,
    WIDTH = 3,
    HEIGHT = 4,
    ASCENDING = 5,
    DESCENDING = 6
}

-- array of windows sorted from left to right
local window_list = {} -- 4D array of tiles in order of [space][x][y][tab]
local index_table = {} -- dictionary of {space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys

-- refresh window layout on screen change
local screen_watcher = Screen.watcher.new(function() PaperWM:refreshWindows() end)

local function trace()
    if PaperWM.logger.getLogLevel() == 5 then
        local name = debug.getinfo(2, "n").name
        if name then PaperWM.logger.vf("PaperWM:%s()", name) end
    end
end

local function getSpace(index)
    local layout = Spaces.allSpaces()
    for _, screen in ipairs(Screen.allScreens()) do
        local screen_uuid = screen:getUUID()
        local num_spaces = #layout[screen_uuid]
        if num_spaces >= index then return layout[screen_uuid][index] end
        index = index - num_spaces
    end
end

local function getFirstVisibleWindow(columns, screen)
    local x = screen:frame().x
    for _, tabs in ipairs(columns or {}) do
        local window = tabs[1][1] -- take first window in column
        if window:frame().x >= x then return window end
    end
end

local function getColumn(space, col) return (window_list[space] or {})[col] end

local function getRow(space, col, row) return (getColumn(space, col) or {})[row] end

local function getWindow(space, col, row) return (getRow(space, col, row) or {})[1] end

-- current focused window
local focused_window = nil
local function getFocusedWindow()
    -- used cached result if available and return main window for tabs
    local window = focused_window or Window.focusedWindow()
    local index = index_table[window and window:id()]
    -- if index then window = getWindow(index.space, index.col, index.row) end
    return window, index
end

local function getCanvas(screen)
    local screen_frame = screen:frame()
    return Rect(screen_frame.x + PaperWM.window_gap,
        screen_frame.y + PaperWM.window_gap,
        screen_frame.w - (2 * PaperWM.window_gap),
        screen_frame.h - (2 * PaperWM.window_gap))
end

local function updateIndexTable(space, column)
    local columns = window_list[space] or {}
    for col = column, #columns do
        for row, tabs in ipairs(getColumn(space, col)) do
            for _, window in ipairs(tabs) do
                index_table[window:id()] = { space = space, col = col, row = row }
            end
        end
    end
end

local pending_window = nil
local function windowEventHandler(window, event, self)
    self.logger.df("%s for [%s] id: %d", event, window, window and window:id() or -1)
    local space = nil

    --[[ When a new window is created, We first get a windowVisible event but
    without a Space. Next we receive a windowFocused event for the window, but
    this also sometimes lacks a Space. Our approach is to store the window
    pending a Space in the pending_window variable and set a timer to try to add
    the window again later. Also schedule the windowFocused handler to run later
    after the window was added ]]
    --

    if event == "windowFocused" then
        if pending_window and window == pending_window then
            Timer.doAfter(Window.animationDuration,
                function()
                    windowEventHandler(window, event, self)
                end)
            return
        end
        focused_window = window
        space = Spaces.windowSpaces(window)[1]
    elseif event == "windowVisible" or event == "windowUnfullscreened" then
        space = self:addWindow(window)
        if pending_window and window == pending_window then
            pending_window = nil -- tried to add window for the second time
        elseif not space then
            pending_window = window
            Timer.doAfter(Window.animationDuration,
                function()
                    windowEventHandler(window, event, self)
                end)
            return
        end
    elseif event == "windowNotVisible" then
        space = self:removeWindow(window)
    elseif event == "windowFullscreened" then
        space = self:removeWindow(window, true) -- don't focus new window if fullscreened
    elseif event == "AXWindowMoved" or event == "AXWindowResized" then
        space = Spaces.windowSpaces(window)[1]
    end

    if space then self:tileSpace(space) end
end

local function focusSpace(space, window)
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        return
    end

    -- move cursor to center of screen
    local point = rectMidPoint(screen:fullFrame())
    Mouse.absolutePosition(point)

    -- focus provided window or first window on new space
    window = window or getFirstVisibleWindow(window_list[space], screen)
    if window then
        window:focus()
        -- MacOS will sometimes switch to another window of the same applications on a different space
        -- Setup a timer to check that the requested window stays focused
        local function focusCheck()
            if window ~= Window.focusedWindow() then
                window:focus()
            end
        end
        for i = 1, 3 do Timer.doAfter(i * Window.animationDuration, focusCheck) end
    elseif Spaces.spaceType(space) == "user" then
        leftClick(point) -- if there are no windows and the space is a user space then click
    end
end

function PaperWM:start()
    trace()

    -- check for some settings
    if not Spaces.screensHaveSeparateSpaces() then
        self.logger.e(
            "please check 'Displays have separate Spaces' in System Preferences -> Mission Control")
    end

    -- clear state
    window_list = {}
    index_table = {}
    ui_watchers = {}

    -- populate window list, index table, ui_watchers, and set initial layout
    self:refreshWindows()

    -- listen for window events
    self.window_filter:subscribe({
        WindowFilter.windowFocused, WindowFilter.windowVisible,
        WindowFilter.windowNotVisible, WindowFilter.windowFullscreened,
        WindowFilter.windowUnfullscreened
    }, function(window, _, event) windowEventHandler(window, event, self) end)

    -- watch for external monitor plug / unplug
    screen_watcher:start()

    return self
end

function PaperWM:stop()
    trace()

    -- stop events
    self.window_filter:unsubscribeAll()
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
    screen_watcher:stop()

    return self
end

function PaperWM:tileColumn(rows, bounds, h, w, id, h4id)
    trace()

    local last_window, frame
    for _, tabs in ipairs(rows) do
        local window = tabs[1] -- take main window
        frame = window:frame()
        w = w or frame.w       -- take given width or width of first window
        if bounds.x then       -- set either left or right x coord
            frame.x = bounds.x
        elseif bounds.x2 then
            frame.x = bounds.x2 - w
        end
        if h then              -- set height if given
            if id and h4id and window:id() == id then
                frame.h = h4id -- use this height for window with id
            else
                frame.h = h    -- use this height for all other windows
            end
        end
        frame.y = bounds.y
        frame.w = w
        frame.y2 = math.min(frame.y2, bounds.y2) -- don't overflow bottom of bounds
        self:moveWindow(window, frame)
        bounds.y = math.min(frame.y2 + self.window_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        self:moveWindow(last_window, frame)
    end
    return w -- return width of column
end

function PaperWM:tileSpace(space)
    trace()

    if not space or Spaces.spaceType(space) ~= "user" then
        self.logger.e("current space invalid")
        return
    end

    -- find screen for space
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        self.logger.e("no screen for space")
        return
    end

    -- if focused window is in space, tile from that
    local focused_window = getFocusedWindow()
    local anchor_window = (focused_window and (Spaces.windowSpaces(focused_window)[1] == space))
        and focused_window or getFirstVisibleWindow(window_list[space], screen)

    if not anchor_window then
        self.logger.e("no anchor window in space")
        return
    end

    local anchor_index = index_table[anchor_window:id()]
    if not anchor_index then
        self.logger.e("anchor index not found")
        -- if self:addWindow(anchor_window) == space then
        --     self.logger.d("added missing window")
        --     anchor_index = index_table[anchor_window:id()]
        -- else
        return -- bail
        -- end
    end

    -- anchor window may be tab, get main window
    -- anchor_window = getWindow(anchor_index.space, anchor_index.col, anchor_index.row)
    -- if anchor_window then
    --     local index = index_table[anchor_window:id()]
    --     if not (anchor_index.space == index.space and anchor_index.col == index.col and anchor_index.row == index.row) then
    --         self.logger.e("anchor indexes do not match")
    --         return
    --     end
    -- else
    --     self.logger.e("no anchor window at anchor index")
    --     return
    -- end

    -- get some global coordinates
    local screen_frame <const> = screen:frame()
    local left_margin <const> = screen_frame.x + self.screen_margin
    local right_margin <const> = screen_frame.x2 - self.screen_margin
    local canvas <const> = getCanvas(screen)

    -- make sure anchor window is on screen
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, canvas.x)
    anchor_frame.w = math.min(anchor_frame.w, canvas.w)
    anchor_frame.h = math.min(anchor_frame.h, canvas.h)
    if anchor_frame.x2 > canvas.x2 then
        anchor_frame.x = canvas.x2 - anchor_frame.w
    end

    -- adjust anchor window column
    local column = getColumn(space, anchor_index.col)
    if not column then
        self.logger.e("no anchor window column")
        return
    end

    -- TODO: need a minimum window height
    if #column == 1 then -- only one row
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        self:moveWindow(anchor_window, anchor_frame)
    else
        local n = #column - 1 -- number of other rows in column
        local h =
            math.max(0, canvas.h - anchor_frame.h - (n * self.window_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        self:tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(),
            anchor_frame.h)
    end

    -- tile windows from anchor right
    local x = math.min(anchor_frame.x2 + self.window_gap, right_margin)
    for col = anchor_index.col + 1, #(window_list[space] or {}) do
        local bounds = { x = x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
        local column_width = self:tileColumn(getColumn(space, col), bounds)
        x = math.min(x + column_width + self.window_gap, right_margin)
    end

    -- tile windows from anchor left
    local x2 = math.max(anchor_frame.x - self.window_gap, left_margin)
    for col = anchor_index.col - 1, 1, -1 do
        local bounds = { x = nil, x2 = x2, y = canvas.y, y2 = canvas.y2 }
        local column_width = self:tileColumn(getColumn(space, col), bounds)
        x2 = math.max(x2 - column_width - self.window_gap, left_margin)
    end
end

function PaperWM:refreshWindows()
    trace()

    -- get all windows across spaces
    local all_windows = self.window_filter:getWindows()

    local retile_spaces = {} -- spaces that need to be retiled
    for _, window in ipairs(all_windows) do
        local index = index_table[window:id()]
        if not index then
            -- add window
            local space = self:addWindow(window)
            if space then retile_spaces[space] = true end
        elseif index.space ~= Spaces.windowSpaces(window)[1] then
            -- move to window list in new space
            self:removeWindow(window)
            local space = self:addWindow(window)
            if space then retile_spaces[space] = true end
        end
    end

    -- retile spaces
    for space, _ in pairs(retile_spaces) do self:tileSpace(space) end
end

function PaperWM:addWindow(add_window)
    trace()

    --[[ A window with no tabs will have a tabCount of 0. A new tab for an
        existing window will have a tabCount equal to the total number of tabs
        (eg. 2 for the first new tab). The tabCount for existing tabs will be
        set back to 0. This means we need to capture and track each new tab when
        it is created. We cannot identify a tab later.]]
    --


    -- MIKE_TAB TODO: if add_window is in window_list, but not at tab[1] position, then it was removed as a tab and is now a window
    local space = Spaces.windowSpaces(add_window)[1]
    if not space then
        self.logger.e("add window does not have a space")
        return nil
    end

    if add_window:tabCount() > 0 then
        -- focus_window should still be set to the previously focused window at this point.
        -- assume that the new tab was created from the focused window
        if focused_window and focused_window:application():name() == add_window:application():name() then
            local main_index = index_table[focused_window:id()]
            if not main_index then
                self.logger.e("main window for new tab does not have an index")
                return nil
            end
            index_table[add_window:id()] = main_index -- point tab at main window index
            table.insert(getRow(main_index.space, main_index.col, main_index.row), add_window)

            self.logger.df("adding new window tab: %s id: %d", add_window, add_window:id())
            hs.notify.show("PaperWM", "New Tab Detected:", add_window:title())
        else
            hs.notify.show("PaperWM", "Can't find main window for new tab:", add_window:title())
            self.logger.ef("can't find main window for new tab: %s", add_window)
            return nil
        end
    else
        -- check if window is already in window list
        if index_table[add_window:id()] then return nil end

        if not window_list[space] then window_list[space] = {} end

        -- find where to insert window
        local add_column = 1

        -- when addWindow() is called from a window created event:
        -- focused_window from previous window focused event will not be add_window
        -- hs.window.focusedWindow() will return add_window
        -- new window focused event for add_window has not happened yet
        if focused_window and
            ((index_table[focused_window:id()] or {}).space == space) and
            (focused_window:id() ~= add_window:id()) then
            add_column = index_table[focused_window:id()].col + 1 -- insert to the right
        else
            local x = add_window:frame().center.x
            for col, rows in ipairs(window_list[space]) do
                local tabs = rows[1]   -- take first row
                local window = tabs[1] -- take main window of tabs
                if x < window:frame().center.x then
                    add_column = col
                    break
                end
            end
        end

        -- add window
        table.insert(window_list[space], add_column, { { add_window } })

        -- update index table
        updateIndexTable(space, add_column)
    end

    -- subscribe to window moved events
    local watcher = add_window:newWatcher(
        function(window, event, _, self)
            windowEventHandler(window, event, self)
        end, self)
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    ui_watchers[add_window:id()] = watcher

    return space
end

function PaperWM:removeWindow(remove_window, skip_new_window_focus)
    trace()

    -- remove watcher
    ui_watchers[remove_window:id()] = nil

    -- get index of window
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        self.logger.e("remove index not found")
        return nil
    end

    if not skip_new_window_focus then -- find nearby window to focus
        local focused_window = getFocusedWindow()
        if focused_window and remove_window:id() == focused_window:id() then
            for _, direction in ipairs({
                Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT
            }) do if self:focusWindow(direction, remove_index) then break end end
        end
    end

    -- find position of window in list of tabs
    local remove_tab = 1
    for i, tab in ipairs(getRow(remove_index.space, remove_index.col, remove_index.row)) do
        if remove_window:id() == tab:id() then
            remove_tab = i
            break
        end
    end

    -- remove window from list of tabs
    table.remove(getRow(remove_index.space, remove_index.col, remove_index.row), remove_tab)

    -- if no more tabs, remove the row
    if #getRow(remove_index.space, remove_index.col, remove_index.row) == 0 then
        table.remove(getColumn(remove_index.space, remove_index.col), remove_index.row)
    end

    -- if no more rows, remove the column
    if #getColumn(remove_index.space, remove_index.col) == 0 then
        table.remove(window_list[remove_index.space], remove_index.col)
    end

    -- update index table
    index_table[remove_window:id()] = nil
    updateIndexTable(remove_index.space, remove_index.col)

    -- remove if space is empty
    if #window_list[remove_index.space] == 0 then
        window_list[remove_index.space] = nil
    end

    return remove_index.space -- return space for removed window
end

function PaperWM:focusWindow(direction, focused_index)
    trace()

    if not focused_index then
        -- get current focused window
        local focused_window
        focused_window, focused_index = getFocusedWindow()
        if not focused_window then return nil end
    end

    if not focused_index then
        self.logger.e("focused index not found")
        return nil
    end

    -- get new focused window
    local new_focused_window
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- walk down column, looking for match in neighbor column
        for row = focused_index.row, 1, -1 do
            -- MIKE_TAB TODO: maybe remember last focused tab instead of focusing first tab
            new_focused_window = getWindow(focused_index.space,
                focused_index.col + direction, row)
            if new_focused_window then break end
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window = getWindow(focused_index.space, focused_index.col,
            focused_index.row + (direction // 2))
    end

    if not new_focused_window then
        self.logger.d("new focused window not found")
        return nil
    end

    -- focus new window, windowFocused event will be emited immediately
    new_focused_window:focus()
    return new_focused_window
end

function PaperWM:swapWindows(direction)
    trace()

    -- use focused window as source window
    local focused_window, focused_index = getFocusedWindow()
    if not focused_window then return end
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- get target windows
        local target_index = { col = focused_index.col + direction }
        local target_column = getColumn(focused_index.space, target_index.col)
        if not target_column then
            self.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = getColumn(focused_index.space, focused_index.col)
        window_list[focused_index.space][target_index.col] = focused_column
        window_list[focused_index.space][focused_index.col] = target_column

        -- update index table
        for row, tabs in ipairs(target_column) do
            for _, window in ipairs(tabs) do
                index_table[window:id()] = {
                    space = focused_index.space,
                    col = focused_index.col,
                    row = row
                }
            end
        end
        for row, tabs in ipairs(focused_column) do
            for _, window in ipairs(tabs) do
                index_table[window:id()] = {
                    space = focused_index.space,
                    col = target_index.col,
                    row = row
                }
            end
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1][1]:frame()
        if direction == Direction.LEFT then
            focused_frame.x = target_frame.x
            target_frame.x = focused_frame.x2 + self.window_gap
        else -- Direction.RIGHT
            target_frame.x = focused_frame.x
            focused_frame.x = target_frame.x2 + self.window_gap
        end
        for _, tabs in ipairs(target_column) do
            local window = tabs[1] -- only move main window
            local frame = window:frame()
            frame.x = target_frame.x
            self:moveWindow(window, frame)
        end
        for _, tabs in ipairs(focused_column) do
            local window = tabs[1] -- only move main window
            local frame = window:frame()
            frame.x = focused_frame.x
            self:moveWindow(window, frame)
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        -- get target window
        local target_index = {
            space = focused_index.space,
            col = focused_index.col,
            row = focused_index.row + (direction // 2)
        }
        local target_tabs = getRow(target_index.space, target_index.col, target_index.row)
        if not target_tabs then
            self.logger.d("target tabs not found")
            return
        end
        local focused_tabs = getRow(focused_index.space, focused_index.col, focused_index.row)
        if not focused_tabs then
            self.logger.d("focused tabs not found")
            return
        end

        -- swap places in window list
        window_list[target_index.space][target_index.col][target_index.row] =
            focused_tabs
        window_list[focused_index.space][focused_index.col][focused_index.row] =
            target_tabs

        -- update index table
        for _, window in ipairs(target_tabs) do
            index_table[window:id()] = focused_index
        end
        for _, window in ipairs(focused_tabs) do
            index_table[window:id()] = target_index
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_window = target_tabs[1]
        local target_frame = target_window:frame()
        if direction == Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + self.window_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + self.window_gap
        end
        self:moveWindow(focused_window, focused_frame)
        self:moveWindow(target_window, target_frame)
    end

    -- update layout
    self:tileSpace(focused_index.space)
end

function PaperWM:centerWindow()
    trace()

    -- get current focused window
    local focused_window = getFocusedWindow()
    if not focused_window then return end

    -- get global coordinates
    local focused_frame = focused_window:frame()
    local screen_frame = focused_window:screen():frame()

    -- center window
    focused_frame.x = screen_frame.x + (screen_frame.w // 2) -
        (focused_frame.w // 2)
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(space)
end

function PaperWM:setWindowFullWidth()
    trace()

    -- get current focused window
    local focused_window = getFocusedWindow()
    if not focused_window then return end

    -- fullscreen window width
    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    focused_frame.x, focused_frame.w = canvas.x, canvas.w
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(space)
end

function PaperWM:cycleWindowSize(direction, cycle_direction)
    trace()

    -- get current focused window
    local focused_window = getFocusedWindow()
    if not focused_window then return end

    local function findNewSize(area_size, frame_size, cycle_direction)
        local sizes = {}
        local new_size
        if cycle_direction == Direction.ASCENDING then
            for index, ratio in ipairs(self.window_ratios) do
                sizes[index] = ratio * (area_size + self.window_gap) - self.window_gap
            end

            -- find new size
            new_size = sizes[1]
            for _, size in ipairs(sizes) do
                if size > frame_size + 10 then
                    new_size = size
                    break
                end
            end
        elseif cycle_direction == Direction.DESCENDING then
            for index, ratio in ipairs(self.window_ratios) do
                sizes[index] = ratio * (area_size + self.window_gap) - self.window_gap
            end

            -- find new size, starting from the end
            new_size = sizes[#sizes] -- Start with the largest size
            for i = #sizes, 1, -1 do
                if sizes[i] < frame_size - 10 then
                    new_size = sizes[i]
                    break
                end
            end
        else
            self.logger.e("cycle_direction must be either Direction.ASCENDING or Direction.DESCENDING")
            return
        end

        return new_size
    end

    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()

    if direction == Direction.WIDTH then
        local new_width = findNewSize(canvas.w, focused_frame.w, cycle_direction)
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_width) // 2)
        focused_frame.w = new_width
    elseif direction == Direction.HEIGHT then
        local new_height = findNewSize(canvas.h, focused_frame.h, cycle_direction)
        focused_frame.y = math.max(canvas.y, focused_frame.y + ((focused_frame.h - new_height) // 2))
        focused_frame.h = new_height
        focused_frame.y = focused_frame.y - math.max(0, focused_frame.y2 - canvas.y2)
    else
        self.logger.e("direction must be either Direction.WIDTH or Direction.HEIGHT")
        return
    end

    -- apply new size
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(space)
end

function PaperWM:slurpWindow()
    trace()

    -- TODO paperwm behavior:
    -- add top window from column to the right to bottom of current column
    -- if no colum to the right and current window is only window in current column,
    -- add current window to bottom of column to the left

    -- get current focused window
    local focused_window, focused_index = getFocusedWindow()
    if not focused_window then return end
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get column to left
    local column = getColumn(focused_index.space, focused_index.col - 1)
    if not column then
        self.logger.d("column not found")
        return
    end

    -- remove row of tabs from column
    local tabs = table.remove(getColumn(focused_index.space, focused_index.col), focused_index.row)
    -- if no more rows, remove column
    if #getColumn(focused_index.space, focused_index.col) == 0 then
        table.remove(window_list[focused_index.space], focused_index.col)
    end

    -- append to end of column
    table.insert(column, tabs)

    -- update index table
    local num_rows = #column
    for _, window in ipairs(tabs) do
        index_table[window:id()] = {
            space = focused_index.space,
            col = focused_index.col - 1,
            row = num_rows
        }
    end
    updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local canvas = getCanvas(focused_window:screen())
    local bounds = {
        x = column[1][1]:frame().x,
        x2 = nil,
        y = canvas.y,
        y2 = canvas.y2
    }
    local h = math.max(0, canvas.h - ((num_rows - 1) * self.window_gap)) //
        num_rows
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.space)
end

function PaperWM:barfWindow()
    trace()

    -- TODO paperwm behavior:
    -- remove bottom window of current column
    -- place window into a new column to the right--

    -- get current focused window
    local focused_window, focused_index = getFocusedWindow()
    if not focused_window then return end
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get column
    local column = getColumn(focused_index.space, focused_index.col)
    if not column or #column == 1 then
        self.logger.d("no multiple rows in column")
        return
    end

    -- remove window and insert in new column
    local tabs = table.remove(column, focused_index.row)
    table.insert(window_list[focused_index.space], focused_index.col + 1,
        { tabs })

    -- update index table
    updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local num_rows = #column
    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    local bounds = { x = focused_frame.x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
    local h = math.max(0, canvas.h - ((num_rows - 1) * self.window_gap)) //
        num_rows
    focused_frame.y = canvas.y
    focused_frame.x = focused_frame.x2 + self.window_gap
    focused_frame.h = canvas.h
    self:moveWindow(focused_window, focused_frame)
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.space)
end

function PaperWM:switchToSpace(index)
    trace()

    local space = getSpace(index)
    if not space then
        self.logger.d("space not found")
        return
    end

    Spaces.gotoSpace(space)
    focusSpace(space)
end

function PaperWM:incrementSpace(direction)
    trace()

    if (direction ~= Direction.LEFT and direction ~= Direction.RIGHT) then
        self.logger.d("move is invalid, left and right only")
        return
    end
    local curr_space_id = Spaces.focusedSpace()
    local layout = Spaces.allSpaces()
    local curr_space_idx = -1
    local num_spaces = 0
    for _, screen in ipairs(Screen.allScreens()) do
        local screen_uuid = screen:getUUID()
        if curr_space_idx < 0 then
            for idx, space_id in ipairs(layout[screen_uuid]) do
                if curr_space_id == space_id then
                    curr_space_idx = idx + num_spaces
                    break
                end
            end
        end
        num_spaces = num_spaces + #layout[screen_uuid]
    end

    if curr_space_idx >= 0 then
        local new_space_idx = ((curr_space_idx - 1 + direction) % num_spaces) + 1
        self:switchToSpace(new_space_idx)
    end
end

function PaperWM:moveWindowToSpace(index)
    trace()

    local focused_window, focused_index = getFocusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    local new_space = getSpace(index)
    if not new_space then
        self.logger.d("space not found")
        return
    end

    if new_space == Spaces.windowSpaces(focused_window)[1] then
        self.logger.d("window already on space")
        return
    end

    if Spaces.spaceType(new_space) ~= "user" then
        self.logger.d("space is invalid")
        return
    end

    local tabs = getRow(focused_index.space, focused_index.col, focused_index.row)
    if not tabs or focused_window:id() ~= tabs[1]:id() then
        self.logger.e("focused window is not in tabs")
        return
    end

    -- focused_window needs to be a local copy so it is not garbage collected
    local old_space = self:removeWindow(focused_window, true)
    self:addWindow(focused_window)

    -- MIKE_TAB TODO: handle tabs
    -- for i, window in ipairs(tabs) do
    --     old_space = self:removeWindow(window, true)
    --     if not old_space then
    --         self.logger.ef("can't remove tab %d", i)
    --         return
    --     end
    --     Spaces.moveWindowToSpace(focused_window, new_space)
    -- end

    -- self:addWindow(focused_window)
    -- -- manually add known tabs
    -- local num_tabs = #tabs
    -- if num_tabs > 1 then
    --     local main_index = index_table[focused_window:id()]
    --     for i = 2, num_tabs do
    --         local window = tabs[i]
    --         index_table[window:id()] = main_index
    --         table.insert(getRow(main_index.space, main_index.col, main_index.row), window)
    --         local watcher = window:newWatcher(
    --             function(win, event, _, self)
    --                 windowEventHandler(win, event, self)
    --             end, self)
    --         watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    --         ui_watchers[window:id()] = watcher
    --     end
    -- end

    self:tileSpace(old_space)
    self:tileSpace(new_space)
    Spaces.gotoSpace(new_space)

    focusSpace(new_space, focused_window)
end

function PaperWM:moveWindow(window, frame)
    trace()

    -- greater than 0.017 hs.window animation step time
    local padding <const> = 0.02

    local watcher = ui_watchers[window:id()]
    if not watcher then
        self.logger.e("window does not have ui watcher")
        return
    end

    if frame == window:frame() then
        self.logger.v("no change in window frame")
        return
    end

    watcher:stop()
    window:raise() -- bring a tab to the front
    window:setFrame(frame)
    Timer.doAfter(Window.animationDuration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
end

PaperWM.actions = {
    stop_events = partial(PaperWM.stop, PaperWM),
    refresh_windows = partial(PaperWM.refreshWindows, PaperWM),
    focus_left = partial(PaperWM.focusWindow, PaperWM, Direction.LEFT),
    focus_right = partial(PaperWM.focusWindow, PaperWM, Direction.RIGHT),
    focus_up = partial(PaperWM.focusWindow, PaperWM, Direction.UP),
    focus_down = partial(PaperWM.focusWindow, PaperWM, Direction.DOWN),
    swap_left = partial(PaperWM.swapWindows, PaperWM, Direction.LEFT),
    swap_right = partial(PaperWM.swapWindows, PaperWM, Direction.RIGHT),
    swap_up = partial(PaperWM.swapWindows, PaperWM, Direction.UP),
    swap_down = partial(PaperWM.swapWindows, PaperWM, Direction.DOWN),
    center_window = partial(PaperWM.centerWindow, PaperWM),
    full_width = partial(PaperWM.setWindowFullWidth, PaperWM),
    cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.ASCENDING),
    cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.ASCENDING),
    reverse_cycle_width = partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.DESCENDING),
    reverse_cycle_height = partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.DESCENDING),
    slurp_in = partial(PaperWM.slurpWindow, PaperWM),
    barf_out = partial(PaperWM.barfWindow, PaperWM),
    switch_space_l = partial(PaperWM.incrementSpace, PaperWM, Direction.LEFT),
    switch_space_r = partial(PaperWM.incrementSpace, PaperWM, Direction.RIGHT),
    switch_space_1 = partial(PaperWM.switchToSpace, PaperWM, 1),
    switch_space_2 = partial(PaperWM.switchToSpace, PaperWM, 2),
    switch_space_3 = partial(PaperWM.switchToSpace, PaperWM, 3),
    switch_space_4 = partial(PaperWM.switchToSpace, PaperWM, 4),
    switch_space_5 = partial(PaperWM.switchToSpace, PaperWM, 5),
    switch_space_6 = partial(PaperWM.switchToSpace, PaperWM, 6),
    switch_space_7 = partial(PaperWM.switchToSpace, PaperWM, 7),
    switch_space_8 = partial(PaperWM.switchToSpace, PaperWM, 8),
    switch_space_9 = partial(PaperWM.switchToSpace, PaperWM, 9),
    move_window_1 = partial(PaperWM.moveWindowToSpace, PaperWM, 1),
    move_window_2 = partial(PaperWM.moveWindowToSpace, PaperWM, 2),
    move_window_3 = partial(PaperWM.moveWindowToSpace, PaperWM, 3),
    move_window_4 = partial(PaperWM.moveWindowToSpace, PaperWM, 4),
    move_window_5 = partial(PaperWM.moveWindowToSpace, PaperWM, 5),
    move_window_6 = partial(PaperWM.moveWindowToSpace, PaperWM, 6),
    move_window_7 = partial(PaperWM.moveWindowToSpace, PaperWM, 7),
    move_window_8 = partial(PaperWM.moveWindowToSpace, PaperWM, 8),
    move_window_9 = partial(PaperWM.moveWindowToSpace, PaperWM, 9)
}

function PaperWM:bindHotkeys(mapping)
    local spec = self.actions
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

return PaperWM
