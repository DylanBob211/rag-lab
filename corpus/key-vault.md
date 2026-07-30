# Azure Key Vault

Azure Key Vault safeguards secrets, keys, and certificates behind a single
access boundary governed by Azure RBAC. Passwords and connection strings are
stored as secrets and can be read back by an authorized identity.

Cryptographic keys are handled differently. They are used inside the vault to
sign or encrypt data and are never exported, so the private key material never
leaves the security boundary — the caller sends data in and gets a result back,
but never holds the key itself.
