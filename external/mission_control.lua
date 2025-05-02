--- Utilities for moving windows and focusing spaces

local MissionControl      = {}
MissionControl.__index    = MissionControl

local Application <const> = hs.application
local Axuielement <const> = hs.axuielement
local Event <const>       = hs.eventtap.event
local EventTypes <const>  = hs.eventtap.event.types
local Geometry <const>    = hs.geometry
local Mouse <const>       = hs.mouse
local Screen <const>      = hs.screen
local Spaces <const>      = hs.spaces
local Timer <const>       = hs.timer
local Window <const>      = hs.window

-- Metadata
MissionControl.name       = "MissionControl"
MissionControl.version    = "0.1"
MissionControl.author     = "Michael Mogenson"
MissionControl.homepage   = "https://github.com/mogenson/PaperWM.spoon"
MissionControl.license    = "MIT - https://opensource.org/licenses/MIT"

MissionControl.log        = hs.logger.new(MissionControl.name)

---blocking wait
---@param seconds number
local function wait(seconds)
    local start = Timer.secondsSinceEpoch()
    while Timer.secondsSinceEpoch() - start < seconds do end
end

---move mouse to position
---@param position table
local function mouseMove(position)
    Event.newMouseEvent(EventTypes.mouseMoved, position):post()
end

---left mouse button down
---@param position table
local function mouseDown(position)
    Event.newMouseEvent(EventTypes.leftMouseDown, position):post()
end

---left mouse button up
---@param position table
local function mouseUp(position)
    Event.newMouseEvent(EventTypes.leftMouseUp, position):post()
end

---click left mouse button
---@param position table
local function mouseClick(position)
    mouseDown(position)
    mouseUp(position)
end

---drag mouse while left button is down
---@param start_position table
---@param end_position table
local function mouseDrag(start_position, end_position)
    ---@diagnostic disable-next-line: undefined-global
    if _WarpMouseEventTap then _WarpMouseEventTap:stop() end
    mouseMove(start_position)
    mouseDown(start_position)
    Event.newMouseEvent(EventTypes.leftMouseDragged, end_position):post()
    mouseUp(end_position)
    ---@diagnostic disable-next-line: undefined-global
    if _WarpMouseEventTap then _WarpMouseEventTap:start() end
end

---find mission control AXGroup from Dock app
---return userdata|nil, string|nil error
local function getMissionControlGroup()
    local dock_app = Application.applicationsForBundleID("com.apple.dock")[1]
    local dock_element = Axuielement.applicationElement(dock_app)
    for _, element in ipairs(dock_element) do
        if element.AXIdentifier == "mc" then
            return element
        end
    end

    return nil, "mission control is not open"
end

---collect all of the Mission Control display AXGroup elements
---return table|nil, string|nil error
local function getDisplayGroups()
    local mc_group, err = getMissionControlGroup()
    if err or not mc_group then
        return nil, err
    end

    local display_groups = {}
    for _, element in ipairs(mc_group) do
        if element.AXIdentifier == "mc.display" then
            table.insert(display_groups, element)
        end
    end

    return display_groups
end

---collect all of the windows in Mission Control
---return table|nil, string|nil error
local function getMissionControlWindows()
    local display_groups, err = getDisplayGroups()
    if err or not display_groups then
        return nil, err
    end

    local windows = {}
    for _, group in ipairs(display_groups) do
        for _, element in ipairs(group) do
            if element.AXIdentifier == "mc.windows" then
                for _, mc_window in ipairs(element) do
                    table.insert(windows, mc_window)
                end
            end
        end
    end

    return windows
end

---collect all of the spaces in Mission Control
---return table|nil, string|nil error
local function getMissionControlSpaces()
    local display_groups, err = getDisplayGroups()
    if err or not display_groups then
        return nil, err
    end

    local spaces = {}
    for _, display_group in ipairs(display_groups) do
        for _, element in ipairs(display_group) do
            if element.AXIdentifier == "mc.spaces" then
                local mc_spaces = element
                for _, element in ipairs(mc_spaces) do
                    if element.AXIdentifier == "mc.spaces.list" then
                        local mc_spaces_list = element
                        for _, mc_space in ipairs(mc_spaces_list) do
                            table.insert(spaces, mc_space)
                        end
                    end
                end
            end
        end
    end

    return spaces
end

