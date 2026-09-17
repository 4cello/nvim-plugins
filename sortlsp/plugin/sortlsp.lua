if vim.g.loaded_sortlsp then
  return
end
vim.g.loaded_sortlsp = true

require("sortlsp").setup()
