---@diagnostic disable

package.preload["windows"] = function()
    _G.hs = {
        spaces = {
            windowSpaces = function(_) return { 1 } end,
            focusedSpace = function() return 1 end,
            activeSpaces = function() return { mock_screen_uuid = 1 } end,
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
        },
    }
    return dofile("windows.lua")
end

package.preload["state"] = function()
    return dofile("state.lua")
end

describe("PaperWM.windows", function()
    local Windows = require("windows")
    local State = require("state")

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
        tileSpace = function() end,
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
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("addWindow", function()
        it("should add a window to the state", function()
            local win = mock_window(101, "Test Window")
            local space = Windows.addWindow(win)

            assert.are.equal(1, space)
            assert.are.equal(1, #State.window_list[space])
            assert.are.equal(1, #State.window_list[space][1])
            assert.are.equal(win, State.window_list[space][1][1])
            assert.is_not_nil(State.index_table[101])
            assert.are.equal(1, State.index_table[101].col)
            assert.are.equal(1, State.index_table[101].row)
            assert.is_not_nil(State.ui_watchers[101])
        end)
    end)


    describe("addWindowsInOrder", function()
        it("should add windows from left to right", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)

            assert.are.equal(win1, State.window_list[1][1][1])
            assert.are.equal(win2, State.window_list[1][2][1])
        end)
    end)

    describe("removeWindow", function()
        it("should remove a window from the state", function()
            local win = mock_window(101, "Test Window")
            Windows.addWindow(win)

            local space = Windows.removeWindow(win, true)

            assert.are.equal(1, space)
            assert.is_nil(State.window_list[space])
            assert.is_nil(State.index_table[101])
            assert.is_nil(State.ui_watchers[101])
        end)
    end)

    describe("swapWindows", function()
        it("should swap two windows horizontally", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            Windows.swapWindows(Windows.Direction.RIGHT)

            assert.are.equal(win2, State.window_list[1][1][1])
            assert.are.equal(win1, State.window_list[1][2][1])
        end)

        it("should swap two windows vertically", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100, y2 = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 108, w = 100, h = 100, y2 = 208 })
            Windows.addWindow(win1)
            -- manually add win2 to the same column
            table.insert(State.window_list[1][1], win2)
            State.index_table[102] = { space = 1, col = 1, row = 2 }
            focused_window = win1

            Windows.swapWindows(Windows.Direction.DOWN)

            assert.are.equal(win2, State.window_list[1][1][1])
            assert.are.equal(win1, State.window_list[1][1][2])
        end)
    end)

    describe("slurpWindow", function()
        it("should move the focused window into the column on the left", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win2

            Windows.slurpWindow()

            assert.are.equal(1, #State.window_list[1])    -- only one column left
            assert.are.equal(2, #State.window_list[1][1]) -- with two windows
            assert.are.equal(win1, State.window_list[1][1][1])
            assert.are.equal(win2, State.window_list[1][1][2])
        end)
    end)

    describe("barfWindow", function()
        it("should move the focused window to a new column on the right", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            table.insert(State.window_list[1][1], win2)
            State.index_table[102] = { space = 1, col = 1, row = 2 }
            focused_window = win1

            Windows.barfWindow()

            assert.are.equal(2, #State.window_list[1])    -- two columns
            assert.are.equal(1, #State.window_list[1][1]) -- one window in first column
            assert.are.equal(1, #State.window_list[1][2]) -- one window in second column
            assert.are.equal(win2, State.window_list[1][1][1])
            assert.are.equal(win1, State.window_list[1][2][1])
        end)
    end)
end)