---calculate which index in the getMissionControlSpaces list corresponds to a
---space with a given space_id
---@param space_id number
---@return number|nil
function MissionControl:getSpaceIndex(space_id)
    local layout = Spaces.allSpaces()
    local index = 0
    for _, screen in ipairs(Screen.allScreens()) do
        local screen_uuid = screen:getUUID()
        for i, space in ipairs(layout[screen_uuid]) do
            if space == space_id then
                return index + i
            end
        end
        index = index + #layout[screen_uuid]
    end

    return nil
end

---get the Mission Control space for the provided index
---@param index number index for Mission Control space
---@return Space|nil
function MissionControl:getSpaceID(index)
    local layout = Spaces.allSpaces()
    for _, screen in ipairs(Screen.allScreens()) do
        local screen_uuid = screen:getUUID()
        local num_spaces = #layout[screen_uuid]
        if num_spaces >= index then return layout[screen_uuid][index] end
        index = index - num_spaces
    end
end

---move the currently focused window to a space for the space ID
---@param space_id number
---@return boolean, string|nil
function MissionControl:moveWindowToSpace(focused_window, space_id)
    if not focused_window then
        return false, "no focused window"
    end

    local title = focused_window:title()
    if not title or #title == 0 then
        title = focused_window:application():title()
    end
    if not title or #title == 0 then
        return false, "no title for window"
    end

    local space_index = self:getSpaceIndex(space_id)
    if not space_index then
        return false, "can't find space_id in spaces"
    end

    self.log.vf("moving window %s to space %d", title, space_index)

    -- open mission control and move mouse to expand spaces list
    Spaces.openMissionControl()
    mouseMove({ x = 10, y = 10 })

    -- get all windows in mission control
    local windows, err = getMissionControlWindows()
    if err or not windows then
        Spaces.closeMissionControl()
        return false, "couldn't get mission control windows: " .. err
    end

    -- find position of window with matching title
    local start_position
    repeat
        self.log.vf("looking for window with title: %s", title)
        for _, window in ipairs(windows) do
            local ax_title = window:attributeValue("AXTitle")
            if ax_title and ax_title:find(title, 1, true) then
                start_position = Geometry(window.AXFrame).center
            end
        end
        -- remove either the last word or the last character until we have a match
        local separater = title:find("%s+%S*$") or #title
        title = title:sub(1, separater - 1)
    until start_position or #title == 0
    if not start_position then
        Spaces.closeMissionControl()
        return false, "couldn't find mission control window"
    end

    -- get all spaces in mission control
    local spaces, err = getMissionControlSpaces()
    if err or not spaces then
        Spaces.closeMissionControl()
        return false, "couldn't get mission control spaces: " .. err
    end

    -- get space for space index
    local space = spaces[space_index]
    if not space then
        Spaces.closeMissionControl()
        return false, "no space for space index: " .. space_index
    end

    -- get position of space
    local end_position = Geometry(space.AXFrame).center
    self.log.vf("draging window from %s to %s", start_position, end_position)

    -- drag window to space then click on space to switch
    wait(hs.spaces.MCwaitTime)
    mouseDrag(start_position, end_position)
    wait(hs.spaces.MCwaitTime)
    mouseClick(end_position)

    return true
end

---attempt to make specified space the active space and keep focus on space
---@param space_id number ID for space
---@param window Window|nil a window in the space
function MissionControl:focusSpace(space_id, window)
    local screen = Screen(Spaces.spaceDisplay(space_id))
    if not screen then
        return
    end

    local do_space_focus = coroutine.wrap(function()
        if window then
            local function check_focus(win, n)
                local focused = true
                for i = 1, n do -- ensure that window focus does not change
                    focused = focused and (Window.focusedWindow() == win)
                    if not focused then return false end
                    coroutine.yield(false) -- not done
                end
                return focused
            end
            repeat
                window:focus()
                coroutine.yield(false) -- not done
            until (Spaces.focusedSpace() == space_id) and check_focus(window, 3)
        else
            local point = screen:frame()
            point.x = point.x + (point.w // 2)
            point.y = point.y - 1
            repeat
                mouseClick(point)      -- click on menubar
                coroutine.yield(false) -- not done
            until Spaces.focusedSpace() == space_id
        end

        -- move cursor to center of screen
        Mouse.absolutePosition(screen:frame().center)
        return true -- done
    end)

    local start_time = Timer.secondsSinceEpoch()
    Timer.doUntil(do_space_focus, function(timer)
        if Timer.secondsSinceEpoch() - start_time > 1 then timer:stop() end
    end, Window.animationDuration)
end

return MissionControl
