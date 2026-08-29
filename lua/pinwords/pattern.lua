---@class PinwordsPatternOpts
---@field whole_word boolean
---@field case_sensitive boolean

local M = {}

---@param text string
---@return string
local function escape_literal(text)
  local escaped = text:gsub("\\", "\\\\")
  escaped = escaped:gsub("\n", "\\n")
  escaped = escaped:gsub("\r", "\\r")
  return escaped
end

---Decide which ends of `raw` can carry a word boundary. `\<` and `\>` only
---ever match next to a keyword character, so wrapping text that starts or ends
---with a symbol (`-foo`, `foo-`) would make it impossible to match. A boundary
---is therefore applied only to ends that are keyword characters.
---@param raw string
---@return boolean left, boolean right
function M.word_boundaries(raw)
  local left = vim.fn.match(raw, "^\\k") == 0
  local right = vim.fn.match(raw, "\\k$") >= 0
  return left, right
end

---Recover which ends of a saved pattern carry a word boundary. The escaped raw
---text is matched explicitly because an escaped literal can end in `\>` on its
---own (pinning `foo\>` yields the body `foo\\>`), which a bare suffix test would
---mistake for a boundary marker.
---@param raw string
---@param pattern_text string
---@return boolean left, boolean right
function M.boundaries_of(raw, pattern_text)
  local body = pattern_text:gsub("^\\V\\[cC]", "")
  local escaped = escape_literal(raw)

  for _, sides in ipairs({ { true, true }, { true, false }, { false, true }, { false, false } }) do
    local left, right = sides[1], sides[2]
    local expected = (left and "\\<" or "") .. escaped .. (right and "\\>" or "")
    if body == expected then
      return left, right
    end
  end

  -- The pattern was not produced by build() for this raw text; fall back to the
  -- boundaries build() would choose.
  return M.word_boundaries(raw)
end

---@param raw string
---@param opts PinwordsPatternOpts
---@return string
function M.build(raw, opts)
  local prefix = "\\V"
  if opts.case_sensitive then
    prefix = prefix .. "\\C"
  else
    prefix = prefix .. "\\c"
  end

  local body = escape_literal(raw)
  if opts.whole_word then
    local left, right = M.word_boundaries(raw)
    if left then
      body = "\\<" .. body
    end
    if right then
      body = body .. "\\>"
    end
  end

  return prefix .. body
end

return M
