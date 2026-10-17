---@diagnostic disable

describe("PaperWM swipe recognition", function()
    local clock, rawCallback, delivered, swipe

    local function input(touches)
        clock = clock + 0.02
        return rawCallback({ getType = function() return 1 end,
            timestamp = function() return clock * 1e9 end,
            getTouches = function() return touches end })
    end

    local function fingers(count, position, phase)
        local touches = {}
        for identity = 1, count do
            touches[#touches + 1] = { identity = identity, phase = phase,
                normalizedPosition = { x = position, y = 0.5 } }
        end
        return touches
    end

    before_each(function()
        clock, delivered = 0, {}
        local mock_hs = {
            math = { randomFromRange = function() return 99 end },
            eventtap = {
                event = { types = { gesture = 1 } },
                new = function(_, callback)
                    rawCallback = callback
                    return { start = function(self) return self end, stop = function() end }
                end,
            },
        }
        swipe = assert(loadfile("swipe.lua", "t", setmetatable({ hs = mock_hs }, { __index = _G })))()
        swipe:start(4, function(identity, kind, deltaX, deltaY, inputTime)
            delivered[#delivered + 1] = { id = identity, kind = kind,
                deltaX = deltaX, deltaY = deltaY, inputTime = inputTime }
        end)
    end)

    after_each(function()
        swipe:stop()
    end)

    it("keeps a four-finger gesture active until every finger lifts", function()
        assert(input(fingers(4, 0.5, "began")) == nil)
        assert(input(fingers(2, 0.6, "moved")) == nil)
        assert(input(fingers(1, 0.7, "moved")) == nil)
        assert(input({}) == nil)
        assert(#delivered == 4 and delivered[1].kind == swipe.BEGIN and delivered[4].kind == swipe.END)
        assert(delivered[2].kind == swipe.MOVED and delivered[3].kind == swipe.MOVED)
        assert(math.abs(delivered[2].deltaX - 0.1) < 0.00001)
        assert(math.abs(delivered[3].deltaX - 0.1) < 0.00001)
        assert(math.abs(delivered[4].inputTime - 0.08) < 0.00001)
        for _, event in ipairs(delivered) do assert(event.id == 99) end
    end)

    it("ends immediately when all four fingers lift together", function()
        input(fingers(4, 0.5, "began"))
        input(fingers(4, 0.5, "ended"))
        assert(#delivered == 2 and delivered[2].kind == swipe.END)
        input({})
        assert(#delivered == 2)
    end)

    it("does not start with fewer fingers or jump when other fingers are removed", function()
        input(fingers(3, 0.5, "began"))
        assert(#delivered == 0)
        local touches = fingers(4, 0.5, "began")
        touches[4].normalizedPosition.x = 0.9
        input(touches)
        input(fingers(1, 0.5, "moved"))
        assert(#delivered == 2 and delivered[2].kind == swipe.MOVED)
        assert(delivered[2].deltaX == 0)
    end)
end)
