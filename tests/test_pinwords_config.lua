local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

T["setup validates options and never errors"] = function()
  local pinwords = require("pinwords")
  local orig_notify = vim.notify
  local notified = {}
  vim.notify = function(msg, level, opts)
    table.insert(notified, { msg = msg, level = level, opts = opts })
  end

  local ok = pcall(pinwords.setup, {
    slots = "9",
    whole_word = "yes",
    case_sensitive = 1,
    auto_allocation = {
      strategy = "unknown",
      on_full = "unknown",
      toggle_same = "yes",
    },
  })

  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)
  MiniTest.expect.equality(#notified > 0, true)

  -- It should still work after invalid setup.
  helpers.setup_buffer({ "foo bar", "baz" })
  ok = pcall(pinwords.set, 1)
  MiniTest.expect.equality(ok, true)
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

T["setup validates colors with hex string"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  helpers.clear_hl("PinWord1")
  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = "#ff0000",
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)
  -- No warnings for valid hex
  local has_color_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("colors") then
      has_color_warning = true
    end
  end
  MiniTest.expect.equality(has_color_warning, false)

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

T["setup validates colors table with bg"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  helpers.clear_hl("PinWord1")
  local ok = pcall(pinwords.setup, {
    colors = {
      [1] = { bg = "#00ff00", fg = "#000000" },
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_color_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("colors") then
      has_color_warning = true
    end
  end
  MiniTest.expect.equality(has_color_warning, false)

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

T["setup validates cword color"] = function()
  local pinwords = require("pinwords")
  local notified = {}
  local orig_notify = vim.notify
  vim.notify = function(msg, level, _opts)
    table.insert(notified, { msg = msg, level = level })
  end

  helpers.clear_hl("PinWordCword")
  local ok = pcall(pinwords.setup, {
    colors = {
      cword = "#ffff00",
    },
  })
  vim.notify = orig_notify

  MiniTest.expect.equality(ok, true)

  local has_color_warning = false
  for _, n in ipairs(notified) do
    if n.msg:match("cword") and n.msg:match("hex") then
      has_color_warning = true
    end
  end
  MiniTest.expect.equality(has_color_warning, false)

  helpers.clear_hl("PinWordCword")
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

T["setup validates flash config values"] = function()
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, {
      flash = {
        enabled = "yes",
        timeout_ms = 0,
        hl_group = 1,
        priority = 1.5,
      },
    })
    MiniTest.expect.equality(ok, true)

    local has_warning = false
    for _, n in ipairs(notified) do
      if n.msg:match("flash%.") then
        has_warning = true
      end
    end
    MiniTest.expect.equality(has_warning, true)
  end)
end

T["setup with non-table opts does not crash"] = function()
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, "invalid")
    MiniTest.expect.equality(ok, true)

    local has_warning = false
    for _, n in ipairs(notified) do
      if n.msg:match("setup opts must be a table") then
        has_warning = true
      end
    end
    MiniTest.expect.equality(has_warning, true)
  end)

  -- Should still work after invalid setup
  helpers.setup_buffer({ "foo bar" })
  local ok = pcall(pinwords.set, 1)
  MiniTest.expect.equality(ok, true)
end

T["setup with numeric opts does not crash"] = function()
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, 42)
    MiniTest.expect.equality(ok, true)

    local has_warning = false
    for _, n in ipairs(notified) do
      if n.msg:match("setup opts must be a table") then
        has_warning = true
      end
    end
    MiniTest.expect.equality(has_warning, true)
  end)
end

T["setup with boolean opts does not crash"] = function()
  local pinwords = require("pinwords")

  helpers.with_notify_override(function(notified)
    local ok = pcall(pinwords.setup, true)
    MiniTest.expect.equality(ok, true)

    local has_warning = false
    for _, n in ipairs(notified) do
      if n.msg:match("setup opts must be a table") then
        has_warning = true
      end
    end
    MiniTest.expect.equality(has_warning, true)
  end)
end

return T
