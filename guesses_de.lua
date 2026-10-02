-- The supplied German dictionary resembles the words accepted by spiegel.de.
-- Its source format concatenates five Unicode characters per word. Transform
-- it lazily, preserving umlauts and ß and excluding untypeable foreign letters.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = DIR .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(DIR .. name .. ".lua"))()
    end
    return package.loaded[key]
end
local Letters = lrequire("letters")
local file = assert(io.open(DIR .. "spiegel_wordlist.txt", "rb"))
local source = file:read("*a")
file:close()
local characters = Letters.split((source:gsub("%s", "")))
assert(#characters % 5 == 0, "German dictionary must contain five-character words")

local seen = {}
for _, word in ipairs(lrequire("words_de")) do seen[word] = true end
local guesses = {}
for i = 1, #characters, 5 do
    local word = Letters.upper(table.concat(characters, "", i, i + 4))
    if Letters.isWord(word, "de") and not seen[word] then
        seen[word] = true
        guesses[#guesses + 1] = word
    end
end
return guesses
