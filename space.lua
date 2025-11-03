local Screen <const> = hs.screen
local Spaces <const> = hs.spaces
local Fnutils <const> = hs.fnutils
local Window <const> = hs.window
local Timer <const> = hs.timer

local Space = {}
Space.__index = Space

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function Space.init(paperwm)
    Space.PaperWM = paperwm
    Space.MissionControl = dofile(hs.spoons.resourcePath("mission_control.lua"))
    Space.MissionControl.PaperWM = paperwm -- Pass PaperWM reference for config access
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

    -- if window is on a managed space and is not floating, then toggling it to floating
    -- this will retile the current space before moving the window
    if Fnutils.contains(allowed_screens, old_screen) and not Space.PaperWM.floating.isFloating(focused_window) then
        Space.PaperWM.floating.toggleFloating(focused_window)
    end

    local ret, err = Space.MissionControl:moveWindowToSpace(focused_window, new_space)
    if not ret or err then
        Space.PaperWM.logger.e(err)
        return
    end

    -- if new space is managed then toggle window to not floating to tile new space
    if Fnutils.contains(allowed_screens, new_screen) then
        local do_add_window = coroutine.wrap(function()
            repeat                     -- wait until window appears on new space
                coroutine.yield(false) -- not done
            until Spaces.windowSpaces(focused_window)[1] == new_space

            -- now we can toggle it not floating, add the window, and tile new space
            Space.PaperWM.floating.toggleFloating(focused_window)
            Space.MissionControl:focusSpace(new_space, focused_window)
            return true -- done
        end)

        local start_time = Timer.secondsSinceEpoch()
        Timer.doUntil(do_add_window, function(timer)
            if Timer.secondsSinceEpoch() - start_time > 1 then timer:stop() end
        end, Window.animationDuration)
    end
end

return Space
