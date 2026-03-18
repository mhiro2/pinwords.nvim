local MiniTest = require("mini.test")
local helpers = require("tests.test_helpers")

local T = helpers.create_test_set()

---@return table, table<string, string[]>
local function new_reporter()
  local calls = {
    start = {},
    ok = {},
    warn = {},
    error = {},
    info = {},
  }

  local reporter = {}
  for kind in pairs(calls) do
    reporter[kind] = function(msg)
      table.insert(calls[kind], msg)
    end
  end

  return reporter, calls
end

---@param messages string[]
---@param needle string
---@return boolean
local function has_message(messages, needle)
  for _, msg in ipairs(messages) do
    if msg:find(needle, 1, true) then
      return true
    end
  end
  return false
end

---@return table
local function valid_config()
  return {
    slots = 9,
    whole_word = true,
    case_sensitive = false,
    auto_allocation = {
      strategy = "first_empty",
      on_full = "replace_oldest",
      toggle_same = true,
    },
    flash = {
      enabled = true,
      timeout_ms = 120,
      hl_group = "PinWordFlash",
      priority = 250,
    },
    telescope = { enabled = false },
    snacks = { enabled = false },
    fzf_lua = { enabled = false },
    colors = nil,
  }
end

T["health.check reports valid config"] = function()
  local pinwords = require("pinwords")
  pinwords.setup({})

  local reporter, calls = new_reporter()
  require("pinwords.health").check({
    pinwords = pinwords,
    reporter = reporter,
    require_fn = require,
  })

  MiniTest.expect.equality(#calls.error, 0)
  MiniTest.expect.equality(has_message(calls.ok, "configuration values are valid"), true)
  MiniTest.expect.equality(has_message(calls.info, "telescope: disabled"), true)
  MiniTest.expect.equality(has_message(calls.info, "snacks: disabled"), true)
  MiniTest.expect.equality(has_message(calls.info, "fzf_lua: disabled"), true)
end

T["health.check reports picker dependency issues"] = function()
  local cfg = valid_config()
  cfg.telescope.enabled = true
  cfg.snacks.enabled = true
  cfg.fzf_lua.enabled = true

  local reporter, calls = new_reporter()
  require("pinwords.health").check({
    pinwords = {
      get_config = function()
        return cfg
      end,
    },
    reporter = reporter,
    require_fn = function(module_name)
      if module_name == "telescope" then
        error("missing telescope")
      end
      if module_name == "snacks" then
        return {}
      end
      if module_name == "fzf-lua" then
        return {}
      end
      return require(module_name)
    end,
  })

  MiniTest.expect.equality(has_message(calls.warn, "telescope.enabled is true"), true)
  MiniTest.expect.equality(has_message(calls.warn, "snacks is available but required API is missing"), true)
  MiniTest.expect.equality(has_message(calls.warn, "fzf_lua is available but required API is missing"), true)
end

T["health.check reports invalid config values"] = function()
  local cfg = valid_config()
  cfg.slots = 0
  cfg.flash.timeout_ms = -1
  cfg.auto_allocation.strategy = "invalid"

  local reporter, calls = new_reporter()
  require("pinwords.health").check({
    pinwords = {
      get_config = function()
        return cfg
      end,
    },
    reporter = reporter,
    require_fn = require,
  })

  MiniTest.expect.equality(has_message(calls.error, "slots must be a positive integer"), true)
  MiniTest.expect.equality(has_message(calls.error, "auto_allocation.strategy must be one of"), true)
  MiniTest.expect.equality(has_message(calls.error, "flash.timeout_ms must be a non-negative integer"), true)
end

return T
