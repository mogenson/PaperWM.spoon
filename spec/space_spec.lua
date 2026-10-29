---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end
package.preload["floating"] = function() return dofile("floating.lua") end
package.preload["windows"] = function() return dofile("windows.lua") end
package.preload["state"] = function() return dofile("state.lua") end
package.preload["space"] = function() return dofile("space.lua") end
package.preload["tiling"] = function() return dofile("tiling.lua") end

describe("PaperWM.space", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local spy = require("luassert.spy")

    local Floating = require("floating")
    local Windows = require("windows")
    local State = require("state")
    local Space = require("space")
    local Tiling = require("tiling")

    local mock_paperwm = Mocks.get_mock_paperwm({
        Floating = Floating,
        Windows = Windows,
        State = State,
        Space = Space,
        Tiling = Tiling,
    })
    local mock_window = Mocks.mock_window

    local focused_window
    local window_spaces

    before_each(function()
        mock_paperwm.preserve_app_focus = false
        mock_paperwm.move_window_keep_space = false
        mock_paperwm.window_filter.getFilters = function()
            return { override = {} }
        end

        State.init(mock_paperwm)
        Floating.init(mock_paperwm)
        Windows.init(mock_paperwm)
        Space.init(mock_paperwm)
        Tiling.init(mock_paperwm)

        local screen = Mocks.mock_screen()
        hs.screen.find = function(_) return screen end
        hs.screen.mainScreen = function() return screen end
        hs.screen.allScreens = function() return { screen } end
        setmetatable(hs.screen, {
            __call = function(_, uuid)
                if uuid == "mock_screen_uuid" then return screen end
                return nil
            end,
        })

        hs.spaces.spaceDisplay = function(_) return "mock_screen_uuid" end
        hs.mouse.getCurrentScreen = function() return screen end

        focused_window = nil
        window_spaces = {}
        hs.window.focusedWindow = function() return focused_window end
        hs.spaces.windowSpaces = function(win)
            return window_spaces[win:id()] or { 1 }
        end
    end)

    describe("switchToSpaceID", function()
        it("focuses the first visible window when preserve_app_focus is false", function()
            local win1 = mock_window(101, "Space 2 Col 1", { x = 10, y = 40, w = 400, h = 600 })
            local win2 = mock_window(102, "Space 2 Col 2", { x = 420, y = 40, w = 400, h = 600 })
            window_spaces[101] = { 2 }
            window_spaces[102] = { 2 }
            Windows.addWindow(win1)
            Windows.addWindow(win2)

            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, win1)
        end)

        it("preserves app focus via MissionControl when focused app has a window on target space", function()
            local app_win_space1 = mock_window(101, "App A Space 1")
            local other_win_space2 = mock_window(201, "App B Space 2", { x = 10, y = 40, w = 400, h = 600 })
            local app_win_space2 = mock_window(102, "App A Space 2", { x = 420, y = 40, w = 400, h = 600 })
            window_spaces[101] = { 1 }
            window_spaces[201] = { 2 }
            window_spaces[102] = { 2 }

            local app_a = {
                bundleID = function() return "com.example.AppA" end,
                visibleWindows = function() return { app_win_space1, app_win_space2 } end,
            }
            app_win_space1.application = function() return app_a end
            app_win_space2.application = function() return app_a end

            Windows.addWindow(app_win_space1)
            Windows.addWindow(other_win_space2)
            Windows.addWindow(app_win_space2)

            focused_window = app_win_space1
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, app_win_space2)
        end)

        it("switches via MissionControl without forcing first window when focused app has no window on target space", function()
            local app_win_space1 = mock_window(101, "App A Space 1")
            local other_win_space2 = mock_window(201, "App B Space 2", { x = 10, y = 40, w = 400, h = 600 })
            window_spaces[101] = { 1 }
            window_spaces[201] = { 2 }

            local app_a = {
                bundleID = function() return "com.example.AppA" end,
                visibleWindows = function() return { app_win_space1 } end,
            }
            app_win_space1.application = function() return app_a end

            Windows.addWindow(app_win_space1)
            Windows.addWindow(other_win_space2)

            focused_window = app_win_space1
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, nil)
        end)

        -- place target_space on a second display, keeping other spaces on the mock screen
        local function put_space_on_second_screen(target_space)
            local main_screen = Mocks.mock_screen()
            local second_screen = {
                id = function() return 2 end,
                frame = main_screen.frame,
                getUUID = function() return "second_screen_uuid" end,
            }
            hs.spaces.spaceDisplay = function(space)
                if space == target_space then return "second_screen_uuid" end
                return "mock_screen_uuid"
            end
            setmetatable(hs.screen, {
                __call = function(_, uuid)
                    if uuid == "mock_screen_uuid" then return main_screen end
                    if uuid == "second_screen_uuid" then return second_screen end
                    return nil
                end,
            })
            return second_screen
        end

        it("ignores non-standard and untitled windows of the focused app on target space", function()
            local app_win_space1 = mock_window(101, "App A Space 1")
            local other_win_space2 = mock_window(201, "App B Space 2", { x = 10, y = 40, w = 400, h = 600 })
            local app_panel_space2 = mock_window(102, "App A Panel")
            app_panel_space2.isStandard = function() return false end
            local app_untitled_space2 = mock_window(103, "")
            window_spaces[101] = { 1 }
            window_spaces[201] = { 2 }
            window_spaces[102] = { 2 }
            window_spaces[103] = { 2 }

            local app_a = {
                bundleID = function() return "com.example.AppA" end,
                visibleWindows = function() return { app_win_space1, app_panel_space2, app_untitled_space2 } end,
            }
            app_win_space1.application = function() return app_a end

            Windows.addWindow(app_win_space1)
            Windows.addWindow(other_win_space2)

            focused_window = app_win_space1
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, nil)
        end)

        it("focuses the first visible window when target space is on another screen and focused app has no window there", function()
            local app_win_space1 = mock_window(101, "App A Space 1")
            local win1 = mock_window(201, "Space 2 Col 1", { x = 10, y = 40, w = 400, h = 600 })
            local win2 = mock_window(202, "Space 2 Col 2", { x = 420, y = 40, w = 400, h = 600 })
            window_spaces[101] = { 1 }
            window_spaces[201] = { 2 }
            window_spaces[202] = { 2 }

            local app_a = {
                bundleID = function() return "com.example.AppA" end,
                visibleWindows = function() return { app_win_space1 } end,
            }
            app_win_space1.application = function() return app_a end

            Windows.addWindow(app_win_space1)
            Windows.addWindow(win1)
            Windows.addWindow(win2)
            put_space_on_second_screen(2)

            focused_window = app_win_space1
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, win1)
        end)

        it("prefers the focused app's window over the first visible window when target space is on another screen", function()
            local app_win_space1 = mock_window(101, "App A Space 1")
            local other_win_space2 = mock_window(201, "App B Space 2", { x = 10, y = 40, w = 400, h = 600 })
            local app_win_space2 = mock_window(102, "App A Space 2", { x = 420, y = 40, w = 400, h = 600 })
            window_spaces[101] = { 1 }
            window_spaces[201] = { 2 }
            window_spaces[102] = { 2 }

            local app_a = {
                bundleID = function() return "com.example.AppA" end,
                visibleWindows = function() return { app_win_space1, app_win_space2 } end,
            }
            app_win_space1.application = function() return app_a end
            app_win_space2.application = function() return app_a end

            Windows.addWindow(app_win_space1)
            Windows.addWindow(other_win_space2)
            Windows.addWindow(app_win_space2)
            put_space_on_second_screen(2)

            focused_window = app_win_space1
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            Space.switchToSpaceID(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, app_win_space2)
        end)

        it("uses the mouse screen when no window is focused", function()
            local win1 = mock_window(201, "Space 2 Col 1", { x = 10, y = 40, w = 400, h = 600 })
            local win2 = mock_window(202, "Space 2 Col 2", { x = 420, y = 40, w = 400, h = 600 })
            window_spaces[201] = { 2 }
            window_spaces[202] = { 2 }

            Windows.addWindow(win1)
            Windows.addWindow(win2)
            local second_screen = put_space_on_second_screen(2)

            focused_window = nil
            mock_paperwm.preserve_app_focus = true
            Space.MissionControl.focusSpace = spy.new(function() end)

            -- mouse on the main screen: target space is on another screen
            Space.switchToSpaceID(2)
            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, win1)

            -- mouse on the target screen: no window is forced
            hs.mouse.getCurrentScreen = function() return second_screen end
            Space.switchToSpaceID(2)
            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, nil)
        end)
    end)

    describe("moveWindowToSpace", function()
        it("stays on current space and does not focus moved window when move_window_keep_space is true", function()
            local win1 = mock_window(101, "Moved Window", { x = 10, y = 40, w = 400, h = 600 })
            local win2 = mock_window(102, "Remaining Window", { x = 420, y = 40, w = 400, h = 600 })
            win1.isFullScreen = function() return false end
            win2.isFullScreen = function() return false end
            window_spaces[101] = { 1 }
            window_spaces[102] = { 1 }

            Windows.addWindow(win1)
            Windows.addWindow(win2)
            focused_window = win1

            mock_paperwm.move_window_keep_space = true
            Space.MissionControl.focusSpace = spy.new(function() end)
            Space.MissionControl.moveWindowToSpace = function(_, win, target_space, callback, switch_to_space)
                assert.is_false(switch_to_space)
                -- reset focus spies after initial float before drag completes
                win1.focus = spy.new(function() end)
                win2.focus = spy.new(function() end)
                window_spaces[win:id()] = { target_space }
                callback(true)
                return true
            end

            Space.moveWindowToSpace(2)

            assert.spy(win1.focus).was_not_called()
            assert.spy(win2.focus).was.called(1)
            assert.spy(Space.MissionControl.focusSpace).was_not_called()
            assert.is_false(Floating.isFloating(win1))
            assert.are.equal(2, State.windowIndex(win1).space)
        end)

        it("switches to destination space and focuses moved window when move_window_keep_space is false", function()
            local win1 = mock_window(101, "Moved Window", { x = 10, y = 40, w = 400, h = 600 })
            win1.isFullScreen = function() return false end
            window_spaces[101] = { 1 }

            Windows.addWindow(win1)
            focused_window = win1

            mock_paperwm.move_window_keep_space = false
            Space.MissionControl.focusSpace = spy.new(function() end)
            Space.MissionControl.moveWindowToSpace = function(_, win, target_space, callback, switch_to_space)
                assert.is_true(switch_to_space)
                window_spaces[win:id()] = { target_space }
                callback(true)
                return true
            end

            Space.moveWindowToSpace(2)

            assert.spy(Space.MissionControl.focusSpace).was.called_with(Space.MissionControl, 2, win1)
            assert.is_false(Floating.isFloating(win1))
            assert.are.equal(2, State.windowIndex(win1).space)
        end)

        it("does not reopen Mission Control in focusSpace when target space is already active on another screen", function()
            local win1 = mock_window(101, "Moved Window", { x = 10, y = 40, w = 400, h = 600 })
            win1.isFullScreen = function() return false end
            window_spaces[101] = { 2 }

            -- Simulate space 1 being focused on screen 1 while space 2 is already active on screen 2
            hs.spaces.focusedSpace = function() return 1 end
            hs.spaces.activeSpaceOnScreen = function(_) return 2 end

            Space.MissionControl.gotoSpace = spy.new(function() return true end)

            Space.MissionControl:focusSpace(2, win1)

            assert.spy(Space.MissionControl.gotoSpace).was_not_called()
        end)
    end)
end)
