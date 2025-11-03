local Fnutils <const> = hs.fnutils

local Actions = {}
Actions.__index = Actions

---initialize modules with reference to PaperWM
---@param paperwm PaperWM
function Actions.init(paperwm)
    Actions.PaperWM = paperwm
end

---supported window movement actions
function Actions.actions()
    local Direction = Actions.PaperWM.windows.Direction
    return {
        stop_events = Fnutils.partial(Actions.PaperWM.stop, Actions.PaperWM),
        refresh_windows = Actions.PaperWM.windows.refreshWindows,
        dump_state = Actions.PaperWM.state.dump,
        toggle_floating = Actions.PaperWM.floating.toggleFloating,
        focus_left = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.LEFT),
        focus_right = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.RIGHT),
        focus_up = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.UP),
        focus_down = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.DOWN),
        focus_prev = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.PREVIOUS),
        focus_next = Fnutils.partial(Actions.PaperWM.windows.focusWindow, Direction.NEXT),
        swap_left = Fnutils.partial(Actions.PaperWM.windows.swapWindows, Direction.LEFT),
        swap_right = Fnutils.partial(Actions.PaperWM.windows.swapWindows, Direction.RIGHT),
        swap_up = Fnutils.partial(Actions.PaperWM.windows.swapWindows, Direction.UP),
        swap_down = Fnutils.partial(Actions.PaperWM.windows.swapWindows, Direction.DOWN),
        swap_column_left = function()
            Actions.PaperWM.logger.e("swap_column_left is deprecated, please use swap_left")
            Actions.PaperWM.windows.swapWindows(Direction.LEFT)
        end,
        swap_column_right = function()
            Actions.PaperWM.logger.e("swap_column_right is deprecated, please use swap_right")
            Actions.PaperWM.windows.swapWindows(Direction.RIGHT)
        end,
        center_window = Actions.PaperWM.windows.centerWindow,
        full_width = Actions.PaperWM.windows.toggleWindowFullWidth(),
        increase_width = Fnutils.partial(Actions.PaperWM.windows.increaseWindowSize, Direction.WIDTH, 1),
        decrease_width = Fnutils.partial(Actions.PaperWM.windows.increaseWindowSize, Direction.WIDTH, -1),
        increase_height = Fnutils.partial(Actions.PaperWM.windows.increaseWindowSize, Direction.HEIGHT, 1),
        decrease_height = Fnutils.partial(Actions.PaperWM.windows.increaseWindowSize, Direction.HEIGHT, -1),
        cycle_width = Fnutils.partial(Actions.PaperWM.windows.cycleWindowSize, Direction.WIDTH, Direction.ASCENDING),
        cycle_height = Fnutils.partial(Actions.PaperWM.windows.cycleWindowSize, Direction.HEIGHT, Direction.ASCENDING),
        reverse_cycle_width = Fnutils.partial(Actions.PaperWM.windows.cycleWindowSize, Direction.WIDTH,
            Direction.DESCENDING),
        reverse_cycle_height = Fnutils.partial(Actions.PaperWM.windows.cycleWindowSize, Direction.HEIGHT,
            Direction.DESCENDING),
        slurp_in = Actions.PaperWM.windows.slurpWindow,
        barf_out = Actions.PaperWM.windows.barfWindow,
        switch_space_l = Fnutils.partial(Actions.PaperWM.space.incrementSpace, Direction.LEFT),
        switch_space_r = Fnutils.partial(Actions.PaperWM.space.incrementSpace, Direction.RIGHT),
        switch_space_1 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 1),
        switch_space_2 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 2),
        switch_space_3 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 3),
        switch_space_4 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 4),
        switch_space_5 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 5),
        switch_space_6 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 6),
        switch_space_7 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 7),
        switch_space_8 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 8),
        switch_space_9 = Fnutils.partial(Actions.PaperWM.space.switchToSpace, 9),
        move_window_1 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 1),
        move_window_2 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 2),
        move_window_3 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 3),
        move_window_4 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 4),
        move_window_5 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 5),
        move_window_6 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 6),
        move_window_7 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 7),
        move_window_8 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 8),
        move_window_9 = Fnutils.partial(Actions.PaperWM.space.moveWindowToSpace, 9),
        focus_window_1 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 1),
        focus_window_2 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 2),
        focus_window_3 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 3),
        focus_window_4 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 4),
        focus_window_5 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 5),
        focus_window_6 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 6),
        focus_window_7 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 7),
        focus_window_8 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 8),
        focus_window_9 = Fnutils.partial(Actions.PaperWM.windows.focusWindowAt, 9),
    }
end

---bind userdefined hotkeys to PaperWM actions
---use PaperWM.default_hotkeys for suggested defaults
---@param mapping Mapping table of actions and hotkeys
function Actions.bindHotkeys(mapping)
    local spec = Actions.actions()
    hs.spoons.bindHotkeysToSpec(spec, mapping)
end

return Actions
