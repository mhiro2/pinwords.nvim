---@class PinwordsSymbol
local M = {}

--- Node types considered meaningful symbol identifiers.
--- Language-agnostic: nearly all Treesitter grammars use these.
local SYMBOL_NODE_TYPES = {
  identifier = true,
  type_identifier = true,
  field_identifier = true,
  property_identifier = true,
  shorthand_property_identifier = true,
  shorthand_property_identifier_pattern = true,
}

---@param node TSNode
---@param bufnr integer
---@return string|nil
local function get_symbol_text(node, bufnr)
  local ok, text = pcall(vim.treesitter.get_node_text, node, bufnr)
  if ok and type(text) == "string" and text ~= "" then
    return text
  end
  return nil
end

--- Resolve the name of a declaration node. Most grammars keep it in a `name`
--- field; C-like grammars nest it in a chain of `declarator` fields instead
--- (`typedef int Foo;`). A qualified name such as `M.method` resolves to its
--- last identifier.
---@param node TSNode
---@param bufnr integer
---@return string|nil
local function find_declared_name(node, bufnr)
  local name = node:field("name")[1]
  if not name then
    local declarator = node:field("declarator")[1]
    while declarator and not SYMBOL_NODE_TYPES[declarator:type()] do
      declarator = declarator:field("declarator")[1]
    end
    name = declarator
  end
  if not name then
    return nil
  end
  if SYMBOL_NODE_TYPES[name:type()] then
    return get_symbol_text(name, bufnr)
  end

  for i = name:named_child_count() - 1, 0, -1 do
    local child = name:named_child(i)
    if child and SYMBOL_NODE_TYPES[child:type()] then
      return get_symbol_text(child, bufnr)
    end
  end
  return nil
end

---@param bufnr integer
---@return vim.treesitter.LanguageTree|nil
local function get_parser(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  if ok then
    return parser
  end
  return nil
end

--- Check whether a Treesitter parser exists for the buffer.
--- Uses pcall because get_parser raises for filetypes without a registered parser.
---@param bufnr integer
---@return boolean
function M.has_parser(bufnr)
  return get_parser(bufnr) ~= nil
end

--- Get the symbol name at the cursor position using Treesitter.
---
--- Only the cursor node, the name declared by that node, and an identifier
--- parent are considered. Sibling identifiers are never used, so a cursor on a
--- literal or comment does not pick up an unrelated name next to it.
---
--- Returns nil if no parser or no symbol found (caller should fallback to cword).
---@param bufnr? integer
---@param winnr? integer
---@return string|nil
function M.get_symbol_at_cursor(bufnr, winnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winnr = winnr or vim.api.nvim_get_current_win()

  local parser = get_parser(bufnr)
  if not parser then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local row, col = cursor[1] - 1, cursor[2]

  -- A buffer without an active highlighter has never been parsed, and
  -- get_node() finds no tree until it is. The range also limits which
  -- injected languages are parsed.
  pcall(function()
    parser:parse({ row, row + 1 })
  end)

  -- Look inside injected languages too, e.g. a code block in Markdown.
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col }, ignore_injections = false })
  if not ok or not node then
    return nil
  end

  -- 1. Cursor is directly on an identifier node
  if SYMBOL_NODE_TYPES[node:type()] then
    return get_symbol_text(node, bufnr)
  end

  -- 2. Cursor is on a keyword of a declaration (e.g., `function` in
  --    `local function name()`); the smallest named node is the declaration.
  local declared = find_declared_name(node, bufnr)
  if declared then
    return declared
  end

  -- 3. Cursor is inside an identifier that has anonymous children
  local parent = node:parent()
  if parent and SYMBOL_NODE_TYPES[parent:type()] then
    return get_symbol_text(parent, bufnr)
  end

  return nil
end

return M
