---@brief [[
--- pinwords.nvim grep integration
--- Provides grep/live_grep across project using pinned words
---@brief ]]

local pattern = require("pinwords.pattern")

local M = {}

-- ripgrep regex metacharacters that need escaping
local RG_META = "[%.%+%*%?%^%$%(%)%[%]%{%}%|\\]"

---@class PinwordsGrepEntry
---@field raw string
---@field whole_word boolean
---@field case_sensitive boolean
---@field pattern string
---@field left_boundary boolean
---@field right_boundary boolean

---`git grep -w` recognizes only ASCII letters, digits and `_` as word
---characters, so `-w` may be used only when both endpoints are ASCII word
---characters.
---@param char string
---@return boolean
local function is_ascii_word_char(char)
  return char:match("^[%w_]$") ~= nil
end

---ripgrep's `\b` is Unicode-aware, so it can anchor next to multibyte letters as
---well. Blanks, punctuation and emoji are not word characters for ripgrep, so a
---boundary next to them would be unsatisfiable and is dropped instead. Emitting
---`\b` wherever ripgrep can honor it keeps the pattern as precise as possible for
---the picker backends, which receive only a pattern and whose results cannot be
---verified afterwards.
---@param char string  a single character, not a byte
---@return boolean
local function is_rg_word_char(char)
  if char == "" then
    return false
  end
  if #char == 1 then
    return char:match("^[%w_]$") ~= nil
  end

  -- 0 blank, 1 punctuation, 3 emoji; letters and CJK fall in the other classes.
  local class = vim.fn.charclass(char)
  return class ~= 0 and class ~= 1 and class ~= 3
end

---@param text string
---@return string first, string last  endpoint characters, not bytes
local function endpoint_chars(text)
  local count = vim.fn.strchars(text)
  if count == 0 then
    return "", ""
  end
  return vim.fn.strcharpart(text, 0, 1), vim.fn.strcharpart(text, count - 1, 1)
end

---Recover which ends of the saved pattern carry a word boundary. Reading the
---pattern instead of recomputing from `iskeyword` keeps grep aligned with the
---highlight applied at pin time, even when the slot was pinned in a buffer with
---different `iskeyword` settings.
---@param entry PinwordsSlot
---@return boolean left, boolean right
local function boundaries_from_pattern(entry)
  if type(entry.pattern) ~= "string" then
    return pattern.word_boundaries(entry.raw)
  end
  return pattern.boundaries_of(entry.raw, entry.pattern)
end

