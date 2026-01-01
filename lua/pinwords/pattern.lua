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
    return prefix .. "\\<" .. body .. "\\>"
  end

  return prefix .. body
end

return M
