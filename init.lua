--- === PaperWM.spoon ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- # Usage
---
--- `PaperWM:start()` will begin automatically tiling new and existing windows.
--- `PaperWM:stop()` will release control over windows.
---
--- Set window gaps using `PaperWM.window_gap`:
--- - As a single number: same gap for all sides
--- - As a table with specific sides: `{top=8, bottom=8, left=8, right=8}`
---
--- For example:
--- ```
--- PaperWM.window_gap = 10  -- 10px gap on all sides
--- -- or
--- PaperWM.window_gap = {top=10, bottom=8, left=12, right=12}
--- ```
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
local Rect <const> = hs.geometry.rect
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Timer <const> = hs.timer
local Watcher <const> = hs.uielement.watcher
local Window <const> = hs.window
local WindowFilter <const> = hs.window.filter
local Fnutils <const> = hs.fnutils

local MissionControl = dofile(hs.spoons.resourcePath("mission_control.lua"))
local Swipe = dofile(hs.spoons.resourcePath("swipe.lua"))

local PaperWM = {}
PaperWM.__index = PaperWM

-- Metadata
PaperWM.name = "PaperWM"
PaperWM.version = "0.6"
PaperWM.author = "Michael Mogenson"
PaperWM.homepage = "https://github.com/mogenson/PaperWM.spoon"
PaperWM.license = "MIT - https://opensource.org/licenses/MIT"

-- Types

---@alias PaperWM table PaperWM module object
---@alias Window userdata a ui.window
---@alias Frame table hs.geometry.rect
---@alias Index { row: number, col: number, space: number }
---@alias Space number a Mission Control space ID
---@alias Screen userdata hs.screen

