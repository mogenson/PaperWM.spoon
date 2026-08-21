---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["tiling"] = function() return dofile("tiling.lua") end
package.preload["windows"] = function() return dofile("windows.lua") end
package.preload["state"] = function() return dofile("state.lua") end
package.preload["floating"] = function() return dofile("floating.lua") end

describe("PaperWM stacking", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local Tiling = require("tiling")
    local Windows = require("windows")
    local State = require("state")
    local Floating = require("floating")

    local mock_paperwm = Mocks.get_mock_paperwm({ Tiling = Tiling, Windows = Windows, State = State, Floating = Floating })
    local mock_window = Mocks.mock_window

    local focused_window

    -- mock screen frame is y=32 h=668, window_gap 8: canvas is x=8 y=40 w=984 y2=692 h=652
    -- accordion_peek 36, 3 windows: shared height 652 - 2*36 = 580
    local canvas_y <const> = 40
    local canvas_y2 <const> = 692
    local peek <const> = 36

    ---create a column of windows in the state for space 1
    ---@return Window[] windows in the column
    local function make_column(col, ids, opts)
        local windows = {}
        for i, id in ipairs(ids) do
            windows[i] = mock_window(id, "Window " .. id, { x = (col - 1) * 400, y = 0, w = 400, h = 100 }, opts)
        end
        local columns = State.windowList(1)
        columns[col] = windows
        return windows
    end

    before_each(function()
        State.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Tiling.init(mock_paperwm)
        Mocks.raise_log = {}
        hs.window.focusedWindow = function() return focused_window end
    end)

    describe("state", function()
        it("should set and clear the stacked flag for a column", function()
            make_column(1, { 101, 102 })
            assert.is_false(State.isStacked(1, 1))
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            assert.is_true(State.isStacked(1, 1))
            State.setStacked(1, 1, false)
            assert.is_false(State.isStacked(1, 1))
            assert.is_nil(State.windowList(1, 1).active_row)
        end)

        it("should clamp the active row to the column size", function()
            make_column(1, { 101, 102 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 5)
            assert.are.equal(2, State.activeRow(1, 1))
        end)

        it("should keep the stacked flag with a column when columns swap", function()
            make_column(1, { 101, 102 })
            local right = make_column(2, { 103 })
            State.setStacked(1, 1, true)

            focused_window = right[1]
            Windows.swapWindows(Windows.Direction.LEFT)

            assert.is_false(State.isStacked(1, 1))
            assert.is_true(State.isStacked(1, 2))
        end)

        it("should remove an emptied stacked column from the space", function()
            local stack = make_column(1, { 101, 102 })
            local first, second = stack[1], stack[2] -- state owns the table, removal shifts it
            make_column(2, { 103 })
            State.setStacked(1, 1, true)

            Windows.removeWindow(first, true)
            Windows.removeWindow(second, true)

            assert.are.equal(1, #State.windowList(1))
        end)
    end)

    describe("tileSpace", function()
        it("should cascade a stacked column with the active window expanded", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            focused_window = stack[2]

            Tiling.tileSpace(1)

            local h <const> = 580
            for _, window in ipairs(stack) do
                assert.are.equal(8, window:frame().x)
                assert.are.equal(400, window:frame().w)
                assert.are.equal(h, window:frame().h)
            end
            assert.are.equal(canvas_y, stack[1]:frame().y)
            assert.are.equal(canvas_y + peek, stack[2]:frame().y)
            assert.are.equal(canvas_y + peek + h, stack[3]:frame().y)
        end)

        it("should cascade below the active window when the first row is active", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            focused_window = stack[1]

            Tiling.tileSpace(1)

            local h <const> = 580
            assert.are.equal(canvas_y, stack[1]:frame().y)
            assert.are.equal(canvas_y + h, stack[2]:frame().y)
            assert.are.equal(canvas_y + h + peek, stack[3]:frame().y)
            assert.are.equal(canvas_y2, stack[3]:frame().y + peek) -- last strip ends at canvas bottom
        end)

        it("should raise the active window last", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            focused_window = stack[2]

            Tiling.tileSpace(1)

            assert.are.equal(102, Mocks.raise_log[#Mocks.raise_log])
        end)

        it("should not raise stack windows when the stack is unchanged", function()
            local stack = make_column(1, { 101, 102 })
            local right = make_column(2, { 103 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            focused_window = stack[2]
            Tiling.tileSpace(1)

            -- focus moves outside the stack, layout of the stack is unchanged:
            -- raising again would steal focus back into a same-app stack window
            Mocks.raise_log = {}
            focused_window = right[1]
            Tiling.tileSpace(1)

            assert.are.same({}, Mocks.raise_log)
        end)

        it("should keep the stored active row when retiling without a focused window", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            focused_window = nil -- fallback anchor picks row 1, must not clobber active row

            Tiling.tileSpace(1)

            assert.are.equal(2, State.activeRow(1, 1))
            assert.are.equal(canvas_y + peek, stack[2]:frame().y)
        end)

        it("should not raise repeatedly when an app clamps its window height", function()
            local stack = make_column(1, { 101, 102 }, { min_height = 700 })
            State.setStacked(1, 1, true)
            focused_window = stack[2]
            Tiling.tileSpace(1)

            -- actual frames never match the requested ones, but the stack
            -- composition is unchanged: raising again would loop forever
            Mocks.raise_log = {}
            Tiling.tileSpace(1)

            assert.are.same({}, Mocks.raise_log)
        end)

        it("should floor the shared height at stack_min_height for deep stacks", function()
            local ids = {}
            for i = 1, 20 do ids[i] = 100 + i end
            local stack = make_column(1, ids)
            State.setStacked(1, 1, true)
            focused_window = stack[1]

            Tiling.tileSpace(1)

            assert.are.equal(150, stack[1]:frame().h)
        end)

        it("should raise again when the active row changes", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            focused_window = stack[2]
            Tiling.tileSpace(1)

            Mocks.raise_log = {}
            focused_window = stack[1]
            Tiling.tileSpace(1)

            assert.are.equal(101, Mocks.raise_log[#Mocks.raise_log])
        end)

        it("should use the stored active row for a stacked column that is not the anchor", function()
            local stack = make_column(1, { 101, 102 })
            local right = make_column(2, { 103 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            focused_window = right[1]

            Tiling.tileSpace(1)

            local h <const> = 652 - peek
            assert.are.equal(canvas_y, stack[1]:frame().y)
            assert.are.equal(canvas_y + peek, stack[2]:frame().y)
            assert.are.equal(h, stack[2]:frame().h)
        end)
    end)

    describe("toggleStack", function()
        it("should stack the focused column and expand the focused window", function()
            local column = make_column(1, { 101, 102 })
            focused_window = column[2]

            Windows.toggleStack()

            assert.is_true(State.isStacked(1, 1))
            assert.are.equal(2, State.activeRow(1, 1))
            assert.are.equal(canvas_y, column[1]:frame().y)
            assert.are.equal(canvas_y + peek, column[2]:frame().y)
        end)

        it("should unstack back to equal heights", function()
            local column = make_column(1, { 101, 102 })
            focused_window = column[2]

            Windows.toggleStack()
            Windows.toggleStack()

            assert.is_false(State.isStacked(1, 1))
            local equal_h <const> = (652 - 8) // 2
            assert.are.equal(equal_h, column[1]:frame().h)
            assert.are.equal(equal_h, column[2]:frame().h)
        end)
    end)

    describe("slurpWindow", function()
        it("should append to a stacked column and make the slurped window active", function()
            make_column(1, { 101, 102 })
            local right = make_column(2, { 103 })
            State.setStacked(1, 1, true)
            focused_window = right[1]

            Windows.slurpWindow()

            local column = State.windowList(1, 1)
            assert.are.equal(3, #column)
            assert.is_true(State.isStacked(1, 1))
            assert.are.equal(3, State.activeRow(1, 1))
            assert.are.equal(580, column[1]:frame().h) -- accordion, not equal split
        end)
    end)

    describe("barfWindow", function()
        it("should keep the same window expanded when a row above is barfed out", function()
            local stack = make_column(1, { 101, 102, 103 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            focused_window = stack[1]

            Windows.barfWindow()

            -- window 102 shifted from row 2 to row 1 and should stay expanded
            assert.are.equal(1, State.activeRow(1, 1))
            assert.are.equal(102, State.windowList(1, 1, 1):id())
        end)
    end)

    describe("slurpWindow", function()
        it("should keep the window above expanded when slurping out of a stacked column", function()
            make_column(1, { 101 })
            local stack = make_column(2, { 102, 103, 104 })
            State.setStacked(1, 2, true)
            State.setActiveRow(1, 2, 2)
            focused_window = stack[2]

            Windows.slurpWindow()

            assert.are.equal(2, #State.windowList(1, 2))
            assert.are.equal(1, State.activeRow(1, 2))
            assert.are.equal(102, State.windowList(1, 2, 1):id())
        end)
    end)

    describe("focusWindow", function()
        it("should land on the active window when moving into a stacked column", function()
            local stack = make_column(1, { 101, 102, 103 })
            local right = make_column(2, { 104 })
            State.setStacked(1, 1, true)
            State.setActiveRow(1, 1, 2)
            focused_window = right[1]

            local landed = Windows.focusWindow(Windows.Direction.LEFT)

            assert.are.equal(stack[2]:id(), landed:id())
        end)

        it("should land on the active window when wrapping left to a stacked column with infinite_loop_window", function()
            local stack = make_column(2, { 101, 102, 103 })
            local left = make_column(1, { 104 })
            State.setStacked(1, 2, true)
            State.setActiveRow(1, 2, 3)
            focused_window = left[1]
            mock_paperwm.infinite_loop_window = true

            local landed = Windows.focusWindow(Windows.Direction.LEFT)

            assert.are.equal(stack[3]:id(), landed:id())
            mock_paperwm.infinite_loop_window = false
        end)
    end)
end)
