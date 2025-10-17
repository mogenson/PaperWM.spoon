local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Fnutils <const> = hs.fnutils
local Window <const> = hs.window

local Space = {}
Space.__index = Space

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Space.init(paperwm)
    Space.PaperWM = paperwm
    Space.MissionControl = dofile(hs.spoons.resourcePath("mission_control.lua"))
end

---tile all column in a space by moving and resizing windows
---@param space Space
function Space.tileSpace(space)
    if not space or Spaces.spaceType(space) ~= "user" then
        Space.PaperWM.logger.e("current space invalid")
        return
    end

    -- find screen for space
    local screen = Screen(Spaces.spaceDisplay(space))
    if not screen then
        Space.PaperWM.logger.e("no screen for space")
        return
    end

    -- if focused window is in space, tile from that
    local focused_window = Window.focusedWindow()
    local anchor_window = (function()
        if focused_window and not Space.PaperWM.state.is_floating[focused_window:id()] and Spaces.windowSpaces(focused_window)[1] == space then
            return focused_window
        else
            return Space.PaperWM.windows.getFirstVisibleWindow(space, screen:frame())
        end
    end)()

    if not anchor_window then
        Space.PaperWM.logger.e("no anchor window in space")
        return
    end

    local anchor_index = Space.PaperWM.state.index_table[anchor_window:id()]
    if not anchor_index then
        Space.PaperWM.logger.e("anchor index not found, refreshing windows")
        Space.PaperWM.windows.refreshWindows() -- try refreshing the windows
        return                                 -- bail
    end

    -- get some global coordinates
    local screen_frame <const> = screen:frame()
    local left_margin <const> = screen_frame.x + Space.PaperWM.screen_margin
    local right_margin <const> = screen_frame.x2 - Space.PaperWM.screen_margin
    local canvas <const> = Space.PaperWM.windows.getCanvas(screen)

    -- make sure anchor window is on screen
    local anchor_frame = anchor_window:frame()
    anchor_frame.x = math.max(anchor_frame.x, canvas.x)
    anchor_frame.w = math.min(anchor_frame.w, canvas.w)
    anchor_frame.h = math.min(anchor_frame.h, canvas.h)
    if anchor_frame.x2 > canvas.x2 then
        anchor_frame.x = canvas.x2 - anchor_frame.w
    end

    -- adjust anchor window column
    local column = Space.PaperWM.windows.getColumn(space, anchor_index.col)
    if not column then
        Space.PaperWM.logger.e("no anchor window column")
        return
    end

    -- TODO: need a minimum window height
    if #column == 1 then
        anchor_frame.y, anchor_frame.h = canvas.y, canvas.h
        Space.PaperWM.windows.moveWindow(anchor_window, anchor_frame)
    else
        local n = #column - 1 -- number of other windows in column
        local bottom_gap = Space.PaperWM.windows.getGap("bottom")
        local h =
            math.max(0, canvas.h - anchor_frame.h - (n * bottom_gap)) // n
        local bounds = {
            x = anchor_frame.x,
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2,
        }
        Space.PaperWM.windows.tileColumn(column, bounds, h, anchor_frame.w, anchor_window:id(),
            anchor_frame.h)
    end
    Space.PaperWM.windows.updateVirtualPositions(space, column, anchor_frame.x)

    local right_gap = Space.PaperWM.windows.getGap("right")
    local left_gap = Space.PaperWM.windows.getGap("left")

    -- tile windows from anchor right
    local x = anchor_frame.x2 + right_gap
    for col = anchor_index.col + 1, #(Space.PaperWM.state.window_list[space] or {}) do
        local bounds = {
            x = math.min(x, right_margin),
            x2 = nil,
            y = canvas.y,
            y2 = canvas.y2,
        }
        local column = Space.PaperWM.windows.getColumn(space, col)
        local width = Space.PaperWM.windows.tileColumn(column, bounds)
        Space.PaperWM.windows.updateVirtualPositions(space, column, x)
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
        local column = Space.PaperWM.windows.getColumn(space, col)
        local width = Space.PaperWM.windows.tileColumn(column, bounds)
        Space.PaperWM.windows.updateVirtualPositions(space, column, x2 - width)
        x2 = x2 - width - left_gap
    end
end

---switch to a Mission Control space
---@param index number incremental id for space
function Space.switchToSpace(index)
    local space = Space.MissionControl:getSpaceID(index)
    if not space then
        Space.PaperWM.logger.d("space not found")
        return
    end

    local screen = Screen(Spaces.spaceDisplay(space))
    local window = Space.PaperWM.windows.getFirstVisibleWindow(space, screen:frame())
    Spaces.gotoSpace(space)
    Space.MissionControl:focusSpace(space, window)
end

---switch to a Mission Control space to the left or right of current space
---@param direction Direction use Direction.LEFT or Direction.RIGHT
function Space.incrementSpace(direction)
    if (direction ~= Space.PaperWM.windows.Direction.LEFT and direction ~= Space.PaperWM.windows.Direction.RIGHT) then
        Space.PaperWM.logger.d("move is invalid, left and right only")
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
        Space.switchToSpace(new_space_idx)
    end
end

---move focused window to a Mission Control space
---@param index number space index
function Space.moveWindowToSpace(index)
    local focused_window = Window.focusedWindow()
    if not focused_window then
        Space.PaperWM.logger.d("focused window not found")
        return
    end

    local new_space = Space.MissionControl:getSpaceID(index)
    if not new_space then
        Space.PaperWM.logger.d("space not found")
        return
    end

    if new_space == Spaces.windowSpaces(focused_window)[1] then
        Space.PaperWM.logger.d("window already on space")
        return
    end

    if Spaces.spaceType(new_space) ~= "user" then
        Space.PaperWM.logger.d("space is invalid")
        return
    end

    local old_screen = focused_window:screen()
    if not old_screen then
        Space.PaperWM.logger.d("no screen for window")
        return
    end

    local new_screen = Screen(Spaces.spaceDisplay(new_space))
    if not new_screen then
        Space.PaperWM.logger.d("no screen for space")
        return
    end

    -- get list of screens allowed by the window filter as hs.screen objects
    local allowed_screens = Space.PaperWM.window_filter:getFilters().override.allowScreens or Screen.allScreens()
    allowed_screens = Fnutils.imap(allowed_screens, function(screen) return Screen.find(screen) end)

    -- get the old space from the window list or by querying removed window
    local old_space = (function(allowed)
        if allowed then
            return Space.PaperWM.windows.removeWindow(focused_window, true) -- don't switch focus
        end
    end)(Fnutils.contains(allowed_screens, old_screen))

    local ret, err = Space.MissionControl:moveWindowToSpace(focused_window, new_space)
    if not ret or err then
        Space.PaperWM.logger.e(err)
        return
    end

    if old_space then
        Space.tileSpace(old_space)
    end

    if Fnutils.contains(allowed_screens, new_screen) then
        Space.PaperWM.windows.addWindow(focused_window)
        Space.tileSpace(new_space)
        Space.MissionControl:focusSpace(new_space, focused_window)
    end
end

return Space
