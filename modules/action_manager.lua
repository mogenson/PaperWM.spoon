-- Action manager for PaperWM
-- Handles user-initiated actions that manipulate windows and spaces

local action_manager = {}

-- Core Hammerspoon API dependency
local Fnutils = hs.fnutils
local Timer = hs.timer
local Window = hs.window
local Spaces = hs.spaces

-- Module references
local PaperWM
local deps = {}

-- Initialize with references to required objects
function action_manager.init(paperWM, dependencies)
    PaperWM = paperWM
    deps = dependencies

    return action_manager
end

-- Returns all actions for hotkey binding
function action_manager.getActions()
    return {
        -- Core actions
        stop_events = Fnutils.partial(PaperWM.stop, PaperWM),
        refresh_windows = Fnutils.partial(deps.window_manager.refreshWindows),
        toggle_floating = Fnutils.partial(deps.window_manager.toggleFloating),

        -- Window navigation
        focus_left = Fnutils.partial(action_manager.focusWindow, PaperWM.Direction.LEFT),
        focus_right = Fnutils.partial(action_manager.focusWindow, PaperWM.Direction.RIGHT),
        focus_up = Fnutils.partial(action_manager.focusWindow, PaperWM.Direction.UP),
        focus_down = Fnutils.partial(action_manager.focusWindow, PaperWM.Direction.DOWN),

        -- Window swapping
        swap_left = Fnutils.partial(action_manager.swapWindows, PaperWM.Direction.LEFT),
        swap_right = Fnutils.partial(action_manager.swapWindows, PaperWM.Direction.RIGHT),
        swap_up = Fnutils.partial(action_manager.swapWindows, PaperWM.Direction.UP),
        swap_down = Fnutils.partial(action_manager.swapWindows, PaperWM.Direction.DOWN),

        -- Window positioning and sizing
        center_window = Fnutils.partial(action_manager.centerWindow),
        full_width = Fnutils.partial(action_manager.toggleWindowFullWidth()),
        cycle_width = Fnutils.partial(action_manager.cycleWindowSize, PaperWM.Direction.WIDTH,
            PaperWM.Direction.ASCENDING),
        cycle_height = Fnutils.partial(action_manager.cycleWindowSize, PaperWM.Direction.HEIGHT,
            PaperWM.Direction.ASCENDING),
        reverse_cycle_width = Fnutils.partial(action_manager.cycleWindowSize, PaperWM.Direction.WIDTH,
            PaperWM.Direction.DESCENDING),
        reverse_cycle_height = Fnutils.partial(action_manager.cycleWindowSize, PaperWM.Direction.HEIGHT,
            PaperWM.Direction.DESCENDING),

        -- Window organization
        slurp_in = Fnutils.partial(action_manager.slurpWindow),
        barf_out = Fnutils.partial(action_manager.barfWindow),

        -- Space navigation
        switch_space_l = Fnutils.partial(deps.space_manager.incrementSpace, PaperWM.Direction.LEFT),
        switch_space_r = Fnutils.partial(deps.space_manager.incrementSpace, PaperWM.Direction.RIGHT),
        switch_space_1 = Fnutils.partial(deps.space_manager.switchToSpace, 1),
        switch_space_2 = Fnutils.partial(deps.space_manager.switchToSpace, 2),
        switch_space_3 = Fnutils.partial(deps.space_manager.switchToSpace, 3),
        switch_space_4 = Fnutils.partial(deps.space_manager.switchToSpace, 4),
        switch_space_5 = Fnutils.partial(deps.space_manager.switchToSpace, 5),
        switch_space_6 = Fnutils.partial(deps.space_manager.switchToSpace, 6),
        switch_space_7 = Fnutils.partial(deps.space_manager.switchToSpace, 7),
        switch_space_8 = Fnutils.partial(deps.space_manager.switchToSpace, 8),
        switch_space_9 = Fnutils.partial(deps.space_manager.switchToSpace, 9),

        -- Window to space movement
        move_window_1 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 1),
        move_window_2 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 2),
        move_window_3 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 3),
        move_window_4 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 4),
        move_window_5 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 5),
        move_window_6 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 6),
        move_window_7 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 7),
        move_window_8 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 8),
        move_window_9 = Fnutils.partial(deps.space_manager.moveWindowToSpace, 9)
    }
end

