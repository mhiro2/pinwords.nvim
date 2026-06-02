---@brief [[
--- pinwords.nvim grep integration
--- Provides grep/live_grep across project using pinned words
---@brief ]]

local M = {}

-- ripgrep regex metacharacters that need escaping
local RG_META = "[%.%+%*%?%^%$%(%)%[%]%{%}%|\\]"

---@class PinwordsGrepEntry
---@field raw string
---@field whole_word boolean
---@field case_sensitive boolean

---@param entry PinwordsSlot
---@return PinwordsGrepEntry
local function to_grep_entry(entry)
  -- Match semantics are captured on the slot at pin time, so read them
  -- directly instead of reparsing the saved Vim pattern.
  return {
    raw = entry.raw,
    whole_word = entry.whole_word,
    case_sensitive = entry.case_sensitive,
  }
end

---@param slots table<integer, PinwordsSlot>
---@param slot? integer
---@return PinwordsGrepEntry[]|nil
local function collect_entries(slots, slot)
  if slot then
    local entry = slots[slot]
    if not entry then
      return nil
    end
    return { to_grep_entry(entry) }
  end

  local keys = vim.tbl_keys(slots)
  table.sort(keys)
  if #keys == 0 then
    return nil
  end

  local entries = {}
  for _, k in ipairs(keys) do
    table.insert(entries, to_grep_entry(slots[k]))
  end
  return entries
end

---@param text string
---@return boolean
local function is_multiline(text)
  return text:find("\n", 1, true) ~= nil or text:find("\r", 1, true) ~= nil
end

---@param entries PinwordsGrepEntry[]|nil
---@return PinwordsGrepEntry[]|nil, integer
local function filter_multiline_entries(entries)
  if not entries then
    return nil, 0
  end

  local filtered = {}
  local skipped = 0
  for _, entry in ipairs(entries) do
    if is_multiline(entry.raw) then
      skipped = skipped + 1
    else
      table.insert(filtered, entry)
    end
  end

  if #filtered == 0 then
    return nil, skipped
  end
  return filtered, skipped
end

---@param action string
---@param skipped integer
---@return nil
local function notify_skipped_entries(action, skipped)
  if skipped <= 0 then
    return
  end

  local suffix = skipped == 1 and "" or "s"
  vim.notify(("pinwords: %s skipped %d multi-line pinned word%s"):format(action, skipped, suffix), vim.log.levels.WARN)
end

---@param action string
---@param slots table<integer, PinwordsSlot>
---@param slot? integer
---@return PinwordsGrepEntry[]|nil
local function resolve_search_entries(action, slots, slot)
  local entries, skipped = filter_multiline_entries(collect_entries(slots, slot))
  if entries then
    notify_skipped_entries(action, skipped)
    return entries
  end

  if skipped > 0 then
    vim.notify(("pinwords: %s supports only single-line pinned words"):format(action), vim.log.levels.WARN)
    return nil
  end

  vim.notify("pinwords: no pinned words", vim.log.levels.INFO)
  return nil
end

---Escape a string for use as a ripgrep literal pattern
---@param text string
---@return string
local function escape_rg(text)
  return (text:gsub(RG_META, "\\%0"))
end

---Escape a string for use as a Vim regex literal body under \V mode
---@param text string
---@return string
local function escape_vim_literal(text)
  local escaped = text:gsub("\\", "\\\\")
  escaped = escaped:gsub("\n", "\\n")
  escaped = escaped:gsub("\r", "\\r")
  return escaped
end

---@param entry PinwordsGrepEntry
---@return string
local function build_rg_term(entry)
  local term = escape_rg(entry.raw)
  if entry.whole_word then
    term = "\\b" .. term .. "\\b"
  end

  if not entry.case_sensitive then
    term = "(?i:" .. term .. ")"
  end
  return term
end

---@param entries PinwordsGrepEntry[]|nil
---@return string|nil
local function build_rg_pattern_from_entries(entries)
  if not entries then
    return nil
  end

  local terms = {}
  for _, entry in ipairs(entries) do
    table.insert(terms, build_rg_term(entry))
  end

  if #terms == 1 then
    return terms[1]
  end
  return table.concat(terms, "|")
end

