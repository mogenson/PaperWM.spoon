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
end)
