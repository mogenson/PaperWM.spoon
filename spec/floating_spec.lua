---@diagnostic disable

package.preload["floating"] = function()
    local function mock_screen()
        return {
            getUUID = function() return "mock_screen_uuid" end,
            frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
        }
    end

    _G.hs = {
        spaces = {
            windowSpaces = function(_) return { 1 } end,
            focusedSpace = function() return 1 end,
            activeSpaces = function() return { mock_screen_uuid = 1 } end,
            spaceType = function(_) return "user" end,
            spaceDisplay = function(_) return "mock_screen_uuid" end,
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
        screen = {
            mainScreen = function()
                return {
                    getUUID = function() return "mock_screen_uuid" end,
                    frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
                }
            end,
        },
        settings = {
            set = function(_, _) end,
            get = function(_) return {} end,
        },
        logger = {
            new = function()
                return {
                    d = function(...) end,
                    e = function(...) end,
                    v = function(...) end,
                    df = function(...) end,
                }
            end
        },
        spoons = {
            resourcePath = function(file) return "./" .. file end,
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
    }
    setmetatable(hs.screen, {
        __call = function(_, uuid)
            if uuid == "mock_screen_uuid" then
                return mock_screen()
            end
            return nil
        end,
    })

    return dofile("floating.lua")
end

package.preload["windows"] = function()
    return dofile("windows.lua")
end

package.preload["state"] = function()
    return dofile("state.lua")
end

package.preload["space"] = function()
    return dofile("space.lua")
end

describe("PaperWM.floating", function()
    local Floating = require("floating")
    local Windows = require("windows")
    local State = require("state")
    local Space = require("space")

    local mock_screen = function()
        return {
            getUUID = function() return "mock_screen_uuid" end,
            frame = function() return { x = 0, y = 0, w = 1000, h = 800 } end,
        }
    end

    -- Mock Hammerspoon objects and functions
    local mock_window = function(id, title, frame)
        frame = frame or { x = 0, y = 0, w = 100, h = 100 }
        frame.x2 = frame.x + frame.w
        frame.y2 = frame.y + frame.h
        frame.center = { x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 }
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
            screen = function() return mock_screen() end,
        }
    end

    local mock_paperwm = {
        state = State,
        windows = Windows,
        space = Space,
        floating = Floating,
        events = {
            windowEventHandler = function() end,
        },
        window_filter = {
            getWindows = function() return {} end,
        },
        logger = {
            d = function(...) end,
            e = function(...) end,
            v = function(...) end,
            df = function(...) end,
        },
        tileSpace = Space.tileSpace,
        window_gap = 8
    }

    local focused_window

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Space.init(mock_paperwm)
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("toggleFloating", function()
        it("should remove a window from the window_list when floating is toggled", function()
            local win = mock_window(101, "Test Window")
            Windows.addWindow(win)

            Floating.toggleFloating(win)

            local state = State.get()
            assert.is_nil(state.window_list[1])
            assert.is_true(state.is_floating[101])
        end)
    end)

    describe("tileSpace with floating window", function()
        it("should ignore a focused floating window", function()
            local win = mock_window(101, "Test Window")
            Windows.addWindow(win)

            Floating.toggleFloating(win)

            local initial_frame = win:frame()

            Space.tileSpace(1)

            assert.are.same(initial_frame, win:frame())
        end)
    end)
end)
