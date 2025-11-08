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
end)
