local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local Spiegel = assert(loadfile(DIR .. "spiegel.lua"))()
local Letters = assert(loadfile(DIR .. "letters.lua"))()
local json = require("dkjson")

local function puzzle(word, date)
    local grid = {}
    local letters = Letters.split(word or "GRÜßE")
    for row = 0, 5 do
        for col = 0, 4 do
            grid[#grid + 1] = {
                row = row, col = col, type = "answer",
                items = { { type = "value", value = letters[col + 1] },
                    { type = "userinput", value = "" } },
            }
        end
    end
    return { data = {
        ckey = "l_spiegel_wordlearchiv_" .. (date or "2026-10-02"):gsub("-", "") .. "_1790892000",
        riddle = { payload = { width = 5, height = 6, grid = grid } },
    } }
end

describe("SPIEGEL retrieval", function()
    local previous, request, timeouts

    before_each(function()
        previous = {}
        for _, name in ipairs({ "socket.http", "socketutil", "json" }) do
            previous[name] = package.loaded[name]
        end
        timeouts = {}
        package.loaded["socketutil"] = {
            block_timeout = 60, total_timeout = -1,
            set_timeout = function(_, block, total) timeouts[#timeouts + 1] = { block, total } end,
            table_sink = function(body)
                return function(chunk) if chunk then body[#body + 1] = chunk end return 1 end
            end,
        }
        package.loaded["json"] = json
        package.loaded["socket.http"] = { request = function(opts) return request(opts) end }
    end)

    after_each(function()
        for _, name in ipairs({ "socket.http", "socketutil", "json" }) do
            package.loaded[name] = previous[name]
        end
    end)

    it("uses the undated endpoint and takes the puzzle date from the server", function()
        request = function(opts)
            assert.are.equal("https://api.spiegel.raetselzentrale.com/api/v3/l/spiegel/wordlearchiv?channel=www.spiegel.de", opts.url)
            opts.sink(json.encode(puzzle()))
            return 1, 200
        end
        local solution, err, date = Spiegel.fetch()
        assert.are.equal("GRÜßE", solution)
        assert.is_nil(err)
        assert.are.equal("2026-10-02", date)
        assert.are.same({ { 5, 15 }, { 60, -1 } }, timeouts)
    end)

    it("requests YYYYMMDD archive paths and handles shuffled grid order", function()
        request = function(opts)
            assert.is_truthy(opts.url:find("/20261001?channel=", 1, true))
            local response = puzzle("äpfel", "2026-10-01")
            local grid = response.data.riddle.payload.grid
            grid[1], grid[30] = grid[30], grid[1]
            opts.sink(json.encode(response))
            return 1, 200
        end
        local solution, err, date = Spiegel.fetch("2026-10-01")
        assert.are.equal("ÄPFEL", solution)
        assert.is_nil(err)
        assert.are.equal("2026-10-01", date)
    end)

    it("rejects wrong dates, malformed grids and unplayable letters", function()
        local invalid = {
            puzzle("ABCDE", "2026-10-01"),
            puzzle("ABÉDE"), puzzle("ABCDE", "2026-02-30"),
        }
        local width = puzzle()
        width.data.riddle.payload.width = 6
        invalid[#invalid + 1] = width
        local repeated = puzzle()
        repeated.data.riddle.payload.grid[2].col = 0
        invalid[#invalid + 1] = repeated
        local disagreement = puzzle()
        disagreement.data.riddle.payload.grid[30].items[1].value = "A"
        invalid[#invalid + 1] = disagreement
        local missing = puzzle()
        table.remove(missing.data.riddle.payload.grid)
        invalid[#invalid + 1] = missing
        for _, response in ipairs(invalid) do
            request = function(opts) opts.sink(json.encode(response)) return 1, 200 end
            local solution, err = Spiegel.fetch("2026-10-02")
            assert.is_nil(solution)
            assert.are.equal("Invalid puzzle response", err)
        end
    end)

    it("handles errors and always restores HTTP timeout settings", function()
        for _, response in ipairs({
            function() return nil, "timeout" end,
            function() return 1, 404 end,
            function() error("network exception") end,
            function(opts) opts.sink("not JSON") return 1, 200 end,
        }) do
            request = response
            local solution, err = Spiegel.fetch()
            assert.is_nil(solution)
            assert.is_string(err)
            assert.are.same({ 60, -1 }, timeouts[#timeouts])
        end
    end)

    it("rejects invalid calendar dates and dates before the archive without HTTP", function()
        request = function() error("must not request") end
        for _, date in ipairs({ "2024-12-13", "2026-02-30", "20261001", "2026-10-01/other" }) do
            local solution, err = Spiegel.fetch(date)
            assert.is_nil(solution)
            assert.are.equal("Invalid date", err)
        end
        assert.is_false(Spiegel.isValidDate("2026-10-03", "2026-10-02"))
        assert.is_true(Spiegel.isValidDate("2024-12-14", "2026-10-02"))
        assert.are.same({}, timeouts)
    end)
end)
