if vim.g.loaded_helloworld then
  return
end
vim.g.loaded_helloworld = true

require("helloworld").setup()
