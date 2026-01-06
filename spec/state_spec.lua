---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["state"] = function() return dofile("state.lua") end

describe("PaperWM.state", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local State = require("state")

    local mock_paperwm = Mocks.get_mock_paperwm({ State = State })

    before_each(function()
        -- Reset state before each test
        State.init(mock_paperwm)
    end)

    describe("isTiled", function()
        it("should return true for a tiled window and false for a floating window", function()
            -- To add a window to index_table, we need to add it to window_list
            local space = 1
            local win = Mocks.mock_window(123, "Tiled Window")
            local window_list = State.windowList(space)
            window_list[1] = { win }

            assert.is_true(State.isTiled(123))
            assert.is_false(State.isTiled(456))
        end)
    end)
end)
