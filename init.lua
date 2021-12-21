--- === PaperWM ===
---
--- Tile windows horizontally. Inspired by PaperWM Gnome extension.
---
--- Download: [https://github.com/mogenson/PaperWM.spoon](https://github.com/mogenson/PaperWM.spoon)

local obj = {}
obj.__index = obj

-- Metadata
obj.name = "PaperWM"
obj.version = "0.1"
obj.author = "Michael Mogenson"
obj.homepage = "https://github.com/mogenson/PaperWM.spoon"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.default_hotkeys = {
	tile_windows = { { "ctrl", "alt", "cmd" }, "Space" },
	focus_left = { { "ctrl", "alt", "cmd" }, "h" },
	focus_right = { { "ctrl", "alt", "cmd" }, "l" },
}

obj.window_filter = hs.window.filter.defaultCurrentSpace

obj.window_gap = 8

function obj:bindHotkeys(mapping)
	local spec = {
		tile_windows = hs.fnutils.partial(self.tileWindows, self),
		focus_left = hs.fnutils.partial(self.focusLeft, self),
		focus_right = hs.fnutils.partial(self.focusRight, self),
	}
	hs.spoons.bindHotkeysToSpec(spec, mapping)
end

function obj:tileWindows()
	print("tileWindows")
	local windows = self.window_filter:getWindows()
	if #windows < 1 then
		return -- no windows to tile
	end

	-- sort windows from left to right
	table.sort(windows, function(first_window, second_window)
		return first_window:frame().x < second_window:frame().x
	end)

	--local focused_window = hs.window.focusedWindow()
	-- todo: tile windows from focused out

	-- tile windows starting at left most
	local frame = windows[1]:frame()
	local screen = windows[1]:screen()
	local x = frame.x
	local y = screen:fullFrame().h - screen:frame().h + self.window_gap
	local h = screen:frame().h - (2 * self.window_gap)
	for i = 1, #windows do
		local frame = windows[i]:frame()
		frame.x, frame.y, frame.h = x, y, h
		windows[i]:setFrame(frame)
		x = x + frame.w + self.window_gap
	end
end

function obj:focusLeft()
	local window = hs.window.focusedWindow()
	if window ~= nil then
		self.window_filter:focusWindowWest(window)
	end
end

function obj:focusRight()
	local window = hs.window.focusedWindow()
	if window ~= nil then
		self.window_filter:focusWindowEast(window)
	end
end

return obj
