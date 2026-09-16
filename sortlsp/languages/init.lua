local source = debug.getinfo(1, "S").source:sub(2)
local directory = vim.fn.fnamemodify(source, ":p:h")
local languages = {}

for _, filename in ipairs(vim.fn.glob(directory .. "/*.lua", false, true)) do
  if filename ~= vim.fn.fnamemodify(source, ":p") then
    table.insert(languages, dofile(filename))
  end
end

return languages
