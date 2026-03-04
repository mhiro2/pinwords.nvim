local M = {}

---@class PinwordsHealthReporter
---@field start fun(msg: string)
---@field ok fun(msg: string)
---@field warn fun(msg: string)
---@field error fun(msg: string)
---@field info fun(msg: string)

---@class PinwordsHealthContext
---@field pinwords? table
---@field require_fn? fun(module_name: string): any
---@field reporter? PinwordsHealthReporter

local valid_strategy = {
  first_empty = true,
  cycle = true,
  lru = true,
}

local valid_on_full = {
  replace_oldest = true,
  replace_last = true,
  no_op = true,
}

---@param value any
---@return boolean
local function is_integer(value)
  return type(value) == "number" and value % 1 == 0
end

---@param value any
---@return boolean
local function is_positive_integer(value)
  return is_integer(value) and value >= 1
end

---@param value any
---@return boolean
local function is_valid_hex(value)
  return type(value) == "string" and value:match("^#%x%x%x%x%x%x$") ~= nil
end

---@param errors string[]
---@param msg string
---@return nil
local function add_error(errors, msg)
  errors[#errors + 1] = msg
end

---@param errors string[]
---@param colors any
---@return nil
local function validate_colors(errors, colors)
  if colors == nil then
    return
  end

  if type(colors) ~= "table" then
    add_error(errors, "colors must be a table or nil")
    return
  end

  for key, value in pairs(colors) do
    local key_ok = key == "cword" or (type(key) == "number" and is_positive_integer(key))
    if not key_ok then
      add_error(errors, "colors keys must be positive integers or 'cword'")
    else
      if type(value) == "string" then
        if not is_valid_hex(value) then
          add_error(errors, "colors entries must use #RRGGBB when string")
        end
      elseif type(value) == "table" then
        if value.bg ~= nil and not is_valid_hex(value.bg) then
          add_error(errors, "colors entry bg must be #RRGGBB")
        end
        if value.fg ~= nil and not is_valid_hex(value.fg) then
          add_error(errors, "colors entry fg must be #RRGGBB")
        end
      else
        add_error(errors, "colors entries must be string or table")
      end
    end
  end
end

---@param errors string[]
---@param cfg any
---@return nil
local function validate_config(errors, cfg)
  if type(cfg) ~= "table" then
    add_error(errors, "config must be a table")
    return
  end

  if not is_positive_integer(cfg.slots) then
    add_error(errors, "slots must be a positive integer")
  end

  if type(cfg.whole_word) ~= "boolean" then
    add_error(errors, "whole_word must be boolean")
  end
  if type(cfg.case_sensitive) ~= "boolean" then
    add_error(errors, "case_sensitive must be boolean")
  end

  if type(cfg.auto_allocation) ~= "table" then
    add_error(errors, "auto_allocation must be a table")
  else
    if not valid_strategy[cfg.auto_allocation.strategy] then
      add_error(errors, "auto_allocation.strategy must be one of: first_empty, cycle, lru")
    end
    if not valid_on_full[cfg.auto_allocation.on_full] then
      add_error(errors, "auto_allocation.on_full must be one of: replace_oldest, replace_last, no_op")
    end
    if type(cfg.auto_allocation.toggle_same) ~= "boolean" then
      add_error(errors, "auto_allocation.toggle_same must be boolean")
    end
  end

  local picker_keys = { "telescope", "snacks", "fzf_lua" }
  for _, key in ipairs(picker_keys) do
    local picker_cfg = cfg[key]
    if type(picker_cfg) ~= "table" then
      add_error(errors, key .. " must be a table")
    elseif type(picker_cfg.enabled) ~= "boolean" then
      add_error(errors, key .. ".enabled must be boolean")
    end
  end

  if type(cfg.flash) ~= "table" then
    add_error(errors, "flash must be a table")
  else
    if type(cfg.flash.enabled) ~= "boolean" then
      add_error(errors, "flash.enabled must be boolean")
    end
    if not is_positive_integer(cfg.flash.timeout_ms) then
      add_error(errors, "flash.timeout_ms must be a positive integer")
    end
    if type(cfg.flash.hl_group) ~= "string" or cfg.flash.hl_group == "" then
      add_error(errors, "flash.hl_group must be a non-empty string")
    end
    if not is_integer(cfg.flash.priority) then
      add_error(errors, "flash.priority must be an integer")
    end
  end

  validate_colors(errors, cfg.colors)
end

---@param require_fn fun(module_name: string): any
---@param module_name string
---@return boolean, any
local function try_require(require_fn, module_name)
  return pcall(require_fn, module_name)
end

---@param reporter PinwordsHealthReporter
---@param require_fn fun(module_name: string): any
---@param enabled boolean
---@param label string
---@param module_name string
---@param validator? fun(module: any): boolean
---@return nil
local function check_optional_dependency(reporter, require_fn, enabled, label, module_name, validator)
  if not enabled then
    reporter.info(label .. ": disabled")
    return
  end

  local ok, mod = try_require(require_fn, module_name)
  if not ok then
    reporter.warn(label .. ".enabled is true but module '" .. module_name .. "' is not available")
    return
  end

  if validator and not validator(mod) then
    reporter.warn(label .. " is available but required API is missing")
    return
  end

  reporter.ok(label .. ": available")
end

---@param ctx? PinwordsHealthContext
---@return nil
function M.check(ctx)
  ctx = ctx or {}
  local reporter = ctx.reporter or vim.health
  local require_fn = ctx.require_fn or require

  reporter.start("pinwords.nvim")

  local pinwords = ctx.pinwords
  if not pinwords then
    local ok, mod = try_require(require_fn, "pinwords")
    if not ok or type(mod) ~= "table" then
      reporter.error("failed to load pinwords module")
      return
    end
    pinwords = mod
  end

  local cfg = {}
  if type(pinwords.get_config) == "function" then
    local ok, loaded = pcall(pinwords.get_config)
    if ok and type(loaded) == "table" then
      cfg = loaded
    else
      reporter.error("failed to read active config from pinwords.get_config()")
      return
    end
  else
    reporter.error("pinwords.get_config() is not available")
    return
  end

  reporter.start("Configuration")
  local config_errors = {}
  validate_config(config_errors, cfg)
  if #config_errors == 0 then
    reporter.ok("configuration values are valid")
  else
    for _, msg in ipairs(config_errors) do
      reporter.error(msg)
    end
  end

  reporter.start("Picker Integrations")
  local telescope_enabled = type(cfg.telescope) == "table" and cfg.telescope.enabled == true
  local snacks_enabled = type(cfg.snacks) == "table" and cfg.snacks.enabled == true
  local fzf_enabled = type(cfg.fzf_lua) == "table" and cfg.fzf_lua.enabled == true

  check_optional_dependency(reporter, require_fn, telescope_enabled, "telescope", "telescope")
  check_optional_dependency(reporter, require_fn, snacks_enabled, "snacks", "snacks", function(mod)
    return type(mod) == "table" and type(mod.picker) == "table"
  end)
  check_optional_dependency(reporter, require_fn, fzf_enabled, "fzf_lua", "fzf-lua", function(mod)
    return type(mod) == "table" and type(mod.fzf_exec) == "function"
  end)
end

return M
