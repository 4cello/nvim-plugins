local M = {}

local ts = vim.treesitter
local api = vim.api

local function source_directory()
  local source = debug.getinfo(1, "S").source:sub(2)
  return vim.fn.fnamemodify(source, ":p:h")
end

local defaults = {
  languages = dofile(source_directory() .. "/languages/init.lua"),
}

local config = vim.deepcopy(defaults)

local function node_text(node, bufnr)
  return ts.get_node_text(node, bufnr)
end

local function language_for_filetype(filetype)
  for _, language in ipairs(config.languages) do
    for _, supported_filetype in ipairs(language.filetypes) do
      if supported_filetype == filetype then
        return language
      end
    end
  end
end

local function find_enclosing_container(node, language)
  while node do
    local container = language.containers[node:type()]
    if container then
      return node, container
    end

    node = node:parent()
  end
end

local function direct_entries(container, container_spec)
  local entries = container_spec.entries
  local allowed_set

  if entries ~= true then
    allowed_set = {}
    for _, name in ipairs(entries) do
      allowed_set[name] = true
    end
  end

  local result = {}

  for child in container:iter_children() do
    if child:named()
      and child:type() ~= "comment"
      and (entries == true or allowed_set[child:type()])
    then
      table.insert(result, child)
    end
  end

  return result
end

local function entry_key(entry, bufnr, container_spec)
  local key = container_spec.key

  if type(key) == "function" then
    return key(entry, bufnr)
  end

  if type(key) == "string" then
    local key_node = entry:field(key)[1]
    if key_node then
      return node_text(key_node, bufnr)
    end
  end

  return node_text(entry, bufnr)
end

local function sort_entries(entries, bufnr, container_spec)
  local decorated = {}

  for i, entry in ipairs(entries) do
    table.insert(decorated, {
      node = entry,
      key = entry_key(entry, bufnr, container_spec),
      index = i,
    })
  end

  table.sort(decorated, function(a, b)
    if a.key == b.key then
      return a.index < b.index
    end

    return a.key < b.key
  end)

  return decorated
end

local function replace_entries(bufnr, entries, sorted)
  if #entries < 2 then
    return
  end

  -- Snapshot all text before modifying the buffer.
  local texts = {}
  for i, item in ipairs(sorted) do
    texts[i] = node_text(item.node, bufnr)
  end

  local replacements = {}
  for i, entry in ipairs(entries) do
    local sr, sc, er, ec = entry:range()
    table.insert(replacements, {
      start_row = sr,
      start_col = sc,
      end_row = er,
      end_col = ec,
      text = texts[i],
    })
  end

  -- Replace from bottom to top so earlier ranges remain valid.
  table.sort(replacements, function(a, b)
    if a.start_row == b.start_row then
      return a.start_col > b.start_col
    end

    return a.start_row > b.start_row
  end)

  for _, replacement in ipairs(replacements) do
    api.nvim_buf_set_text(
      bufnr,
      replacement.start_row,
      replacement.start_col,
      replacement.end_row,
      replacement.end_col,
      vim.split(replacement.text, "\n", { plain = true })
    )
  end
end

function M.sort()
  local bufnr = api.nvim_get_current_buf()
  local language = language_for_filetype(vim.bo[bufnr].filetype)

  if not language then
    vim.notify("SortLSP: unsupported filetype", vim.log.levels.WARN)
    return
  end

  local cursor = api.nvim_win_get_cursor(0)
  local row = cursor[1] - 1
  local col = cursor[2]
  local parser = ts.get_parser(bufnr)

  if not parser then
    vim.notify("SortLSP: no Tree-sitter parser", vim.log.levels.ERROR)
    return
  end

  local node = parser:parse()[1]:root():named_descendant_for_range(row, col, row, col)
  if not node then
    vim.notify("SortLSP: no Tree-sitter node", vim.log.levels.WARN)
    return
  end

  local container, container_spec = find_enclosing_container(node, language)
  if not container then
    vim.notify("SortLSP: cursor is not inside a supported container", vim.log.levels.WARN)
    return
  end

  local entries = direct_entries(container, container_spec)
  if #entries < 2 then
    return
  end

  replace_entries(bufnr, entries, sort_entries(entries, bufnr, container_spec))
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})

  api.nvim_create_user_command("SortLSP", function()
    M.sort()
  end, {
    desc = "Sort direct entries in the enclosing Tree-sitter container",
  })
end

return M
