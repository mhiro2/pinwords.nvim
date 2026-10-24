local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

---@param tbl table
---@param path string[]
---@return any
local function get_path(tbl, path)
  local value = tbl
  for _, key in ipairs(path) do
    value = value[key]
  end
  return value
end

---Run setup with opts and assert it emits exactly the expected warnings and leaves the
---listed config fields at the expected values.
---@param opts any
---@param warnings string[]
---@param expected table<string, any> dotted config path => value
local function expect_sanitized(opts, warnings, expected)
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, opts)
    MiniTest.expect.equality(ok, true)

    local messages = {}
    for _, n in ipairs(notified) do
      MiniTest.expect.equality(n.level, vim.log.levels.WARN)
      messages[#messages + 1] = n.msg
    end
    local expected_messages = {}
    for _, warning in ipairs(warnings) do
      expected_messages[#expected_messages + 1] = "pinwords: " .. warning
    end
    MiniTest.expect.equality(messages, expected_messages)
  end)

  local cfg = pinwords.get_config()
  for path, value in pairs(expected) do
    MiniTest.expect.equality(get_path(cfg, vim.split(path, ".", { plain = true })), value)
  end
end

T["setup falls back to the default for each invalid option"] = function()
  local cases = {
    {
      opts = { slots = "9", whole_word = false },
      warning = "slots must be a positive integer; fallback to default",
      expected = { slots = 9, whole_word = false },
    },
    {
      opts = { slots = 0, case_sensitive = true },
      warning = "slots must be a positive integer; fallback to default",
      expected = { slots = 9, case_sensitive = true },
    },
    {
      opts = { whole_word = "yes", slots = 4 },
      warning = "whole_word must be boolean; fallback to default",
      expected = { whole_word = true, slots = 4 },
    },
    {
      opts = { case_sensitive = 1, slots = 4 },
      warning = "case_sensitive must be boolean; fallback to default",
      expected = { case_sensitive = false, slots = 4 },
    },
    {
      opts = { auto_allocation = { strategy = "unknown", on_full = "no_op" } },
      warning = "auto_allocation.strategy must be one of: first_empty, cycle, lru; fallback to default",
      expected = { ["auto_allocation.strategy"] = "first_empty", ["auto_allocation.on_full"] = "no_op" },
    },
    {
      opts = { auto_allocation = { on_full = "unknown", strategy = "lru" } },
      warning = "auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op; fallback to default",
      expected = { ["auto_allocation.on_full"] = "replace_oldest", ["auto_allocation.strategy"] = "lru" },
    },
    {
      opts = { auto_allocation = { toggle_same = "yes", strategy = "cycle" } },
      warning = "auto_allocation.toggle_same must be boolean; fallback to default",
      expected = { ["auto_allocation.toggle_same"] = true, ["auto_allocation.strategy"] = "cycle" },
    },
  }

  for _, case in ipairs(cases) do
    expect_sanitized(case.opts, { case.warning }, case.expected)
  end
end

T["setup with fewer slots prunes existing slots and matches"] = function()
  helpers.setup_buffer({ "foo bar baz" })

  local pinwords = require("pinwords")
  pinwords.set(3)

  MiniTest.expect.equality(helpers.find_match("PinWord3") ~= nil, true)

  pinwords.setup({ slots = 2 })

  local slots = pinwords.list()
  MiniTest.expect.equality(slots[3], nil)
  MiniTest.expect.equality(helpers.find_match("PinWord3"), nil)
end

T["setup keeps a valid hex slot color and applies it"] = function()
  helpers.clear_hl("PinWord1")
  helpers.with_normal_bg(0x000000, function()
    expect_sanitized({ colors = { [1] = "#ff0000" } }, {}, { colors = { [1] = "#ff0000" } })

    -- #ff0000 blended half-way into the black Normal background.
    local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
    MiniTest.expect.equality(hl.bg, 0x800000)
  end)
  helpers.clear_hl("PinWord1")
end

T["setup warns on invalid hex color"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = "invalid",
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_color_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("valid hex color") then
      has_color_warning = true
    end
  end
  MiniTest.expect.equality(has_color_warning, true)
end

T["setup keeps a valid bg and fg color table and applies it"] = function()
  helpers.clear_hl("PinWord1")
  local color = { bg = "#00ff00", fg = "#000000" }
  expect_sanitized({ colors = { [1] = color } }, {}, { colors = { [1] = color } })

  -- An explicit fg disables blending, so bg is applied as given.
  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.bg, 0x00ff00)
  MiniTest.expect.equality(hl.fg, 0x000000)
  helpers.clear_hl("PinWord1")
end

T["setup warns on invalid bg in table"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = { bg = "bad" },
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("%.bg must be a valid hex") then
      has_warning = true
    end
  end
  MiniTest.expect.equality(has_warning, true)
end

T["setup warns on invalid fg in table"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = { bg = "#ff0000", fg = "bad" },
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("%.fg must be a valid hex") then
      has_warning = true
    end
  end
  MiniTest.expect.equality(has_warning, true)
end

T["setup warns on invalid sp in table"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = { sp = "bad", underline = true },
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("%.sp must be a valid hex") then
      has_warning = true
    end
  end
  MiniTest.expect.equality(has_warning, true)
end

T["setup keeps a valid sp in table and applies it"] = function()
  helpers.clear_hl("PinWord1")
  local color = { sp = "#ff0000", undercurl = true }
  expect_sanitized({ colors = { [1] = color } }, {}, { colors = { [1] = color } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.sp, 0xff0000)
  MiniTest.expect.equality(hl.undercurl, true)
  helpers.clear_hl("PinWord1")
end

T["setup keeps a valid cword color and applies it"] = function()
  helpers.clear_hl("PinWordCword")
  helpers.with_normal_bg(0x000000, function()
    expect_sanitized({ colors = { cword = "#ffff00" } }, {}, { colors = { cword = "#ffff00" } })

    local hl = vim.api.nvim_get_hl(0, { name = "PinWordCword", link = false })
    MiniTest.expect.equality(hl.bg, 0x808000)
  end)
  helpers.clear_hl("PinWordCword")
end

local function setup_capturing_warnings(opts)
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end
  local ok = pcall(pinwords.setup, opts)
  vim.notify = orig_notify
  MiniTest.expect.equality(ok, true)
  return notified
end

local function notified_matches(notified, pattern)
  for _, n in ipairs(notified) do
    if n.msg:match(pattern) then
      return true
    end
  end
  return false
end

T["setup warns on non-boolean style attribute"] = function()
  helpers.clear_hl("PinWord1")
  local notified = setup_capturing_warnings({
    colors = { [1] = { bg = "#ff0000", bold = "yes" } },
  })
  MiniTest.expect.equality(notified_matches(notified, "colors%[1%]%.bold must be a boolean"), true)
  helpers.clear_hl("PinWord1")
end

T["setup warns on out-of-range ctermbg"] = function()
  helpers.clear_hl("PinWord1")
  local notified = setup_capturing_warnings({
    colors = { [1] = { ctermbg = 256 } },
  })
  MiniTest.expect.equality(
    notified_matches(notified, "colors%[1%]%.ctermbg must be an integer between 0 and 255"),
    true
  )
  helpers.clear_hl("PinWord1")
end

T["setup warns on non-integer ctermfg"] = function()
  helpers.clear_hl("PinWord1")
  local notified = setup_capturing_warnings({
    colors = { [1] = { ctermfg = 1.5 } },
  })
  MiniTest.expect.equality(
    notified_matches(notified, "colors%[1%]%.ctermfg must be an integer between 0 and 255"),
    true
  )
  helpers.clear_hl("PinWord1")
end

T["setup keeps boundary cterm colors and false style booleans"] = function()
  helpers.clear_hl("PinWord1")
  local color = { ctermbg = 0, ctermfg = 255, bold = true, underline = false }
  expect_sanitized({ colors = { [1] = color } }, {}, { colors = { [1] = color } })

  local hl = vim.api.nvim_get_hl(0, { name = "PinWord1", link = false })
  MiniTest.expect.equality(hl.ctermbg, 0)
  MiniTest.expect.equality(hl.ctermfg, 255)
  MiniTest.expect.equality(hl.bold, true)
  MiniTest.expect.equality(hl.underline, nil)
  helpers.clear_hl("PinWord1")
end

T["validate rejects invalid style and cterm values"] = function()
  local config = require("pinwords.config")
  local cfg = config.default_config()
  cfg.colors = { [1] = { bold = "yes" }, [2] = { ctermbg = 300 } }

  local errors = config.validate(cfg)
  local joined = table.concat(errors, "\n")
  MiniTest.expect.equality(joined:match("bold must be a boolean") ~= nil, true)
  MiniTest.expect.equality(joined:match("ctermbg must be an integer between 0 and 255") ~= nil, true)
end

T["setup warns on non-table colors"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  local ok = pcall(pinwords.setup, {
    colors = "invalid",
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("colors must be a table") then
      has_warning = true
    end
  end
  MiniTest.expect.equality(has_warning, true)
end

T["setup falls back to the default for each invalid flash option"] = function()
  local cases = {
    {
      flash = { enabled = "yes", timeout_ms = 10 },
      warning = "flash.enabled must be boolean; fallback to default",
      expected = { ["flash.enabled"] = true, ["flash.timeout_ms"] = 10 },
    },
    {
      flash = { timeout_ms = -1, enabled = false },
      warning = "flash.timeout_ms must be a non-negative integer; fallback to default",
      expected = { ["flash.timeout_ms"] = 120, ["flash.enabled"] = false },
    },
    {
      flash = { timeout_ms = 1.5, priority = 10 },
      warning = "flash.timeout_ms must be a non-negative integer; fallback to default",
      expected = { ["flash.timeout_ms"] = 120, ["flash.priority"] = 10 },
    },
    {
      flash = { hl_group = 1, priority = 10 },
      warning = "flash.hl_group must be a non-empty string; fallback to default",
      expected = { ["flash.hl_group"] = "PinWordFlash", ["flash.priority"] = 10 },
    },
    {
      flash = { hl_group = "", timeout_ms = 10 },
      warning = "flash.hl_group must be a non-empty string; fallback to default",
      expected = { ["flash.hl_group"] = "PinWordFlash", ["flash.timeout_ms"] = 10 },
    },
    {
      flash = { priority = 1.5, hl_group = "Search" },
      warning = "flash.priority must be an integer; fallback to default",
      expected = { ["flash.priority"] = 250, ["flash.hl_group"] = "Search" },
    },
  }

  for _, case in ipairs(cases) do
    expect_sanitized({ flash = case.flash }, { case.warning }, case.expected)
  end
end

T["setup accepts flash timeout_ms zero"] = function()
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, {
      flash = {
        timeout_ms = 0,
      },
    })

    MiniTest.expect.equality(ok, true)
    MiniTest.expect.equality(#notified, 0)
  end)

  MiniTest.expect.equality(pinwords.get_config().flash.timeout_ms, 0)
end

T["setup with non-table opts falls back to the default config"] = function()
  local pinwords = require("pinwords")
  local defaults = require("pinwords.config").default_config()

  for _, opts in ipairs({ "invalid", 42, true }) do
    expect_sanitized(opts, { "setup opts must be a table; fallback to default" }, {})
    MiniTest.expect.equality(pinwords.get_config(), defaults)

    helpers.setup_buffer({ "foo bar" })
    pinwords.set(1)
    MiniTest.expect.equality(pinwords.list()[1].pattern, "\\V\\c\\<foo\\>")
    MiniTest.expect.equality(helpers.find_match("PinWord1").pattern, "\\V\\c\\<foo\\>")
    pinwords.clear_all()
  end
end

return T
