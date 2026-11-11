-- Book of Dogs: blocks slurs in descriptions (typed here or received from anyone).
-- The word lists are stored shifted one letter so this file isn't a list of slurs.
-- Text is normalized first: lowercase, look-alike numbers/symbols to letters,
-- accents stripped, repeated letters collapsed, so "N 1 G G..." style tricks still match.
local ADDON, NS = ...

local function unshift(t) local o = {} for i, w in ipairs(t) do o[i] = w:gsub(".", function(c) return string.char(c:byte() - 1) end) end return o end
local A = {"dijol","hpmzxph","kjhbcp","kvohmfcvoz","lbgjs","ofhsp","ojhb","ojhbi","ojhfs","ojhvs","qpsdinpolfz","sbhifbe","tboeojhfs","upxfmifbe","xfucbdl","{jqfsifbe"}
local W = {"hpl","cfbofs","dijobnbo","dsbdlfs","ebhp","ebsljf","ebslz","hpmjxph","hsfbtfs","hzq","ibmgcsfe","ipolfz","ipolz","jokvo","kbq","ljlf","lzlf","nvmbup","qblj","qjdbojoz","qjdlbojoz","sfetljo","tbncp","tizmpdl","tqjd","tqjdl","trvbx","ubscbcz","xjhfs","xpq","{jqfsifbe"}
A, W = unshift(A), unshift(W)
local WSET = {} for _, w in ipairs(W) do WSET[w] = true end

local LEET = {["0"] = "o", ["1"] = "i", ["!"] = "i", ["|"] = "i", ["3"] = "e", ["4"] = "a", ["@"] = "a",
              ["5"] = "s", ["$"] = "s", ["7"] = "t", ["+"] = "t", ["9"] = "g", ["6"] = "g", ["8"] = "b", ["2"] = "z"}
-- common accented letters (UTF-8) to plain ones
local ACCENT = {["à"]="a",["á"]="a",["â"]="a",["ã"]="a",["ä"]="a",["å"]="a",["è"]="e",["é"]="e",["ê"]="e",["ë"]="e",
  ["ì"]="i",["í"]="i",["î"]="i",["ï"]="i",["ò"]="o",["ó"]="o",["ô"]="o",["õ"]="o",["ö"]="o",["ù"]="u",["ú"]="u",
  ["û"]="u",["ü"]="u",["ñ"]="n",["ç"]="c",["ý"]="y",["ÿ"]="y"}

local function collapse(s)
  local out, last = {}, nil
  for c in s:gmatch(".") do if c ~= last then out[#out + 1] = c end last = c end
  return table.concat(out)
end


-- returns true if the text contains a blocked word
local function blocked(s)
  -- anywhere: squash out everything that isn't a letter, so spacing/punctuation tricks don't help
  local squashed = collapse(s:gsub("[^%a]", ""))
  for _, w in ipairs(A) do if squashed:find(w, 1, true) then return true end end
  -- whole words (short ones that would otherwise hit innocent words), plus simple plurals
  for word in s:gmatch("%a+") do
    word = collapse(word)
    if WSET[word] or WSET[(word:gsub("s$", ""))] or WSET[(word:gsub("es$", ""))] then return true end
  end
  -- letters typed one at a time ("k i k e", "k.i.k.e"): join runs of single letters
  local run = {}
  local function check()
    if #run > 2 then
      local j = table.concat(run)
      for _, w in ipairs(A) do if collapse(j):find(w, 1, true) then return true end end
      -- any stretch of the run can be the word ("you are a s p i c")
      for a = 1, #j - 2 do
        for b = a + 2, math.min(#j, a + 12) do
          local sub = collapse(j:sub(a, b))
          if WSET[sub] or WSET[(sub:gsub("s$", ""))] then return true end
        end
      end
    end
    run = {}
  end
  for word in s:gmatch("%a+") do
    if #word == 1 then run[#run + 1] = word elseif check() then return true end
  end
  if check() then return true end
  return false
end

function NS.Blocked(text)
  if not text or text == "" then return false end
  local plain = text:lower()
  for k, v in pairs(ACCENT) do plain = plain:gsub(k, v) end
  -- check as typed, and with look-alike symbols read as letters ("n1gg3r")
  return blocked(plain) or blocked((plain:gsub(".", function(c) return LEET[c] or c end)))
end