---@param entry PinwordsSlot
---@return PinwordsGrepEntry
local function to_grep_entry(entry)
  -- Match semantics are captured on the slot at pin time, so read them
  -- directly instead of recomputing them against the current buffer.
  local left, right = boundaries_from_pattern(entry)
  return {
    raw = entry.raw,
    whole_word = entry.whole_word,
    case_sensitive = entry.case_sensitive,
    pattern = entry.pattern,
    left_boundary = entry.whole_word and left,
    right_boundary = entry.whole_word and right,
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
  local first, last = endpoint_chars(entry.raw)
  -- Mirror the highlight pattern, but skip a `\b` that ripgrep could never
  -- satisfy because the endpoint is not a word character for ripgrep.
  if entry.left_boundary and is_rg_word_char(first) then
    term = "\\b" .. term
  end
  if entry.right_boundary and is_rg_word_char(last) then
    term = term .. "\\b"
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
  if entry.left_boundary then
    term = "\\<" .. term
  end
  if entry.right_boundary then
    term = term .. "\\>"
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

---Backend flags are only a pre-filter: `git grep -w` cannot express one-sided
---boundaries and judges words by ASCII alone, and a ripgrep `\b` is omitted
---where ripgrep could not satisfy it. Checking each result with a Vim pattern
---makes the verification exact for multibyte text, `iskeyword`, and case
---folding, matching what the highlight would do.
---
---Build the pattern used to verify results: the slot's literal text with a "no
---keyword character adjacent" assertion on each end that carries a boundary.
---`\<` and `\>` cannot express that next to a non-keyword character -- a slot
---pinned where `iskeyword` was wider would then match nothing at all -- while
---`\%(\k\)\@<!` and `\%(\k\)\@!` state exactly the same condition for any text.
---@param entry PinwordsGrepEntry
---@return string
local function verification_pattern(entry)
  local body = escape_vim_literal(entry.raw)
  if entry.left_boundary then
    body = "\\%(\\k\\)\\@<!" .. body
  end
  if entry.right_boundary then
    body = body .. "\\%(\\k\\)\\@!"
  end
  return (entry.case_sensitive and "\\V\\C" or "\\V\\c") .. body
end

---@param entry PinwordsGrepEntry
---@return vim.regex|nil regex, string pattern_text
local function entry_regex(entry)
  local pattern_text = verification_pattern(entry)
  local ok, regex = pcall(vim.regex, pattern_text)
  return ok and regex or nil, pattern_text
end

---@param entries PinwordsGrepEntry[]
---@return boolean
local function entries_need_verification(entries)
  for _, entry in ipairs(entries) do
    if entry.left_boundary or entry.right_boundary then
      return true
    end
  end
  return false
end

---Compile the entry's pattern anchored at a byte column, so a result can be
---checked at exactly the position the backend reported while the rest of the
---line still provides context for `\<` and `\>`. `\%<n>c` counts bytes, which is
---what quickfix columns are.
---@param pattern_text string
---@param col integer
---@param cache table<string, vim.regex|false>
---@return vim.regex|nil
local function anchored_regex(pattern_text, col, cache)
  local key = pattern_text .. "\0" .. col
  local cached = cache[key]
  if cached ~= nil then
    return cached or nil
  end

  -- The pattern always begins with the four-byte `\V\c` / `\V\C` prefix.
  local anchored = pattern_text:sub(1, 4) .. ("\\%%%dc"):format(col) .. pattern_text:sub(5)
  local ok, regex = pcall(vim.regex, anchored)
  cache[key] = ok and regex or false
  return ok and regex or nil
end

---Keep the results that at least one pinned entry really matches. A result is
---kept at its own column when the match starts there, so several matches on one
---line stay distinct; otherwise the column moves to the line's first match,
---which is what the single-column backends report. Results are visited in
---backend order, and duplicates produced by that move are dropped.
---@param entries PinwordsGrepEntry[]
---@param items vim.quickfix.entry[]
---@return vim.quickfix.entry[]
local function verify_items(entries, items)
  if not entries_need_verification(entries) then
    return items
  end

  local verifiers = {}
  for _, entry in ipairs(entries) do
    -- An entry with no usable pattern accepts its results unchecked, so one such
    -- entry does not disable verification for the others.
    local regex, pattern_text = entry_regex(entry)
    verifiers[#verifiers + 1] = { regex = regex, pattern_text = pattern_text }
  end

  local anchored_cache = {}
  local seen = {}
  local out = {}

  for _, item in ipairs(items) do
    local col
    for _, verifier in ipairs(verifiers) do
      if not verifier.regex then
        col = item.col
        break
      end

      local anchored = anchored_regex(verifier.pattern_text, item.col, anchored_cache)
      if anchored and anchored:match_str(item.text) then
        col = item.col
        break
      end

      local match_start = verifier.regex:match_str(item.text)
      if match_start and not col then
        col = match_start + 1
      end
    end

    if col then
      item.col = col
      local key = ("%s:%d:%d"):format(item.filename, item.lnum, col)
      if not seen[key] then
        seen[key] = true
        out[#out + 1] = item
      end
    end
  end

  return out
end

---Sort quickfix items by location and drop exact duplicates so overlapping
---per-entry matches do not appear twice in the merged list.
---@param items vim.quickfix.entry[]
---@return vim.quickfix.entry[]
local function sort_and_dedup_items(items)
  table.sort(items, function(a, b)
    if a.filename ~= b.filename then
      return a.filename < b.filename
    end
    if a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    end
    return a.col < b.col
  end)

  local seen = {}
  local out = {}
  for _, item in ipairs(items) do
    local key = ("%s:%d:%d"):format(item.filename, item.lnum, item.col)
    if not seen[key] then
      seen[key] = true
      out[#out + 1] = item
    end
  end
  return out
end

-- Identifies the most recent search. Async completion callbacks compare against
-- it so a slower, older invocation cannot overwrite the quickfix list of a newer
-- one, and so nothing fires after teardown.
local run_id = 0

---@return integer
local function next_run_id()
  run_id = run_id + 1
  return run_id
end

---@param id integer
---@return boolean
local function is_current_run(id)
  return id == run_id
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
---@param entries PinwordsGrepEntry[]
---@return nil
local function handle_rg_result(result, entries)
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

  -- ripgrep may return lines that satisfy the pattern but not the slot's word
  -- boundaries, e.g. when a `\b` had to be omitted as unsatisfiable.
  local items = verify_items(entries, parse_rg_vimgrep(result.stdout or ""))
  if #items == 0 then
    vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
    return
  end

  open_quickfix("pinwords grep", items)
end

---Dispatch ripgrep asynchronously so the UI is not blocked while scanning.
---Returns true when the rg invocation was started (whether or not it has
---completed). The pattern is passed via `-e` so a term starting with `-` is
---never parsed as an option.
---@param rg_pattern string
---@param entries PinwordsGrepEntry[]
---@param id integer
---@return boolean
local function try_rg_fallback(rg_pattern, entries, id)
  if vim.fn.executable("rg") ~= 1 or type(vim.system) ~= "function" then
    return false
  end

  vim.system({
    "rg",
    "--vimgrep",
    "--color=never",
    "--no-heading",
    "-e",
    rg_pattern,
  }, { text = true }, function(result)
    vim.schedule(function()
      if not is_current_run(id) then
        return
      end
      handle_rg_result(result, entries)
    end)
  end)

  return true
end

---Return true when the cwd is inside a Git working tree. `git grep` is run from
---the cwd (not the repository root) so it searches the cwd subtree, matching the
---scope of the `rg` and `vimgrep` fallbacks.
---@return boolean
local function inside_git_repo()
  local cwd = vim.uv.cwd()
  if not cwd then
    return false
  end
  return vim.fs.root(cwd, ".git") ~= nil
end

---True when `git grep -w` reproduces the entry's boundaries exactly: `-w`
---requires a boundary on both ends, so it fits only when both ends need one and
---both are word characters for git.
---@param entry PinwordsGrepEntry
---@return boolean
local function git_grep_can_use_word_flag(entry)
  local first, last = endpoint_chars(entry.raw)
  return entry.left_boundary and entry.right_boundary and is_ascii_word_char(first) and is_ascii_word_char(last)
end

---Build the `git grep` argv for a single pinned entry. `-F` keeps the term a
---literal so there is no regex-dialect mismatch, while `-w`/`-i` reproduce the
---slot's whole-word and case sensitivity. `-w` is used only when it matches the
---entry's boundaries exactly; one-sided boundaries are enforced afterwards by
---`verify_items`, since `-w` cannot express them. `-n --column`
---output matches the `file:line:col:text` shape that `parse_rg_vimgrep` already
---understands. `--untracked --exclude-standard` mirrors ripgrep: search tracked
---files plus untracked files that are not gitignored.
---@param entry PinwordsGrepEntry
---@return string[]
local function build_git_grep_cmd(entry)
  local cmd = { "git", "grep", "--no-color", "-I", "-n", "--column", "--untracked", "--exclude-standard", "-F" }
  if git_grep_can_use_word_flag(entry) then
    cmd[#cmd + 1] = "-w"
  end
  if not entry.case_sensitive then
    cmd[#cmd + 1] = "-i"
  end
  cmd[#cmd + 1] = "-e"
  cmd[#cmd + 1] = entry.raw
  return cmd
end

---Run `git grep` for every entry asynchronously, merging the results into a
---single quickfix list once all invocations finish. Each entry uses its own
---invocation because `-w`/`-i` are global flags in git grep, so per-slot match
---semantics could not otherwise be honored in one call. Returns true when the
---invocations were started so the caller skips the synchronous fallback.
---@param entries PinwordsGrepEntry[]
---@param id integer
---@return boolean
local function try_git_grep_fallback(entries, id)
  if type(vim.system) ~= "function" or vim.fn.executable("git") ~= 1 then
    return false
  end
  if not inside_git_repo() then
    return false
  end

  local pending = #entries
  local items = {}
  ---@type string|nil
  local err_msg = nil

  for _, entry in ipairs(entries) do
    vim.system(build_git_grep_cmd(entry), { text = true }, function(result)
      vim.schedule(function()
        if not is_current_run(id) then
          return
        end

        if result.code == 0 then
          local parsed = verify_items({ entry }, parse_rg_vimgrep(result.stdout or ""))
          for _, item in ipairs(parsed) do
            items[#items + 1] = item
          end
        elseif result.code ~= 1 then
          local msg = vim.trim(result.stderr or "")
          if msg == "" then
            msg = "git grep exited with code " .. result.code
          end
          err_msg = err_msg or msg
        end

        pending = pending - 1
        if pending > 0 then
          return
        end

        if #items > 0 then
          open_quickfix("pinwords grep", sort_and_dedup_items(items))
        elseif err_msg then
          vim.notify("pinwords: grep failed: " .. err_msg, vim.log.levels.WARN)
        else
          vim.notify("pinwords: grep found no matches", vim.log.levels.INFO)
        end
      end)
    end)
  end

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

---Run fallback grep for already-resolved entries using ripgrep when available,
---then `git grep`, then Vim's vimgrep.
---@param entries PinwordsGrepEntry[]
---@param id integer  run id claimed by the caller before it resolved entries
local function run_fallback_grep(entries, id)
  local rg_pattern = build_rg_pattern_from_entries(entries)
  if rg_pattern and try_rg_fallback(rg_pattern, entries, id) then
    return
  end

  -- ripgrep is unavailable; delegate to an asynchronous `git grep` so large
  -- repositories no longer freeze the UI the way a synchronous vimgrep does.
  if try_git_grep_fallback(entries, id) then
    return
  end

  local vim_pattern = build_vim_pattern_from_entries(entries)
  if not vim_pattern then
    return
  end

  -- Neither ripgrep nor git is available, so fall back to Vim's synchronous
  -- vimgrep. It walks the project tree in-process, so warn before the UI
  -- freezes; wildignore is extended to skip VCS metadata and build outputs.
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

---Run fallback grep using ripgrep when available, then Vim's vimgrep.
---@param slots table<integer, PinwordsSlot>
---@param slot? integer
function M._fallback_grep(slots, slot)
  local id = next_run_id()
  local entries = resolve_search_entries("grep", slots, slot)
  if not entries then
    return
  end
  run_fallback_grep(entries, id)
end

---Invalidate in-flight searches so their completion callbacks no longer touch
---the quickfix list.
---@return nil
function M.teardown()
  next_run_id()
end

---Run grep via the best available picker backend.
---@param opts? { slot?: integer }
function M.grep(opts)
  opts = opts or {}
  -- Claim a run id up front: any search supersedes an in-flight fallback, even
  -- when this one ends in a picker or without pinned words.
  local id = next_run_id()
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

  -- Fallback: vimgrep to quickfix. Entries are already resolved, so reuse them
  -- instead of resolving again and repeating the multi-line skip warning.
  run_fallback_grep(entries, id)
end

---Run live_grep via the best available picker backend.
---@param opts? { slot?: integer }
function M.live_grep(opts)
  opts = opts or {}
  local id = next_run_id()
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

  -- Fallback: vimgrep to quickfix. Entries are already resolved, so reuse them
  -- instead of resolving again and repeating the multi-line skip warning.
  run_fallback_grep(entries, id)
end

return M
