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

local move_coroutine, active_drag

---yield while moving a window; every other caller keeps blocking
---@param seconds number
local function wait(seconds)
    if coroutine.running() == move_coroutine then
        coroutine.yield(seconds)
    else
        Timer.usleep(math.floor(seconds * 1000000))
    end
end

-- macOS 27 correlates a mouse-down, drag and up into a single gesture using
-- kCGMouseEventNumber, and ignores a gesture whose events do not share it.
-- Lua cannot read the HID event counters, so start above them like other
-- remote input tools do (OpenJDK's Robot starts at 32000).
local robot_event_number_start = 32000
local mouse_event_number
---@return number|nil, string|nil error
local function nextMouseEventNumber()
    if not mouse_event_number then mouse_event_number = robot_event_number_start end
    if mouse_event_number >= 0x7fffffff then
        return nil, "mouse event number exhausted; reload Hammerspoon"
    end
    mouse_event_number = mouse_event_number + 1
    return mouse_event_number
end

---move mouse to position, without modifiers from the hotkey that started us
---@param position table
local function mouseMove(position)
    Event.newMouseEvent(EventTypes.mouseMoved, position, {}):post()
end

---post one part of a left button gesture
---@param event_type number
---@param position table
---@param number number event number shared by the whole gesture
---@param dx number|nil horizontal movement for this event
---@param dy number|nil vertical movement for this event
local function mouseButtonEvent(event_type, position, number, dx, dy)
    Event.newMouseEvent(event_type, position, {})
        :setProperty(Event.properties.mouseEventNumber, number)
        :setProperty(Event.properties.mouseEventClickState, 1)
        :setProperty(Event.properties.mouseEventDeltaX, dx or 0)
        :setProperty(Event.properties.mouseEventDeltaY, dy or 0)
        :post()
end

---abort a drag in flight without dropping on an unknown target
local function cancelMouseDrag()
    if active_drag then
        hs.eventtap.keyStroke({}, "escape", 0)
        mouseButtonEvent(EventTypes.leftMouseUp, active_drag.start, active_drag.number)
        active_drag = nil
    end
end

---drag the mouse from one position to another
---Mission Control only follows a gesture that begins with a small movement and
---continues in steps; a single jump between the two positions is ignored
---@param start_position table
---@param end_position table
---@param validate_drop function|nil called while the button is still down
---@return boolean, string|nil error
local function mouseDrag(start_position, end_position, validate_drop)
    local number, err = nextMouseEventNumber()
    if not number then return false, err end
    local vx, vy = end_position.x - start_position.x, end_position.y - start_position.y
    local distance = math.sqrt(vx * vx + vy * vy)
    if distance <= 8 then return false, "drag start and end are too close" end
    mouseMove(start_position)
    wait(0.08)
    active_drag = { start = start_position, number = number }
    mouseButtonEvent(EventTypes.leftMouseDown, start_position, number)
    wait(0.12)
    local first = { x = start_position.x + vx * 8 / distance, y = start_position.y + vy * 8 / distance }
    local previous = start_position
    local function step(position)
        mouseButtonEvent(EventTypes.leftMouseDragged, position, number,
            math.floor(position.x) - math.floor(previous.x), math.floor(position.y) - math.floor(previous.y))
        previous = position
    end
    step(first)
    wait(0.12)
    local steps = math.ceil((distance - 8) / 20)
    for i = 1, steps do
        step({ x = first.x + (end_position.x - first.x) * i / steps,
            y = first.y + (end_position.y - first.y) * i / steps })
        wait(0.02)
    end
    wait(0.4)
    if validate_drop then
        local valid, drop_err = validate_drop()
        if not valid then cancelMouseDrag(); return false, drop_err end
    end
    mouseButtonEvent(EventTypes.leftMouseUp, end_position, number)
    active_drag = nil
    return true
end

---find the Mission Control accessibility group
---macOS 26 moved Mission Control's accessibility tree from the Dock to the
---WindowManager process, where the mc.display groups hang directly off the
---application element. The Dock is left holding an empty "mc" stub.
---return userdata|nil, string|nil error
local function getMissionControlGroup()
    local manager = Application.applicationsForBundleID("com.apple.WindowManager")[1]
    if manager then
        local manager_element = Axuielement.applicationElement(manager)
        for _, element in ipairs(manager_element) do
            if element.AXIdentifier == "mc.display" then
                return manager_element
            end
        end
    end

    -- macOS 15 and earlier
    local dock_app = Application.applicationsForBundleID("com.apple.dock")[1]
    local dock_element = Axuielement.applicationElement(dock_app)
    for _, element in ipairs(dock_element) do
        if element.AXIdentifier == "mc" then
            return element
        end
    end

    return nil, "mission control is not open"
end

---wait until the Mission Control accessibility tree is available
---the tree does not exist until the opening animation finishes
---@param timeout number seconds to wait before giving up
---@return boolean
local function waitForMissionControl(timeout)
    local start = Timer.secondsSinceEpoch()
    repeat
        if getMissionControlGroup() then return true end
        wait(0.01)
    until Timer.secondsSinceEpoch() - start > timeout
    return false
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

    -- Mission Control lists displays in its own order; match the order of
    -- Screen.allScreens() so space indexes line up with Spaces.allSpaces().
    -- mc.display frames cover the whole display, so compare against fullFrame()
    -- (frame() excludes the menu bar and Dock on the primary display)
    local ordered = {}
    for _, screen in ipairs(Screen.allScreens()) do
        local frame = screen:fullFrame()
        for i, group in ipairs(display_groups) do
            local group_frame = group.AXFrame
            if group_frame and group_frame.x == frame.x and group_frame.y == frame.y then
                table.insert(ordered, table.remove(display_groups, i))
                break
            end
        end
    end
    for _, group in ipairs(display_groups) do
        -- displays Mission Control knows about but hs.screen does not
        table.insert(ordered, group)
    end

    return ordered
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
            elseif element.AXIdentifier and element.AXIdentifier:find("%.space%.%d+$") then
                -- macOS 26+: window thumbnails are direct children of mc.display,
                -- identified as "<bundle id>.space.<space id>"
                table.insert(windows, element)
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

---get a safe drop point for a desktop thumbnail
---WindowManager reports an anchor inside the thumbnail rather than a top left
---corner, so adding half of the reported size lands outside of it
---@param space userdata|nil AXButton of the target desktop
---@param window_manager boolean|nil thumbnail was read from WindowManager
---@return table|nil, string|nil error
local function getSpaceDropPoint(space, window_manager)
    if not space or not space.AXFrame then return nil, "target desktop disappeared" end
    if not window_manager then return Geometry(space.AXFrame).center end
    local point = space.AXPosition
    local bar = space.AXParent and space.AXParent.AXFrame
    if not point or not bar or bar.h <= 40 then return nil, "desktop bar is not expanded" end
    if point.x <= bar.x or point.x >= bar.x + bar.w or point.y <= bar.y or point.y >= bar.y + bar.h then
        return nil, "desktop anchor is outside its bar"
    end
    return { x = point.x, y = point.y }
end

---match a Mission Control thumbnail title against a window title
---Mission Control shortens long titles in the middle with an ellipsis, e.g.
---"a very long window...title" for "a very long window title"
---@param candidate string|nil thumbnail AXTitle
---@param title string window title
---@return boolean
local function titleMatches(candidate, title)
    if candidate == title then return true end
    local prefix, suffix = (candidate or ""):match("^(.-)…(.*)$")
    if not prefix or #prefix < 8 then return false end
    return title:sub(1, #prefix) == prefix and (suffix == "" or title:sub(-#suffix) == suffix)
end

---move the currently focused window to a space for the space ID
---the gesture runs in a coroutine so the steps can be timed without blocking
---Hammerspoon, and the result is reported once the window really moved
---@param focused_window Window
---@param space_id number
---@param callback function|nil called with (success, error) when finished
---@return boolean started, string|nil error
function MissionControl:moveWindowToSpace(focused_window, space_id, callback)
    if self.moving then return false, "another window move is in progress" end
    if not focused_window then return false, "no focused window" end
    if Spaces.spaceType(space_id) ~= "user" then return false, "target is not a normal desktop" end
    local app = focused_window:application()
    if not app then return false, "window application is no longer available" end
    local title = focused_window:title()
    if not title or #title == 0 then title = app:title() end
    if not title or #title == 0 then return false, "no title for window or application" end
    local target_screen = Screen(Spaces.spaceDisplay(space_id))
    if not target_screen then return false, "no screen for target space" end
    local bundle_id = app:bundleID()
    local title_before = title
    local paused, cursor = {}, Mouse.absolutePosition()
    local pending, timeout, completed
    self.moving = true

    local function finish(success, err)
        if completed then return end
        completed = true
        if pending then pending:stop() end
        if timeout then timeout:stop() end
        pcall(cancelMouseDrag)
        pcall(Spaces.closeMissionControl)
        for _, tap in ipairs(paused) do tap:start() end
        Mouse.absolutePosition(cursor)
        move_coroutine = nil
        self.moving = false
        if callback then callback(success, err)
        elseif not success then self.log.e(err) end
    end

    move_coroutine = coroutine.create(function()
        -- PaperWM's own mouse watchers must not consume the synthetic gesture
        local events = self.PaperWM and self.PaperWM.events
        for _, tap in pairs({ warp = _WarpMouseEventTap, paperwm = events and events.mouse_watcher }) do
            if tap:isEnabled() then paused[#paused + 1] = tap; tap:stop() end
        end
        focused_window:focus()
        wait(0.4)
        Spaces.openMissionControl()
        local full = target_screen:fullFrame()
        -- hovering the spaces bar expands it, which its geometry depends on
        mouseMove({ x = full.x + full.w / 2, y = full.y + 20 })
        if not waitForMissionControl(2) then return false, "mission control did not open" end
        wait(math.max(0.8, Spaces.MCwaitTime))

        local source_screen = focused_window:screen()
        if not source_screen then return false, "source screen disappeared" end
        local active_space = Spaces.activeSpaceOnScreen(source_screen)
        local source_active = false
        for _, space in ipairs(Spaces.windowSpaces(focused_window) or {}) do
            if space == active_space then source_active = true end
        end
        if not source_active then return false, "source space is not active" end

        -- a title can change while Mission Control animates
        local current_title = focused_window:title()
        if current_title and #current_title > 0 then title = current_title end
        local windows, err = getMissionControlWindows()
        if not windows then return false, err end
        local thumbnail, window_manager
        for _, candidate in ipairs(windows) do
            local identifier = candidate.AXIdentifier or ""
            local candidate_space = tonumber(identifier:match("%.space%.(%d+)$"))
            local modern = candidate_space ~= nil
            local same_app = not modern or (bundle_id and identifier:sub(1, #bundle_id + 7) == bundle_id .. ".space.")
            -- another space can hold a window with the same title
            if titleMatches(candidate.AXTitle, title) and same_app and (not modern or candidate_space == active_space) then
                if thumbnail then return false, "multiple windows have the same title" end
                thumbnail, window_manager = candidate, modern
            end
        end
        if not thumbnail then
            return false, string.format("couldn't find mission control window %q (was %q)", title, title_before)
        end
        local start_position = Geometry(thumbnail.AXFrame).center
        local hit = Axuielement.systemWideElement():elementAtPosition(start_position)
        local hit_space = hit and tonumber((hit.AXIdentifier or ""):match("%.space%.(%d+)$"))
        local source_frame = source_screen:fullFrame()
        -- hit testing can return an overlapping hidden thumbnail from another
        -- space; ignore only that case, any other mismatch is a real one
        local hidden_hit = window_manager and hit_space and hit_space ~= active_space
            and hit.AXRole == "AXButton" and thumbnail.AXRole == "AXButton"
            and Spaces.spaceDisplay(hit_space) == source_screen:getUUID()
            and thumbnail:pid() ~= nil and hit:pid() == thumbnail:pid()
            and start_position.x >= source_frame.x and start_position.x < source_frame.x + source_frame.w
            and start_position.y >= source_frame.y and start_position.y < source_frame.y + source_frame.h
        if hidden_hit then
            self.log.df("ignoring thumbnail from space %d while dragging in space %d", hit_space, active_space)
        elseif not hit or hit.AXTitle ~= thumbnail.AXTitle or hit.AXIdentifier ~= thumbnail.AXIdentifier then
            return false, "drag start does not hit the selected window"
        end
        local function destination()
            local spaces, space_err = getMissionControlSpaces()
            if not spaces then return nil, space_err end
            return getSpaceDropPoint(spaces[self:getSpaceIndex(space_id)], window_manager)
        end
        local end_position, point_err = destination()
        if not end_position then return false, point_err end
        local dragged, drag_err = mouseDrag(start_position, end_position, function()
            if not getMissionControlGroup() then return false, "mission control closed during drag" end
            local point, live_err = destination()
            if not point then return false, live_err end
            if math.abs(point.x - end_position.x) > 2 or math.abs(point.y - end_position.y) > 2 then
                return false, "target desktop moved during drag"
            end
            return true
        end)
        if not dragged then return false, drag_err end
        wait(0.8)
        Spaces.closeMissionControl()
        wait(0.5)
        local actual = Spaces.windowSpaces(focused_window) or {}
        for _, space in ipairs(actual) do
            if space == space_id then return true end
        end
        return false, "window did not reach the target space; actual=" .. hs.inspect(actual)
    end)

    local function resume()
        if completed then return end
        local ok, value, err = coroutine.resume(move_coroutine)
        if not ok then finish(false, tostring(value))
        elseif coroutine.status(move_coroutine) == "dead" then finish(value, err)
        else pending = Timer.doAfter(value, resume) end
    end
    timeout = Timer.doAfter(15, function() finish(false, "window move timed out") end)
    pending = Timer.doAfter(0, resume)
    return true
end

---switch to a space by pressing its Mission Control thumbnail
---hs.spaces.gotoSpace() fails on macOS 27 and Mission Control ignores synthetic
---clicks, so use the accessibility action instead
---@param space_id number
---@return boolean, string|nil error
function MissionControl:gotoSpace(space_id)
    if self.moving then return false, "a window move is in progress" end
    local space_index = self:getSpaceIndex(space_id)
    if not space_index then
        return false, "can't find space_id in spaces"
    end

    Spaces.openMissionControl()
    mouseMove({ x = 10, y = 10 })

    if not waitForMissionControl(2) then
        Spaces.closeMissionControl()
        return false, "mission control did not open"
    end
    wait(Spaces.MCwaitTime)

    local spaces, err = getMissionControlSpaces()
    if err or not spaces then
        Spaces.closeMissionControl()
        return false, "couldn't get mission control spaces: " .. tostring(err)
    end

    local space = spaces[space_index]
    if not space then
        Spaces.closeMissionControl()
        return false, "no space for space index: " .. space_index
    end

    local pressed, press_err = space:performAction("AXPress")
    if not pressed then
        Spaces.closeMissionControl()
        return false, "couldn't press space thumbnail: " .. tostring(press_err)
    end
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

    if Spaces.focusedSpace() ~= space_id then
        self:gotoSpace(space_id)
    end

    local do_window_focus = coroutine.wrap(function()
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
            until check_focus(window, 3)
        end

        return true -- done
    end)

    local start_time = Timer.secondsSinceEpoch()
    Timer.doUntil(do_window_focus, function(timer)
        if Timer.secondsSinceEpoch() - start_time > 1 then timer:stop() end
    end, Window.animationDuration)

    if MissionControl.PaperWM and MissionControl.PaperWM.center_mouse then
        Mouse.absolutePosition(screen:frame().center)
    end
end

return MissionControl
