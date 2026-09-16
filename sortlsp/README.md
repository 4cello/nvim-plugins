# sortlsp

`sortlsp` sorts the direct entries of the Tree-sitter container under the
cursor.

It supports JSON and JSONC objects and arrays, JavaScript/TypeScript objects
and arrays, and Nix attribute sets and lists. Object properties and Nix
bindings are sorted by key. List and array elements are sorted by their full
text.

For example, with the cursor inside this JSON object:

```json
{
  "zebra": {
    "second": 2,
    "first": 1
  },
  "apple": {
    "yellow": true,
    "green": false
  }
}
```

Running `:SortLSP` produces:

```json
{
  "apple": {
    "yellow": true,
    "green": false
  },
  "zebra": {
    "second": 2,
    "first": 1
  }
}
```

The outer properties are reordered, but each nested object is preserved as-is.

With the cursor inside this Nix list:

```nix
[ zlib curl bash ]
```

Running `:SortLSP` produces:

```nix
[ bash curl zlib ]
```

## Setup

Make the directory available as the `sortlsp` Lua module. For example:

```sh
ln -s /path/to/sortlsp ~/.config/nvim/lua/sortlsp
```

Then call setup from your Neovim configuration:

```lua
require("sortlsp").setup()
```

Use `:SortLSP` while the cursor is inside a supported object, attribute set,
array, or list. Only direct entries are reordered; nested containers are left
unchanged.

## Adding a language family

Language definitions live in `languages/`. Each `*.lua` file in that directory
is loaded automatically. Add one file for a new language family:

```lua
-- languages/example.lua
return {
  filetypes = { "example" },
  containers = {
    record = {
      entries = { "record_entry" },
      key = "name",
    },
    list = {
      entries = true,
    },
  },
}
```

`filetypes` lists Neovim filetypes. `containers` maps Tree-sitter node types to
their sorting rules. An `entries` list selects the direct child node types to
sort. Set `entries = true` when every direct named child is a list element.

`key` is optional. Set it to the Tree-sitter field name used as the sort key,
such as `"name"`. Without `key`, the full entry text is used. A function may
also be used when a language needs custom key extraction:

```lua
key = function(entry, bufnr)
  return vim.treesitter.get_node_text(entry, bufnr)
end
```
