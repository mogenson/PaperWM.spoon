# PaperWM.spoon

Tiled scrollable window manager for MacOS. Inspired by
[PaperWM](https://github.com/paperwm/PaperWM).

Spoon plugin for [HammerSpoon](https://www.hammerspoon.org) MacOS automation app.

# Demo

https://user-images.githubusercontent.com/900731/147793584-f937811a-20aa-4282-baf5-035e5ddc12ea.mp4

## Installation

1. Clone to Hammerspoon Spoons directory: `git clone https://github.com/mogenson/PaperWM.spoon ~/.hammerspoon/Spoons/PaperWM.spoon`.

2. Open `System Preferences` -> `Desktop and Dock`. Scroll to the bottom to "Mission
Control", then uncheck "Automatically rearrange Spaces based on most recent use" and
check "Displays have separate Spaces".

<img width="780" alt="Screenshot of macOS settings" src="https://github.com/user-attachments/assets/b0842c44-2a3b-43fc-85eb-66729cd7f8db">

### Install with [SpoonInstall](https://www.hammerspoon.org/Spoons/SpoonInstall.html)

```lua
hs.loadSpoon("SpoonInstall")

spoon.SpoonInstall.repos.PaperWM = {
    url = "https://github.com/mogenson/PaperWM.spoon",
    desc = "PaperWM.spoon repository",
    branch = "release",
}

spoon.SpoonInstall:andUse("PaperWM", {
    repo = "PaperWM",
    config = { screen_margin = 16, window_gap = 2 },
    start = true,
    hotkeys = {
		< see below >
    }
})
```

## Usage

Add the following to your `~/.hammerspoon/init.lua`:

```lua
PaperWM = hs.loadSpoon("PaperWM")
PaperWM:bindHotkeys({
    -- switch to a new focused window in tiled grid
    focus_left  = {{"alt", "cmd"}, "left"},
    focus_right = {{"alt", "cmd"}, "right"},
    focus_up    = {{"alt", "cmd"}, "up"},
    focus_down  = {{"alt", "cmd"}, "down"},

    -- switch windows by cycling forward/backward
    -- (forward = down or right, backward = up or left)
    focus_prev = {{"alt", "cmd"}, "k"},
    focus_next = {{"alt", "cmd"}, "j"},

    -- move windows around in tiled grid
    swap_left  = {{"alt", "cmd", "shift"}, "left"},
    swap_right = {{"alt", "cmd", "shift"}, "right"},
    swap_up    = {{"alt", "cmd", "shift"}, "up"},
    swap_down  = {{"alt", "cmd", "shift"}, "down"},

    -- alternative: swap entire columns, rather than
    -- individual windows (to be used instead of
    -- swap_left / swap_right bindings)
    -- swap_column_left = {{"alt", "cmd", "shift"}, "left"},
    -- swap_column_right = {{"alt", "cmd", "shift"}, "right"},

    -- position and resize focused window
    center_window        = {{"alt", "cmd"}, "c"},
    full_width           = {{"alt", "cmd"}, "f"},
    cycle_width          = {{"alt", "cmd"}, "r"},
    reverse_cycle_width  = {{"ctrl", "alt", "cmd"}, "r"},
    cycle_height         = {{"alt", "cmd", "shift"}, "r"},
    reverse_cycle_height = {{"ctrl", "alt", "cmd", "shift"}, "r"},

    -- increase/decrease width
    increase_width = {{"alt", "cmd"}, "l"},
    decrease_width = {{"alt", "cmd"}, "h"},

    -- move focused window into / out of a column
    slurp_in = {{"alt", "cmd"}, "i"},
    barf_out = {{"alt", "cmd"}, "o"},

    -- move the focused window into / out of the tiling layer
    toggle_floating = {{"alt", "cmd", "shift"}, "escape"},

    -- focus the first / second / etc window in the current space
    focus_window_1 = {{"cmd", "shift"}, "1"},
    focus_window_2 = {{"cmd", "shift"}, "2"},
    focus_window_3 = {{"cmd", "shift"}, "3"},
    focus_window_4 = {{"cmd", "shift"}, "4"},
    focus_window_5 = {{"cmd", "shift"}, "5"},
    focus_window_6 = {{"cmd", "shift"}, "6"},
    focus_window_7 = {{"cmd", "shift"}, "7"},
    focus_window_8 = {{"cmd", "shift"}, "8"},
    focus_window_9 = {{"cmd", "shift"}, "9"},

    -- switch to a new Mission Control space
    switch_space_l = {{"alt", "cmd"}, ","},
    switch_space_r = {{"alt", "cmd"}, "."},
    switch_space_1 = {{"alt", "cmd"}, "1"},
    switch_space_2 = {{"alt", "cmd"}, "2"},
    switch_space_3 = {{"alt", "cmd"}, "3"},
    switch_space_4 = {{"alt", "cmd"}, "4"},
    switch_space_5 = {{"alt", "cmd"}, "5"},
    switch_space_6 = {{"alt", "cmd"}, "6"},
    switch_space_7 = {{"alt", "cmd"}, "7"},
    switch_space_8 = {{"alt", "cmd"}, "8"},
    switch_space_9 = {{"alt", "cmd"}, "9"},

    -- move focused window to a new space and tile
    move_window_1 = {{"alt", "cmd", "shift"}, "1"},
    move_window_2 = {{"alt", "cmd", "shift"}, "2"},
    move_window_3 = {{"alt", "cmd", "shift"}, "3"},
    move_window_4 = {{"alt", "cmd", "shift"}, "4"},
    move_window_5 = {{"alt", "cmd", "shift"}, "5"},
    move_window_6 = {{"alt", "cmd", "shift"}, "6"},
    move_window_7 = {{"alt", "cmd", "shift"}, "7"},
    move_window_8 = {{"alt", "cmd", "shift"}, "8"},
    move_window_9 = {{"alt", "cmd", "shift"}, "9"}
})
PaperWM:start()
```

Feel free to customize hotkeys or use
`PaperWM:bindHotkeys(PaperWM.default_hotkeys)` for defaults. PaperWM actions are also
available for manual keybinding via the `PaperWM.actions` table; for example, the
following would enable navigation by either arrow keys or vim-style h/j/k/l directions:

```lua
PaperWM = hs.loadSpoon("PaperWM")
PaperWM:bindHotkeys(PaperWM.default_hotkeys)

hs.hotkey.bind({"ctrl", "alt", "cmd"}, "h", PaperWM.actions.focus_left)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "j", PaperWM.actions.focus_down)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "k", PaperWM.actions.focus_up)
hs.hotkey.bind({"ctrl", "alt", "cmd"}, "l", PaperWM.actions.focus_right)

hs.hotkey.bind({"ctrl", "alt", "cmd", "shift"}, "h", PaperWM.actions.swap_left)
hs.hotkey.bind({"ctrl", "alt", "cmd", "shift"}, "j", PaperWM.actions.swap_down)
hs.hotkey.bind({"ctrl", "alt", "cmd", "shift"}, "k", PaperWM.actions.swap_up)
hs.hotkey.bind({"ctrl", "alt", "cmd", "shift"}, "l", PaperWM.actions.swap_right)
```

`PaperWM:start()` will begin automatically tiling new and existing windows. `PaperWM:stop()` will
release control over windows.

Set `PaperWM.window_gap` to the number of pixels between windows and screen edges.
This can be a single number for all sides, or a table specifying
`top`, `bottom`, `left`, and `right` gaps individually.

For example:
```lua
PaperWM.window_gap = 10  -- 10px gap on all sides
-- or
PaperWM.window_gap  =  { top = 10, bottom = 8, left = 12, right = 12 } -- Specific gaps per side
```

Configure the `PaperWM.window_filter` to set which apps and screens are managed. For example:

```lua
PaperWM.window_filter:rejectApp("iStat Menus Status") -- ignore a specific app
PaperWM.window_filter:setScreens({"Built%-in Retina Display"}) -- list of screens to tile (escape string match characters)
PaperWM:start() -- restart for new window filter to take effect
```

Set `PaperWM.window_ratios` to the ratios to cycle window widths and heights
through. For example:

```lua
PaperWM.window_ratios = { 0.23607, 0.38195, 0.61804 }
```

### Smooth Scrolling

https://github.com/user-attachments/assets/6f1c4659-0ca8-4ba1-a181-8c1c6987e8ef

PaperWM.spoon can scroll windows left or right by swiping fingers horizontally across the trackpad. Set the number of fingers (eg. 2, 3, or 4) and, optionally, a gain to adjust the sensitivity:

```lua
-- number of fingers to detect a horizontal swipe, set to 0 to disable (the default)
PaperWM.swipe_fingers = 0

-- increase this number to make windows move farther when swiping
PaperWM.swipe_gain = 1.0
```

Inspired by [ScrollDesktop.spoon](https://github.com/jocap/ScrollDesktop.spoon)

## Limitations

MacOS does not allow a window to be moved fully off-screen. Windows that would
be tiled off-screen are placed in a margin on the left and right edge of the
screen. They are still visible and clickable.

It's difficult to detect when a window is dragged from one space or screen to
another. Use the `move_window_N` commands to move windows between spaces and
screens.

Arrange screens vertically to prevent windows from bleeding into other screens. Use [WarpMouse.spoon](https://github.com/mogenson/WarpMouse.spoon) to simulate side-by-side screens.

<img width="780" alt="Screen Shot 2022-01-07 at 14 18 27" src="https://user-images.githubusercontent.com/900731/148595785-546f9086-9add-4731-8477-233b202378f4.png">

## Add-ons

The following spoons compliment PaperWM.spoon nicely.

- [ActiveSpace.spoon](https://github.com/mogenson/ActiveSpace.spoon) Show active and layout of Mission Control spaces in the menu bar.
- [WarpMouse.spoon](https://github.com/mogenson/WarpMouse.spoon) Move mouse cursor between screen edges to simulate side-by-side screens.
- [Swipe.spoon](https://github.com/mogenson/Swipe.spoon) Perform actions when trackpad swipe gestures are recognized. Here's an example config to change PaperWM.spoon focused window:
```lua
-- focus adjacent window with 3 finger swipe
local current_id, threshold
Swipe = hs.loadSpoon("Swipe")
Swipe:start(3, function(direction, distance, id)
    if id == current_id then
        if distance > threshold then
            threshold = math.huge -- trigger once per swipe

            -- use "natural" scrolling
            if direction == "left" then
                PaperWM.actions.focus_right()
            elseif direction == "right" then
                PaperWM.actions.focus_left()
            elseif direction == "up" then
                PaperWM.actions.focus_down()
            elseif direction == "down" then
                PaperWM.actions.focus_up()
            end
        end
    else
        current_id = id
        threshold = 0.2 -- swipe distance > 20% of trackpad size
    end
end)
```

## Contributing

Contributions are welcome! Here are a few preferences:
- Global variables are `CamelCase` (eg. `PaperWM`)
- Local variables are `snake_case` (eg. `local focused_window`)
- Function names are `lowerCamelCase` (eg. `function windowEventHandler()`)
- Use `<const>` where possible
- Create a local copy when deeply nested members are used often (eg. `local Watcher <const> = hs.uielement.watcher`)

Code format checking and linting is provided by [lua-language-server](https://github.com/LuaLS/lua-language-server) for commits and pull requests. Run `lua-language-server --check=init.lua` locally before commiting.
