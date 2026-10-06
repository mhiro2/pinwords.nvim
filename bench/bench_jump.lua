local h = require("bench.bench_helpers")
local jump = require("pinwords.jump")
local matcher = require("pinwords.matcher")
local state = require("pinwords.state")

local M = {}

local LARGE_LINES = 100000

---@param words { raw: string, case_sensitive: boolean }[]
local function pin_words(words)
  for i, word in ipairs(words) do
    state.set_slot(i, {
      raw = word.raw,
      pattern = (word.case_sensitive and "\\V\\C\\<" or "\\V\\c\\<") .. word.raw .. "\\>",
      hl_group = "PinWord" .. i,
      case_sensitive = word.case_sensitive,
    })
    state.touch_slot(i)
  end
  state.flush_sync()
end

---Fill the buffer with filler text and put "target" on the given lines only.
---@param target_lines integer[]
local function setup_large_buffer(target_lines)
  local lines = {}
  for i = 1, LARGE_LINES do
    lines[i] = "lorem ipsum dolor sit amet consectetur line" .. i
  end
  for _, lnum in ipairs(target_lines) do
    lines[lnum] = "lorem target ipsum"
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
end

---@param name string
---@param target_lines integer[]
---@param words { raw: string, case_sensitive: boolean }[]
---@param cursor integer[]
---@param jump_fn fun()
---@return { name: string, stats: table }
local function bench_large(name, target_lines, words, cursor, jump_fn)
  h.teardown()
  require("pinwords").setup({})
  setup_large_buffer(target_lines)
  pin_words(words)

  local stats = h.measure(function()
    vim.api.nvim_win_set_cursor(0, cursor)
    jump_fn()
  end, 20)

  return { name = name, stats = stats }
end

function M.run()
  local results = {}

  for _, num_slots in ipairs({ 1, 5, 9 }) do
    h.teardown()
    require("pinwords").setup({ slots = num_slots })
    h.setup_buffer_with_content()
    h.fill_slots(num_slots)
    local win = vim.api.nvim_get_current_win()
    matcher.reapply_all_for_window(win)
    vim.api.nvim_win_set_cursor(0, { 1, 0 })

    local stats = h.measure(function()
      jump.next()
    end, 100)

    table.insert(results, {
      name = string.format("jump.next  slots=%d", num_slots),
      stats = stats,
    })
  end

  -- Scenarios on a large buffer: these are dominated by how much of the
  -- buffer each search scans, not by per-call overhead.
  local orig_notify = vim.notify
  vim.notify = function() end

  local target = { raw = "target", case_sensitive = false }
  -- A case-sensitive hit plus a case-insensitive miss lands in two search
  -- groups, so the miss must not force a scan of the whole buffer.
  local target_cs = { raw = "target", case_sensitive = true }
  local missing = { raw = "missing", case_sensitive = false }
  local large = string.format("%dk", LARGE_LINES / 1000)

  table.insert(results, bench_large("jump.next  " .. large .. " near", { 2 }, { target }, { 1, 0 }, jump.next))
  table.insert(
    results,
    bench_large("jump.next  " .. large .. " near +missing", { 2 }, { target_cs, missing }, { 1, 0 }, jump.next)
  )
  table.insert(
    results,
    bench_large("jump.prev  " .. large .. " near +missing", { LARGE_LINES - 1 }, {
      target_cs,
      missing,
    }, { LARGE_LINES, 0 }, jump.prev)
  )
  table.insert(
    results,
    bench_large("jump.next  " .. large .. " sparse", { LARGE_LINES / 2 }, { target }, { 1, 0 }, jump.next)
  )
  table.insert(results, bench_large("jump.next  " .. large .. " wrap", { 2 }, { target }, { 3, 0 }, jump.next))
  table.insert(results, bench_large("jump.next  " .. large .. " no match", {}, { target }, { 1, 0 }, jump.next))

  vim.notify = orig_notify
  h.teardown()
  return results
end

return M