---@param entry PinwordsGrepEntry
---@return string
local function build_vim_term(entry)
  local term = escape_vim_literal(entry.raw)
  if entry.whole_word then
    term = "\\<" .. term .. "\\>"
  end
  return (entry.case_sensitive and "\\C" or "\\c") .. term
end

---@param entries PinwordsGrepEntry[]|nil
---@return string|nil
local function build_vim_pattern_from_entries(entries)
  if not entries then
    return nil
  end

  local terms = {}
  for _, entry in ipairs(entries) do
    table.insert(terms, build_vim_term(entry))
  end

  if #terms == 1 then
    return "\\V" .. terms[1]
  end

  return "\\V\\(" .. table.concat(terms, "\\|") .. "\\)"
end

---Build a ripgrep-compatible regex pattern from pinned words.
---@param slots table<integer, PinwordsSlot>
---@param slot? integer  specific slot, or nil for all
---@return string|nil pattern  ripgrep regex, or nil if no words
function M.build_rg_pattern(slots, slot)
  return build_rg_pattern_from_entries(collect_entries(slots, slot))
end

---Build a Vim regex pattern from pinned words.
---Uses \V mode for literal matching and combines words via \| alternation.
---@param slots table<integer, PinwordsSlot>
---@param slot? integer
---@return string|nil
function M.build_vim_pattern(slots, slot)
  return build_vim_pattern_from_entries(collect_entries(slots, slot))
end

---Run fallback grep using Vim's vimgrep.
---@param title string
---@param items vim.quickfix.entry[]
---@return nil
local function open_quickfix(title, items)
  vim.fn.setqflist({}, " ", {
    title = title,
    items = items,
  })
  vim.api.nvim_cmd({ cmd = "copen" }, {})
end

---@param stdout string
---@return vim.quickfix.entry[]
local function parse_rg_vimgrep(stdout)
  local items = {}

  for line in stdout:gmatch("[^\r\n]+") do
    local filename, lnum, col, text = line:match("^(.+):(%d+):(%d+):(.*)$")
    if filename then
      items[#items + 1] = {
        filename = filename,
        lnum = tonumber(lnum),
        col = tonumber(col),
        text = text,
      }
    end
  end

  return items
end

---@param result vim.SystemCompleted
---@return nil
local function handle_rg_result(result)
  if result.code == 1 then
    vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
    return
  end

  if result.code ~= 0 then
    local msg = vim.trim(result.stderr or "")
    if msg == "" then
      msg = "rg exited with code " .. result.code
    end
    vim.notify("pinwords: grep failed: " .. msg, vim.log.levels.WARN)
    return
  end

  local items = parse_rg_vimgrep(result.stdout or "")
  if #items == 0 then
    vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
    return
  end

  open_quickfix("pinwords grep", items)
end

---Dispatch ripgrep asynchronously so the UI is not blocked while scanning.
---Returns true when the rg invocation was started (whether or not it has completed).
---@param rg_pattern string
---@return boolean
local function try_rg_fallback(rg_pattern)
  if vim.fn.executable("rg") ~= 1 or type(vim.system) ~= "function" then
    return false
  end

  vim.system({
    "rg",
    "--vimgrep",
    "--color=never",
    "--no-heading",
    rg_pattern,
  }, { text = true }, function(result)
    vim.schedule(function()
      handle_rg_result(result)
    end)
  end)

  return true
end

-- Wildignore globs applied around the synchronous vimgrep fallback so the
-- traversal skips VCS metadata, dependency caches, and common build outputs.
local FALLBACK_IGNORE_GLOBS = {
  "**/.git/**",
  "**/.hg/**",
  "**/.svn/**",
  "**/node_modules/**",
  "**/vendor/**",
  "**/deps/**",
  "**/__pycache__/**",
  "**/.venv/**",
  "**/.tox/**",
  "**/build/**",
  "**/dist/**",
  "**/target/**",
  "**/.cache/**",
}

---Run vimgrep with a temporarily extended `wildignore` so the traversal does
---not descend into VCS metadata, dependency caches, or build outputs.
---@param vim_pattern string
---@return boolean ok, string? err
local function run_vimgrep_with_ignores(vim_pattern)
  local saved_wildignore = vim.o.wildignore
  local separator = saved_wildignore == "" and "" or ","
  vim.o.wildignore = saved_wildignore .. separator .. table.concat(FALLBACK_IGNORE_GLOBS, ",")

  local ok, err = pcall(vim.fn.vimgrep, vim_pattern, "**/*", "gj")

  vim.o.wildignore = saved_wildignore
  return ok, err
