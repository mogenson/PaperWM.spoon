-- Utility functions used throughout PaperWM

local utils = {}

-- Core Hammerspoon API dependencies
local Rect = hs.geometry.rect

-- Module references
local PaperWM
local window_list

-- Initialize with references to required objects
function utils.init(paperWM)
    PaperWM = paperWM
    return utils
end

-- Sets the window_list reference (called from window_manager)
function utils.setWindowList(wl)
    window_list = wl
end

---Get the gap value for a specific side
---Handles both numeric and table-based gap configurations
---@param side string "top", "bottom", "left", or "right"
---@return number gap size in pixels
function utils.getGap(side)
    local gap = PaperWM.window_gap
    if type(gap) == "number" then
        return gap            -- backward compatibility with single number
    elseif type(gap) == "table" then
        return gap[side] or 8 -- default to 8 if missing
    else
        return 8              -- fallback default
    end
end

---Calculate the usable screen area accounting for gaps
---Returns a rectangle representing the area for tiling windows
---@param screen Screen
---@return Frame
function utils.getCanvas(screen)
    local screen_frame = screen:frame()
    local left_gap = utils.getGap("left")
    local right_gap = utils.getGap("right")
    local top_gap = utils.getGap("top")
    local bottom_gap = utils.getGap("bottom")

    return Rect(
        screen_frame.x + left_gap,
        screen_frame.y + top_gap,
        screen_frame.w - (left_gap + right_gap),
        screen_frame.h - (top_gap + bottom_gap)
    )
end

---Find the first window that's visible on screen
---Used when determining which window to focus after switching spaces
---@param space Space space to lookup windows
---@param screen_frame Frame the coordinates of the screen
---@pram direction Direction|nil either LEFT or RIGHT
---@return Window|nil
function utils.getFirstVisibleWindow(space, screen_frame, direction)
    -- Default to finding the leftmost window if direction not specified
    direction = direction or PaperWM.Direction.LEFT
    local distance = math.huge
    local closest = nil

    -- Iterate through all windows in the space to find the closest visible one
    for _, windows in ipairs(window_list[space] or {}) do
        local window = windows[1] -- take first window in column
        local d = (function()
            if direction == PaperWM.Direction.LEFT then
                -- Distance from left edge of screen
                return window:frame().x - screen_frame.x
            elseif direction == PaperWM.Direction.RIGHT then
                -- Distance from right edge of screen
                return screen_frame.x2 - window:frame().x2
            end
        end)() or math.huge

        -- Keep track of the closest visible window
        if d >= 0 and d < distance then
            distance = d
            closest = window
        end
    end
    return closest
end

return utils
