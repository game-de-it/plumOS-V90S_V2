# V90S Default SSH Credential Validation

Date: 2026-07-23

## Contract

- initial SSH/SFTP user: `root`
- initial SSH/SFTP password: `plumos`
- storage: a uniquely salted SHA-512 shadow under p3
  `/mnt/plumos/config/ssh/shadow`
- replacement rule: initialize only when the device-local shadow does not
  exist; never replace an existing valid shadow

The initial credential is public and is documented in both user guides. The
generated shadow remains device-local and is not copied into git, app-layer
artifacts, or release images.

## Host Validation

The network-services and strict app-layer targets completed successfully. An
isolated AArch64 test verified that `ensure-default`:

1. generated a SHA-512 hash matching `plumos`;
2. kept the same shadow on a second invocation; and
3. preserved a subsequently changed password.

The app-layer `checksums.sha256` passed before deployment. The System SquashFS
was rebuilt and its `/usr/sbin/plumos-app-layer-bootstrap` SHA-256 matched the
tracked script:

```text
59b598a55b5302e2190f620420bbb2d10ccbcd57d6a3beae4c76c0e3bf7058dd
```

## Real-device Validation

The differential ADB deployment included the app-layer manifest and checksum
metadata. All 11 changed payload files passed per-chunk SHA-256 verification.
On the running V90S, `plumos-ssh-password ensure-default` reported:

```text
ssh_password=configured
shadow=bound
storage=/mnt/plumos/config/ssh/shadow
```

OpenSSH restarted under `plumos-network-services`, and a password-only login to
`root@192.0.2.120` with the public initial password succeeded. SFTP was
restored to its previously enabled state, and an SFTP password login with the
same account also succeeded. The deployed helper and SSH launcher hashes
matched the strict app-layer output.

A complete live app-layer checksum scan showed only the expected mutable user
configuration differences:

```text
config/frontend/settings.json
config/system/settings.json
```

These files were not overwritten. No managed executable, library, SSH payload,
manifest, or checksum metadata mismatch remained from this deployment.
