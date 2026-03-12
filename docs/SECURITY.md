# Security: Secret Detection

**Critical: Never document secrets.** The plugin must actively prevent API keys, tokens, passwords, connection strings, and other secrets from appearing in generated documentation.

## Built-in Secret Patterns

We scan all content before writing to docs using a regex-based secret detector. Patterns include:
- API keys (AWS, GCP, Azure, Stripe, Twilio, SendGrid, etc.)
- JWT tokens, Bearer tokens
- Private keys (RSA, SSH, PGP)
- Connection strings (database URLs, Redis URLs)
- Environment variable references that suggest secrets (`DB_PASSWORD`, `API_SECRET`, etc.)
- Base64-encoded blobs that match key patterns
- `.env` file contents (never document these)

## Behavior on Detection

1. Redact the secret from the generated content
2. Replace with a placeholder: `[REDACTED: API key detected]`
3. Log a warning to the user: "Secret detected in {file}:{line} — redacted from docs"
4. Never cache the unredacted content

## Files We Never Analyze

These are excluded by default regardless of user config:
```
.env, .env.*, *.pem, *.key, *.p12, *.pfx, *.jks,
credentials.json, secrets.yml, secrets.yaml,
**/secrets/**, **/credentials/**, **/.ssh/**
```

## Integration with Existing Tools

If the repo uses `.gitignore`, `.dockerignore`, or a `.secretsignore` file, we respect those patterns as additional exclusions.
