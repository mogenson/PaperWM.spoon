local WindowFilter <const> = hs.window.filter

local Config = {}
Config.__index = Config

---default configuration
Config.default_hotkeys = {
    stop_events          = { { "alt", "cmd", "shift" }, "q" },
    refresh_windows      = { { "alt", "cmd", "shift" }, "r" },
    dump_state           = { { "alt", "cmd", "shift" }, "d" },
    toggle_floating      = { { "alt", "cmd", "shift" }, "escape" },
    focus_floating       = { { "alt", "cmd", "shift" }, "f" },
    focus_left           = { { "alt", "cmd" }, "left" },
    focus_right          = { { "alt", "cmd" }, "right" },
    focus_up             = { { "alt", "cmd" }, "up" },
    focus_down           = { { "alt", "cmd" }, "down" },
    swap_left            = { { "alt", "cmd", "shift" }, "left" },
    swap_right           = { { "alt", "cmd", "shift" }, "right" },
    swap_up              = { { "alt", "cmd", "shift" }, "up" },
    swap_down            = { { "alt", "cmd", "shift" }, "down" },
    center_window        = { { "alt", "cmd" }, "c" },
    full_width           = { { "alt", "cmd" }, "f" },
    cycle_width          = { { "alt", "cmd" }, "r" },
    cycle_height         = { { "alt", "cmd", "shift" }, "r" },
    reverse_cycle_width  = { { "ctrl", "alt", "cmd" }, "r" },
    reverse_cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in             = { { "alt", "cmd" }, "i" },
    barf_out             = { { "alt", "cmd" }, "o" },
    switch_space_l       = { { "alt", "cmd" }, "," },
    switch_space_r       = { { "alt", "cmd" }, "." },
    switch_space_1       = { { "alt", "cmd" }, "1" },
    switch_space_2       = { { "alt", "cmd" }, "2" },
    switch_space_3       = { { "alt", "cmd" }, "3" },
    switch_space_4       = { { "alt", "cmd" }, "4" },
    switch_space_5       = { { "alt", "cmd" }, "5" },
    switch_space_6       = { { "alt", "cmd" }, "6" },
    switch_space_7       = { { "alt", "cmd" }, "7" },
    switch_space_8       = { { "alt", "cmd" }, "8" },
    switch_space_9       = { { "alt", "cmd" }, "9" },
    move_window_1        = { { "alt", "cmd", "shift" }, "1" },
    move_window_2        = { { "alt", "cmd", "shift" }, "2" },
    move_window_3        = { { "alt", "cmd", "shift" }, "3" },
    move_window_4        = { { "alt", "cmd", "shift" }, "4" },
    move_window_5        = { { "alt", "cmd", "shift" }, "5" },
    move_window_6        = { { "alt", "cmd", "shift" }, "6" },
    move_window_7        = { { "alt", "cmd", "shift" }, "7" },
    move_window_8        = { { "alt", "cmd", "shift" }, "8" },
    move_window_9        = { { "alt", "cmd", "shift" }, "9" },
}

---filter for windows to manage
Config.window_filter = WindowFilter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    hasTitlebar = true,
    allowRoles = "AXStandardWindow",
})
-- external bar: make space for external menu bar
Config.external_bar = nil ---@type {top: number, bottom: number}?

---window gaps: can be set as a single number or a table with top, bottom, left, right values
Config.window_gap = 8 ---@type number|{ top: number, bottom: number, left: number, right: number }

---ratios to use when cycling widths and heights, golden ratio by default
Config.window_ratios = { 0.23607, 0.38195, 0.61804 } ---@type number[]

---size of the on-screen margin to place off-screen windows
Config.screen_margin = 1 ---@type number

---number of fingers to detect a horizontal swipe, set to 0 to disable
Config.swipe_fingers = 0 ---@type number

---increase this number to make windows move futher when swiping
Config.swipe_gain = 1 ---@type number

-- set to a table of modifier keys to enable window dragging
Config.drag_window = nil ---@type string[]|nil e.g. { "alt", "cmd" }`

-- set to a table of modifier keys to enable window lifting
Config.lift_window = nil ---@type string[]|nil e.g. { "alt", "cmd", "shift" }

---center mouse cursor on screen after switching spaces
Config.center_mouse = true ---@type boolean

return Config
