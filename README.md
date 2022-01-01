# PaperWM.spoon

Tiled scrollable window manager for MacOS. Inspired by
[PaperWM](https://github.com/paperwm/PaperWM).

Spoon plugin for [HammerSpoon](https://www.hammerspoon.org) MacOS automation app.

# Demo

https://user-images.githubusercontent.com/900731/147793584-f937811a-20aa-4282-baf5-035e5ddc12ea.mp4

## Installation

Clone to `~/.hammerspoon/Spoons` directory so `init.lua` from this repo is
located at `~/.hammerspoon/Spoons/PaperWM.spoon/init.lua`.

## Usage

Add the following to your `~/.hammerspoon/init.lua`:

```lua
PaperWM = hs.loadSpoon("PaperWM")
PaperWM:bindHotkeys({
    focus_left = { { "ctrl", "alt", "cmd" }, "h" },
    focus_right = { { "ctrl", "alt", "cmd" }, "l" },
    focus_up = { { "ctrl", "alt", "cmd" }, "k" },
    focus_down = { { "ctrl", "alt", "cmd" }, "j" },
    swap_left = { { "ctrl", "alt", "cmd", "shift" }, "h" },
    swap_right = { { "ctrl", "alt", "cmd", "shift" }, "l" },
    swap_up = { { "ctrl", "alt", "cmd", "shift" }, "k" },
    swap_down = { { "ctrl", "alt", "cmd", "shift" }, "j" },
    center_window = { { "ctrl", "alt", "cmd" }, "u" },
    full_width = { { "ctrl", "alt", "cmd" }, "f" },
    cycle_width = { { "ctrl", "alt", "cmd" }, "r" },
    cycle_height = { { "ctrl", "alt", "cmd", "shift" }, "r" },
    slurp_in = { { "ctrl", "alt", "cmd" }, "i" },
    barf_out = { { "ctrl", "alt", "cmd" }, "o" },
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

Automatic tiling only occurs on primary screen. Multiple screens are not
currently supported.

Multiple Mission Control Spaces are supported, but the previous layout is
lost when switching back and forth between Spaces.

MacOS does not allow a window to be moved fully off-screen. Windows that would
be tiled off-screen are placed in a margin on the left and right edge of the
screen. They are still visible and clickable.
