local Rect <const> = hs.geometry.rect
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Timer <const> = hs.timer
local Watcher <const> = hs.uielement.watcher
local Window <const> = hs.window

local Windows = {}
Windows.__index = Windows

---@enum Direction
local Direction <const> = {
    LEFT = -1,
    RIGHT = 1,
    UP = -2,
    DOWN = 2,
    NEXT = 3,
    PREVIOUS = -3,
    WIDTH = 4,
    HEIGHT = 5,
    ASCENDING = 6,
    DESCENDING = 7,
}
Windows.Direction = Direction

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Windows.init(paperwm)
    Windows.PaperWM = paperwm
end

---return the first window that's completely on the screen
---@param space Space space to lookup windows
---@param screen_frame Frame the coordinates of the screen
---@pram direction Direction|nil either LEFT or RIGHT
---@return Window|nil
function Windows.getFirstVisibleWindow(space, screen_frame, direction)
    direction = direction or Direction.LEFT
    local distance = math.huge
    local closest = nil

    for _, windows in ipairs(Windows.PaperWM.state.window_list[space] or {}) do
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
function Windows.getColumn(space, col) return (Windows.PaperWM.state.window_list[space] or {})[col] end

---get a window in a row, in a column, in a space from the window_list
---@param space Space
---@param col number
---@param row number
---@return Window
function Windows.getWindow(space, col, row)
    return (Windows.getColumn(space, col) or {})[row]
end

---get the gap value for the specified side
---@param side string "top", "bottom", "left", or "right"
---@return number gap size in pixels
function Windows.getGap(side)
    local gap = Windows.PaperWM.window_gap
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
function Windows.getCanvas(screen)
    local screen_frame = screen:frame()
    local left_gap = Windows.getGap("left")
    local right_gap = Windows.getGap("right")
    local top_gap = Windows.getGap("top")
    local bottom_gap = Windows.getGap("bottom")

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
function Windows.updateIndexTable(space, column)
    local columns = Windows.PaperWM.state.window_list[space] or {}
    for col = column, #columns do
        for row, window in ipairs(Windows.getColumn(space, col)) do
            Windows.PaperWM.state.index_table[window:id()] = { space = space, col = col, row = row }
        end
    end
end

---update the virtual x position for a table of windows on the specified space
---@param space Space
---@param windows Window[]
function Windows.updateVirtualPositions(space, windows, x)
    if Windows.PaperWM.swipe_fingers == 0 then return end
    if not Windows.PaperWM.state.x_positions[space] then
        Windows.PaperWM.state.x_positions[space] = {}
    end
    for _, window in ipairs(windows) do
        Windows.PaperWM.state.x_positions[space][window] = x
    end
end

---save the is_floating list to settings
function Windows.persistFloatingList()
    local persisted = {}
    for k, _ in pairs(Windows.PaperWM.state.is_floating) do
        table.insert(persisted, k)
    end
    hs.settings.set(Windows.PaperWM.state.IsFloatingKey, persisted)
end

