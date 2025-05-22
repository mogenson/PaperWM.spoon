-- Space management for PaperWM

local space_manager = {}

-- Core Hammerspoon API dependencies
local Screen = hs.screen
local Spaces = hs.spaces
local Fnutils = hs.fnutils

-- Module references
local PaperWM
local MissionControl
local window_manager
local layout_engine
local utils

-- Initialize with references to required objects
function space_manager.init(paperWM, missionControl, windowManager, layoutEngine)
    PaperWM = paperWM
    MissionControl = missionControl
    window_manager = windowManager
    layout_engine = layoutEngine
    utils = require("modules.utils")

    return space_manager
end

---switch to a Mission Control space
---@param index number incremental id for space
function space_manager.switchToSpace(index)
    -- Get the space ID from index
    local space = MissionControl:getSpaceID(index)
    if not space then
        PaperWM.logger.d("space not found")
        return
    end

    -- Get the screen associated with this space
    local screen = Screen(Spaces.spaceDisplay(space))

    -- Find a window to focus on the target space
    local window = utils.getFirstVisibleWindow(space, screen:frame())

    -- Switch to space and focus a window there
    Spaces.gotoSpace(space)
    MissionControl:focusSpace(space, window)
end

---switch to a Mission Control space to the left or right of current space
---@param direction Direction use Direction.LEFT or Direction.RIGHT
function space_manager.incrementSpace(direction)
    -- Validate direction
    if (direction ~= PaperWM.Direction.LEFT and direction ~= PaperWM.Direction.RIGHT) then
        PaperWM.logger.d("move is invalid, left and right only")
        return
    end

    -- Find current space and build a linear representation of all spaces
    local curr_space_id = Spaces.focusedSpace()
    local layout = Spaces.allSpaces()
    local curr_space_idx = -1
    local num_spaces = 0

    -- Build flattened list of spaces across all screens
    for _, screen in ipairs(Screen.allScreens()) do
        local screen_uuid = screen:getUUID()

        -- Try to find current space index
        if curr_space_idx < 0 then
            for idx, space_id in ipairs(layout[screen_uuid]) do
                if curr_space_id == space_id then
                    curr_space_idx = idx + num_spaces
                    break
                end
            end
        end

        -- Count total spaces
        num_spaces = num_spaces + #layout[screen_uuid]
    end

    -- Calculate new space index with wraparound
    if curr_space_idx >= 0 then
        local new_space_idx = ((curr_space_idx - 1 + direction) % num_spaces) + 1
        space_manager.switchToSpace(new_space_idx)
    end
end

---move focused window to a Mission Control space
---@param index number space index
function space_manager.moveWindowToSpace(index)
    -- Get the window to move
    local focused_window = hs.window.focusedWindow()
    if not focused_window then
        PaperWM.logger.d("focused window not found")
        return
    end

    -- Get target space by index
    local new_space = MissionControl:getSpaceID(index)
    if not new_space then
        PaperWM.logger.d("space not found")
        return
    end

    -- Various validation checks
    if new_space == Spaces.windowSpaces(focused_window)[1] then
        PaperWM.logger.d("window already on space")
        return
    end

    if Spaces.spaceType(new_space) ~= "user" then
        PaperWM.logger.d("space is invalid")
        return
    end

    -- Get screens for source and destination
    local old_screen = focused_window:screen()
    if not old_screen then
        PaperWM.logger.d("no screen for window")
        return
    end

    local new_screen = Screen(Spaces.spaceDisplay(new_space))
    if not new_screen then
        PaperWM.logger.d("no screen for space")
        return
    end

    -- Check window filter to see if window should be managed on new screen
    local allowed_screens = PaperWM.window_filter:getFilters().override.allowScreens or Screen.allScreens()
    allowed_screens = Fnutils.imap(allowed_screens, function(screen) return Screen.find(screen) end)

    -- Remove window from source space tracking if allowed
    local old_space = (function(allowed)
        if allowed then
            return window_manager.removeWindow(focused_window, true) -- don't switch focus
        end
    end)(Fnutils.contains(allowed_screens, old_screen))

    -- Use Mission Control to physically move the window
    local ret, err = MissionControl:moveWindowToSpace(focused_window, new_space)
    if not ret or err then
        PaperWM.logger.e(err)
        return
    end

    -- Update source space layout
    if old_space then
        layout_engine.tileSpace(old_space)
    end

    -- Add window to destination space tracking if allowed
    if Fnutils.contains(allowed_screens, new_screen) then
        window_manager.addWindow(focused_window)
        layout_engine.tileSpace(new_space)
        MissionControl:focusSpace(new_space, focused_window)
    end
end

return space_manager