---@alias Mapping { [string]: (table | string)[]}
PaperWM.default_hotkeys = {
    stop_events          = { { "alt", "cmd", "shift" }, "q" },
    refresh_windows      = { { "alt", "cmd", "shift" }, "r" },
    toggle_floating      = { { "alt", "cmd", "shift" }, "escape" },
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

-- window gaps: can be set as a single number or a table with top, bottom, left, right values
PaperWM.window_gap = {
    top = 8,
    bottom = 8,
    left = 8,
    right = 8,
}

-- ratios to use when cycling widths and heights, golden ratio by default
PaperWM.window_ratios = { 0.23607, 0.38195, 0.61804 }

-- size of the on-screen margin to place off-screen windows
PaperWM.screen_margin = 1

-- number of fingers to detect a horizontal swipe, set to 0 to disable
PaperWM.swipe_fingers = 0

-- increase this number to make windows move futher when swiping
PaperWM.swipe_gain = 1

-- logger
PaperWM.logger = hs.logger.new(PaperWM.name)
MissionControl.log = PaperWM.logger

-- constants
---@enum Direction
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

-- hs.settings key for persisting is_floating, stored as an array of window id
local IsFloatingKey <const> = 'PaperWM_is_floating'

-- array of windows sorted from left to right
local window_list = {} -- 3D array of tiles in order of [space][x][y]
local index_table = {} -- dictionary of {space, x, y} with window id for keys
local ui_watchers = {} -- dictionary of uielement watchers with window id for keys
local is_floating = {} -- dictionary of boolean with window id for keys
local x_positions = {} -- dictionary of horizontal positions with [space][window] for keys

-- refresh window layout on screen change
local screen_watcher = Screen.watcher.new(function() PaperWM:refreshWindows() end)

---return the first window that's completely on the screen
---@param space Space space to lookup windows
---@param screen_frame Frame the coordinates of the screen
---@pram direction Direction|nil either LEFT or RIGHT
---@return Window|nil
local function getFirstVisibleWindow(space, screen_frame, direction)
    direction = direction or Direction.LEFT
    local distance = math.huge
    local closest = nil

    for _, windows in ipairs(window_list[space] or {}) do
        local window = windows[1] -- take first window in column
        local d = (function()
            if direction == Direction.LEFT then
                return window:frame().x - screen_frame.x
            elseif direction == Direction.RIGHT then
                return screen_frame.x2 - window:frame().x2
            end
        end)() or math.huge
        if d >= 0 and d < distance then
            distance = d
            closest = window
        end
    end
    return closest
end

---get a column of windows for a space from the window_list
---@param space Space
---@param col number
---@return Window[]
local function getColumn(space, col) return (window_list[space] or {})[col] end

---get a window in a row, in a column, in a space from the window_list
---@param space Space
---@param col number
---@param row number
---@return Window
local function getWindow(space, col, row)
    return (getColumn(space, col) or {})[row]
end

---get the gap value for the specified side
---@param side string "top", "bottom", "left", or "right"
---@return number gap size in pixels
local function getGap(side)
    local gap = PaperWM.window_gap
    if type(gap) == "number" then
        return gap            -- backward compatibility with single number
    elseif type(gap) == "table" then
        return gap[side] or 8 -- default to 8 if missing
    else
        return 8              -- fallback default
    end
end

---get the tileable bounds for a screen
---@param screen Screen
---@return Frame
local function getCanvas(screen)
    local screen_frame = screen:frame()
    local left_gap = getGap("left")
    local right_gap = getGap("right")
    local top_gap = getGap("top")
    local bottom_gap = getGap("bottom")

    return Rect(
        screen_frame.x + left_gap,
        screen_frame.y + top_gap,
        screen_frame.w - (left_gap + right_gap),
        screen_frame.h - (top_gap + bottom_gap)
    )
end

---update the column number in window_list to be ascending from provided column up
---@param space Space
---@param column number
local function updateIndexTable(space, column)
    local columns = window_list[space] or {}
    for col = column, #columns do
        for row, window in ipairs(getColumn(space, col)) do
            index_table[window:id()] = { space = space, col = col, row = row }
        end
    end
end

---update the virtual x position for a table of windows on the specified space
---@param space Space
---@param windows Window[]
local function updateVirtualPositions(space, windows, x)
    if PaperWM.swipe_fingers == 0 then return end
    if not x_positions[space] then
        x_positions[space] = {}
    end
    for _, window in ipairs(windows) do
        x_positions[space][window] = x
    end
end

---save the is_floating list to settings
local function persistFloatingList()
    local persisted = {}
    for k, _ in pairs(is_floating) do
        table.insert(persisted, k)
    end
    hs.settings.set(IsFloatingKey, persisted)
end

local prev_focused_window = nil ---@type Window|nil
local pending_window = nil ---@type Window|nil

---callback for window events
---@param window Window
---@param event string name of the event
---@param self PaperWM
local function windowEventHandler(window, event, self)
    self.logger.df("%s for [%s] id: %d", event, window,
        window and window:id() or -1)
    local space = nil

    --[[ When a new window is created, We first get a windowVisible event but
    without a Space. Next we receive a windowFocused event for the window, but
    this also sometimes lacks a Space. Our approach is to store the window
    pending a Space in the pending_window variable and set a timer to try to add
    the window again later. Also schedule the windowFocused handler to run later
    after the window was added ]]
    --

    if is_floating[window:id()] then
        -- this event is only meaningful for floating windows
        if event == "windowDestroyed" then
            is_floating[window:id()] = nil
            persistFloatingList()
        end
        -- no other events are meaningful for floating windows
        return
    end

    if event == "windowFocused" then
        if pending_window and window == pending_window then
            Timer.doAfter(Window.animationDuration,
                function()
                    self.logger.vf("pending window timer for %s", window)
                    windowEventHandler(window, event, self)
                end)
            return
        end
        prev_focused_window = window -- for addWindow()
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

---generate callback fucntion for touchpad swipe gesture event
---@param self PaperWM
local function swipeHandler(self)
    -- saved upvalues between callback function calls
    local space, screen_frame = nil, nil

    ---callback for touchpad swipe gesture event
    ---@param id number unique id across callbacks for the same swipe
    ---@param type number one of Swipe.BEGIN, Swipe.MOVED, Swipe.END
    ---@param dx number change in horizonal position since last callback: between 0 and 1
    ---@param dy number change in vertical position since last callback: between 0 and 1
    return function(id, type, dx, dy)
        if type == Swipe.BEGIN then
            self.logger.df("new swipe: %d", id)

            -- use focused window for space to scroll windows
            local focused_window = Window.focusedWindow()
            if not focused_window then
                self.logger.d("focused window not found")
                return
            end

            -- get focused window index
            local focused_index = index_table[focused_window:id()]
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
            space        = focused_index.space

            -- stop all window moved watchers
            for window, _ in pairs(x_positions[space] or {}) do
                if not window then break end
                local watcher = ui_watchers[window:id()]
                if watcher then
                    watcher:stop()
                end
            end
        elseif type == Swipe.END then
            self.logger.df("swipe end: %d", id)

            if not space or not screen_frame then
                return -- no cached upvalues
            end

            -- restart all window moved watchers
            for window, _ in pairs(x_positions[space] or {}) do
                if not window then break end
                local watcher = ui_watchers[window:id()]
                if watcher then
                    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
                end
            end

            -- ensure a focused window is on screen
            local focused_window = Window.focusedWindow()
            if focused_window then
                local frame = focused_window:frame()
                local visible_window = (function()
                    if frame.x < screen_frame.x then
                        return getFirstVisibleWindow(space, screen_frame,
                            Direction.LEFT)
                    elseif frame.x2 > screen_frame.x2 then
                        return getFirstVisibleWindow(space, screen_frame,
                            Direction.RIGHT)
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

            -- clear cached upvalues
            space, screen_frame = nil, nil
        elseif type == Swipe.MOVED then
            if not space or not screen_frame then
                return -- no cached upvalues
            end

            if math.abs(dy) >= math.abs(dx) then
                return -- only handle horizontal swipes
            end

            dx = math.floor(self.swipe_gain * dx * screen_frame.w)


            local left_margin  = screen_frame.x + self.screen_margin
            local right_margin = screen_frame.x2 - self.screen_margin

            for window, x in pairs(x_positions[space] or {}) do
                if not window then break end
                x = x + dx
                local frame = window:frame()
                if dx > 0 then -- scroll right
                    frame.x = math.min(x, right_margin)
                else           -- scroll left
                    frame.x = math.max(x, left_margin - frame.w)
                end
                window:setTopLeft(frame.x, frame.y) -- avoid the animationDuration
                x_positions[space][window] = x      -- update virtual position
            end
        end
    end
end

---start automatic window tiling
---@return PaperWM
function PaperWM:start()
    -- check for some settings
    if not Spaces.screensHaveSeparateSpaces() then
        self.logger.e(
            "please check 'Displays have separate Spaces' in System Preferences -> Mission Control")
    end

    -- clear state
    window_list = {}
    index_table = {}
    ui_watchers = {}
    is_floating = {}
    x_positions = {}

    -- restore saved is_floating state, filtering for valid windows
    local persisted = hs.settings.get(IsFloatingKey) or {}
    for _, id in ipairs(persisted) do
        local window = Window.get(id)
        if window and self.window_filter:isWindowAllowed(window) then
            is_floating[id] = true
        end
    end
    persistFloatingList()

    -- populate window list, index table, ui_watchers, and set initial layout
    self:refreshWindows()

    -- listen for window events
    self.window_filter:subscribe({
        WindowFilter.windowFocused, WindowFilter.windowVisible,
        WindowFilter.windowNotVisible, WindowFilter.windowFullscreened,
        WindowFilter.windowUnfullscreened, WindowFilter.windowDestroyed
    }, function(window, _, event) windowEventHandler(window, event, self) end)

    -- watch for external monitor plug / unplug
    screen_watcher:start()

    -- recognize horizontal touchpad swipe gestures
    if self.swipe_fingers > 1 then
        Swipe:start(self.swipe_fingers, swipeHandler(self))
    end

    return self
end

---stop automatic window tiling
---@return PaperWM
function PaperWM:stop()
    -- stop events
    self.window_filter:unsubscribeAll()
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
    screen_watcher:stop()

    -- fit all windows within the bounds of the screen
    for _, window in ipairs(self.window_filter:getWindows()) do
        window:setFrameInScreenBounds()
    end

    -- stop listening for touchpad swipes
    Swipe:stop()

    return self
end

---tile a column of window by moving and resizing
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param h number|nil set windows to specified height
---@param w number|nil set windows to specified width
---@param id number|nil id of window to set specific height
---@param h4id number|nil specific height for provided window id
---@return number width of tiled column
function PaperWM:tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    local bottom_gap = getGap("bottom")

    for _, window in ipairs(windows) do
        frame = window:frame()
        w = w or frame.w -- take given width or width of first window
        if bounds.x then -- set either left or right x coord
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
        bounds.y = math.min(frame.y2 + bottom_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        self:moveWindow(last_window, frame)
    end
    return w -- return width of column
end

---tile all column in a space by moving and resizing windows
---@param space Space
function PaperWM:tileSpace(space)
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
    local focused_window = Window.focusedWindow()
    local anchor_window = (function()
        if focused_window and not is_floating[focused_window:id()] and Spaces.windowSpaces(focused_window)[1] == space then
            return focused_window
        else
            return getFirstVisibleWindow(space, screen:frame())
        end
    end)()

    if not anchor_window then
        self.logger.e("no anchor window in space")
        return
    end

    local anchor_index = index_table[anchor_window:id()]
    if not anchor_index then
        self.logger.e("anchor index not found")
        return -- bail
    end

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
    if #column == 1 then
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        self:moveWindow(anchor_window, anchor_frame)
    else
        local n = #column - 1 -- number of other windows in column
        local bottom_gap = getGap("bottom")
        local h =
            math.max(0, canvas.h - anchor_frame.h - (n * bottom_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        self:tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(),
            anchor_frame.h)
    end
    updateVirtualPositions(space, column, anchor_frame.x)

    local right_gap = getGap("right")
    local left_gap = getGap("left")

    -- tile windows from anchor right
    local x = anchor_frame.x2 + right_gap
    for col = anchor_index.col + 1, #(window_list[space] or {}) do
        local bounds = {
            x = math.min(x, right_margin),
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        local column = getColumn(space, col)
        local width = self:tileColumn(column, bounds)
        updateVirtualPositions(space, column, x)
        x = x + width + right_gap
    end

    -- tile windows from anchor left
    local x = anchor_frame.x
    local x2 = math.max(anchor_frame.x - left_gap, left_margin)
    for col = anchor_index.col - 1, 1, -1 do
        local bounds = { x = nil, x2 = x2, y = canvas.y, y2 = canvas.y2 }
        local column = getColumn(space, col)
        local width = self:tileColumn(column, bounds)
        x = x - width - left_gap
        updateVirtualPositions(space, column, x)
        x2 = math.max(x2 - width - left_gap, left_margin)
    end
end

---get all windows across all spaces and retile them
function PaperWM:refreshWindows()
    -- get all windows across spaces
    local all_windows = self.window_filter:getWindows()

    local retile_spaces = {} -- spaces that need to be retiled
    for _, window in ipairs(all_windows) do
        local index = index_table[window:id()]
        if is_floating[window:id()] then
            -- ignore floating windows
        elseif not index then
            -- add window
            local space = self:addWindow(window)
            if space then retile_spaces[space] = true end
        elseif index.space ~= Spaces.windowSpaces(window)[1] then
            -- move to window list in new space, don't focus nearby window
            self:removeWindow(window, true)
            local space = self:addWindow(window)
            if space then retile_spaces[space] = true end
        end
    end

    -- retile spaces
    for space, _ in pairs(retile_spaces) do self:tileSpace(space) end
end

---add a new window to be tracked and automatically tiled
---@param add_window Window new window to be added
---@return Space|nil space that contains new window
function PaperWM:addWindow(add_window)
    -- A window with no tabs will have a tabCount of 0
    -- A new tab for a window will have tabCount equal to the total number of tabs
    -- All existing tabs in a window will have their tabCount reset to 0
    -- We can't query whether an exiting hs.window is a tab or not after creation
    local apple <const> = "com.apple"
    if add_window:tabCount() > 0 and add_window:application():bundleID():sub(1, #apple) == apple then
        -- It's mostly built-in Apple apps like Finder and Terminal whose tabs
        -- show up as separate windows. Third party apps like Microsoft Office
        -- use tabs that are all contained within one window and tile fine.
        hs.notify.show("PaperWM", "Windows with tabs are not supported!",
            "See https://github.com/mogenson/PaperWM.spoon/issues/39")
        return
    end

    -- ignore windows that have a zoom button, but are not maximizable
    if not add_window:isMaximizable() then
        self.logger.d("ignoring non-maximizable window")
        return
    end

    -- check if window is already in window list
    if index_table[add_window:id()] then return end

    local space = Spaces.windowSpaces(add_window)[1]
    if not space then
        self.logger.e("add window does not have a space")
        return
    end
    if not window_list[space] then window_list[space] = {} end

    -- find where to insert window
    local add_column = 1

    -- when addWindow() is called from a window created event:
    -- focused_window from previous window focused event will not be add_window
    -- hs.window.focusedWindow() will return add_window
    -- new window focused event for add_window has not happened yet
    if prev_focused_window and
        ((index_table[prev_focused_window:id()] or {}).space == space) and
        (prev_focused_window:id() ~= add_window:id()) then
        add_column = index_table[prev_focused_window:id()].col +
            1 -- insert to the right
    else
        local x = add_window:frame().center.x
        for col, windows in ipairs(window_list[space]) do
            if x < windows[1]:frame().center.x then
                add_column = col
                break
            end
        end
    end

    -- add window
    table.insert(window_list[space], add_column, { add_window })

    -- update index table
    updateIndexTable(space, add_column)

    -- subscribe to window moved events
    local watcher = add_window:newWatcher(
        function(window, event, _, self)
            windowEventHandler(window, event, self)
        end, self)
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    ui_watchers[add_window:id()] = watcher

    return space
end

---remove a window from being tracked and automatically tiled
---@param remove_window Window window to be removed
---@param skip_new_window_focus boolean|nil don't focus a nearby window if true
---@return Space|nil space that contained removed window
function PaperWM:removeWindow(remove_window, skip_new_window_focus)
    -- get index of window
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        self.logger.e("remove index not found")
        return
    end

    if not skip_new_window_focus then -- find nearby window to focus
        for _, direction in ipairs({
            Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT
        }) do if self:focusWindow(direction, remove_index) then break end end
    end

    -- remove window
    table.remove(window_list[remove_index.space][remove_index.col],
        remove_index.row)
    if #window_list[remove_index.space][remove_index.col] == 0 then
        table.remove(window_list[remove_index.space], remove_index.col)
    end

    -- remove watcher
    ui_watchers[remove_window:id()]:stop()
    ui_watchers[remove_window:id()] = nil

    -- clear window position
    (x_positions[remove_index.space] or {})[remove_window] = nil

    -- update index table
    index_table[remove_window:id()] = nil
    updateIndexTable(remove_index.space, remove_index.col)

    -- remove if space is empty
    if #window_list[remove_index.space] == 0 then
        window_list[remove_index.space] = nil
        x_positions[remove_index.space] = nil
    end

    return remove_index.space -- return space for removed window
end

---move focus to a new window next to the currently focused window
---@param direction Direction use either Direction UP, DOWN, LEFT, or RIGHT
---@param focused_index Index index of focused window within the window_list
function PaperWM:focusWindow(direction, focused_index)
    if not focused_index then
        -- get current focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            self.logger.d("focused window not found")
            return
        end

        -- get focused window index
        focused_index = index_table[focused_window:id()]
    end

    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get new focused window
    local new_focused_window = nil
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- walk down column, looking for match in neighbor column
        for row = focused_index.row, 1, -1 do
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
        return
    end

    -- focus new window, windowFocused event will be emited immediately
    new_focused_window:focus()

    -- try to prevent MacOS from stealing focus away to another window
    Timer.doAfter(Window.animationDuration, function()
        if Window.focusedWindow() ~= new_focused_window then
            self.logger.df("refocusing window %s", new_focused_window)
            new_focused_window:focus()
        end
    end)

    return new_focused_window
end

local function findWindowDiff(diff)
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.i("current focused window not found")
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]

    if not focused_index then
        PaperWM.logger.i("focused index not found (diff=" .. diff .. ", window=" .. focused_window:title() .. ")")
        return
    end

    -- get new focused window
    local found_window

    local focused_column = getColumn(focused_index.space, focused_index.col)
    local new_row_index = focused_index.row + diff

    -- first try above/below in same row
    local found_window = getWindow(focused_index.space, focused_index.col, focused_index.row + diff)

    if not found_window then
        -- get the bottom row in the previous column, or the first row in the next column
        local adjacent_column = getColumn(focused_index.space, focused_index.col + diff)
        if adjacent_column then
            local col_idx = 1
            if diff < 0 then col_idx = #adjacent_column end
            found_window = adjacent_column[col_idx]
        end
    end

    if not found_window then
        PaperWM.logger.i("new focused window not found (diff=" .. diff .. ", current=" .. focused_window:title() .. ")")
        return
    end
    return found_window
end

function PaperWM:focusWindowDiff(diff)
    local new_focused_window = findWindowDiff(diff)
    if not new_focused_window then return end
    new_focused_window:focus()
end

---swap the focused window with a window next to it
---if swapping horizontally and the adjacent window is in a column, swap the
---entire column. if swapping vertically and the focused window is in a column,
---swap positions within the column
---@param direction Direction use Direction LEFT, RIGHT, UP, or DOWN
function PaperWM:swapWindows(direction)
    -- use focused window as source window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]
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
        for row, window in ipairs(target_column) do
            index_table[window:id()] = {
                space = focused_index.space,
                col = focused_index.col,
                row = row
            }
        end
        for row, window in ipairs(focused_column) do
            index_table[window:id()] = {
                space = focused_index.space,
                col = target_index.col,
                row = row
            }
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1]:frame()
        local right_gap = getGap("right")
        local left_gap = getGap("left")
        if direction == Direction.LEFT then
            focused_frame.x = target_frame.x
            target_frame.x = focused_frame.x2 + right_gap
        else -- Direction.RIGHT
            target_frame.x = focused_frame.x
            focused_frame.x = target_frame.x2 + right_gap
        end
        for _, window in ipairs(target_column) do
            local frame = window:frame()
            frame.x = target_frame.x
            self:moveWindow(window, frame)
        end
        for _, window in ipairs(focused_column) do
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
        local target_window = getWindow(target_index.space, target_index.col,
            target_index.row)
        if not target_window then
            self.logger.d("target window not found")
            return
        end

        -- swap places in window list
        window_list[target_index.space][target_index.col][target_index.row] =
            focused_window
        window_list[focused_index.space][focused_index.col][focused_index.row] =
            target_window

        -- update index table
        index_table[target_window:id()] = focused_index
        index_table[focused_window:id()] = target_index

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_window:frame()
        local bottom_gap = getGap("bottom")
        if direction == Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + bottom_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + bottom_gap
        end
        self:moveWindow(focused_window, focused_frame)
        self:moveWindow(target_window, target_frame)
    end

    -- update layout
    self:tileSpace(focused_index.space)
end

function PaperWM:swapColumns(direction)
    -- use focused window as source window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.e("focused window not found")
        return
    end

    -- get focused window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    local focused_column = getColumn(focused_index.space, focused_index.col)
    if not focused_column then
        self.logger.e("focused column not found")
        return
    end

    local adjacent_column_index = focused_index.col + direction
    local adjacent_column = getColumn(focused_index.space, adjacent_column_index)
    if not adjacent_column then return end

    -- swap column in window list
    window_list[focused_index.space][adjacent_column_index] = focused_column
    window_list[focused_index.space][focused_index.col] = adjacent_column

    local focused_frame = focused_window:frame()
    local adjacent_window = adjacent_column[1]
    if not adjacent_window then
        self.logger.e("adjacent window not found")
        return
    end

    local adjacent_frame = adjacent_window:frame()
    local focused_x = focused_frame.x
    local adjacent_x = adjacent_frame.x

    -- update index table
    for row, window in ipairs(adjacent_column) do
        local index = index_table[window:id()]
        if index then
            index_table[window:id()]["col"] = focused_index.col
        else
            self.logger.e("index_table missing window " .. window:id())
        end
    end

    for row, window in ipairs(focused_column) do
        local index = index_table[window:id()]
        if index then
            index_table[window:id()]["col"] = adjacent_column_index
        else
            self.logger.e("index_table missing window " .. window:id())
        end
    end

    -- update window positions
    for row, window in ipairs(adjacent_column) do
        local frame = window:frame()
        self:moveWindow(window, Rect(focused_x, frame.y, frame.w, frame.h))
    end

    for row, window in ipairs(focused_column) do
        local frame = window:frame()
        self:moveWindow(window, Rect(adjacent_x, frame.y, frame.w, frame.h))
    end

    -- update layout
    self:tileSpace(focused_index.space)
end

---move the focused window to the center of the screen, horizontally
---don't resize the window or change it's vertical position
function PaperWM:centerWindow()
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

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

---set the focused window to the width of the screen and cache the original width
---restore the original window size if called again, don't change the height
function PaperWM:toggleWindowFullWidth()
    local width_cache = {}
    return function(self)
        -- get current focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            self.logger.d("focused window not found")
            return
        end

        local canvas = getCanvas(focused_window:screen())
        local focused_frame = focused_window:frame()
        local id = focused_window:id()

        local width = width_cache[id]
        if width then
            -- restore window width
            focused_frame.x = canvas.x + ((canvas.w - width) / 2)
            focused_frame.w = width
            width_cache[id] = nil
        else
            -- set window to fullscreen width
            width_cache[id] = focused_frame.w
            focused_frame.x, focused_frame.w = canvas.x, canvas.w
        end

        -- update layout
        self:moveWindow(focused_window, focused_frame)
        local space = Spaces.windowSpaces(focused_window)[1]
        self:tileSpace(space)
    end
end

---resize the width or height of the window, keeping the other dimension the
---same. cycles through the ratios specified in PaperWM.window_ratios
---@param direction Direction use Direction.WIDTH or Direction.HEIGHT
---@param cycle_direction Direction use Direction.ASCENDING or DESCENDING
function PaperWM:cycleWindowSize(direction, cycle_direction)
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    local function findNewSize(area_size, frame_size, cycle_direction, dimension)
        local gap
        if dimension == Direction.WIDTH then
            -- For width, use the average of left and right gaps
            gap = (getGap("left") + getGap("right")) / 2
        else
            -- For height, use the average of top and bottom gaps
            gap = (getGap("top") + getGap("bottom")) / 2
        end

        local sizes = {}
        local new_size = nil
        if cycle_direction == Direction.ASCENDING then
            for index, ratio in ipairs(self.window_ratios) do
                sizes[index] = ratio * (area_size + gap) - gap
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
                sizes[index] = ratio * (area_size + gap) - gap
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
            self.logger.e(
                "cycle_direction must be either Direction.ASCENDING or Direction.DESCENDING")
        end

        return new_size
    end

    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()

    if direction == Direction.WIDTH then
        local new_width = findNewSize(canvas.w, focused_frame.w, cycle_direction, Direction.WIDTH)
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_width) // 2)
        focused_frame.w = new_width
    elseif direction == Direction.HEIGHT then
        local new_height = findNewSize(canvas.h, focused_frame.h, cycle_direction, Direction.HEIGHT)
        focused_frame.y = math.max(canvas.y,
            focused_frame.y + ((focused_frame.h - new_height) // 2))
        focused_frame.h = new_height
        focused_frame.y = focused_frame.y -
            math.max(0, focused_frame.y2 - canvas.y2)
    else
        self.logger.e(
            "direction must be either Direction.WIDTH or Direction.HEIGHT")
        return
    end

    -- apply new size
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(space)
end

function PaperWM:increaseWindowSize(direction, scale)
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()

    if direction == Direction.WIDTH then
        local diff = canvas.w * 0.1 * scale
        local new_size = math.max(diff, math.min(canvas.w, focused_frame.w + diff))

        focused_frame.w = new_size
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_size) // 2)
    elseif direction == Direction.HEIGHT then
        local diff = canvas.h * 0.1 * scale
        local new_size = math.max(diff, math.min(canvas.h, focused_frame.h + diff))

        focused_frame.h = new_size
        focused_frame.y = focused_frame.y -
            math.max(0, focused_frame.y2 - canvas.y2)
    end

    -- apply new size
    self:moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    self:tileSpace(space)
end

---take the current focused window and move it into the bottom of
---the column to the left
function PaperWM:slurpWindow()
    -- TODO paperwm behavior:
    -- add top window from column to the right to bottom of current column
    -- if no colum to the right and current window is only window in current column,
    -- add current window to bottom of column to the left

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
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

    -- remove window
    table.remove(window_list[focused_index.space][focused_index.col],
        focused_index.row)
    if #window_list[focused_index.space][focused_index.col] == 0 then
        table.remove(window_list[focused_index.space], focused_index.col)
    end

    -- append to end of column
    table.insert(column, focused_window)

    -- update index table
    local num_windows = #column
    index_table[focused_window:id()] = {
        space = focused_index.space,
        col = focused_index.col - 1,
        row = num_windows
    }
    updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local canvas = getCanvas(focused_window:screen())
    local bottom_gap = getGap("bottom")
    local bounds = {
        x = column[1]:frame().x,
        x2 = nil,
        y = canvas.y,
        y2 = canvas.y2
    }
    local h = math.max(0, canvas.h - ((num_windows - 1) * bottom_gap)) //
        num_windows
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.space)
end

---remove focused window from it's current column and place into
---a new column to the right
function PaperWM:barfWindow()
    -- TODO paperwm behavior:
    -- remove bottom window of current column
    -- place window into a new column to the right--

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = index_table[focused_window:id()]
    if not focused_index then
        self.logger.e("focused index not found")
        return
    end

    -- get column
    local column = getColumn(focused_index.space, focused_index.col)
    if #column == 1 then
        self.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.row)
    table.insert(window_list[focused_index.space], focused_index.col + 1,
        { focused_window })

    -- update index table
    updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local num_windows = #column
    local canvas = getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    local bottom_gap = getGap("bottom")
    local right_gap = getGap("right")

    local bounds = { x = focused_frame.x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
    local h = math.max(0, canvas.h - ((num_windows - 1) * bottom_gap)) //
        num_windows
    focused_frame.y = canvas.y
    focused_frame.x = focused_frame.x2 + right_gap
    focused_frame.h = canvas.h
    self:moveWindow(focused_window, focused_frame)
    self:tileColumn(column, bounds, h)

    -- update layout
    self:tileSpace(focused_index.space)
end

---switch to a Mission Control space
---@param index number incremental id for space
function PaperWM:switchToSpace(index)
    local space = MissionControl:getSpaceID(index)
    if not space then
        self.logger.d("space not found")
        return
    end

    local screen = Screen(Spaces.spaceDisplay(space))
    local window = getFirstVisibleWindow(space, screen:frame())
    Spaces.gotoSpace(space)
    MissionControl:focusSpace(space, window)
end

---switch to a Mission Control space to the left or right of current space
---@param direction Direction use Direction.LEFT or Direction.RIGHT
function PaperWM:incrementSpace(direction)
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

---move focused window to a Mission Control space
---@param index number space index
function PaperWM:moveWindowToSpace(index)
    local focused_window = Window.focusedWindow()
    if not focused_window then
        self.logger.d("focused window not found")
        return
    end

    local new_space = MissionControl:getSpaceID(index)
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

    local old_screen = focused_window:screen()
    if not old_screen then
        self.logger.d("no screen for window")
        return
    end

    local new_screen = Screen(Spaces.spaceDisplay(new_space))
    if not new_screen then
        self.logger.d("no screen for space")
        return
    end

    -- get list of screens allowed by the window filter as hs.screen objects
    local allowed_screens = self.window_filter:getFilters().override.allowScreens or Screen.allScreens()
    allowed_screens = Fnutils.imap(allowed_screens, function(screen) return Screen.find(screen) end)

    -- get the old space from the window list or by querying removed window
    local old_space = (function(allowed)
        if allowed then
            return self:removeWindow(focused_window, true) -- don't switch focus
        end
    end)(Fnutils.contains(allowed_screens, old_screen))

    local ret, err = MissionControl:moveWindowToSpace(focused_window, new_space)
    if not ret or err then
        self.logger.e(err)
        return
    end

    if old_space then
        self:tileSpace(old_space)
    end

    if Fnutils.contains(allowed_screens, new_screen) then
        self:addWindow(focused_window)
        self:tileSpace(new_space)
        MissionControl:focusSpace(new_space, focused_window)
    end
end

---move and resize a window to the coordinates specified by the frame
---disable watchers while window is moving and re-enable after
---@param window Window window to move
---@param frame Frame coordinates to set window size and location
function PaperWM:moveWindow(window, frame)
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
    window:setFrame(frame)
    Timer.doAfter(Window.animationDuration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
end

---add or remove focused window from the floating layer and retile the space
function PaperWM:toggleFloating()
    local window = Window.focusedWindow()
    if not window then
        self.logger.d("focused window not found")
        return
    end

    local id = window:id()
    if is_floating[id] then
        is_floating[id] = nil
    else
        is_floating[id] = true
    end
    persistFloatingList()

    local space = (function()
        if is_floating[id] then
            return self:removeWindow(window, true)
        else
            return self:addWindow(window)
        end
    end)()
    if space then
        self:tileSpace(space)
    end
end

---supported window movement actions
PaperWM.actions = {
    stop_events = Fnutils.partial(PaperWM.stop, PaperWM),
    refresh_windows = Fnutils.partial(PaperWM.refreshWindows, PaperWM),
    toggle_floating = Fnutils.partial(PaperWM.toggleFloating, PaperWM),
    focus_left = Fnutils.partial(PaperWM.focusWindow, PaperWM, Direction.LEFT),
    focus_right = Fnutils.partial(PaperWM.focusWindow, PaperWM, Direction.RIGHT),
    focus_up = Fnutils.partial(PaperWM.focusWindow, PaperWM, Direction.UP),
    focus_down = Fnutils.partial(PaperWM.focusWindow, PaperWM, Direction.DOWN),
    focus_prev = Fnutils.partial(PaperWM.focusWindowDiff, PaperWM, -1),
    focus_next = Fnutils.partial(PaperWM.focusWindowDiff, PaperWM, 1),
    swap_left = Fnutils.partial(PaperWM.swapWindows, PaperWM, Direction.LEFT),
    swap_right = Fnutils.partial(PaperWM.swapWindows, PaperWM, Direction.RIGHT),
    swap_up = Fnutils.partial(PaperWM.swapWindows, PaperWM, Direction.UP),
    swap_down = Fnutils.partial(PaperWM.swapWindows, PaperWM, Direction.DOWN),
    swap_column_left = Fnutils.partial(PaperWM.swapColumns, PaperWM, Direction.LEFT),
    swap_column_right = Fnutils.partial(PaperWM.swapColumns, PaperWM, Direction.RIGHT),
    center_window = Fnutils.partial(PaperWM.centerWindow, PaperWM),
    full_width = Fnutils.partial(PaperWM:toggleWindowFullWidth(), PaperWM),
    increase_width = Fnutils.partial(PaperWM.increaseWindowSize, PaperWM, Direction.WIDTH, 1),
    decrease_width = Fnutils.partial(PaperWM.increaseWindowSize, PaperWM, Direction.WIDTH, -1),
    increase_height = Fnutils.partial(PaperWM.increaseWindowSize, PaperWM, Direction.HEIGHT, 1),
    decrease_height = Fnutils.partial(PaperWM.increaseWindowSize, PaperWM, Direction.HEIGHT, -1),
    cycle_width = Fnutils.partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.ASCENDING),
    cycle_height = Fnutils.partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.ASCENDING),
    reverse_cycle_width = Fnutils.partial(PaperWM.cycleWindowSize, PaperWM, Direction.WIDTH, Direction.DESCENDING),
    reverse_cycle_height = Fnutils.partial(PaperWM.cycleWindowSize, PaperWM, Direction.HEIGHT, Direction.DESCENDING),
    slurp_in = Fnutils.partial(PaperWM.slurpWindow, PaperWM),
    barf_out = Fnutils.partial(PaperWM.barfWindow, PaperWM),
    switch_space_l = Fnutils.partial(PaperWM.incrementSpace, PaperWM, Direction.LEFT),
    switch_space_r = Fnutils.partial(PaperWM.incrementSpace, PaperWM, Direction.RIGHT),
    switch_space_1 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 1),
    switch_space_2 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 2),
    switch_space_3 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 3),
    switch_space_4 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 4),
    switch_space_5 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 5),
    switch_space_6 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 6),
    switch_space_7 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 7),
    switch_space_8 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 8),
    switch_space_9 = Fnutils.partial(PaperWM.switchToSpace, PaperWM, 9),
    move_window_1 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 1),
    move_window_2 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 2),
    move_window_3 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 3),
    move_window_4 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 4),
    move_window_5 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 5),
    move_window_6 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 6),
    move_window_7 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 7),
    move_window_8 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 8),
    move_window_9 = Fnutils.partial(PaperWM.moveWindowToSpace, PaperWM, 9)
}

---bind userdefined hotkeys to PaperWM actions
---use PaperWM.default_hotkeys for suggested defaults
---@param mapping Mapping table of actions and hotkeys
function PaperWM:bindHotkeys(mapping)
    local spec = self.actions
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

return PaperWM
