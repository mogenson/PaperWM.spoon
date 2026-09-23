local Window <const> = hs.window
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Fnutils <const> = hs.fnutils

local Tiling = {}
Tiling._index = Tiling


---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Tiling.init(paperwm)
    Tiling.PaperWM = paperwm
end

---update the virtual x position for a table of windows on the specified space
---@param space Space
---@param windows Window[]
local function update_virtual_positions(space, windows, x)
    local x_positions = Tiling.PaperWM.state.xPositions(space)
    for _, window in ipairs(windows) do
        x_positions[window:id()] = x
    end
end

---tile a column of window by moving and resizing
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param h number|nil set windows to specified height
---@param w number|nil set windows to specified width
---@param id number|nil id of window to set specific height
---@param h4id number|nil specific height for provided window id
---@return number width of tiled column
function Tiling.tileColumn(windows, bounds, h, w, id, h4id)
    local last_window, frame
    local bottom_gap = Tiling.PaperWM.windows.getGap("bottom")

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
        Tiling.PaperWM.windows.moveWindow(window, frame)
        bounds.y = math.min(frame.y2 + bottom_gap, bounds.y2)
        last_window = window
    end
    -- expand last window height to bottom
    if frame.y2 ~= bounds.y2 then
        frame.y2 = bounds.y2
        Tiling.PaperWM.windows.moveWindow(last_window, frame)
    end
    return w -- return width of column
end

---tile a stacked column as an accordion: every window shares the same width
---and height, offset vertically by accordion_peek so each title bar stays
---visible and clickable. windows above the active row cascade from the top of
---the bounds, windows below start at the active window's bottom edge and
---overflow the bottom of the bounds. windows are raised in row order with the
---active window raised last so every peeking strip stays on top of the window
---before it
---@param windows Window[] column of windows
---@param bounds Frame bounds to constrain column of tiled windows
---@param active_row number row of the expanded window
---@param w number|nil set windows to specified width
---@return number width of tiled column
function Tiling.tileStackedColumn(windows, bounds, active_row, w)
    local peek <const> = Tiling.PaperWM.accordion_peek
    local n = #windows
    active_row = math.max(1, math.min(active_row, n))
    w = w or windows[1]:frame().w
    local x = bounds.x or (bounds.x2 - w)
    local h = math.max(Tiling.PaperWM.stack_min_height, (bounds.y2 - bounds.y) - ((n - 1) * peek))

    for row, window in ipairs(windows) do
        local frame = window:frame()
        frame.x = x
        frame.w = w
        frame.h = h
        if row <= active_row then
            frame.y = bounds.y + ((row - 1) * peek)
        else
            frame.y = bounds.y + ((active_row - 1) * peek) + h + ((row - active_row - 1) * peek)
        end
        frame.x2 = frame.x + frame.w
        frame.y2 = frame.y + frame.h
        Tiling.PaperWM.windows.moveWindow(window, frame)
    end

    -- raising the active window makes it its app's main window, which steals
    -- focus when the app is frontmost. apps may also refuse requested frames
    -- (minimum sizes), so achieved frames can never be trusted to settle:
    -- restack only when the stack composition or the active row changes
    local signature = tostring(active_row)
    for _, window in ipairs(windows) do
        signature = signature .. ":" .. window:id()
    end
    local column_meta = windows --[[@as table]]
    if column_meta.stack_signature ~= signature then
        for row, window in ipairs(windows) do
            if row ~= active_row then window:raise() end
        end
        windows[active_row]:raise()
        column_meta.stack_signature = signature
    end
    return w
end

