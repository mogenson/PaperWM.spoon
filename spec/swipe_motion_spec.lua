---@diagnostic disable

describe("PaperWM swipe motion", function()
    local mock_hs, clock, windows, positions, watchers, focused, timers, errors, tiled, columns
    local Motion, controller, paperwm

    local function near(actual, expected, tolerance)
        assert(math.abs(actual - expected) < (tolerance or 0.00001), tostring(actual) .. " ~= " .. expected)
    end

    local function window(identity, position, width)
        return {
            id = function() return identity end,
            frame = function() return { x = position, x2 = position + width, y = 33, w = width, h = 1239 } end,
            setTopLeft = function(_, nextX) position = nextX end,
            focus = function() focused = windows[identity] end,
        }
    end

    local function tick(elapsed)
        clock = clock + elapsed
        local timer = timers[#timers]
        if timer and not timer.stopped then timer.callback() end
    end

    local function dragRight()
        controller:begin(7)
        for index = 1, 4 do
            clock = index * 0.02
            controller:move(7, 321 / 4 / 2048, 0)
            tick(0)
        end
        clock = clock + 0.005
    end

    before_each(function()
        clock, timers, errors, tiled = 0, {}, {}, 0
        positions, watchers = { [97] = -556, [1553] = 417 }, { [97] = true, [1553] = true }
        windows = { [97] = window(97, -556, 965), [1553] = window(1553, 417, 1623) }
        columns = { { windows[97] }, { windows[1553] } }
        focused = windows[1553]
        local screen = { frame = function() return { x = 0, x2 = 2048, w = 2048 } end }
        mock_hs = {
            timer = {
                absoluteTime = function() return clock * 1e9 end,
                doEvery = function(_, callback)
                    local timer = { callback = callback, stop = function(self) self.stopped = true end }
                    timers[#timers + 1] = timer
                    return timer
                end,
            },
            window = { get = function(identity) return windows[identity] end,
                focusedWindow = function() return focused end },
            screen = function() return screen end,
            spaces = { spaceDisplay = function() return "screen" end },
        }
        paperwm = {
            screen_margin = 1, swipe_gain = 1,
            state = {
                xPositions = function() return positions end,
                windowIndex = function(candidate)
                    for column, entries in ipairs(columns) do
                        for row, entry in ipairs(entries) do
                            if entry == candidate then return { space = 1, col = column, row = row } end
                        end
                    end
                end,
                windowList = function() return columns end,
                isStacked = function() return false end,
                uiWatcherStart = function(identity) watchers[identity] = true end,
                uiWatcherStop = function(identity) watchers[identity] = false end,
            },
            windows = {
                Direction = { LEFT = 1, RIGHT = 2 },
                getFirstVisibleWindow = function() return windows[97] end,
                getCanvas = function() return { x = 8, x2 = 2040, w = 2032 } end,
            },
            tileSpace = function() tiled = tiled + 1 end,
            logger = { e = function(message) errors[#errors + 1] = message end },
        }
        Motion = assert(loadfile("swipe_motion.lua", "t", setmetatable({ hs = mock_hs }, { __index = _G })))()
        controller = Motion.new(paperwm)
    end)

    after_each(function()
        controller:cancel("test_end")
    end)

    it("preserves the initial velocity and reaches the target at zero speed", function()
        for _, direction in ipairs({ -1, 1 }) do
            local duration, initial, curve = Motion.curve(243 * direction, 1200 * direction)
            near(curve(0), 0)
            near(curve(duration), 243 * direction)
            near(initial, 1200 * direction)
            near(curve(0.000001) / 0.000001, initial, 0.1)
            near((curve(duration) - curve(duration - 0.000001)) / 0.000001, 0, 0.1)
        end
    end)

    it("bounds duration and prevents overshoot for short, fast or reverse snaps", function()
        for _, distance in ipairs({ -243, -1, 1, 243 }) do
            for _, velocity in ipairs({ -20000, 0, 20000 }) do
                local duration, _, curve = Motion.curve(distance, velocity)
                assert(duration >= 0.12 and duration <= 0.35)
                local previous = 0
                for step = 1, 100 do
                    local position = curve(step / 100 * duration) / distance
                    assert(position >= previous - 0.000001 and position <= 1.000001)
                    previous = position
                end
            end
        end
    end)

    it("animates the recorded iTerm landing from -235 to 8 before restoring watchers", function()
        dragRight()
        near(windows[97]:frame().x, -235)
        controller:finish(7)
        assert(controller:velocity(clock) > 0)
        near(windows[97]:frame().x, -235)
        assert(not watchers[97] and not watchers[1553] and tiled == 0)
        tick(0.03)
        assert(windows[97]:frame().x > -235 and windows[97]:frame().x < 8)
        tick(0.4)
        near(windows[97]:frame().x, 8)
        near(windows[1553]:frame().x, 981)
        assert(controller.session == nil and watchers[97] and watchers[1553])
        assert(focused == windows[97] and tiled == 0)
        near(positions[97], 8)
        near(positions[1553], 981)
    end)

    it("uses zero release velocity after a pause", function()
        dragRight()
        clock = clock + 0.1
        controller:finish(7)
        local _, _, curve = Motion.curve(243, 0)
        tick(0.03)
        near(windows[97]:frame().x, math.floor(-235 + curve(0.03) + 0.5))
    end)

    it("hands an unfinished snap to the next gesture without moving windows", function()
        dragRight()
        controller:finish(7)
        tick(0.03)
        local position = windows[97]:frame().x
        local oldTimer = timers[#timers]
        controller:begin(8)
        assert(oldTimer.stopped and controller.session.id == 8)
        near(windows[97]:frame().x, position)
        oldTimer.callback()
        near(windows[97]:frame().x, position)
        clock = clock + 0.02
        controller:move(8, -10 / 2048, 0)
        tick(0)
        near(windows[97]:frame().x, position - 10, 1.01)
    end)

    it("cancels and restores watchers if an animation move fails", function()
        dragRight()
        controller:finish(7)
        windows[97].setTopLeft = function() error("window closed") end
        tick(0.03)
        assert(controller.session == nil and timers[#timers].stopped)
        assert(watchers[97] and watchers[1553] and #errors == 1)
    end)

    it("cancels when the focus leaves managed windows before release", function()
        dragRight()
        focused = window(999, 0, 500)
        controller:finish(7)
        assert(controller.session == nil and timers[#timers].stopped)
        assert(watchers[97] and watchers[1553])
    end)

    it("finishes without an animation when the focus already fits", function()
        controller:begin(7)
        controller:finish(7)
        assert(controller.session == nil and #timers == 0 and tiled == 0)
    end)

    local function setLayout(widths, focusColumn, scroll)
        columns, windows, positions, watchers = {}, {}, {}, {}
        local position = 8 - (scroll or 0)
        for identity, width in ipairs(widths) do
            windows[identity] = window(identity, position, width)
            columns[identity] = { windows[identity] }
            positions[identity], watchers[identity] = position, true
            position = position + width + 8
        end
        focused = windows[focusColumn]
    end

    it("moves only to the next window and left-aligns it even on a long swipe", function()
        setLayout({ 800, 800, 800, 800 }, 1)
        controller:begin(9)
        clock = 0.02
        controller:move(9, -2, 0)
        tick(0)
        near(windows[2]:frame().x, 8)
        assert(windows[4]:frame().x2 >= 2040)
        controller:finish(9)
        tick(0.4)
        assert(focused == windows[2])
        near(windows[2]:frame().x, 8)
    end)

    it("left-aligns the previous window on a rightward swipe", function()
        setLayout({ 800, 800, 800, 800 }, 2, 808)
        controller:begin(9)
        clock = 0.02
        controller:move(9, 0.02, 0)
        controller:finish(9)
        tick(0.4)
        assert(focused == windows[1])
        near(windows[1]:frame().x, 8)
    end)

    it("clamps at the right end instead of leaving empty space after the last window", function()
        setLayout({ 800, 800, 800, 800 }, 2, 808)
        controller:begin(9)
        clock = 0.02
        controller:move(9, -2, 0)
        tick(0)
        near(windows[4]:frame().x2, 2040)
        controller:finish(9)
        tick(0.4)
        assert(focused == windows[3])
        near(windows[4]:frame().x2, 2040)
        assert(windows[3]:frame().x > 8)
    end)

    it("does not expose empty space at either end while dragging", function()
        setLayout({ 800, 800, 800, 800 }, 1)
        controller:begin(9)
        clock = 0.02
        controller:move(9, 2, 0)
        near(windows[1]:frame().x, 8)
        controller:finish(9)
        assert(controller.session == nil)
        setLayout({ 800, 800, 800, 800 }, 4, 1192)
        controller:begin(10)
        clock = 0.04
        controller:move(10, -2, 0)
        near(windows[4]:frame().x2, 2040)
        controller:finish(10)
        assert(controller.session == nil)
    end)

    it("returns to the current window for a small accidental movement", function()
        setLayout({ 800, 800, 800, 800 }, 2, 808)
        controller:begin(9)
        clock = 0.02
        controller:move(9, -5 / 2048, 0)
        controller:finish(9)
        tick(0.4)
        assert(focused == windows[2])
        near(windows[2]:frame().x, 8)
    end)

    it("keeps short content at the left edge without allowing overscroll", function()
        setLayout({ 800 }, 1)
        controller:begin(9)
        clock = 0.02
        controller:move(9, -1, 0)
        near(windows[1]:frame().x, 8)
        controller:finish(9)
        assert(controller.session == nil)
    end)

    it("initializes from cached windows without enumerating application windows", function()
        mock_hs.window.get = function(_) error("must not enumerate windows") end
        for _, candidate in pairs(windows) do
            candidate.application = function() error("must not query application metadata") end
        end
        controller:begin(9)
        assert(#controller.session.windows == 2)
        assert(controller.session.windows[1].window == windows[97])
        assert(controller.session.windows[2].window == windows[1553])
        controller:cancel("test")
        assert(watchers[97] and watchers[1553])
    end)

    it("keeps slow window moves out of the input callback", function()
        for _, candidate in pairs(windows) do
            local original = candidate.setTopLeft
            candidate.setTopLeft = function(self, position)
                clock = clock + 0.012
                original(self, position)
            end
        end
        controller:begin(9)
        clock = clock + 0.02
        controller:move(9, 0.02, 0)
        near(clock, 0.02)
        near(windows[97]:frame().x, -556)
        tick(1 / 60)
        near(clock, 0.02 + 1 / 60 + 0.024)
        near(windows[97]:frame().x, -515)
        controller:cancel("test")
    end)

    it("reaches the target after delayed animation callbacks", function()
        dragRight()
        controller:finish(7)
        tick(0.06)
        assert(windows[97]:frame().x > -235 and windows[97]:frame().x < 8)
        tick(0.5)
        near(windows[97]:frame().x, 8)
        assert(controller.session == nil and watchers[97] and watchers[1553])
    end)

    it("combines pending touch updates into one timer-driven window move", function()
        local calls = 0
        local original = windows[97].setTopLeft
        windows[97].setTopLeft = function(self, position)
            calls = calls + 1
            original(self, position)
        end
        controller:begin(9)
        for index = 1, 3 do
            clock = index * 0.004
            controller:move(9, 10 / 2048, 0)
        end
        assert(calls == 0 and #timers == 1)
        near(positions[97], -556)
        tick(0.005)
        assert(calls == 1)
        near(windows[97]:frame().x, -526)
        near(positions[97], -526)
        tick(1 / 60)
        assert(calls == 1)
        controller:cancel("test")
    end)

    it("releases before the first render without jumping or losing the destination", function()
        controller:begin(9)
        clock = 0.005
        controller:move(9, 100 / 2048, 0)
        local dragTimer = timers[#timers]
        clock = 0.01
        controller:finish(9)
        assert(dragTimer.stopped and controller.session.phase == "snap")
        near(windows[97]:frame().x, -556)
        dragTimer.callback()
        near(windows[97]:frame().x, -556)
        tick(0.02)
        assert(windows[97]:frame().x > -556 and windows[97]:frame().x < 8)
        tick(0.4)
        near(windows[97]:frame().x, 8)
        assert(focused == windows[97] and tiled == 0)
    end)

    it("discards pending movement on cancellation and stops the drag timer", function()
        controller:begin(9)
        clock = 0.01
        controller:move(9, 100 / 2048, 0)
        local dragTimer = timers[#timers]
        controller:cancel("windowDestroyed")
        assert(dragTimer.stopped and watchers[97] and watchers[1553])
        dragTimer.callback()
        near(windows[97]:frame().x, -556)
        near(positions[97], -556)
    end)

    it("uses input timestamps and pending displacement for release velocity", function()
        clock = 1
        controller:begin(9, 0.6)
        clock = 1.01
        controller:move(9, 40 / 2048, 0, 0.62)
        clock = 1.02
        controller:move(9, 40 / 2048, 0, 0.64)
        clock = 1.03
        controller:finish(9, 0.65)
        local _, _, curve = Motion.curve(564, 1600)
        tick(0.02)
        near(windows[97]:frame().x, math.floor(-556 + curve(0.02) + 0.5))
        tick(0.4)
        near(windows[97]:frame().x, 8)
    end)

    it("preserves pending direction reversals before a render", function()
        setLayout({ 800, 800, 800, 800 }, 2, 808)
        controller:begin(9)
        clock = 0.01
        controller:move(9, -100 / 2048, 0)
        clock = 0.015
        controller:move(9, 140 / 2048, 0)
        tick(0.005)
        near(windows[2]:frame().x, 48)
        controller:finish(9)
        tick(0.4)
        assert(focused == windows[1])
        near(windows[1]:frame().x, 8)
    end)

    it("retiles when selection changes the active row of a stacked column", function()
        paperwm.state.isStacked = function(_, column) return column == 1 end
        paperwm.state.activeRow = function() return 2 end
        dragRight()
        controller:finish(7)
        tick(0.4)
        assert(focused == windows[97] and tiled == 1)
    end)

    it("keeps an already active stacked row without retiling", function()
        paperwm.state.isStacked = function() return true end
        paperwm.state.activeRow = function() return 1 end
        dragRight()
        controller:finish(7)
        tick(0.4)
        assert(focused == windows[97] and tiled == 0)
    end)
end)