---Move focus to a window in a specified direction
---@param direction Direction use either Direction UP, DOWN, LEFT, or RIGHT
---@param focused_index Index index of focused window within the window_list
function action_manager.focusWindow(direction, focused_index)
    -- If no index provided, use currently focused window
    if not focused_index then
        local focused_window = Window.focusedWindow()
        if not focused_window then
            PaperWM.logger.d("focused window not found")
            return
        end

        local index_table = deps.window_manager.getIndexTable()
        focused_index = index_table[focused_window:id()]
    end

    -- Bail if we can't determine window position
    if not focused_index then
        PaperWM.logger.e("focused index not found")
        return
    end

    -- Find window to focus based on direction
    local new_focused_window = nil

    if direction == PaperWM.Direction.LEFT or direction == PaperWM.Direction.RIGHT then
        -- For left/right, walk down column looking for a match in adjacent column
        for row = focused_index.row, 1, -1 do
            new_focused_window = deps.window_manager.getWindow(focused_index.space,
                focused_index.col + direction, row)
            if new_focused_window then break end
        end
    elseif direction == PaperWM.Direction.UP or direction == PaperWM.Direction.DOWN then
        -- For up/down, just move within the same column
        new_focused_window = deps.window_manager.getWindow(focused_index.space, focused_index.col,
            focused_index.row + (direction // 2))
    end

    -- Bail if no window found in that direction
    if not new_focused_window then
        PaperWM.logger.d("new focused window not found")
        return
    end

    -- Focus the window
    new_focused_window:focus()

    -- Sometimes macOS steals focus away, so try to focus again after animation completes
    Timer.doAfter(Window.animationDuration, function()
        if Window.focusedWindow() ~= new_focused_window then
            PaperWM.logger.df("refocusing window %s", new_focused_window)
            new_focused_window:focus()
        end
    end)

    return new_focused_window
end

---Swap the focused window with another window
---Swaps entire columns for left/right, individual windows for up/down
---@param direction Direction use Direction LEFT, RIGHT, UP, or DOWN
function action_manager.swapWindows(direction)
    -- Get the currently focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Get window's position in the grid
    local index_table = deps.window_manager.getIndexTable()
    local window_list = deps.window_manager.getWindowList()
    local focused_index = index_table[focused_window:id()]

    if not focused_index then
        PaperWM.logger.e("focused index not found")
        return
    end

    -- Handle horizontal swapping (swaps entire columns)
    if direction == PaperWM.Direction.LEFT or direction == PaperWM.Direction.RIGHT then
        -- Get target column
        local target_index = { col = focused_index.col + direction }
        local target_column = deps.window_manager.getColumn(focused_index.space, target_index.col)
        if not target_column then
            PaperWM.logger.d("target column not found")
            return
        end

        -- Get focused column
        local focused_column = deps.window_manager.getColumn(focused_index.space, focused_index.col)

        -- Swap columns in window_list (the data structure)
        window_list[focused_index.space][target_index.col] = focused_column
        window_list[focused_index.space][focused_index.col] = target_column

        -- Update index table for all windows in both columns
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

        -- Calculate new frame positions for swapped columns
        local focused_frame = focused_window:frame()
        local target_frame = target_column[1]:frame()
        local right_gap = deps.utils.getGap("right")

        if direction == PaperWM.Direction.LEFT then
            focused_frame.x = target_frame.x
            target_frame.x = focused_frame.x2 + right_gap
        else -- Direction.RIGHT
            target_frame.x = focused_frame.x
            focused_frame.x = target_frame.x2 + right_gap
        end

        -- Move all windows in both columns
        for _, window in ipairs(target_column) do
            local frame = window:frame()
            frame.x = target_frame.x
            deps.window_manager.moveWindow(window, frame)
        end
        for _, window in ipairs(focused_column) do
            local frame = window:frame()
            frame.x = focused_frame.x
            deps.window_manager.moveWindow(window, frame)
        end

        -- Handle vertical swapping (swaps individual windows)
    elseif direction == PaperWM.Direction.UP or direction == PaperWM.Direction.DOWN then
        -- Find target window
        local target_index = {
            space = focused_index.space,
            col = focused_index.col,
            row = focused_index.row + (direction // 2)
        }

        local target_window = deps.window_manager.getWindow(target_index.space, target_index.col,
            target_index.row)

        if not target_window then
            PaperWM.logger.d("target window not found")
            return
        end

        -- Swap windows in window_list
        window_list[target_index.space][target_index.col][target_index.row] = focused_window
        window_list[focused_index.space][focused_index.col][focused_index.row] = target_window

        -- Update index table
        index_table[target_window:id()] = focused_index
        index_table[focused_window:id()] = target_index

        -- Calculate new frame positions for swapped windows
        local focused_frame = focused_window:frame()
        local target_frame = target_window:frame()
        local bottom_gap = deps.utils.getGap("bottom")

        if direction == PaperWM.Direction.UP then
            focused_frame.y = target_frame.y
            target_frame.y = focused_frame.y2 + bottom_gap
        else -- Direction.DOWN
            target_frame.y = focused_frame.y
            focused_frame.y = target_frame.y2 + bottom_gap
        end

        -- Move both windows
        deps.window_manager.moveWindow(focused_window, focused_frame)
        deps.window_manager.moveWindow(target_window, target_frame)
    end

    -- Update overall layout
    deps.layout_engine.tileSpace(focused_index.space)
end

---Center the focused window horizontally on screen
---Does not change the window's width or vertical position
function action_manager.centerWindow()
    -- Get focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Get window and screen frames
    local focused_frame = focused_window:frame()
    local screen_frame = focused_window:screen():frame()

    -- Center window horizontally
    focused_frame.x = screen_frame.x + (screen_frame.w // 2) -
        (focused_frame.w // 2)
    deps.window_manager.moveWindow(focused_window, focused_frame)

    -- Update layout
    local space = Spaces.windowSpaces(focused_window)[1]
    deps.layout_engine.tileSpace(space)
end

---Toggle full width for the focused window
---Expands window to full width or restores previous width
function action_manager.toggleWindowFullWidth()
    -- Cache for storing original widths
    local width_cache = {}

    -- Return a function that uses the closure to maintain state
    return function()
        -- Get focused window
        local focused_window = Window.focusedWindow()
        if not focused_window then
            PaperWM.logger.d("focused window not found")
            return
        end

        -- Get usable screen area and window frame
        local canvas = deps.utils.getCanvas(focused_window:screen())
        local focused_frame = focused_window:frame()
        local id = focused_window:id()

        -- Check if window is already full width
        local width = width_cache[id]
        if width then
            -- Restore original width and center window
            focused_frame.x = canvas.x + ((canvas.w - width) / 2)
            focused_frame.w = width
            width_cache[id] = nil
        else
            -- Save current width and make window full width
            width_cache[id] = focused_frame.w
            focused_frame.x = canvas.x
            focused_frame.w = canvas.w
        end

        -- Apply changes
        deps.window_manager.moveWindow(focused_window, focused_frame)

        -- Update layout
        local space = Spaces.windowSpaces(focused_window)[1]
        deps.layout_engine.tileSpace(space)
    end
end

---Resize the width or height of the window, keeping the other dimension the same
---Cycles through the ratios specified in PaperWM.window_ratios
---@param direction Direction use Direction.WIDTH or Direction.HEIGHT
---@param cycle_direction Direction use Direction.ASCENDING or DESCENDING
function action_manager.cycleWindowSize(direction, cycle_direction)
    -- Get current focused window
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Helper function to calculate the next size in the sequence
    local function findNewSize(area_size, frame_size, cycle_direction, dimension)
        -- Calculate appropriate gap based on dimension
        local gap
        if dimension == PaperWM.Direction.WIDTH then
            -- For width, use the average of left and right gaps
            gap = (deps.utils.getGap("left") + deps.utils.getGap("right")) / 2
        else
            -- For height, use the average of top and bottom gaps
            gap = (deps.utils.getGap("top") + deps.utils.getGap("bottom")) / 2
        end

        -- Calculate all possible sizes based on ratios
        local sizes = {}
        local new_size = nil

        -- Apply the ratios to calculate absolute pixel dimensions
        for index, ratio in ipairs(PaperWM.window_ratios) do
            sizes[index] = ratio * (area_size + gap) - gap
        end

        -- In ASCENDING mode, find the next larger size
        if cycle_direction == PaperWM.Direction.ASCENDING then
            -- Default to smallest size if we don't find a larger one
            new_size = sizes[1]

            -- Find first size that's noticeably larger than current
            for _, size in ipairs(sizes) do
                if size > frame_size + 10 then -- 10px threshold to avoid imperceptible changes
                    new_size = size
                    break
                end
            end
            -- In DESCENDING mode, find the next smaller size
        elseif cycle_direction == PaperWM.Direction.DESCENDING then
            -- Default to largest size if we don't find a smaller one
            new_size = sizes[#sizes]

            -- Find first size that's noticeably smaller than current
            for i = #sizes, 1, -1 do
                if sizes[i] < frame_size - 10 then -- 10px threshold
                    new_size = sizes[i]
                    break
                end
            end
        else
            PaperWM.logger.e(
                "cycle_direction must be either Direction.ASCENDING or Direction.DESCENDING")
        end

        return new_size
    end

    -- Get canvas (available space) and current window frame
    local canvas = deps.utils.getCanvas(focused_window:screen())
    local focused_frame = focused_window:frame()

    -- Handle width cycling
    if direction == PaperWM.Direction.WIDTH then
        local new_width = findNewSize(canvas.w, focused_frame.w, cycle_direction, PaperWM.Direction.WIDTH)
        -- Center window horizontally while changing width
        focused_frame.x = focused_frame.x + ((focused_frame.w - new_width) // 2)
        focused_frame.w = new_width
        -- Handle height cycling
    elseif direction == PaperWM.Direction.HEIGHT then
        local new_height = findNewSize(canvas.h, focused_frame.h, cycle_direction, PaperWM.Direction.HEIGHT)
        -- Center window vertically while changing height (with bounds checking)
        focused_frame.y = math.max(canvas.y,
            focused_frame.y + ((focused_frame.h - new_height) // 2))
        focused_frame.h = new_height
        -- Ensure the window bottom doesn't extend past the canvas bottom
        focused_frame.y = focused_frame.y -
            math.max(0, focused_frame.y2 - canvas.y2)
    else
        PaperWM.logger.e(
            "direction must be either Direction.WIDTH or Direction.HEIGHT")
        return
    end

    -- Apply new size
    deps.window_manager.moveWindow(focused_window, focused_frame)

    -- Update layout to maintain tiling consistency
    local space = Spaces.windowSpaces(focused_window)[1]
    deps.layout_engine.tileSpace(space)
end

---Take the current focused window and move it into the bottom of
---the column to the left
function action_manager.slurpWindow()
    -- Find the window to manipulate
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Get window's position in our tracking system
    local index_table = deps.window_manager.getIndexTable()
    local window_list = deps.window_manager.getWindowList()
    local focused_index = index_table[focused_window:id()]

    if not focused_index then
        PaperWM.logger.e("focused index not found")
        return
    end

    -- Find target column (to the left of current window)
    local column = deps.window_manager.getColumn(focused_index.space, focused_index.col - 1)
    if not column then
        PaperWM.logger.d("column not found")
        return
    end

    -- Update data structures: Remove window from source column
    table.remove(window_list[focused_index.space][focused_index.col],
        focused_index.row)

    -- If column is now empty, remove the column entirely
    if #window_list[focused_index.space][focused_index.col] == 0 then
        table.remove(window_list[focused_index.space], focused_index.col)
    end

    -- Add window to target column at the end
    table.insert(column, focused_window)

    -- Update window position tracking
    local num_windows = #column
    index_table[focused_window:id()] = {
        space = focused_index.space,
        col = focused_index.col - 1,
        row = num_windows
    }

    -- Update other window indices that may have shifted
    deps.window_manager.updateIndexTable(focused_index.space, focused_index.col)

    -- Update entire layout to ensure consistency
    deps.layout_engine.tileSpace(focused_index.space)
end

---Remove focused window from it's current column and place into
---a new column to the right
function action_manager.barfWindow()
    -- Find window to manipulate
    local focused_window = Window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Get window position in tracking system
    local index_table = deps.window_manager.getIndexTable()
    local window_list = deps.window_manager.getWindowList()
    local focused_index = index_table[focused_window:id()]

    if not focused_index then
        PaperWM.logger.e("focused index not found")
        return
    end

    -- Get current column and verify it's not the only window (can't barf single window)
    local column = deps.window_manager.getColumn(focused_index.space, focused_index.col)
    if #column == 1 then
        PaperWM.logger.d("only window in column")
        return
    end

    -- Update data structures: remove window and create new column
    table.remove(column, focused_index.row)
    table.insert(window_list[focused_index.space], focused_index.col + 1,
        { focused_window }) -- Insert new column with single window

    -- Update window position tracking
    deps.window_manager.updateIndexTable(focused_index.space, focused_index.col)

    -- Update entire layout to ensure consistency
    deps.layout_engine.tileSpace(focused_index.space)
end

return action_manager
