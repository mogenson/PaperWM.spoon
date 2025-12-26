---@diagnostic disable

local M = {}

function M.mock_screen()
    return {
        frame = function() return { x = 0, y = 0, w = 1000, h = 800, x2 = 1000, y2 = 800, center = { x = 500, y = 400 } } end,
        getUUID = function() return "mock_screen_uuid" end,
    }
end

function M.mock_window(id, title, frame)
    frame = frame or { x = 0, y = 0, w = 100, h = 100 }

    function set_frame(new_frame, bounds)
        bounds = bounds or new_frame
        frame.x = new_frame.x > bounds.x and new_frame.x or bounds.x
        frame.y = new_frame.y > bounds.y and new_frame.y or bounds.y
        frame.w = frame.x + new_frame.w <= bounds.x + bounds.w and new_frame.w or
            bounds.x + bounds.w - frame.x
        frame.h = frame.y + new_frame.h <= bounds.y + bounds.h and new_frame.h or
            bounds.y + bounds.h - frame.y
        frame.x2 = frame.x + frame.w
        frame.y2 = frame.y + frame.h
        frame.center = { x = frame.x + frame.w / 2, y = frame.y + frame.h / 2 }
    end

    set_frame(frame)

    return {
        id = function() return id end,
        title = function() return title end,
        frame = function() return frame end,
        application = function() return { bundleID = function() return "com.apple.Finder" end } end,
        tabCount = function() return 0 end,
        isMaximizable = function() return true end,
        newWatcher = function() return { start = function() end, stop = function() end } end,
        focus = function() end,
        setFrame = function(self, new_frame) set_frame(new_frame) end,
        setFrameInScreenBounds = function(self, new_frame, _) set_frame(new_frame, M.mock_screen().frame()) end,
        screen = function() return M.mock_screen() end,
    }
end

function M.get_mock_paperwm(modules)
    return {
        state = modules.State,
        windows = modules.Windows,
        floating = modules.Floating,
        tiling = modules.Tiling,
        space = modules.Space,
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
            vf = function(...) end,
        },
        screen_margin = 8,
        window_gap = 8,
        tileSpace = function(space) modules.Tiling.tileSpace(space) end,
    }
end

function M.init_mocks(modules)
    _G.hs = {
        spaces = {
            windowSpaces = function(_) return { 1 } end,
            spaceType = function(_) return "user" end,
            spaceDisplay = function(_) return "mock_screen_uuid" end,
            focusedSpace = function() return 1 end,
            allSpaces = function() return { mock_screen_uuid = { 1, 2, 3 } } end,
        },
        screen = {
            find = function(_) return M.mock_screen() end,
            mainScreen = function() return M.mock_screen() end,
            allScreens = function() return { M.mock_screen() } end,
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
        settings = {
            set = function(_, _) end,
            get = function(_) return {} end,
        },
    }

    setmetatable(hs.screen, {
        __call = function(_, uuid)
            if uuid == "mock_screen_uuid" then
                return M.mock_screen()
            end
            return nil
        end,
    })
end

return M
