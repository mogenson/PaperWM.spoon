-- Layout engine for tiling windows

local layout_engine = {}

-- Core Hammerspoon API dependencies
local Screen = hs.screen
local Spaces = hs.spaces
local Window = hs.window

-- Module references
local PaperWM
local window_manager
local utils

-- Initialize with references to required objects
function layout_engine.init(paperWM, windowManager)
    PaperWM = paperWM
    window_manager = windowManager
    utils = require("modules.utils")

    return layout_engine
end

---Tile a column of windows
---Arranges windows vertically within specified bounds
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param h number|nil set windows to specified height
---@param w number|nil set windows to specified width
---@param id number|nil id of window to set specific height
---@param h4id number|nil specific height for provided window id
---@return number width of tiled column
function layout_engine.tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    local bottom_gap = utils.getGap("bottom")

    -- Position each window in the column
    for _, window in ipairs(windows) do
        frame = window:frame()

        -- Use specified width or use current width
        w = w or frame.w

        -- Set horizontal position based on bounds
        if bounds.x then
            frame.x = bounds.x
        elseif bounds.x2 then
            frame.x = bounds.x2 - w
        end

        -- Set height based on parameters
        if h then
            if id and h4id and window:id() == id then
                frame.h = h4id -- Use specific height for window with matching id
            else
                frame.h = h    -- Use standard height for other windows
            end
        end

        -- Position and size the window
        frame.y = bounds.y
        frame.w = w
        frame.y2 = math.min(frame.y2, bounds.y2) -- Prevent overflow

        -- Apply the changes
        window_manager.moveWindow(window, frame)

        -- Update bounds for next window
        bounds.y = math.min(frame.y2 + bottom_gap, bounds.y2)
        last_window = window
    end

    -- Expand the last window to fill remaining space
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        window_manager.moveWindow(last_window, frame)
    end

    return w -- Return the column width
end

---Tile all columns in a space
---This is the main layout algorithm that positions all windows
---@param space Space
function layout_engine.tileSpace(space)
    -- Validate the space
    if not space or Spaces.spaceType(space) ~= "user" then
        PaperWM.logger.e("current space invalid")
        return
    end

    -- Find screen for this space
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        PaperWM.logger.e("no screen for space")
        return
    end

    -- Find anchor window (starting point for tiling)
    -- Use focused window if it's in this space, otherwise find a visible window
    local focused_window = Window.focusedWindow()
    local window_list = window_manager.getWindowList()
    local is_floating = window_manager.getIsFloating()
    local index_table = window_manager.getIndexTable()

    local anchor_window = (function()
        if focused_window and
            not is_floating[focused_window:id()] and
            Spaces.windowSpaces(focused_window)[1] == space then
            return focused_window
        else
            return utils.getFirstVisibleWindow(space, screen:frame())
        end
    end)()

    -- Bail if no anchor window found
    if not anchor_window then
        PaperWM.logger.e("no anchor window in space")
        return
    end

    -- Get anchor window's position in the grid
    local anchor_index = index_table[anchor_window:id()]
    if not anchor_index then
        PaperWM.logger.e("anchor index not found")
        return
    end

    -- Get screen geometry information
    local screen_frame = screen:frame()
    local left_margin = screen_frame.x + PaperWM.screen_margin
    local right_margin = screen_frame.x2 - PaperWM.screen_margin
    local canvas = utils.getCanvas(screen)

    -- Ensure anchor window is properly positioned on screen
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, canvas.x)
    anchor_frame.w = math.min(anchor_frame.w, canvas.w)
    anchor_frame.h = math.min(anchor_frame.h, canvas.h)
    if anchor_frame.x2 > canvas.x2 then
        anchor_frame.x = canvas.x2 - anchor_frame.w
    end

    -- Get the column containing the anchor window
    local column = window_manager.getColumn(space, anchor_index.col)
    if not column then
        PaperWM.logger.e("no anchor window column")
        return
    end

    -- Tile the anchor column
    -- If only one window in the column, let it take full height
    if #column == 1 then
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        window_manager.moveWindow(anchor_window, anchor_frame)
    else
        -- Distribute space among windows in the column
        local n = #column - 1 -- number of other windows
        local bottom_gap = utils.getGap("bottom")
        -- Calculate height for windows other than anchor
        local h = math.max(0, canvas.h - anchor_frame.h - (n * bottom_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        -- Tile the column, giving anchor window its preferred height
        layout_engine.tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(),
            anchor_frame.h)
    end

    -- Update virtual positions for swipe gestures
    window_manager.updateVirtualPositions(space, column, anchor_frame.x)

    -- Get gap sizes for tiling calculations
    local right_gap = utils.getGap("right")
    local left_gap = utils.getGap("left")

    -- Tile columns to the right of anchor
    local x = anchor_frame.x2 + right_gap
    for col = anchor_index.col + 1, #(window_list[space] or {}) do
        local bounds = {
            x = math.min(x, right_margin),
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2
        }
        local column = window_manager.getColumn(space, col)
        local width = layout_engine.tileColumn(column, bounds)
        window_manager.updateVirtualPositions(space, column, x)
        x = x + width + right_gap
    end

    -- Tile columns to the left of anchor
    local x = anchor_frame.x
    local x2 = math.max(anchor_frame.x - left_gap, left_margin)
    for col = anchor_index.col - 1, 1, -1 do
        local bounds = { x = nil, x2 = x2, y = canvas.y, y2 = canvas.y2 }
        local column = window_manager.getColumn(space, col)
        local width = layout_engine.tileColumn(column, bounds)
        x = x - width - left_gap
        window_manager.updateVirtualPositions(space, column, x)
        x2 = math.max(x2 - width - left_gap, left_margin)
    end
end

return layout_engine
