-- Window tracking and management system for PaperWM

local window_manager = {}

-- Core Hammerspoon API dependencies
local Screen = hs.screen
local Spaces = hs.spaces
local Timer = hs.timer
local Watcher = hs.uielement.watcher
local Window = hs.window
local Fnutils = hs.fnutils

-- Module references
local PaperWM
local MissionControl
local utils

-- PRIMARY DATA STRUCTURES
-- These variables form the core state tracking system for PaperWM

-- 3D array of windows organized by [space][column][row]
-- This is the primary data structure that represents the tiled layout
local window_list = {} 

-- Maps window IDs to their position in the window_list
-- Enables O(1) lookup of a window's position in the grid
local index_table = {} 

-- Maps window IDs to their UI event watchers
-- Allows watching for window moved/resize events
local ui_watchers = {} 

-- Tracks which windows are in floating mode (not tiled)
-- Windows in this list are excluded from tiling operations
local is_floating = {} 

-- Tracks virtual x-positions for windows during swipe operations
-- Enables smooth scrolling of windows, even beyond screen edges
local x_positions = {} 

-- Window state tracking for event handling
-- Used to handle complex event sequences when windows are created or focused
local prev_focused_window = nil 
local pending_window = nil

-- Screen change watcher
local screen_watcher = nil

-- Initialize with references to required objects
function window_manager.init(paperWM, missionControl)
    PaperWM = paperWM
    MissionControl = missionControl
    utils = require("modules.utils")
    utils.init(PaperWM)
    utils.setWindowList(window_list)
    
    -- Initialize screen watcher
    if screen_watcher then
        screen_watcher:stop()
    end
    screen_watcher = Screen.watcher.new(function() window_manager.refreshWindows() end)
    screen_watcher:start()
    
    -- Restore floating window state from settings
    window_manager.initializeFloatingWindows()
    
    return window_manager
end

-- Stop monitoring and clean up
function window_manager.stop()
    -- Stop event watchers
    for _, watcher in pairs(ui_watchers) do watcher:stop() end
    
    -- Stop screen watcher
    if screen_watcher then
        screen_watcher:stop()
    end
end

---Get a column of windows from the window_list
---Provides safe access to a column, returning empty table if not found
---@param space Space
---@param col number
---@return Window[]
function window_manager.getColumn(space, col) 
    return (window_list[space] or {})[col] 
end

---Get a specific window by its grid coordinates
---Provides safe access to a window, returning nil if not found
---@param space Space
---@param col number
---@param row number
---@return Window
function window_manager.getWindow(space, col, row)
    return (window_manager.getColumn(space, col) or {})[row]
end

---Update index_table entries for a space starting from a specific column
---Ensures index_table remains in sync with window_list after changes
---@param space Space
---@param column number
function window_manager.updateIndexTable(space, column)
    local columns = window_list[space] or {}
    for col = column, #columns do
        for row, window in ipairs(window_manager.getColumn(space, col)) do
            index_table[window:id()] = { space = space, col = col, row = row }
        end
    end
end

---Update the virtual x positions used for swipe gestures
---@param space Space
---@param windows Window[]
function window_manager.updateVirtualPositions(space, windows, x)
    -- Skip if swipe gestures are disabled
    if PaperWM.swipe_fingers == 0 then return end
    
    -- Initialize space tracking table if needed
    if not x_positions[space] then
        x_positions[space] = {}
    end
    
    -- Update virtual position for each window
    for _, window in ipairs(windows) do
        x_positions[space][window] = x
    end
end

---Save the floating window list to persistent storage
---This allows floating status to survive Hammerspoon restarts
function window_manager.persistFloatingList()
    local persisted = {}
    for k, _ in pairs(is_floating) do
        table.insert(persisted, k)
    end
    hs.settings.set(PaperWM.IsFloatingKey, persisted)
end

