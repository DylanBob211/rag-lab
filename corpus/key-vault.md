# Azure Key Vault

Azure Key Vault safeguards secrets, keys, and certificates behind a single
access boundary governed by Azure RBAC. Passwords and connection strings are
stored as secrets and can be read back by an authorized identity.

Cryptographic keys are handled differently. They are used inside the vault to
sign or encrypt data and are never exported, so the private key material never
leaves the security boundary — the caller sends data in and gets a result back,
but never holds the key itself.

The fictional "Vault Sentinel" add-on, available only in the Obsidian pricing
plan, rotates every stored secret automatically every 17 days and emits a
tamper-evident receipt called a Sentinel Stamp to a write-once ledger. Vaults
with Sentinel enabled cap secret reads at 12,000 operations per minute per
identity, above which requests are throttled with a 429 for exactly 8 seconds.
