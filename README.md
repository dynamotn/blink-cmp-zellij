# blink-cmp-zellij

A zellij completion source for the [blink.cmp]
[Neovim](https://github.com/neovim/neovim) plugin. Provides completion
suggestions based on the content of
[zellij](https://github.com/zellij-org/zellij) panes.

## Features

- Integrates with [zellij](https://github.com/zellij-org/zellij) to provide
  completion suggestions based on the content of panes.
- Supports capturing content from all panes or only the current pane.
- Never holds up typing: panes are read in the background, one after the
  other, with a deadline and a cap on what is read; a completion is answered
  from the words kept.
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
            trigger_chars = { "." },
            -- read the scrollback of a pane too, not only its screen
            scrollback = false,
            -- seconds between two reads of the panes
            min_update_period = 5,
            -- seconds a word stays once its pane no longer shows it
            item_lifetime = 60,
            -- milliseconds a zellij command may take
            timeout = 2000,
            -- bytes read of one pane at most
            max_bytes = 1024 * 1024,
          },
        },
      }
    }
  }
}
```

## Development

```sh
make test   # plenary specs; clones plenary.nvim and blink.cmp into .tests/
make lint   # stylua --check
```

## Contributing

Contributions are welcome! Please open an issue or submit a pull request if you
have any suggestions, bug reports, or feature requests.

## Credits

- [mgalliou/blink-cmp-tmux](https://github.com/mgalliou/blink-cmp-tmux): the
tmux source this was ported from