-- Load and initialize the saved floating window state
function window_manager.initializeFloatingWindows()
    -- Restore floating window state from settings
    local persisted = hs.settings.get(PaperWM.IsFloatingKey) or {}
    for _, id in ipairs(persisted) do
        local window = Window.get(id)
        if window and PaperWM.window_filter:isWindowAllowed(window) then
            is_floating[id] = true
        end
    end
    window_manager.persistFloatingList()
end

---move and resize a window to the coordinates specified by the frame
---disable watchers while window is moving and re-enable after
---@param window Window window to move
---@param frame Frame coordinates to set window size and location
function window_manager.moveWindow(window, frame)
    -- Slightly longer than window animation duration to ensure completion
    local padding = 0.02

    -- Get window's UI watcher
    local watcher = ui_watchers[window:id()]
    if not watcher then
        PaperWM.logger.e("window does not have ui watcher")
        return
    end

    -- Skip if no change in position
    if frame == window:frame() then
        PaperWM.logger.v("no change in window frame")
        return
    end

    -- Stop watcher to prevent reacting to our own window changes
    watcher:stop()
    
    -- Move window
    window:setFrame(frame)
    
    -- Re-enable watcher after animation completes
    Timer.doAfter(Window.animationDuration + padding, function()
        watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    end)
end