---tile a column of window by moving and resizing
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param h number|nil set windows to specified height
---@param w number|nil set windows to specified width
---@param id number|nil id of window to set specific height
---@param h4id number|nil specific height for provided window id
---@return number width of tiled column
function Windows.tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    local bottom_gap = Windows.getGap("bottom")

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
        Windows.moveWindow(window, frame)
        bounds.y = math.min(frame.y2 + bottom_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        Windows.moveWindow(last_window, frame)
    end
    return w -- return width of column
end

---get all windows across all spaces and retile them
function Windows.refreshWindows()
    -- get all windows across spaces
    local all_windows = Windows.PaperWM.window_filter:getWindows()

    local retile_spaces = {} -- spaces that need to be retiled
    for _, window in ipairs(all_windows) do
        local index = Windows.PaperWM.state.index_table[window:id()]
        if Windows.PaperWM.state.is_floating[window:id()] then
            -- ignore floating windows
        elseif not index then
            -- add window
            local space = Windows.addWindow(window)
            if space then retile_spaces[space] = true end
        elseif index.space ~= Spaces.windowSpaces(window)[1] then
            -- move to window list in new space, don't focus nearby window
            Windows.removeWindow(window, true)
            local space = Windows.addWindow(window)
            if space then retile_spaces[space] = true end
        end
    end

    -- retile spaces
    for space, _ in pairs(retile_spaces) do Windows.PaperWM:tileSpace(space) end
end

---add a new window to be tracked and automatically tiled
---@param add_window Window new window to be added
---@return Space|nil space that contains new window
function Windows.addWindow(add_window)
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
        Windows.PaperWM.logger.d("ignoring non-maximizable window")
        return
    end

    -- check if window is already in window list
    if Windows.PaperWM.state.index_table[add_window:id()] then return end

    local space = Spaces.windowSpaces(add_window)[1]
    if not space then
        Windows.PaperWM.logger.e("add window does not have a space")
        return
    end
    if not Windows.PaperWM.state.window_list[space] then Windows.PaperWM.state.window_list[space] = {} end

    -- find where to insert window
    local add_column = 1

    -- when addWindow() is called from a window created event:
    -- focused_window from previous window focused event will not be add_window
    -- hs.window.focusedWindow() will return add_window
    -- new window focused event for add_window has not happened yet
    if Windows.PaperWM.state.prev_focused_window and
        ((Windows.PaperWM.state.index_table[Windows.PaperWM.state.prev_focused_window:id()] or {}).space == space) and
        (Windows.PaperWM.state.prev_focused_window:id() ~= add_window:id()) then
        add_column = Windows.PaperWM.state.index_table[Windows.PaperWM.state.prev_focused_window:id()].col +
            1 -- insert to the right
    else
        local x = add_window:frame().center.x
        for col, windows in ipairs(Windows.PaperWM.state.window_list[space]) do
            if x < windows[1]:frame().center.x then
                add_column = col     -- insert left of window
                break                -- add_window will take this window's column
            else                     -- everything after insert column will be pushed right
                add_column = col + 1 -- insert right of window
            end
        end
    end

    -- add window
    table.insert(Windows.PaperWM.state.window_list[space], add_column, { add_window })

    -- update index table
    Windows.updateIndexTable(space, add_column)

    -- subscribe to window moved events
    local watcher = add_window:newWatcher(
        function(window, event, _, self)
            Windows.PaperWM.events.windowEventHandler(window, event, self)
        end, Windows.PaperWM)
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    Windows.PaperWM.state.ui_watchers[add_window:id()] = watcher

    return space
end

---remove a window from being tracked and automatically tiled
---@param remove_window Window window to be removed
---@param skip_new_window_focus boolean|nil don't focus a nearby window if true
---@return Space|nil space that contained removed window
function Windows.removeWindow(remove_window, skip_new_window_focus)
    -- get index of window
    local remove_index = Windows.PaperWM.state.index_table[remove_window:id()]
    if not remove_index then
        Windows.PaperWM.logger.e("remove index not found")
        return
    end

    if not skip_new_window_focus then -- find nearby window to focus
        for _, direction in ipairs({
            Direction.DOWN, Direction.UP, Direction.LEFT, Direction.RIGHT,
        }) do if Windows.focusWindow(direction, remove_index) then break end end
    end

    -- remove window
    table.remove(Windows.PaperWM.state.window_list[remove_index.space][remove_index.col],
        remove_index.row)
    if #Windows.PaperWM.state.window_list[remove_index.space][remove_index.col] == 0 then
        table.remove(Windows.PaperWM.state.window_list[remove_index.space], remove_index.col)
    end

    -- remove watcher
    Windows.PaperWM.state.ui_watchers[remove_window:id()]:stop()
    Windows.PaperWM.state.ui_watchers[remove_window:id()] = nil

    -- clear window position
    (Windows.PaperWM.state.x_positions[remove_index.space] or {})[remove_window] = nil

    -- update index table
    Windows.PaperWM.state.index_table[remove_window:id()] = nil
    Windows.updateIndexTable(remove_index.space, remove_index.col)

    -- remove if space is empty
    if #Windows.PaperWM.state.window_list[remove_index.space] == 0 then
        Windows.PaperWM.state.window_list[remove_index.space] = nil
        Windows.PaperWM.state.x_positions[remove_index.space] = nil
    end

    return remove_index.space -- return space for removed window
end

---move focus to a new window next to the currently focused window
---@param direction Direction use either Direction UP, DOWN, LEFT, or RIGHT
---@param focused_index Index index of focused window within the window_list
function Windows.focusWindow(direction, focused_index)
    if not focused_index then
        -- get current focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            Windows.PaperWM.logger.d("focused window not found")
            return
        end

        -- get focused window index
        focused_index = Windows.PaperWM.state.index_table[focused_window:id()]
    end

    if not focused_index then
        Windows.PaperWM.logger.e("focused index not found")
        return
    end

    -- get new focused window
    local new_focused_window = nil
    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- walk down column, looking for match in neighbor column
        for row = focused_index.row, 1, -1 do
            new_focused_window = Windows.getWindow(focused_index.space,
                focused_index.col + direction, row)
            if new_focused_window then break end
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        new_focused_window = Windows.getWindow(focused_index.space, focused_index.col,
            focused_index.row + (direction // 2))
    elseif direction == Direction.NEXT or direction == Direction.PREVIOUS then
        local diff = direction // Direction.NEXT -- convert to 1/-1
        local focused_column = Windows.getColumn(focused_index.space, focused_index.col)
        local new_row_index = focused_index.row + diff

        -- first try above/below in same row
        new_focused_window = Windows.getWindow(focused_index.space, focused_index.col, focused_index.row + diff)

        if not new_focused_window then
            -- get the bottom row in the previous column, or the first row in the next column
            local adjacent_column = Windows.getColumn(focused_index.space, focused_index.col + diff)
            if adjacent_column then
                local col_idx = 1
                if diff < 0 then col_idx = #adjacent_column end
                new_focused_window = adjacent_column[col_idx]
            end
        end
    end

    if not new_focused_window then
        Windows.PaperWM.logger.d("new focused window not found")
        return
    end

    -- focus new window, windowFocused event will be emited immediately
    new_focused_window:focus()

    -- try to prevent MacOS from stealing focus away to another window
    Timer.doAfter(Window.animationDuration, function()
        if Window.focusedWindow() ~= new_focused_window then
            Windows.PaperWM.logger.df("refocusing window %s", new_focused_window)
            new_focused_window:focus()
        end
    end)

    return new_focused_window
end

---focus a window at a specified position
---@param new_index number the index from left to right on the current screen
function Windows.focusWindowAt(new_index)
    local screen = Screen.mainScreen()
    local space = Spaces.activeSpaces()[screen:getUUID()]
    local columns = Windows.PaperWM.state.window_list[space]
    if not columns then return end

    local index = 1
    for col_idx = 1, #columns do
        column = columns[col_idx]
        for row_idx = 1, #column do
            if index == new_index then
                column[row_idx]:focus()
                return
            end
            index = index + 1
        end
    end
end

---swap the focused window with a window next to it
---if swapping horizontally and the adjacent window is in a column, swap the
---entire column. if swapping vertically and the focused window is in a column,
---swap positions within the column
---@param direction Direction use Direction LEFT, RIGHT, UP, or DOWN
function Windows.swapWindows(direction)
    -- use focused window as source window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    -- get focused window index
    local focused_index = Windows.PaperWM.state.index_table[focused_window:id()]
    if not focused_index then
        Windows.PaperWM.logger.e("focused index not found")
        return
    end

    if direction == Direction.LEFT or direction == Direction.RIGHT then
        -- get target windows
        local target_index = { col = focused_index.col + direction }
        local target_column = Windows.getColumn(focused_index.space, target_index.col)
        if not target_column then
            Windows.PaperWM.logger.d("target column not found")
            return
        end

        -- swap place in window list
        local focused_column = Windows.getColumn(focused_index.space, focused_index.col)
        Windows.PaperWM.state.window_list[focused_index.space][target_index.col] = focused_column
        Windows.PaperWM.state.window_list[focused_index.space][focused_index.col] = target_column

        -- update index table
        for row, window in ipairs(target_column) do
            Windows.PaperWM.state.index_table[window:id()] = {
                space = focused_index.space,
                col = focused_index.col,
                row = row,
            }
        end
        for row, window in ipairs(focused_column) do
            Windows.PaperWM.state.index_table[window:id()] = {
                space = focused_index.space,
                col = target_index.col,
                row = row,
            }
        end

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1]:frame()
        local right_gap = Windows.getGap("right")
        local left_gap = Windows.getGap("left")
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
            Windows.moveWindow(window, frame)
        end
        for _, window in ipairs(focused_column) do
            local frame = window:frame()
            frame.x = focused_frame.x
            Windows.moveWindow(window, frame)
        end
    elseif direction == Direction.UP or direction == Direction.DOWN then
        -- get target window
        local target_index = {
            space = focused_index.space,
            col = focused_index.col,
            row = focused_index.row + (direction // 2),
        }
        local target_window = Windows.getWindow(target_index.space, target_index.col,
            target_index.row)
        if not target_window then
            Windows.PaperWM.logger.d("target window not found")
            return
        end

        -- swap places in window list
        Windows.PaperWM.state.window_list[target_index.space][target_index.col][target_index.row] =
            focused_window
        Windows.PaperWM.state.window_list[focused_index.space][focused_index.col][focused_index.row] =
            target_window

        -- update index table
        Windows.PaperWM.state.index_table[target_window:id()] = focused_index
        Windows.PaperWM.state.index_table[focused_window:id()] = target_index

        -- swap frames
        local focused_frame = focused_window:frame()
        local target_frame = target_window:frame()
        local bottom_gap = Windows.getGap("bottom")
        if direction == Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + bottom_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + bottom_gap
        end
        Windows.moveWindow(focused_window, focused_frame)
        Windows.moveWindow(target_window, target_frame)
    end

    -- update layout
    Windows.PaperWM:tileSpace(focused_index.space)
end

---exchange two columns of windows
---@param direction Direction Direction.LEFT or Direction.RIGHT
function Windows.swapColumns(direction)
    -- use focused window as source window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.e("focused window not found")
        return
    end

    -- get focused window index
    local focused_index = Windows.PaperWM.state.index_table[focused_window:id()]
    if not focused_index then
        Windows.PaperWM.logger.e("focused index not found")
        return
    end

    local focused_column = Windows.getColumn(focused_index.space, focused_index.col)
    if not focused_column then
        Windows.PaperWM.logger.e("focused column not found")
        return
    end

    local adjacent_column_index = focused_index.col + direction
    local adjacent_column = Windows.getColumn(focused_index.space, adjacent_column_index)
    if not adjacent_column then return end

    -- swap column in window list
    Windows.PaperWM.state.window_list[focused_index.space][adjacent_column_index] = focused_column
    Windows.PaperWM.state.window_list[focused_index.space][focused_index.col] = adjacent_column

    local focused_frame = focused_window:frame()
    local adjacent_window = adjacent_column[1]
    if not adjacent_window then
        Windows.PaperWM.logger.e("adjacent window not found")
        return
    end

    local adjacent_frame = adjacent_window:frame()
    local focused_x = focused_frame.x
    local adjacent_x = adjacent_frame.x

    -- update index table
    for row, window in ipairs(adjacent_column) do
        local index = Windows.PaperWM.state.index_table[window:id()]
        if index then
            Windows.PaperWM.state.index_table[window:id()]["col"] = focused_index.col
        else
            Windows.PaperWM.logger.e("index_table missing window " .. window:id())
        end
    end

    for row, window in ipairs(focused_column) do
        local index = Windows.PaperWM.state.index_table[window:id()]
        if index then
            Windows.PaperWM.state.index_table[window:id()]["col"] = adjacent_column_index
        else
            Windows.PaperWM.logger.e("index_table missing window " .. window:id())
        end
    end

    -- update window positions
    for row, window in ipairs(adjacent_column) do
        local frame = window:frame()
        Windows.moveWindow(window, Rect(focused_x, frame.y, frame.w, frame.h))
    end

    for row, window in ipairs(focused_column) do
        local frame = window:frame()
        Windows.moveWindow(window, Rect(adjacent_x, frame.y, frame.w, frame.h))
    end

    -- update layout
    Windows.PaperWM:tileSpace(focused_index.space)
end

---move the focused window to the center of the screen, horizontally
---don't resize the window or change it's vertical position
function Windows.centerWindow()
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    -- get global coordinates
    local focused_frame = focused_window:frame()
    local screen_frame = focused_window:screen():frame()

    -- center window
    focused_frame.x = screen_frame.x + (screen_frame.w // 2) -
        (focused_frame.w // 2)
    Windows.moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    Windows.PaperWM:tileSpace(space)
end

---set the focused window to the width of the screen and cache the original width
---restore the original window size if called again, don't change the height
function Windows.toggleWindowFullWidth()
    local width_cache = {}
    return function(self)
        -- get current focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            self.logger.d("focused window not found")
            return
        end

        local canvas = Windows.getCanvas(focused_window:screen())
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
        Windows.moveWindow(focused_window, focused_frame)
        local space = Spaces.windowSpaces(focused_window)[1]
        Windows.PaperWM:tileSpace(space)
    end
end

---resize the width or height of the window, keeping the other dimension the
---same. cycles through the ratios specified in PaperWM.window_ratios
---@param direction Direction use Direction.WIDTH or Direction.HEIGHT
---@param cycle_direction Direction use Direction.ASCENDING or DESCENDING
function Windows.cycleWindowSize(direction, cycle_direction)
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    local function findNewSize(area_size, frame_size, cycle_direction, dimension)
        local gap
        if dimension == Direction.WIDTH then
            -- For width, use the average of left and right gaps
            gap = (Windows.getGap("left") + Windows.getGap("right")) / 2
        else
            -- For height, use the average of top and bottom gaps
            gap = (Windows.getGap("top") + Windows.getGap("bottom")) / 2
        end

        local sizes = {}
        local new_size = nil
        if cycle_direction == Direction.ASCENDING then
            for index, ratio in ipairs(Windows.PaperWM.window_ratios) do
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
            for index, ratio in ipairs(Windows.PaperWM.window_ratios) do
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
            Windows.PaperWM.logger.e(
                "cycle_direction must be either Direction.ASCENDING or Direction.DESCENDING")
        end

        return new_size
    end

    local canvas = Windows.getCanvas(focused_window:screen())
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
        Windows.PaperWM.logger.e(
            "direction must be either Direction.WIDTH or Direction.HEIGHT")
        return
    end

    -- apply new size
    Windows.moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    Windows.PaperWM:tileSpace(space)
end

---resize the focused window in a direction by scale amount
---@param direction Direction Direction.WIDTH or Direction.HEIGHT
---@param scale number the percent to change the window size by
function Windows.increaseWindowSize(direction, scale)
    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    local canvas = Windows.getCanvas(focused_window:screen())
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
    Windows.moveWindow(focused_window, focused_frame)

    -- update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    Windows.PaperWM:tileSpace(space)
end

---take the current focused window and move it into the bottom of
---the column to the left
function Windows.slurpWindow()
    -- TODO paperwm behavior:
    -- add top window from column to the right to bottom of current column
    -- if no colum to the right and current window is only window in current column,
    -- add current window to bottom of column to the left

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = Windows.PaperWM.state.index_table[focused_window:id()]
    if not focused_index then
        Windows.PaperWM.logger.e("focused index not found")
        return
    end

    -- get column to left
    local column = Windows.getColumn(focused_index.space, focused_index.col - 1)
    if not column then
        Windows.PaperWM.logger.d("column not found")
        return
    end

    -- remove window
    table.remove(Windows.PaperWM.state.window_list[focused_index.space][focused_index.col],
        focused_index.row)
    if #Windows.PaperWM.state.window_list[focused_index.space][focused_index.col] == 0 then
        table.remove(Windows.PaperWM.state.window_list[focused_index.space], focused_index.col)
    end

    -- append to end of column
    table.insert(column, focused_window)

    -- update index table
    local num_windows = #column
    Windows.PaperWM.state.index_table[focused_window:id()] = {
        space = focused_index.space,
        col = focused_index.col - 1,
        row = num_windows,
    }
    Windows.updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local canvas = Windows.getCanvas(focused_window:screen())
    local bottom_gap = Windows.getGap("bottom")
    local bounds = {
        x = column[1]:frame().x,
        x2 = nil,
        y = canvas.y,
        y2 = canvas.y2,
    }
    local h = math.max(0, canvas.h - ((num_windows - 1) * bottom_gap)) //
        num_windows
    Windows.tileColumn(column, bounds, h)

    -- update layout
    Windows.PaperWM:tileSpace(focused_index.space)
end

---remove focused window from it's current column and place into
---a new column to the right
function Windows.barfWindow()
    -- TODO paperwm behavior:
    -- remove bottom window of current column
    -- place window into a new column to the right--

    -- get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    -- get window index
    local focused_index = Windows.PaperWM.state.index_table[focused_window:id()]
    if not focused_index then
        Windows.PaperWM.logger.e("focused index not found")
        return
    end

    -- get column
    local column = Windows.getColumn(focused_index.space, focused_index.col)
    if #column == 1 then
        Windows.PaperWM.logger.d("only window in column")
        return
    end

    -- remove window and insert in new column
    table.remove(column, focused_index.row)
    table.insert(Windows.PaperWM.state.window_list[focused_index.space], focused_index.col + 1,
        { focused_window })

    -- update index table
    Windows.updateIndexTable(focused_index.space, focused_index.col)

    -- adjust window frames
    local num_windows = #column
    local canvas = Windows.getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()
    local bottom_gap = Windows.getGap("bottom")
    local right_gap = Windows.getGap("right")

    local bounds = { x = focused_frame.x, x2 = nil, y = canvas.y, y2 = canvas.y2 }
    local h = math.max(0, canvas.h - ((num_windows - 1) * bottom_gap)) //
        num_windows
    focused_frame.y = canvas.y
    focused_frame.x = focused_frame.x2 + right_gap
    focused_frame.h = canvas.h
    Windows.moveWindow(focused_window, focused_frame)
    Windows.tileColumn(column, bounds, h)

    -- update layout
    Windows.PaperWM:tileSpace(focused_index.space)
end

---move and resize a window to the coordinates specified by the frame
---disable watchers while window is moving and re-enable after
---@param window Window window to move
---@param frame Frame coordinates to set window size and location
function Windows.moveWindow(window, frame)
    -- greater than 0.017 hs.window animation step time
    local padding <const> = 0.02

    local watcher = Windows.PaperWM.state.ui_watchers[window:id()]
    if not watcher then
        Windows.PaperWM.logger.e("window does not have ui watcher")
        return
    end

    if frame == window:frame() then
        Windows.PaperWM.logger.v("no change in window frame")
        return
    end

    watcher:stop()
    window:setFrame(frame)
    Timer.doAfter(Window.animationDuration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
end

---add or remove focused window from the floating layer and retile the space
---@param window Window|nil optional window to float and focus
function Windows.toggleFloating(window)
    window = window or Window.focusedWindow()
    if not window then
        Windows.PaperWM.logger.d("focused window not found")
        return
    end

    local id = window:id()
    if Windows.PaperWM.state.is_floating[id] then
        Windows.PaperWM.state.is_floating[id] = nil
    else
        Windows.PaperWM.state.is_floating[id] = true
    end
    Windows.persistFloatingList()

    local space = (function()
        if Windows.PaperWM.state.is_floating[id] then
            return Windows.removeWindow(window, true)
        else
            return Windows.addWindow(window)
        end
    end)()
    if space then
        window:focus()
        Windows.PaperWM:tileSpace(space)
    end
end

return Windows
