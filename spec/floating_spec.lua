---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["floating"] = function() return dofile("floating.lua") end
package.preload["windows"] = function() return dofile("windows.lua") end
package.preload["state"] = function() return dofile("state.lua") end
package.preload["space"] = function() return dofile("space.lua") end
package.preload["tiling"] = function() return dofile("tiling.lua") end

describe("PaperWM.floating", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local spy = require("luassert.spy")

    local Floating = require("floating")
    local Windows = require("windows")
    local State = require("state")
    local Space = require("space")
    local Tiling = require("tiling")

    local mock_paperwm = Mocks.get_mock_paperwm({ Floating = Floating, Windows = Windows, State = State, Space = Space, Tiling = Tiling })
    local mock_window = Mocks.mock_window

    local focused_window

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Space.init(mock_paperwm)
        Tiling.init(mock_paperwm)
        hs.window.focusedWindow = function() return focused_window end
        hs.window.visibleWindows = function() return {} end
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

            mock_paperwm:tileSpace(1)

            assert.are.same(initial_frame, win:frame())
        end)
    end)

    describe("focusFloating", function()
        it("should focus all floating windows", function()
            -- Create mock windows
            local tiled_win1 = mock_window(101, "Tiled Window 1")
            tiled_win1.focus = spy.new(function() end)
            local tiled_win2 = mock_window(102, "Tiled Window 2")
            tiled_win2.focus = spy.new(function() end)
            local floating_win1 = mock_window(201, "Floating Window 1")
            floating_win1.focus = spy.new(function() end)
            local floating_win2 = mock_window(202, "Floating Window 2")
            floating_win2.focus = spy.new(function() end)

            -- Add tiled windows to the state
            local space = 1
            local window_list = State.windowList(space)
            window_list[1] = { tiled_win1, tiled_win2 }

            -- Mock visibleWindows to return all windows
            hs.window.visibleWindows = function()
                return { tiled_win1, tiled_win2, floating_win1, floating_win2 }
            end

            -- Call the function
            Floating.focusFloating()

            -- Assert that focus was called on floating windows
            assert.spy(floating_win1.focus).was.called(1)
            assert.spy(floating_win2.focus).was.called(1)

            -- Assert that focus was NOT called on tiled windows
            assert.spy(tiled_win1.focus).was.not_called()
            assert.spy(tiled_win2.focus).was.not_called()
        end)
    end)
end)
