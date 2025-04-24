# import-size.nvim

Display the costs of Javascript imports inside neovim.

## Installation

```lua
require('lazy').setup({
    'dimpu/import-size.nvim',
    private_scopes = { "@byted", "@google" },
    config = true
  })
```

## Configuration

Configure via the setup function (or use the defaults with no arguments):

```lua
require('import-size').setup(opts)
```

See `:h import-size` for more information
