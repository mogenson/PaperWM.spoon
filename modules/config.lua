-- Configuration constants and default settings for PaperWM

local config = {}

-- Direction constants used throughout the system
-- These values encode direction information for various operations:
-- - LEFT/RIGHT: Horizontal movement (-1/+1)
-- - UP/DOWN: Vertical movement (-2/+2) 
-- - WIDTH/HEIGHT: Dimension to adjust (3/4)
-- - ASCENDING/DESCENDING: Direction of size cycling (5/6)
config.Direction = {
    LEFT = -1,
    RIGHT = 1,
    UP = -2,
    DOWN = 2,
    WIDTH = 3,
    HEIGHT = 4,
    ASCENDING = 5,
    DESCENDING = 6
}

-- Settings persistence key for floating window state
-- This allows floating window status to persist between Hammerspoon sessions
config.IsFloatingKey = 'PaperWM_is_floating'

-- Window filtering configuration
-- This determines which windows are managed by PaperWM
-- Default: visible, not fullscreen, with titlebars, standard windows only
config.window_filter = hs.window.filter.new():setOverrideFilter({
    visible = true,
    fullscreen = false,
    hasTitlebar = true,
    allowRoles = "AXStandardWindow"
})

-- Window spacing configuration
-- Defines the space between windows and screen edges
-- Can be a single number for equal gaps or a table for different gaps per side
config.window_gap = {
    top = 8,
    bottom = 8,
    left = 8,
    right = 8,
}

-- Golden ratio values for cycling window sizes
-- These ratios (approximately 1/4, 1/3, and 2/3 of screen) provide 
-- aesthetically pleasing window proportions when cycling sizes
config.window_ratios = { 0.23607, 0.38195, 0.61804 }

-- Size of margin for off-screen windows
-- macOS prevents windows from being placed completely off-screen
-- This margin ensures windows remain visible and clickable at screen edges
config.screen_margin = 1

-- Swipe gesture configuration
-- Number of fingers needed for horizontal swipe (0 to disable)
config.swipe_fingers = 0

-- Sensitivity multiplier for swipe gestures
-- Higher values make windows move further when swiping
config.swipe_gain = 1

-- Hotkey mapping configuration
-- This defines the default key combinations for all available actions
config.default_hotkeys = {
    -- System actions
    stop_events          = { { "alt", "cmd", "shift" }, "q" },
    refresh_windows      = { { "alt", "cmd", "shift" }, "r" },
    toggle_floating      = { { "alt", "cmd", "shift" }, "escape" },
    
    -- Focus navigation actions
    focus_left           = { { "alt", "cmd" }, "left" },
    focus_right          = { { "alt", "cmd" }, "right" },
    focus_up             = { { "alt", "cmd" }, "up" },
    focus_down           = { { "alt", "cmd" }, "down" },
    
    -- Window swapping actions
    swap_left            = { { "alt", "cmd", "shift" }, "left" },
    swap_right           = { { "alt", "cmd", "shift" }, "right" },
    swap_up              = { { "alt", "cmd", "shift" }, "up" },
    swap_down            = { { "alt", "cmd", "shift" }, "down" },
    
    -- Window positioning and sizing actions
    center_window        = { { "alt", "cmd" }, "c" },
    full_width           = { { "alt", "cmd" }, "f" },
    cycle_width          = { { "alt", "cmd" }, "r" },
    cycle_height         = { { "alt", "cmd", "shift" }, "r" },
    reverse_cycle_width  = { { "ctrl", "alt", "cmd" }, "r" },
    reverse_cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    
    -- Column manipulation actions
    slurp_in             = { { "alt", "cmd" }, "i" },
    barf_out             = { { "alt", "cmd" }, "o" },
    
    -- Space navigation actions
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
    
    -- Window to space movement actions
    move_window_1        = { { "alt", "cmd", "shift" }, "1" },
    move_window_2        = { { "alt", "cmd", "shift" }, "2" },
    move_window_3        = { { "alt", "cmd", "shift" }, "3" },
    move_window_4        = { { "alt", "cmd", "shift" }, "4" },
    move_window_5        = { { "alt", "cmd", "shift" }, "5" },
    move_window_6        = { { "alt", "cmd", "shift" }, "6" },
    move_window_7        = { { "alt", "cmd", "shift" }, "7" },
    move_window_8        = { { "alt", "cmd", "shift" }, "8" },
    move_window_9        = { { "alt", "cmd", "shift" }, "9" }
}

return config