---@diagnostic disable

package.preload["space"] = function()
    local function mock_screen()
        return {
            frame = function() return { x = 0, y = 0, w = 1000, h = 800, x2 = 1000, y2 = 800, center = { x = 500, y = 400 } } end,
            getUUID = function() return "mock_screen_uuid" end,
        }
    end

    _G.hs = {
        spaces = {
            windowSpaces = function(_) return { 1 } end,
            spaceType = function(_) return "user" end,
            spaceDisplay = function(_) return "mock_screen_uuid" end,
            focusedSpace = function() return 1 end,
            allSpaces = function() return { mock_screen_uuid = { 1, 2, 3 } } end,
        },
        screen = {
            find = function(_) return mock_screen() end,
            mainScreen = function() return mock_screen() end,
            allScreens = function() return { mock_screen() } end,
        },
        uielement = {
            watcher = {
                windowMoved = "windowMoved",
                windowResized = "windowResized",
            },
        },
        window = {
            animationDuration = 0.0,
            focusedWindow = function() return nil end,
        },
        geometry = {
            rect = function(x, y, w, h) return { x = x, y = y, w = w, h = h, x2 = x + w, y2 = y + h } end,
        },
        spoons = {
            resourcePath = function(file) return "./" .. file end,
        },
        fnutils = {
            partial = function(func, ...)
                local args = { ... }
                return function(...)
                    local all_args = {}
                    for i = 1, #args do all_args[i] = args[i] end
                    local arg_n = #args
                    local varargs = { ... }
                    for i = 1, #varargs do all_args[arg_n + i] = varargs[i] end
                    return func(table.unpack(all_args))
                end
            end,
        },
        logger = {
            new = function(_)
                return {
                    d = function(...) end,
                    e = function(...) end,
                    v = function(...) end,
                    df = function(...) end,
                    vf = function(...) end,
                }
            end,
        },
        eventtap = {
            event = {
                types = {
                    mouseMoved = "mouseMoved",
                    leftMouseDown = "leftMouseDown",
                    leftMouseUp = "leftMouseUp",
                    leftMouseDragged = "leftMouseDragged",
                },
                newMouseEvent = function(_, _) return { post = function() end } end,
            },
        },
        timer = {
            secondsSinceEpoch = function() return 0 end,
            doUntil = function(c, t, d) c() end,
        },
        mouse = {
            absolutePosition = function(_) end,
        },
    }

    setmetatable(hs.screen, {
        __call = function(_, uuid)
            if uuid == "mock_screen_uuid" then
                return mock_screen()
            end
            return nil
        end,
    })

    return dofile("space.lua")
end

package.preload["mission_control"] = function()
    return dofile("mission_control.lua")
end

package.preload["windows"] = function()
    return dofile("windows.lua")
end

package.preload["state"] = function()
    return dofile("state.lua")
end

describe("PaperWM.space", function()
    local Space = require("space")
    local Windows = require("windows")
    local State = require("state")

    -- Mock Hammerspoon objects and functions
    local mock_window = function(id, title, frame)
        frame = frame or { x = 0, y = 0, w = 100, h = 100 }
        frame.center = { x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 }
        frame.x2 = frame.x + frame.w
        frame.y2 = frame.y + frame.h
        return {
            id = function() return id end,
            title = function() return title end,
            frame = function() return frame end,
            application = function() return { bundleID = function() return "com.apple.Terminal" end } end,
            tabCount = function() return 0 end,
            isMaximizable = function() return true end,
            newWatcher = function()
                return {
                    start = function() end,
                    stop = function() end,
                }
            end,
            focus = function() end,
            setFrame = function(new_frame) frame = new_frame end,
            screen = function() return hs.screen.find() end,
        }
    end

    local mock_paperwm = {
        state = State,
        windows = Windows,
        logger = {
            d = function() end,
            e = function() end,
            v = function() end,
            df = function() end,
        },
        screen_margin = 0,
        window_gap = 8,
    }

    local focused_window

    before_each(function()
        -- Reset state before each test
        State.window_list = {}
        State.index_table = {}
        State.ui_watchers = {}
        State.is_floating = {}
        State.x_positions = {}
        Windows.init(mock_paperwm)
        Space.init(mock_paperwm)
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("tileSpace", function()
        it("should tile a single window to fit in the screen", function()
            local win = mock_window(101, "Test Window", { x = 0, y = 0, w = 100, h = 100 })
            Windows.addWindow(win)
            focused_window = win

            Space.tileSpace(1)

            local frame = win:frame()
            assert.are.equal(8, frame.x)
            assert.are.equal(8, frame.y)
            assert.are.equal(100, frame.w)
            assert.are.equal(800 - 2 * 8, frame.h)
        end)

        it("should tile two windows side-by-side", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            Space.tileSpace(1)

            local frame1 = win1:frame()
            assert.are.equal(8, frame1.x)
            assert.are.equal(8, frame1.y)
            assert.are.equal(100, frame1.w)
            assert.are.equal(800 - 2 * 8, frame1.h)

            local frame2 = win2:frame()
            assert.are.equal(108, frame2.x)
            assert.are.equal(8, frame2.y)
            assert.are.equal(100, frame2.w)
            assert.are.equal(800 - 8, frame2.y2) -- tileColumn sets y2
        end)
    end)
end)
