local Window <const> = hs.window
local Screen <const> = hs.screen
local Spaces <const> = hs.spaces

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

---tile all column in a space by moving and resizing windows
---@param space Space
function Tiling.tileSpace(space)
    local start = hs.timer.absoluteTime()

    if not space or Spaces.spaceType(space) ~= "user" then
        Tiling.PaperWM.logger.e("current space invalid")
        return
    end

    -- find screen for space
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        Tiling.PaperWM.logger.e("no screen for space")
        return
    end

    -- if focused window is in space, tile from that
    local focused_window = Window.focusedWindow()
    local anchor_window = (function()
        if focused_window and not Tiling.PaperWM.floating.isFloating(focused_window) and Spaces.windowSpaces(focused_window)[1] == space then
            return focused_window
        else
            return Tiling.PaperWM.windows.getFirstVisibleWindow(space, screen:frame())
        end
    end)()

    if not anchor_window then
        Tiling.PaperWM.logger.e("no anchor window in space")
        return
    end

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
    if #column == 1 then
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
        local width = Tiling.tileColumn(column, bounds)
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
        local width = Tiling.tileColumn(column, bounds)
        update_virtual_positions(space, column, x2 - width)
        x2 = x2 - width - left_gap
    end

    -- tileSpace() takes anywhere from 3 to 60 ms on an M3 Macbook
    local finish = hs.timer.absoluteTime()
    local elapsed = (finish - start) / 1000000
    Tiling.PaperWM.logger.df("tileSpace(%d) elapsed time: %0.3f ms", space, elapsed)

    start = hs.timer.absoluteTime()

    local all_windows = hs.window.visibleWindows()
    print("all windows:")
    for _, win in ipairs(all_windows) do
        print(("  [%s]: %d"):format(win:title(), win:id()))
    end

    local index_table = Tiling.PaperWM.state.get().index_table
    local floating_windows = hs.fnutils.ifilter(all_windows, function(win) return index_table[win:id()] == nil end)

    print("floating windows:")
    for _, win in ipairs(floating_windows) do
        local id = win:id()
        if id ~= 0 then -- there's always one window with id: 0 and no title, what is it?
            print(("  focusing [%s]: %d"):format(win:title(), id))
            win:focus()
        end
    end

    anchor_window:focus() -- restore focus to user's window

    --  seems like this takes about 20 - 100 ms on an M3 Macbook
    finish = hs.timer.absoluteTime()
    elapsed = (finish - start) / 1000000
    print(("floating window focus elapsed time: %0.3f ms"):format(elapsed))
end

return Tiling
