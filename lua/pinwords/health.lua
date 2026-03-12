local M = {}
local config_module = require("pinwords.config")

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
  local config_errors = config_module.validate(cfg)
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