---tile all column in a space by moving and resizing windows
---optionally starting with anchor_window and moving out
---@param space Space
---@param anchor_window Window
function Tiling.tileSpace(space, anchor_window)
    if not space or Spaces.spaceType(space) ~= "user" then
        Tiling.PaperWM.logger.e("current space invalid")
        return
    end

    -- floating the last tiled window leaves nothing to arrange
    if #Tiling.PaperWM.state.windowList(space) == 0 then return end

    -- find screen for space
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        Tiling.PaperWM.logger.e("no screen for space")
        return
    end

    local function windowOnSpace(window)
        return Fnutils.contains(Spaces.windowSpaces(window), space)
    end

    -- if anchor window is in space, tile from that. otherwise use focused window
    anchor_window = anchor_window or (function()
        local focused_window = Window.focusedWindow()
        if focused_window and not Tiling.PaperWM.floating.isFloating(focused_window) and windowOnSpace(focused_window) then
            return focused_window
        else
            return Tiling.PaperWM.windows.getFirstVisibleWindow(space, screen:frame())
        end
    end)()

    if not anchor_window or not windowOnSpace(anchor_window) then
        Tiling.PaperWM.logger.e("no anchor window in space")
        return
    end

    Tiling.PaperWM.logger.df("tiling from anchor window: %s (%d)", anchor_window:title(), anchor_window:id())

    local anchor_index = Tiling.PaperWM.state.windowIndex(anchor_window)
    if not anchor_index then
        Tiling.PaperWM.logger.e("anchor index not found, refreshing windows")
        Tiling.PaperWM.windows.refreshWindows() -- try refreshing the windows
        return                                  -- bail
    end

    -- get some global coordinates
    local screen_frame <const> = screen:frame()
    local left_margin <const> = screen_frame.x + Tiling.PaperWM.screen_margin
    local right_margin <const> = screen_frame.x2 - Tiling.PaperWM.screen_margin
    local canvas <const> = Tiling.PaperWM.windows.getCanvas(screen)

    -- make sure anchor window is on screen
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, canvas.x)
    anchor_frame.w = math.min(anchor_frame.w, canvas.w)
    anchor_frame.h = math.min(anchor_frame.h, canvas.h)
    if anchor_frame.x2 > canvas.x2 then
        anchor_frame.x = canvas.x2 - anchor_frame.w
    end

    -- adjust anchor window column
    local column = Tiling.PaperWM.state.windowList(space, anchor_index.col)
    if not column then
        Tiling.PaperWM.logger.e("no anchor window column")
        return
    end

    -- TODO: need a minimum window height
    if Tiling.PaperWM.state.isStacked(space, anchor_index.col) then
        -- the anchor can be a fallback pick (e.g. first visible window) during
        -- background retiles: only the focused window may change the active row
        local focused_window = Window.focusedWindow()
        if focused_window and focused_window:id() == anchor_window:id() then
            Tiling.PaperWM.state.setActiveRow(space, anchor_index.col, anchor_index.row)
        end
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2,
        }
        local active_row = Tiling.PaperWM.state.activeRow(space, anchor_index.col)
        Tiling.tileStackedColumn(column, bounds, active_row, anchor_frame.w)
    elseif #column == 1 then
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        Tiling.PaperWM.windows.moveWindow(anchor_window, anchor_frame)
    else
        local n = #column - 1 -- number of other windows in column
        local bottom_gap = Tiling.PaperWM.windows.getGap("bottom")
        local h =
            math.max(0, canvas.h - anchor_frame.h - (n * bottom_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2,
        }
        Tiling.tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(), anchor_frame.h)
    end
    update_virtual_positions(space, column, anchor_frame.x)

    local right_gap = Tiling.PaperWM.windows.getGap("right")
    local left_gap = Tiling.PaperWM.windows.getGap("left")

    -- tile windows from anchor right
    local x = anchor_frame.x2 + right_gap
    for col = anchor_index.col + 1, #(Tiling.PaperWM.state.windowList(space)) do
        local bounds = {
            x = math.min(x, right_margin),
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2,
        }
        local column = Tiling.PaperWM.state.windowList(space, col)
        local width
        if Tiling.PaperWM.state.isStacked(space, col) then
            width = Tiling.tileStackedColumn(column, bounds, Tiling.PaperWM.state.activeRow(space, col))
        else
            width = Tiling.tileColumn(column, bounds)
        end
        update_virtual_positions(space, column, x)
        x = x + width + right_gap
    end

    -- tile windows from anchor left
    local x2 = anchor_frame.x - left_gap
    for col = anchor_index.col - 1, 1, -1 do
        local bounds = {
            x = nil,
            x2 = math.max(x2, left_margin),
            y = canvas.y,
            y2 = canvas.y2,
        }
        local column = Tiling.PaperWM.state.windowList(space, col)
        local width
        if Tiling.PaperWM.state.isStacked(space, col) then
            width = Tiling.tileStackedColumn(column, bounds, Tiling.PaperWM.state.activeRow(space, col))
        else
            width = Tiling.tileColumn(column, bounds)
        end
        update_virtual_positions(space, column, x2 - width)
        x2 = x2 - width - left_gap
    end
end

return Tiling
