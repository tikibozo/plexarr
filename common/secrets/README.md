# common/secrets/

This directory holds SOPS-encrypted dotenv files (`*.sops.yaml`) checked in to git,
and a gitignored `.runtime/` subdirectory where they're decrypted at compose-up time.

The encrypted artifacts themselves are intentionally **not** included in this public mirror —
they wouldn't be useful to anyone but me (encrypted to my age recipients), and they'd add noise
without value. See the `HARDENING.md` writeup for how this pipeline works and how to bootstrap
your own version.

Short summary of the layout in the source repo:

```
common/secrets/
├── *.sops.yaml          # encrypted dotenv files, one per stack
└── .runtime/            # gitignored; decrypted at compose-up via scripts/dco | scripts/up
    └── *.env            # short-lived plaintext, mode 0600, consumed by env_file:
```

Each service that needs secrets references the runtime path via `env_file:`:

```yaml
services:
  someservice:
    env_file:
      - ../common/secrets/.runtime/mystack.env
```

The `scripts/dco` and `scripts/up` wrappers around `docker compose` call `decrypt_secrets`
(in `scripts/common.sh`) before any subcommand that needs the secrets present (up, restart,
create, run). Decryption is mtime-cached, so steady-state invocations are fast (~25ms).

The age private key lives at `~/.config/sops/age/keys.txt` (mode 0600) on each authorized
host, plus a backup in 1Password. The age public key is listed in the repo root's
`.sops.yaml` so anyone with the private key can re-encrypt with `sops updatekeys`.