---Add a new window to be tracked and tiled
---@param add_window Window new window to be added
---@return Space|nil space that contains new window
function window_manager.addWindow(add_window)
    -- Handle tabs in windows
    local apple = "com.apple"
    if add_window:tabCount() > 0 and add_window:application():bundleID():sub(1, #apple) == apple then
        hs.notify.show("PaperWM", "Windows with tabs are not supported!",
            "See https://github.com/mogenson/PaperWM.spoon/issues/39")
        return
    end

    -- Ignore non-maximizable windows
    if not add_window:isMaximizable() then
        PaperWM.logger.d("ignoring non-maximizable window")
        return
    end

    -- Skip windows already being tracked
    if index_table[add_window:id()] then return end

    -- Get the space the window is on
    local space = Spaces.windowSpaces(add_window)[1]
    if not space then
        PaperWM.logger.e("add window does not have a space")
        return
    end
    
    -- Initialize space in window_list if needed
    if not window_list[space] then window_list[space] = {} end

    -- Determine where to insert the window
    local add_column = 1

    -- If a window was previously focused, insert to its right
    if prev_focused_window and
        ((index_table[prev_focused_window:id()] or {}).space == space) and
        (prev_focused_window:id() ~= add_window:id()) then
        add_column = index_table[prev_focused_window:id()].col + 1
    else
        -- Otherwise position based on window's center x coordinate
        local x = add_window:frame().center.x
        for col, windows in ipairs(window_list[space]) do
            if x < windows[1]:frame().center.x then
                add_column = col
                break
            end
        end
    end

    -- Add the window to window_list
    table.insert(window_list[space], add_column, { add_window })

    -- Update index lookup table
    window_manager.updateIndexTable(space, add_column)

    -- Create watcher for window movement events
    local event_handler = require("modules.event_handler")
    local watcher = add_window:newWatcher(function(window, event)
        event_handler.windowEventHandler(window, event)
    end)
    
    -- Start watching for move/resize events
    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
    ui_watchers[add_window:id()] = watcher

    return space
end

---Remove a window from tracking and tiling
---@param remove_window Window window to be removed
---@param skip_new_window_focus boolean|nil don't focus a nearby window if true
---@return Space|nil space that contained removed window
function window_manager.removeWindow(remove_window, skip_new_window_focus)
    -- Get window's position in the grid
    local remove_index = index_table[remove_window:id()]
    if not remove_index then
        PaperWM.logger.e("remove index not found")
        return
    end

    -- Find a nearby window to focus unless skipping
    if not skip_new_window_focus then
        -- Try focusing in this order: down, up, left, right
        local action_manager = require("modules.action_manager")
        for _, direction in ipairs({
            PaperWM.Direction.DOWN, PaperWM.Direction.UP, 
            PaperWM.Direction.LEFT, PaperWM.Direction.RIGHT
        }) do 
            if action_manager.focusWindow(direction, remove_index) then 
                break 
            end 
        end
    end

    -- Remove window from column
    table.remove(window_list[remove_index.space][remove_index.col],
        remove_index.row)
        
    -- Remove the column if it's now empty
    if #window_list[remove_index.space][remove_index.col] == 0 then
        table.remove(window_list[remove_index.space], remove_index.col)
    end

    -- Stop and remove the UI watcher
    ui_watchers[remove_window:id()]:stop()
    ui_watchers[remove_window:id()] = nil

    -- Clear swipe position tracking
    (x_positions[remove_index.space] or {})[remove_window] = nil

    -- Update index lookup table
    index_table[remove_window:id()] = nil
    window_manager.updateIndexTable(remove_index.space, remove_index.col)

    -- Clean up space if it's now empty
    if #window_list[remove_index.space] == 0 then
        window_list[remove_index.space] = nil
        x_positions[remove_index.space] = nil
    end

    return remove_index.space -- Return space for removed window
end

---Refresh all windows across all spaces
---Re-tiles everything, useful after display changes
function window_manager.refreshWindows()
    -- Get all managed windows across all spaces
    local all_windows = PaperWM.window_filter:getWindows()

    -- Track which spaces need to be re-tiled
    local retile_spaces = {}
    
    -- Process each window
    for _, window in ipairs(all_windows) do
        local index = index_table[window:id()]
        
        -- Skip floating windows
        if is_floating[window:id()] then
            -- ignore floating windows
        
        -- Add new windows
        elseif not index then
            local space = window_manager.addWindow(window)
            if space then retile_spaces[space] = true end
        
        -- Handle windows that moved between spaces
        elseif index.space ~= Spaces.windowSpaces(window)[1] then
            -- move to window list in new space, don't focus nearby window
            window_manager.removeWindow(window, true)
            local space = window_manager.addWindow(window)
            if space then retile_spaces[space] = true end
        end
    end

    -- Re-tile all affected spaces
    local layout_engine = require("modules.layout_engine")
    for space, _ in pairs(retile_spaces) do 
        layout_engine.tileSpace(space) 
    end
end

---add or remove focused window from the floating layer and retile the space
function window_manager.toggleFloating()
    -- Get window to toggle
    local window = Window.focusedWindow()
    if not window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Toggle floating state
    local id = window:id()
    if is_floating[id] then
        is_floating[id] = nil
    else
        is_floating[id] = true
    end
    
    -- Save floating list to persistent storage
    window_manager.persistFloatingList()

    -- Update window tracking based on new state
    local space = (function()
        if is_floating[id] then
            return window_manager.removeWindow(window, true)  -- If now floating, remove from tiling
        else
            return window_manager.addWindow(window)  -- If now tiled, add to tiling
        end
    end)()
    
    -- Update layout
    local layout_engine = require("modules.layout_engine")
    if space then
        layout_engine.tileSpace(space)
    end
end

---Generate callback function for touchpad swipe gesture events
---Creates a closure that maintains state between swipe callbacks
function window_manager.swipeHandler()
    -- Upvalues preserved between callback invocations
    local space, screen_frame = nil, nil

    ---Callback function for touchpad swipe gestures
    ---@param id number unique id across callbacks for the same swipe
    ---@param type number one of Swipe.BEGIN, Swipe.MOVED, Swipe.END
    ---@param dx number change in horizonal position since last callback: between 0 and 1
    ---@param dy number change in vertical position since last callback: between 0 and 1
    return function(id, type, dx, dy)
        local Swipe = dofile(hs.spoons.resourcePath("external/swipe.lua"))
        
        -- Handle swipe start
        if type == Swipe.BEGIN then
            PaperWM.logger.df("new swipe: %d", id)

            -- Find the focused window to determine which space to affect
            local focused_window = Window.focusedWindow()
            if not focused_window then
                PaperWM.logger.d("focused window not found")
                return
            end

            -- Get window's position in the grid
            local focused_index = index_table[focused_window:id()]
            if not focused_index then
                PaperWM.logger.e("focused index not found")
                return
            end

            -- Find the screen containing the space
            local screen = Screen(Spaces.spaceDisplay(focused_index.space))
            if not screen then
                PaperWM.logger.e("no screen for space")
                return
            end

            -- Cache values for use in subsequent callbacks
            screen_frame = screen:frame()
            space        = focused_index.space

            -- Temporarily disable move watchers during swipe
            for window, _ in pairs(x_positions[space] or {}) do
                if not window then break end
                local watcher = ui_watchers[window:id()]
                if watcher then
                    watcher:stop()
                end
            end
        
        -- Handle swipe end
        elseif type == Swipe.END then
            PaperWM.logger.df("swipe end: %d", id)

            -- Skip if we don't have the necessary state
            if not space or not screen_frame then
                return
            end

            -- Re-enable window watchers
            for window, _ in pairs(x_positions[space] or {}) do
                if not window then break end
                local watcher = ui_watchers[window:id()]
                if watcher then
                    watcher:start({ Watcher.windowMoved, Watcher.windowResized })
                end
            end

            -- Ensure a window that's visible on screen is focused
            local focused_window = Window.focusedWindow()
            if focused_window then
                local frame = focused_window:frame()
                local visible_window = (function()
                    -- If window is off the left edge, focus leftmost visible window
                    if frame.x < screen_frame.x then
                        return utils.getFirstVisibleWindow(space, screen_frame,
                            PaperWM.Direction.LEFT)
                    -- If window is off the right edge, focus rightmost visible window
                    elseif frame.x2 > screen_frame.x2 then
                        return utils.getFirstVisibleWindow(space, screen_frame,
                            PaperWM.Direction.RIGHT)
                    end
                end)()
                
                -- Focus a visible window or retile the space
                local layout_engine = require("modules.layout_engine")
                if visible_window then
                    visible_window:focus()
                else
                    layout_engine.tileSpace(space)
                end
            else
                PaperWM.logger.e("no focused window at end of swipe")
            end

            -- Clear cached state
            space, screen_frame = nil, nil
        
        -- Handle swipe movement
        elseif type == Swipe.MOVED then
            -- Skip if we don't have the necessary state
            if not space or not screen_frame then
                return
            end

            -- Only process horizontal swipes (ignore if vertical component is larger)
            if math.abs(dy) >= math.abs(dx) then
                return
            end

            -- Scale the movement by screen width and gain factor
            dx = math.floor(PaperWM.swipe_gain * dx * screen_frame.w)

            -- Calculate screen edge margins
            local left_margin  = screen_frame.x + PaperWM.screen_margin
            local right_margin = screen_frame.x2 - PaperWM.screen_margin

            -- Update position of all windows in the space
            for window, x in pairs(x_positions[space] or {}) do
                if not window then break end
                
                -- Update virtual position
                x = x + dx
                
                local frame = window:frame()
                if dx > 0 then -- scrolling right
                    frame.x = math.min(x, right_margin)
                else           -- scrolling left
                    frame.x = math.max(x, left_margin - frame.w)
                end
                
                -- Update window position immediately (bypass animation)
                window:setTopLeft(frame.x, frame.y)
                
                -- Save virtual position for next movement
                x_positions[space][window] = x
            end
        end
    end
end

-- Expose internal state (for module access)
function window_manager.getWindowList()
    return window_list
end

function window_manager.getIndexTable()
    return index_table
end

function window_manager.getUIWatchers()
    return ui_watchers
end

function window_manager.getIsFloating()
    return is_floating
end

function window_manager.getXPositions()
    return x_positions
end

function window_manager.setPrevFocusedWindow(window)
    prev_focused_window = window
end

function window_manager.getPrevFocusedWindow()
    return prev_focused_window
end

function window_manager.setPendingWindow(window)
    pending_window = window
end

function window_manager.getPendingWindow()
    return pending_window
end

return window_manager