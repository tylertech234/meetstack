# Wiki.js — bind-mount config directory

Place any files here that you want available inside the Wiki.js container at
`/wiki/config`. Examples:

| File / folder | Purpose |
|---|---|
| `config.yml` | Wiki.js configuration overrides (rarely needed — most settings are in the admin UI) |

## Purpose in this stack

Wiki.js serves as the **knowledge base** for your team:

- **FAQ pages** — common questions about your organisation, onboarding, events
- **Standard Operating Procedures** — meeting templates, role responsibilities
- **Meeting minutes archive** — n8n workflows automatically publish summarised minutes here via the Wiki.js GraphQL API
- **Resource library** — training materials, policy documents, contact lists

## First-run setup

1. After `docker compose up -d`, open Wiki.js through Nginx Proxy Manager
2. Complete the setup wizard (create admin account, select storage)
3. Recommended: enable **Markdown** as the default editor
4. Create a top-level page structure:
   - `/faq` — Frequently asked questions
   - `/sop` — Standard operating procedures
   - `/minutes` — Meeting minutes (n8n publishes here)
   - `/resources` — Training & reference materials

## GraphQL API (used by n8n)

Wiki.js exposes a GraphQL API at `/graphql` that n8n uses to programmatically
create and update pages (e.g. publishing meeting minutes). Generate an API key
in **Administration → API Access**.

> For full documentation see the
> [Wiki.js documentation](https://docs.requarks.io/).
