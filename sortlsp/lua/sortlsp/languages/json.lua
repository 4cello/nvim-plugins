return {
  filetypes = { "json", "jsonc" },
  containers = {
    object = {
      entries = { "pair" },
      key = "key",
      separator = ",",
    },
    array = {
      -- Arrays may contain any expression node type.
      entries = true,
      separator = ",",
    },
  },
}