end

---Run fallback grep using ripgrep when available, then Vim's vimgrep.
---@param slots table<integer, PinwordsSlot>
---@param slot? integer
function M._fallback_grep(slots, slot)
  local entries = resolve_search_entries("grep", slots, slot)
  if not entries then
    return
  end

  local rg_pattern = build_rg_pattern_from_entries(entries)
  if rg_pattern and try_rg_fallback(rg_pattern) then
    return
  end

  local vim_pattern = build_vim_pattern_from_entries(entries)
  if not vim_pattern then
    return
  end

  -- vimgrep is synchronous and walks the project tree, so warn the user before
  -- the UI freezes while ripgrep is unavailable.
  vim.notify("pinwords: ripgrep not available; scanning project files (this may take a moment)", vim.log.levels.INFO)

  local ok, err = run_vimgrep_with_ignores(vim_pattern)
  if not ok then
    local msg = tostring(err)
    if msg:find("E480", 1, true) or msg:find("No match", 1, true) then
      vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
      return
    end
    vim.notify("pinwords: grep failed: " .. msg, vim.log.levels.WARN)
    return
  end

  local qf = vim.fn.getqflist({ size = 0 })
  local size = 0
  if type(qf) == "table" and type(qf.size) == "number" then
    size = qf.size
  end

  if size == 0 then
    vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
    return
  end

  vim.api.nvim_cmd({ cmd = "copen" }, {})
end

---Run grep via the best available picker backend.
---@param opts? { slot?: integer }
function M.grep(opts)
  opts = opts or {}
  local pinwords = require("pinwords")
  local slots = pinwords.list()
  local entries = resolve_search_entries("grep", slots, opts.slot)
  if not entries then
    return
  end

  local cfg = pinwords.get_config()
  local backend_pattern = build_rg_pattern_from_entries(entries)
  if not backend_pattern then
    return
  end

  -- Try snacks
  if cfg.snacks.enabled then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.grep({
        search = backend_pattern,
        live = false,
        regex = true,
      })
      return
    end
  end

  -- Try telescope
  if cfg.telescope.enabled then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then
      builtin.grep_string({
        search = backend_pattern,
        use_regex = true,
      })
      return
    end
  end

  -- Try fzf-lua
  if cfg.fzf_lua.enabled then
    local ok, fzf_lua = pcall(require, "fzf-lua")
    if ok then
      fzf_lua.grep({
        search = backend_pattern,
        no_esc = true,
      })
      return
    end
  end

  -- Fallback: vimgrep to quickfix
  M._fallback_grep(slots, opts.slot)
end

---Run live_grep via the best available picker backend.
---@param opts? { slot?: integer }
function M.live_grep(opts)
  opts = opts or {}
  local pinwords = require("pinwords")
  local slots = pinwords.list()
  local entries = resolve_search_entries("live grep", slots, opts.slot)
  if not entries then
    return
  end

  local cfg = pinwords.get_config()
  local backend_pattern = build_rg_pattern_from_entries(entries)
  if not backend_pattern then
    return
  end

  -- Try snacks
  if cfg.snacks.enabled then
    local ok, snacks = pcall(require, "snacks")
    if ok and snacks.picker then
      snacks.picker.grep({
        search = backend_pattern,
        live = true,
        regex = true,
      })
      return
    end
  end

  -- Try telescope
  if cfg.telescope.enabled then
    local ok, builtin = pcall(require, "telescope.builtin")
    if ok then
      builtin.live_grep({
        default_text = backend_pattern,
      })
      return
    end
  end

  -- Try fzf-lua
  if cfg.fzf_lua.enabled then
    local ok, fzf_lua = pcall(require, "fzf-lua")
    if ok then
      fzf_lua.live_grep({
        search = backend_pattern,
        no_esc = true,
      })
      return
    end
  end

  -- Fallback: vimgrep to quickfix
  M._fallback_grep(slots, opts.slot)
end

return M
