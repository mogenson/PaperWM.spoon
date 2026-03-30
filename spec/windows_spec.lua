---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end

describe("PaperWM.windows", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local Windows = require("windows")
    local State = require("state")
    local Tiling = require("tiling")
    local Floating = require("floating")

    local mock_paperwm = Mocks.get_mock_paperwm({ Windows = Windows, State = State, Tiling = Tiling, Floating = Floating })
    local mock_window = Mocks.mock_window

    local focused_window

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Tiling.init(mock_paperwm)
        mock_paperwm.default_width = nil
        mock_paperwm.app_widths = nil
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("addWindow", function()
        it("should add a window to the state", function()
            local win = mock_window(101, "Test Window")
            local space = Windows.addWindow(win)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, space)
            assert.are.equal(1, #state.window_list[space])
            assert.are.equal(1, #state.window_list[space][1])
            assert.are.equal(win, state.window_list[space][1][1])
            assert.is_not_nil(state.index_table[101])
            assert.are.equal(1, state.index_table[101].col)
            assert.are.equal(1, state.index_table[101].row)
            assert.is_not_nil(state.ui_watchers[101])
        end)

        it("should skip Apple windows with tabs", function()
            local win = mock_window(101, "Test Window", nil)
            win.tabCount = function() return 2 end
            win.application = function() return { bundleID = function() return "com.apple.Terminal" end } end

            local space = Windows.addWindow(win)

            local state = Windows.PaperWM.state.get()
            assert.is_nil(space)
            assert.is_nil(state.index_table[101])
            assert.is_nil(state.ui_watchers[101])
        end)

        it("should add Finder window that reports tabcount of 1", function()
            local win = mock_window(101, "Test Window", nil)
            win.tabCount = function() return 1 end
            win.application = function() return { bundleID = function() return "com.apple.finder" end } end

            local space = Windows.addWindow(win)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, space)
            assert.are.equal(1, #state.window_list[space])
            assert.are.equal(1, #state.window_list[space][1])
            assert.are.equal(win, state.window_list[space][1][1])
            assert.is_not_nil(state.index_table[101])
            assert.are.equal(1, state.index_table[101].col)
            assert.are.equal(1, state.index_table[101].row)
            assert.is_not_nil(state.ui_watchers[101])
        end)

        it("should add Safari windows with tabs", function()
            local win = mock_window(101, "Test Window", nil)
            win.tabCount = function() return 2 end
            win.application = function() return { bundleID = function() return "com.apple.Safari" end } end

            local space = Windows.addWindow(win)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, space)
            assert.are.equal(1, #state.window_list[space])
            assert.are.equal(1, #state.window_list[space][1])
            assert.are.equal(win, state.window_list[space][1][1])
            assert.is_not_nil(state.index_table[101])
            assert.are.equal(1, state.index_table[101].col)
            assert.are.equal(1, state.index_table[101].row)
            assert.is_not_nil(state.ui_watchers[101])
        end)

        it("non-Apple apps with tabs can be added", function()
            local win = mock_window(101, "Test Window", nil)
            win.tabCount = function() return 2 end
            win.application = function() return { bundleID = function() return "com.Microsoft.Word" end } end

            local space = Windows.addWindow(win)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, space)
            assert.are.equal(1, #state.window_list[space])
            assert.are.equal(1, #state.window_list[space][1])
            assert.are.equal(win, state.window_list[space][1][1])
            assert.is_not_nil(state.index_table[101])
            assert.are.equal(1, state.index_table[101].col)
            assert.are.equal(1, state.index_table[101].row)
            assert.is_not_nil(state.ui_watchers[101])
        end)

        it("should set width from app_widths by app name", function()
            mock_paperwm.app_widths = { ["Google Chrome"] = 0.5 }
            local win = mock_window(101, "Test Window")
            win.application = function()
                return {
                    name = function() return "Google Chrome" end,
                }
            end

            Windows.addWindow(win)

            assert.are.equal(492, win:frame().w)
        end)

        it("should set width from app_widths by bundleID", function()
            mock_paperwm.app_widths = { ["com.google.Chrome"] = 0.6 }
            local win = mock_window(101, "Test Window")
            win.application = function()
                return {
                    bundleID = function() return "com.google.Chrome" end,
                }
            end

            Windows.addWindow(win)

            assert.are.equal(590, win:frame().w)
        end)

        it("should set width from default_width when app_widths is not configured", function()
            mock_paperwm.default_width = 0.4
            local win = mock_window(101, "Test Window")

            Windows.addWindow(win)

            assert.are.equal(394, win:frame().w)
        end)

        it("app_widths should take precedence over default_width", function()
            mock_paperwm.default_width = 0.4
            mock_paperwm.app_widths = { ["Google Chrome"] = 0.5 }
            local win = mock_window(101, "Test Window")
            win.application = function()
                return {
                    name = function() return "Google Chrome" end,
                }
            end

            Windows.addWindow(win)

            assert.are.equal(492, win:frame().w)
        end)
    end)

    describe("addWindowsInOrder", function()
        it("should add windows from left to right", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2", { x = 200, y = 0, w = 100, h = 100 })
            Windows.addWindow(win1)
            Windows.addWindow(win2)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(win1, state.window_list[1][1][1])
            assert.are.equal(win2, state.window_list[1][2][1])
        end)
    end)

    describe("removeWindow", function()
        it("should remove a window from the state", function()
            local win = mock_window(101, "Test Window")
            Windows.addWindow(win)

            local space = Windows.removeWindow(win, true)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, space)
            assert.is_nil(state.window_list[space])
            assert.is_nil(state.index_table[101])
            assert.is_nil(state.ui_watchers[101])
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

            local state = Windows.PaperWM.state.get()
            assert.are.equal(win2, state.window_list[1][1][1])
            assert.are.equal(win1, state.window_list[1][2][1])
        end)

        it("should swap two windows vertically", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100, y2 = 100 })
            local win2 = mock_window(102, "Window 2", { x = 0, y = 108, w = 100, h = 100, y2 = 208 })
            Windows.addWindow(win1)
            -- manually add win2 to the same column
            table.insert(State.windowList(1, 1), win2)
            focused_window = win1

            Windows.swapWindows(Windows.Direction.DOWN)

            local state = Windows.PaperWM.state.get()
            assert.are.equal(win2, state.window_list[1][1][1])
            assert.are.equal(win1, state.window_list[1][1][2])
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

            local state = Windows.PaperWM.state.get()
            assert.are.equal(1, #state.window_list[1])    -- only one column left
            assert.are.equal(2, #state.window_list[1][1]) -- with two windows
            assert.are.equal(win1, state.window_list[1][1][1])
            assert.are.equal(win2, state.window_list[1][1][2])
        end)
    end)

    describe("barfWindow", function()
        it("should move the focused window to a new column on the right", function()
            local win1 = mock_window(101, "Window 1", { x = 0, y = 0, w = 100, h = 100 })
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            focused_window = win1

            Windows.barfWindow()

            local state = Windows.PaperWM.state.get()
            assert.are.equal(2, #state.window_list[1])    -- two columns
            assert.are.equal(1, #state.window_list[1][1]) -- one window in first column
            assert.are.equal(1, #state.window_list[1][2]) -- one window in second column
            assert.are.equal(win2, state.window_list[1][1][1])
            assert.are.equal(win1, state.window_list[1][2][1])
        end)
    end)

    describe("splitScreen", function()
        it("should split screen the focused window the left window", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win2

            Windows.splitScreen()

            local frame1 = win1:frame()
            local frame2 = win2:frame()
            assert.are.equal(8, frame1.x)
            assert.are.equal(484, frame1.w)
            assert.are.equal(500, frame2.x)
            assert.are.equal(492, frame2.w)
        end)
    end)

    describe("focusWindow", function()
        it("should focus the window to the right", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            local s = spy.on(win2, "focus")
            Windows.focusWindow(Windows.Direction.RIGHT)
            assert.spy(s).was.called()
        end)

        it("should focus the window to the left", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win2

            local s = spy.on(win1, "focus")
            Windows.focusWindow(Windows.Direction.LEFT)
            assert.spy(s).was.called()
        end)

        it("should focus the window below in the same column", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            focused_window = win1

            local s = spy.on(win2, "focus")
            Windows.focusWindow(Windows.Direction.DOWN)
            assert.spy(s).was.called()
        end)

        it("should focus the window above in the same column", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            focused_window = win2

            local s = spy.on(win1, "focus")
            Windows.focusWindow(Windows.Direction.UP)
            assert.spy(s).was.called()
        end)

        it("should return nil when no window is to the right (no wrap)", function()
            mock_paperwm.infinite_loop_window = false
            local win1 = mock_window(101, "Window 1")
            Windows.addWindow(win1)
            focused_window = win1

            local result = Windows.focusWindow(Windows.Direction.RIGHT)
            assert.is_nil(result)
        end)

        it("should return nil when no window is to the left (no wrap)", function()
            mock_paperwm.infinite_loop_window = false
            local win1 = mock_window(101, "Window 1")
            Windows.addWindow(win1)
            focused_window = win1

            local result = Windows.focusWindow(Windows.Direction.LEFT)
            assert.is_nil(result)
        end)

        it("should return nil when no window is below (no wrap)", function()
            mock_paperwm.infinite_loop_window = false
            local win1 = mock_window(101, "Window 1")
            Windows.addWindow(win1)
            focused_window = win1

            local result = Windows.focusWindow(Windows.Direction.DOWN)
            assert.is_nil(result)
        end)

        it("should return nil when no window is above (no wrap)", function()
            mock_paperwm.infinite_loop_window = false
            local win1 = mock_window(101, "Window 1")
            Windows.addWindow(win1)
            focused_window = win1

            local result = Windows.focusWindow(Windows.Direction.UP)
            assert.is_nil(result)
        end)

        describe("with infinite_loop_window enabled", function()
            before_each(function()
                mock_paperwm.infinite_loop_window = true
            end)

            after_each(function()
                mock_paperwm.infinite_loop_window = false
            end)

            it("should wrap RIGHT from last column to first", function()
                local win1 = mock_window(101, "Window 1")
                local win2 = mock_window(102, "Window 2")
                Windows.addWindow(win1)
                Windows.addWindow(win2)
                focused_window = win2 -- rightmost column

                local s = spy.on(win1, "focus")
                Windows.focusWindow(Windows.Direction.RIGHT)
                assert.spy(s).was.called()

                -- win2's column is moved from index 2 to index 1 (front of list)
                local state = Windows.PaperWM.state.get()
                assert.are.equal(2, #state.window_list[1])
                assert.are.equal(win2, state.window_list[1][1][1])
                assert.are.equal(win1, state.window_list[1][2][1])
            end)

            it("should wrap LEFT from first column to last", function()
                local win1 = mock_window(101, "Window 1")
                local win2 = mock_window(102, "Window 2")
                Windows.addWindow(win1)
                Windows.addWindow(win2)
                focused_window = win1 -- leftmost column

                local s = spy.on(win2, "focus")
                Windows.focusWindow(Windows.Direction.LEFT)
                assert.spy(s).was.called()

                -- win1's column is moved from index 1 to index 2 (back of list)
                local state = Windows.PaperWM.state.get()
                assert.are.equal(2, #state.window_list[1])
                assert.are.equal(win2, state.window_list[1][1][1])
                assert.are.equal(win1, state.window_list[1][2][1])
            end)

            it("should wrap DOWN from last row to first in same column", function()
                local win1 = mock_window(101, "Window 1")
                local win2 = mock_window(102, "Window 2")
                Windows.addWindow(win1)
                table.insert(State.windowList(1, 1), win2)
                focused_window = win2 -- bottom row

                local s = spy.on(win1, "focus")
                Windows.focusWindow(Windows.Direction.DOWN)
                assert.spy(s).was.called()

                -- vertical wrap only changes focus; row order is unchanged
                local state = Windows.PaperWM.state.get()
                assert.are.equal(win1, state.window_list[1][1][1])
                assert.are.equal(win2, state.window_list[1][1][2])
            end)

            it("should wrap UP from first row to last in same column", function()
                local win1 = mock_window(101, "Window 1")
                local win2 = mock_window(102, "Window 2")
                Windows.addWindow(win1)
                table.insert(State.windowList(1, 1), win2)
                focused_window = win1 -- top row

                local s = spy.on(win2, "focus")
                Windows.focusWindow(Windows.Direction.UP)
                assert.spy(s).was.called()

                -- vertical wrap only changes focus; row order is unchanged
                local state = Windows.PaperWM.state.get()
                assert.are.equal(win1, state.window_list[1][1][1])
                assert.are.equal(win2, state.window_list[1][1][2])
            end)

            it("should not wrap horizontally when only one column", function()
                local win1 = mock_window(101, "Window 1")
                Windows.addWindow(win1)
                focused_window = win1

                local result = Windows.focusWindow(Windows.Direction.RIGHT)
                assert.is_nil(result)
            end)

            it("should not wrap vertically when only one row", function()
                local win1 = mock_window(101, "Window 1")
                Windows.addWindow(win1)
                focused_window = win1

                local result = Windows.focusWindow(Windows.Direction.DOWN)
                assert.is_nil(result)
            end)
        end)
    end)

    describe("focusWindowAt", function()
        it("should focus the window at the specified index", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            local win3 = mock_window(103, "Window 3")

            -- Setup state: 2 columns. Col 1 has win1, win2. Col 2 has win3.
            Windows.addWindow(win1)
            table.insert(State.windowList(1, 1), win2)
            table.insert(State.windowList(1), { win3 })

            -- spy on focus
            local s = spy.on(win3, "focus")

            -- win1 is index 1, win2 is index 2, win3 is index 3
            Windows.focusWindowAt(3)

            assert.spy(s).was.called()
        end)

        it("should focus the first window", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")

            Windows.addWindow(win1)
            Windows.addWindow(win2)

            local s = spy.on(win1, "focus")

            Windows.focusWindowAt(1)

            assert.spy(s).was.called()
        end)
    end)

    describe("focusWindowFirst", function()
        it("should focus the leftmost window", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            Windows.addWindow(win2)

            local s = spy.on(win1, "focus")
            Windows.focusWindowFirst()
            assert.spy(s).was.called()
        end)
    end)

    describe("focusWindowLast", function()
        it("should focus the rightmost window", function()
            local win1 = mock_window(101, "Window 1")
            local win2 = mock_window(102, "Window 2")
            Windows.addWindow(win1)
            Windows.addWindow(win2)

            local s = spy.on(win2, "focus")
            Windows.focusWindowLast()
            assert.spy(s).was.called()
        end)
    end)
end)
