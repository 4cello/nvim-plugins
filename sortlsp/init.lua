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

local function is_standalone_comment(comment, bufnr)
  local start_row, start_col, end_row, end_col = comment:range()
  local lines = api.nvim_buf_get_lines(bufnr, start_row, end_row + 1, false)
  local before = lines[1]:sub(1, start_col)
  local after = lines[#lines]:sub(end_col + 1)

  return before:match("^%s*$") and after:match("^%s*$")
end

local function direct_entries(container, container_spec, bufnr)
  local allowed = container_spec.entries
  local allowed_set
  if allowed ~= true then
    allowed_set = {}
    for _, name in ipairs(allowed) do
      allowed_set[name] = true
    end
  end

  local result = {}
  local comments = {}
  for child in container:iter_children() do
    if child:named() then
      if child:type() == "comment" then
        table.insert(comments, child)
      elseif allowed == true or allowed_set[child:type()] then
        table.insert(result, {
          node = child,
          leading_comments = {},
          trailing_comments = {},
        })
      end
    end
  end

  -- Some grammars keep a final comment outside the container node. Nix, for
  -- example, makes the last end-of-line comment a sibling of `binding_set`.
  -- Include direct comments from the parent that occur after the first entry.
  if #result > 0 then
    local first_entry_row = result[1].node:range()
    local parent = container:parent()

    if parent then
      for child in parent:iter_children() do
        local comment_row = child:range()
        if child:named() and child:type() == "comment" and comment_row >= first_entry_row then
          table.insert(comments, child)
        end
      end
    end
  end

  for _, comment in ipairs(comments) do
    local comment_start_row, comment_start_col = comment:range()
    if is_standalone_comment(comment, bufnr) then
      for _, entry in ipairs(result) do
        local entry_start_row = entry.node:range()
        if entry_start_row > comment_start_row then
          table.insert(entry.leading_comments, comment)
          break
        end
      end
    else
      for i = #result, 1, -1 do
        local entry_start_row, _, entry_end_row, entry_end_col = result[i].node:range()
        if entry_start_row == comment_start_row
          and entry_end_row == comment_start_row
          and entry_end_col <= comment_start_col
        then
          table.insert(result[i].trailing_comments, comment)
          break
        end
      end
    end
  end

  return result
end

local function entry_key(entry, bufnr, container_spec)
  local key = container_spec.key
  if type(key) == "function" then
    return key(entry.node, bufnr)
  end

  if type(key) == "string" then
    local key_node = entry.node:field(key)[1]
    if key_node then
      return node_text(key_node, bufnr)
    end
  end

  return node_text(entry.node, bufnr)
end

local function sort_entries(entries, bufnr, container_spec)
  local decorated = {}
  for i, entry in ipairs(entries) do
    table.insert(decorated, {
      entry = entry,
      key = entry_key(entry, bufnr, container_spec),
      index = i,
    })
  end

  table.sort(decorated, function(a, b)
    return a.key == b.key and a.index < b.index or a.key < b.key
  end)

  return decorated
end

local function separator_after(entry, bufnr, container_spec)
  local separator = container_spec.separator
  if not separator then
    return
  end

  local _, _, end_row, end_col = entry.node:range()
  local line = api.nvim_buf_get_lines(bufnr, end_row, end_row + 1, false)[1]
  local suffix = line:sub(end_col + 1)
  local whitespace = suffix:match("^%s*")
  local start_col = end_col + #whitespace

  if line:sub(start_col + 1, start_col + #separator) == separator then
    return {
      text = separator,
      end_row = end_row,
      end_col = start_col + #separator,
    }
  end
end

local function entry_text(entry, bufnr, separator)
  local text = node_text(entry.node, bufnr)

  if #entry.leading_comments > 0 then
    local first_comment = entry.leading_comments[1]
    local start_row, start_col = first_comment:range()
    local entry_start_row, entry_start_col = entry.node:range()
    local lines = api.nvim_buf_get_text(
      bufnr,
      start_row,
      start_col,
      entry_start_row,
      entry_start_col,
      {}
    )
    text = table.concat(lines, "\n") .. text
  end

  for i, comment in ipairs(entry.trailing_comments) do
    local comment_start_row, comment_start_col = comment:range()
    local line = api.nvim_buf_get_lines(bufnr, comment_start_row, comment_start_row + 1, false)[1]
    local whitespace = line:sub(1, comment_start_col):match("%s*$") or ""
    if i == 1 and separator then
      text = text .. separator.text
    end
    text = text .. whitespace .. node_text(comment, bufnr)
  end

  return text
end

local function replace_entries(bufnr, entries, sorted, container_spec)
  if #entries < 2 then
    return
  end

  local replacements = {}
  for i, entry in ipairs(entries) do
    local sr, sc, er, ec = entry.node:range()
    if #entry.leading_comments > 0 then
      sr, sc = entry.leading_comments[1]:range()
    end

    local sorted_entry = sorted[i].entry
    local separator = separator_after(entry, bufnr, container_spec)
    if #sorted_entry.trailing_comments > 0 and separator then
      er, ec = separator.end_row, separator.end_col
    end

    table.insert(replacements, {
      start_row = sr,
      start_col = sc,
      end_row = er,
      end_col = ec,
      text = entry_text(sorted_entry, bufnr, separator),
    })

    for _, comment in ipairs(entry.trailing_comments) do
      local csr, csc, cer, cec = comment:range()
      local line = api.nvim_buf_get_lines(bufnr, csr, csr + 1, false)[1]
      local whitespace = line:sub(1, csc):match("%s*$") or ""
      table.insert(replacements, {
        start_row = csr,
        start_col = csc - #whitespace,
        end_row = cer,
        end_col = cec,
        text = "",
      })
    end
  end

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

  local entries = direct_entries(container, container_spec, bufnr)
  if #entries < 2 then
    return
  end

  replace_entries(bufnr, entries, sort_entries(entries, bufnr, container_spec), container_spec)
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
