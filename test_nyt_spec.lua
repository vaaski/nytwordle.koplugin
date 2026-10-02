local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local NYT = assert(loadfile(DIR .. "nyt.lua"))()

describe("NYT dates", function()
    it("validates strict calendar dates, leap years and the future", function()
        for _, date in ipairs({ "2024-02-29", "2000-02-29", "2026-10-02" }) do
            assert.is_true(NYT.isValidDate(date, "2026-10-02"))
        end
        for _, date in ipairs({ "1900-02-29", "2026-02-29", "2026-04-31", "2026-00-01",
                                "2026-13-01", "2026-01-00", "2026-10-03", "2026-1-01",
                                "0000-01-01", "2026-10-02/other", "" }) do
            assert.is_false(NYT.isValidDate(date, "2026-10-02"), date)
        end
        assert.is_false(NYT.isValidDate(nil))
    end)
end)

describe("NYT retrieval", function()
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
        package.loaded["json"] = require("dkjson")
        package.loaded["socket.http"] = { request = function(opts) return request(opts) end }
    end)

    after_each(function()
        for _, name in ipairs({ "socket.http", "socketutil", "json" }) do
            package.loaded[name] = previous[name]
        end
    end)

    it("fetches the date endpoint and normalizes the answer", function()
        request = function(opts)
            assert.are.equal("https://www.nytimes.com/svc/wordle/v2/2024-01-01.json", opts.url)
            opts.sink('{"print_date":"2024-01-01","solution":"apple"}')
            return 1, 200
        end
        assert.are.equal("APPLE", NYT.fetch("2024-01-01"))
        assert.are.same({ { 5, 15 }, { 60, -1 } }, timeouts)
    end)

    it("handles timeouts, HTTP errors and exceptions and restores timeouts", function()
        for _, response in ipairs({
            function() return nil, "timeout" end,
            function() return 1, 404 end,
            function() error("network exception") end,
        }) do
            request = response
            local solution, err = NYT.fetch("2024-01-01")
            assert.is_nil(solution)
            assert.is_string(err)
            assert.are.same({ 60, -1 }, timeouts[#timeouts])
        end
    end)

    it("rejects malformed JSON, wrong dates and invalid solutions", function()
        for _, body in ipairs({ "not json", "null", "[]",
            '{"print_date":"2024-01-02","solution":"apple"}',
            '{"print_date":"2024-01-01","solution":"longer"}',
            '{"print_date":"2024-01-01","solution":"ab1de"}',
            '{"print_date":"2024-01-01"}',
        }) do
            request = function(opts) opts.sink(body) return 1, 200 end
            local solution, err = NYT.fetch("2024-01-01")
            assert.is_nil(solution)
            assert.are.equal("Invalid puzzle response", err)
        end
    end)

    it("does not request invalid dates", function()
        request = function() error("must not request") end
        local solution, err = NYT.fetch("2024-02-30")
        assert.is_nil(solution)
        assert.are.equal("Invalid date", err)
        assert.are.same({}, timeouts)
    end)
end)
