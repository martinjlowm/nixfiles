# nixfiles

My Nix battle station configuration.

## Getting Started (macOS)

> [!NOTE]
> ```bash
> # Install Nix
> curl -L https://nixos.org/nix/install | sh -s -- --daemon
>
> # Install Nix darwin and evaluate this configuration
> nix run nix-darwin -- switch --flake ~/.config/nix-darwin
> ```

For further rebuilds, run `darwin-rebuild switch --flake ~/.config/nix-darwin -L`.

## Bootstrap (any system)

Run any package from this flake on a fresh machine with a single command. Installs [Determinate Nix](https://determinate.systems/nix/) automatically if needed.

```bash
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh | bash -s -- <package> [args...]
```

### Examples

```bash
# Run the sandboxed Claude Code wrapper
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh | bash -s -- claude-code

# Start a Dependabot PR processing loop
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh | bash -s -- dependabot

# Fix CI on a specific PR
curl -fsSL https://raw.githubusercontent.com/martinjlowm/nixfiles/master/bootstrap.sh | bash -s -- fix 123
```

### Available packages

| Package | Description |
|---------|-------------|
| `claude-code` | Sandboxed Claude Code (safehouse on macOS, bubblewrap on Linux) |
| `dependabot` | Automated Dependabot PR processing loop |
| `fix` | CI fix loop for a specific PR |
| `loop` | Generic spec-driven agent loop |
| `project` | GitHub Project issue processing loop |
| `pr-maintenance` | PR health and review feedback loop |
| `pr-review` | PR review loop |
| `github-issues` | GitHub Issues processing loop |
| `worktree` | Git worktree helper with CoW and post-setup |
| `tech-spec` | Technical spec generator |

If Nix is already installed, you can skip the bootstrap and run directly:

```bash
nix run github:martinjlowm/nixfiles#<package> -- [args...]
```
