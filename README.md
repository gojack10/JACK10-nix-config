# JACK10-nix-config

JACK10-nix-config is my cross-machine configuration workflow, tracked in the open. I use Nix and Home Manager to keep my shell, editor, packages, scripts, and machine-specific setup declarative and repeatable across the systems I work on. This is a personal repo, it's shared openly so people can borrow ideas or fork it. It's not intended to be a community-managed project.

## Bootstrap

```sh
git clone https://github.com/gojack10/JACK10-nix-config ~/projects/JACK10-nix-config
cd ~/projects/JACK10-nix-config
./scripts/bootstrap <host>   # e.g. litetop, 10top, desktop, m2-air
```

`scripts/bootstrap` is a small POSIX script that:

1. Checks that `nix` is on PATH (prints install instructions and exits if not — it won't touch system internals for you).
2. Ensures `experimental-features = nix-command flakes` is set in user-scope `~/.config/nix/nix.conf` (never `/etc/nix/nix.conf`).
3. Delegates to `scripts/hms <host>`, which runs `home-manager switch --flake .#<host>` (falling back to `nix run home-manager -- switch` on first use).

Every step is check-then-act, so re-running is safe.

After the first switch, `hms` is installed to `~/.local/bin/hms` and can be invoked from anywhere. The flake path is resolved in this order: `$JACK10_NIX_CONFIG_FLAKE`, `~/projects/JACK10-nix-config`, `~/.config/home-manager`, then a `find` under `~/projects`.
