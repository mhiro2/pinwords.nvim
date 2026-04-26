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

--- Search direct children of a node for an identifier.
---@param node TSNode
---@param bufnr integer
---@return string|nil
local function find_symbol_in_children(node, bufnr)
  for child in node:iter_children() do
    if child:named() and SYMBOL_NODE_TYPES[child:type()] then
      return get_symbol_text(child, bufnr)
    end
  end
  return nil
end

--- Check whether a Treesitter parser exists for the buffer.
--- Uses pcall because get_parser raises for filetypes without a registered parser.
---@param bufnr integer
---@return boolean
function M.has_parser(bufnr)
  local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
  return ok and parser ~= nil
end

--- Get the symbol name at the cursor position using Treesitter.
---
--- Traversal is limited to the cursor node and its immediate parent to avoid
--- extracting identifiers that are unrelated to the cursor position (e.g.,
--- a function name when cursor is on a string argument).
---
--- Returns nil if no parser or no symbol found (caller should fallback to cword).
---@param bufnr? integer
---@param winnr? integer
---@return string|nil
function M.get_symbol_at_cursor(bufnr, winnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  winnr = winnr or vim.api.nvim_get_current_win()

  if not M.has_parser(bufnr) then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(winnr)
  local row, col = cursor[1] - 1, cursor[2]

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = bufnr, pos = { row, col } })
  if not ok or not node then
    return nil
  end

  -- 1. Cursor is directly on an identifier node
  if SYMBOL_NODE_TYPES[node:type()] then
    return get_symbol_text(node, bufnr)
  end

  -- 2. Check children of the cursor node (e.g., keyword node with identifier child)
  local child_text = find_symbol_in_children(node, bufnr)
  if child_text then
    return child_text
  end

  -- 3. Check parent: it may be an identifier, or its children include one
  --    (e.g., cursor on keyword, identifier is a sibling under the parent)
  local parent = node:parent()
  if not parent then
    return nil
  end

  if SYMBOL_NODE_TYPES[parent:type()] then
    return get_symbol_text(parent, bufnr)
  end

  return find_symbol_in_children(parent, bufnr)
end

return M
