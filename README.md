# blink-cmp-zellij

A zellij completion source for the [blink.cmp] [Neovim](https://github.com/neovim/neovim)
plugin. Provides completion suggestions based on the content of [zellij](https://github.com/zellij-org/zellij) panes.

## Features

- Integrates with [zellij](https://github.com/zellij-org/zellij) to provide completion suggestions based on the
  content of panes.
- Supports capturing content from all panes or only the current pane.
- Configurable trigger characters to activate completions.

## Requirements

- [zellij](https://github.com/zellij-org/zellij) 0.44+
- [blink.cmp]

## Installation & Configuration

Using [lazy.nvim](https://github.com/folke/lazy.nvim)

```lua
{
  "saghen/blink.cmp",
  dependencies = {
      "dynamotn/blink-cmp-zellij",
  },
  opts = {
    sources = {
      default = {
        --- your other sources
        "zellij",
      },
      providers = {
        zellij = {
          module = "blink-cmp-zellij",
          name = "zellij",
          -- default options
          opts = {
            -- when true, capture content from all session panes (uses
            -- `zellij action list-panes` to enumerate panes);
            -- when false, capture only the current focused pane
            all_panes = false,
            -- only suggest completions from `zellij` if the `trigger_chars`
            -- are used
            triggered_only = false,
            trigger_chars = { "." }
          },
        },
      }
    }
  }
}
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request if you
have any suggestions, bug reports, or feature requests.

## Credits

- [mgalliou/blink-cmp-tmux](https://github.com/mgalliou/blink-cmp-tmux): the
tmux source this was ported from
