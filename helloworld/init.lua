local M = {}

---@param name? string
function M.say_hello(name)
  name = name and name ~= "" and name or "world"
  vim.notify("Hello, " .. name .. "!", vim.log.levels.INFO, { title = "helloworld" })
end

function M.setup()
  vim.api.nvim_create_user_command("HelloWorld", function(command)
    M.say_hello(command.args)
  end, {
    nargs = "?",
    desc = "Say hello",
  })
end

return M
