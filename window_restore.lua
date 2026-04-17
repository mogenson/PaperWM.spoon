local Window <const> = hs.window

local WindowRestore = {}
WindowRestore.__index = WindowRestore

---hs.settings key for persisting saved window frames
local SavedFramesKey <const> = "PaperWM_saved_frames"

---initialize module with reference to PaperWM
---@param paperwm PaperWM
function WindowRestore.init(paperwm)
    WindowRestore.PaperWM = paperwm
end

---generate a stable string key for a window across sessions
---uses bundle ID + title so the key survives Hammerspoon restarts
---@param window Window
---@return string
local function windowKey(window)
    local app = window:application()
    local bundle = (app and app:bundleID()) or "unknown"
    return bundle .. "|" .. (window:title() or "")
end

---save the frame of every window currently managed by PaperWM
---called at the beginning of start(), before tiling takes effect
function WindowRestore.saveWindowFrames()
    local paperwm = WindowRestore.PaperWM
    local windows = paperwm.window_filter:getWindows()

    local saved = {}
    for _, window in ipairs(windows) do
        local frame = window:frame()
        local screen = window:screen()
        table.insert(saved, {
            key      = windowKey(window),
            id       = window:id(),
            frame    = { x = frame.x, y = frame.y, w = frame.w, h = frame.h },
            screen_id = screen and screen:getUUID() or nil,
        })
    end

    -- persist to settings for cross-session restore
    hs.settings.set(SavedFramesKey, saved)
    -- keep in memory for same-session restore (avoids re-serialisation round-trip)
    WindowRestore._saved = saved

    paperwm.logger.d("WindowRestore: saved " .. #saved .. " window frames")
end

---restore every managed window to its frame saved by saveWindowFrames()
---called at the end of stop(), after tiling is released
function WindowRestore.restoreWindowFrames()
    local paperwm = WindowRestore.PaperWM

    -- prefer in-memory snapshot (same session); fall back to persisted data
    local saved = WindowRestore._saved or hs.settings.get(SavedFramesKey)
    if not saved or #saved == 0 then
        paperwm.logger.d("WindowRestore: no saved frames to restore")
        return
    end

    -- build lookup by window ID for same-session matching (fast, exact)
    local by_id = {}
    for _, entry in ipairs(saved) do
        if entry.id then
            by_id[entry.id] = entry
        end
    end

    -- build lookup by stable key for cross-session matching
    -- multiple entries with the same key are consumed in order
    local by_key = {}
    for _, entry in ipairs(saved) do
        if not by_key[entry.key] then
            by_key[entry.key] = {}
        end
        table.insert(by_key[entry.key], entry)
    end

    local count = 0
    local windows = paperwm.window_filter:getWindows()
    for _, window in ipairs(windows) do
        -- same-session: match by window ID (most reliable)
        local entry = by_id[window:id()]

        -- cross-session fallback: match by bundle + title
        if not entry then
            local key = windowKey(window)
            local entries = by_key[key]
            if entries and #entries > 0 then
                entry = table.remove(entries, 1)
            end
        end

        if entry then
            local f = entry.frame
            window:setFrame(hs.geometry.rect(f.x, f.y, f.w, f.h))
            count = count + 1
        end
    end

    paperwm.logger.d("WindowRestore: restored " .. count .. " window frames")

    -- discard in-memory snapshot; persisted copy remains in hs.settings
    -- so the next start() can still use it if Hammerspoon restarted
    WindowRestore._saved = nil
end

return WindowRestore
