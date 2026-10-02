local Letters = {}

-- - German alphabet ----------------------------------------------------------

local upper = { ["ä"] = "Ä", ["ö"] = "Ö", ["ü"] = "Ü", ["ẞ"] = "ß" }
local german = { ["Ä"] = true, ["Ö"] = true, ["Ü"] = true, ["ß"] = true }

function Letters.split(word)
    local letters = {}
    for letter in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        letters[#letters + 1] = letter
    end
    return letters
end

function Letters.upper(word)
    return (word:gsub("[%z\1-\127\194-\244][\128-\191]*", function(letter)
        return upper[letter] or letter:upper()
    end))
end

function Letters.isLetter(letter, lang)
    return letter:match("^[A-Z]$") ~= nil or (lang == "de" and german[letter] == true)
end

function Letters.isWord(word, lang)
    if type(word) ~= "string" then return false end
    local letters = Letters.split(word)
    if #letters ~= 5 or table.concat(letters) ~= word then return false end
    for _, letter in ipairs(letters) do
        if not Letters.isLetter(letter, lang) then return false end
    end
    return true
end

return Letters
