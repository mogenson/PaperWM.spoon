# PaperWM.spoon

Tiled scrollable window manager for MacOS. Inspired by
[PaperWM](https://github.com/paperwm/PaperWM).

Spoon plugin for [HammerSpoon](https://www.hammerspoon.org) MacOS automation app.

# Demo

https://user-images.githubusercontent.com/900731/147793584-f937811a-20aa-4282-baf5-035e5ddc12ea.mp4

## Installation

1. Clone to Hammerspoon Spoons directory: `git clone https://github.com/mogenson/PaperWM.spoon ~/.hammerspoon/Spoons/PaperWM.spoon`.

2. Open `System Preferences` -> `Mission Control`. Uncheck "Automatically
rearrange Spaces based on most recent use" and check "Displays have separate
Spaces".

<img width="780" alt="Screen Shot 2022-01-07 at 14 10 11" src="https://user-images.githubusercontent.com/900731/148595715-1f7a3509-1289-4d10-b64d-86b84c076b43.png">

## Usage

Add the following to your `~/.hammerspoon/init.lua`:

```lua
PaperWM = hs.loadSpoon("PaperWM")
PaperWM:bindHotkeys({
    -- switch to a new focused window in tiled grid
    focus_left  = {{"ctrl", "alt", "cmd"}, "left"},
    focus_right = {{"ctrl", "alt", "cmd"}, "right"},
    focus_up    = {{"ctrl", "alt", "cmd"}, "up"},
    focus_down  = {{"ctrl", "alt", "cmd"}, "down"},

    -- move windows around in tiled grid
    swap_left  = {{"ctrl", "alt", "cmd", "shift"}, "left"},
    swap_right = {{"ctrl", "alt", "cmd", "shift"}, "right"},
    swap_up    = {{"ctrl", "alt", "cmd", "shift"}, "up"},
    swap_down  = {{"ctrl", "alt", "cmd", "shift"}, "down"},

    -- position and resize focused window
    center_window = {{"ctrl", "alt", "cmd"}, "c"},
    full_width    = {{"ctrl", "alt", "cmd"}, "f"},
    cycle_width   = {{"ctrl", "alt", "cmd"}, "r"},
    cycle_height  = {{"ctrl", "alt", "cmd", "shift"}, "r"},

    -- move focused window into / out of a column
    slurp_in = {{"ctrl", "alt", "cmd"}, "i"},
    barf_out = {{"ctrl", "alt", "cmd"}, "o"},

    -- switch to a new Mission Control space
    switch_space_1 = {{"ctrl", "alt", "cmd"}, "1"},
    switch_space_2 = {{"ctrl", "alt", "cmd"}, "2"},
    switch_space_3 = {{"ctrl", "alt", "cmd"}, "3"},
    switch_space_4 = {{"ctrl", "alt", "cmd"}, "4"},
    switch_space_5 = {{"ctrl", "alt", "cmd"}, "5"},
    switch_space_6 = {{"ctrl", "alt", "cmd"}, "6"},
    switch_space_7 = {{"ctrl", "alt", "cmd"}, "7"},
    switch_space_8 = {{"ctrl", "alt", "cmd"}, "8"},
    switch_space_9 = {{"ctrl", "alt", "cmd"}, "9"},

    -- move focused window to a new space and tile
    move_window_1 = {{"ctrl", "alt", "cmd", "shift"}, "1"},
    move_window_2 = {{"ctrl", "alt", "cmd", "shift"}, "2"},
    move_window_3 = {{"ctrl", "alt", "cmd", "shift"}, "3"},
    move_window_4 = {{"ctrl", "alt", "cmd", "shift"}, "4"},
    move_window_5 = {{"ctrl", "alt", "cmd", "shift"}, "5"},
    move_window_6 = {{"ctrl", "alt", "cmd", "shift"}, "6"},
    move_window_7 = {{"ctrl", "alt", "cmd", "shift"}, "7"},
    move_window_8 = {{"ctrl", "alt", "cmd", "shift"}, "8"},
    move_window_9 = {{"ctrl", "alt", "cmd", "shift"}, "9"}
})
PaperWM:start()
```

Feel free to customize hotkeys or use
`PaperWM:bindHotkeys(PaperWM.default_hotkeys)` for defaults.

`PaperWM:start()` will begin automatically tiling new and existing windows. `PaperWM:stop()` will
release control over windows.

Set `PaperWM.window_gap` to the number of pixels to space between windows and
the top and bottom screen edges.

Overwrite `PaperWM.window_filter` to ignore specific applications. For example:

```lua
PaperWM.window_filter = PaperWM.window_filter:setAppFilter("Finder", false)
PaperWM:start() -- restart for new window filter to take effect
```

## Limitations

MacOS does not allow a window to be moved fully off-screen. Windows that would
be tiled off-screen are placed in a margin on the left and right edge of the
screen. They are still visible and clickable.

It's difficult to detect when a window is dragged from one space or screen to
another. Use the `move_window_N` commands to move windows between spaces and
screens.

Arrange screens vertically to prevent windows from bleeding into other screens.

<img width="780" alt="Screen Shot 2022-01-07 at 14 18 27" src="https://user-images.githubusercontent.com/900731/148595785-546f9086-9add-4731-8477-233b202378f4.png">
