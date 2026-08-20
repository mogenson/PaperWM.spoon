---@diagnostic disable

package.preload["mocks"] = function() return dofile("spec/mocks.lua") end

describe("PaperWM.window_restore", function()
    local Mocks = require("mocks")
    Mocks.init_mocks()

    local spy = require("luassert.spy")

    local WindowRestore = dofile("window_restore.lua")
    local mock_window = Mocks.mock_window

    local settings_store
    local mock_paperwm

    before_each(function()
        -- stateful settings mock so get() returns what set() stored
        settings_store = {}
        hs.settings.set = function(key, value) settings_store[key] = value end
        hs.settings.get = function(key) return settings_store[key] end

        -- reset module's in-memory snapshot
        WindowRestore._saved = nil

        mock_paperwm = {
            window_filter = { getWindows = function() return {} end },
            logger = { d = function() end, e = function() end },
        }
        WindowRestore.init(mock_paperwm)
    end)

    -- -------------------------------------------------------------------------
    describe("saveWindowFrames", function()
        it("saves nothing when there are no managed windows", function()
            WindowRestore.saveWindowFrames()
            assert.are.equal(0, #settings_store["PaperWM_saved_frames"])
        end)

        it("saves one entry per managed window", function()
            local win1 = mock_window(101, "Window 1", { x = 10, y = 20, w = 300, h = 200 })
            local win2 = mock_window(102, "Window 2", { x = 50, y = 60, w = 400, h = 300 })
            mock_paperwm.window_filter.getWindows = function() return { win1, win2 } end

            WindowRestore.saveWindowFrames()

            assert.are.equal(2, #settings_store["PaperWM_saved_frames"])
        end)

        it("records correct frame coordinates", function()
            local win = mock_window(101, "Window 1", { x = 10, y = 20, w = 300, h = 200 })
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.saveWindowFrames()

            local entry = settings_store["PaperWM_saved_frames"][1]
            assert.are.equal(10,  entry.frame.x)
            assert.are.equal(20,  entry.frame.y)
            assert.are.equal(300, entry.frame.w)
            assert.are.equal(200, entry.frame.h)
        end)

        it("stores the window ID for same-session matching", function()
            local win = mock_window(101, "Window 1")
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.saveWindowFrames()

            local entry = settings_store["PaperWM_saved_frames"][1]
            assert.are.equal(101, entry.id)
        end)

        it("stores a stable bundleID|title key for cross-session matching", function()
            local win = mock_window(101, "Window 1")
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.saveWindowFrames()

            local entry = settings_store["PaperWM_saved_frames"][1]
            assert.are.equal("com.apple.Terminal|Window 1", entry.key)
        end)

        it("keeps an in-memory snapshot in _saved", function()
            local win = mock_window(101, "Window 1")
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.saveWindowFrames()

            assert.is_not_nil(WindowRestore._saved)
            assert.are.equal(1, #WindowRestore._saved)
        end)

        it("snapshot is independent of later frame mutations", function()
            local win = mock_window(101, "Window 1", { x = 10, y = 20, w = 300, h = 200 })
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.saveWindowFrames()

            -- mutate the live frame after saving
            win:frame().x = 999

            local entry = WindowRestore._saved[1]
            assert.are.equal(10, entry.frame.x)
        end)
    end)

    -- -------------------------------------------------------------------------
    describe("restoreWindowFrames", function()
        it("does nothing when no frames have been saved", function()
            local win = mock_window(101, "Window 1")
            win.setFrame = spy.new(win.setFrame)
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.restoreWindowFrames()

            assert.spy(win.setFrame).was.not_called()
        end)

        it("restores saved frame by window ID within the same session", function()
            local win = mock_window(101, "Window 1", { x = 10, y = 20, w = 300, h = 200 })
            mock_paperwm.window_filter.getWindows = function() return { win } end
            WindowRestore.saveWindowFrames()

            -- simulate PaperWM tiling the window to a different position
            win:setFrame({ x = 0, y = 32, w = 1000, h = 668 })

            WindowRestore.restoreWindowFrames()

            local restored = win:frame()
            assert.are.equal(10,  restored.x)
            assert.are.equal(20,  restored.y)
            assert.are.equal(300, restored.w)
            assert.are.equal(200, restored.h)
        end)

        it("falls back to stable key matching after a session restart", function()
            -- pre-populate settings as if written by a previous session
            settings_store["PaperWM_saved_frames"] = {
                { key = "com.apple.Terminal|My Window", id = nil,
                  frame = { x = 100, y = 200, w = 800, h = 600 } }
            }
            -- _saved is nil: simulates a fresh Hammerspoon session

            local win = mock_window(999, "My Window", { x = 0, y = 0, w = 100, h = 100 })
            mock_paperwm.window_filter.getWindows = function() return { win } end

            WindowRestore.restoreWindowFrames()

            local restored = win:frame()
            assert.are.equal(100, restored.x)
            assert.are.equal(200, restored.y)
            assert.are.equal(800, restored.w)
            assert.are.equal(600, restored.h)
        end)

        it("does not move windows that have no saved entry", function()
            local win_saved   = mock_window(101, "Saved",  { x = 10, y = 20, w = 300, h = 200 })
            local win_unsaved = mock_window(102, "Unsaved", { x = 50, y = 60, w = 400, h = 300 })
            mock_paperwm.window_filter.getWindows = function() return { win_saved } end
            WindowRestore.saveWindowFrames()

            mock_paperwm.window_filter.getWindows = function() return { win_saved, win_unsaved } end
            win_unsaved.setFrame = spy.new(win_unsaved.setFrame)

            WindowRestore.restoreWindowFrames()

            assert.spy(win_unsaved.setFrame).was.not_called()
        end)

        it("consumes duplicate stable keys in order so each window gets a distinct frame", function()
            settings_store["PaperWM_saved_frames"] = {
                { key = "com.apple.Terminal|Tab", id = nil, frame = { x = 0,   y = 0, w = 400, h = 300 } },
                { key = "com.apple.Terminal|Tab", id = nil, frame = { x = 500, y = 0, w = 400, h = 300 } },
            }

            local win1 = mock_window(1, "Tab", { x = 999, y = 0, w = 100, h = 100 })
            local win2 = mock_window(2, "Tab", { x = 999, y = 0, w = 100, h = 100 })
            mock_paperwm.window_filter.getWindows = function() return { win1, win2 } end

            WindowRestore.restoreWindowFrames()

            assert.are.equal(0,   win1:frame().x)
            assert.are.equal(500, win2:frame().x)
        end)

        it("clears the in-memory snapshot after restore", function()
            local win = mock_window(101, "Window 1")
            mock_paperwm.window_filter.getWindows = function() return { win } end
            WindowRestore.saveWindowFrames()

            assert.is_not_nil(WindowRestore._saved)
            WindowRestore.restoreWindowFrames()
            assert.is_nil(WindowRestore._saved)
        end)
    end)
end)
