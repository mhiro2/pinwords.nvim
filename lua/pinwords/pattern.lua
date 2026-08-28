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
