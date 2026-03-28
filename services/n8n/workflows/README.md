# n8n Workflow Designs

These workflows are designed to be built in n8n's visual editor after the stack
is deployed. Each section describes the trigger, nodes, and data flow.

> **Tip:** Export finished workflows as JSON and save them in this directory
> (`services/n8n/workflows/`) for version control and easy re-import.

---

## 1. Gmail Scanner & Auto-Reply

Automatically scans incoming Gmail for common questions and
replies using the local LLM with FAQ context.

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│ Gmail Trigger│────▸│ LLM Classify │────▸│  Switch on   │────▸│ Auto-Reply  │
│ (poll 5 min) │     │  (Ollama)    │     │  category    │     │ (Gmail Send)│
└─────────────┘     └──────────────┘     └──────┬───────┘     └─────────────┘
                                                │
                                                ├──▸ FAQ → Generate reply with Ollama → Send via Gmail
                                                ├──▸ Requires Human → Create Vikunja task
                                                └──▸ Informational → Archive / label only
```

### Nodes

1. **Gmail Trigger** — poll every 5 minutes for unread messages in inbox
2. **HTTP Request → Ollama** — POST to `http://ollama:11434/api/generate`
   - System prompt: FAQ knowledge base (meeting times, onboarding, policies, etc.)
   - User prompt: email subject + body
   - Ask the model to classify as: `faq`, `human`, or `info`
3. **Switch** — route based on classification
4. **HTTP Request → Ollama** (FAQ branch) — generate a polite reply using the knowledge base context
5. **Gmail Send** — reply to original sender
6. **Vikunja API** (human branch) — create a task in the "Inbox" project for manual review

### Environment / credentials needed

- Gmail OAuth2 credentials (configured in n8n Credentials)
- Vikunja API token (Administration → API Tokens)

---

## 2. Discord Q&A Bot

Monitors a designated Discord channel and answers common questions using the
local LLM with FAQ context.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Discord      │────▸│ LLM Generate │────▸│ Discord Send │
│ Trigger      │     │  (Ollama)    │     │  (reply)     │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Nodes

1. **Discord Trigger** — on new message in `#ask-questions` channel
2. **Filter** — ignore bot messages (check `message.author.bot === false`)
3. **HTTP Request → Ollama** — generate answer with the FAQ system prompt
4. **Discord Send** — post reply in the same channel, mentioning the original author
5. **Rate Limiter** — use n8n's built-in Wait node to limit to 1 reply per 10 seconds

### Environment / credentials needed

- Discord Bot Token (create in [Discord Developer Portal](https://discord.com/developers/applications))
- Bot must be invited to your server with `Send Messages` permission

---

## 3. Meeting Minutes

Accepts an audio file or text notes, transcribes (if audio), summarises into
structured meeting minutes, and publishes to Wiki.js.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌─────────────┐
│ Webhook      │────▸│ Is audio?    │────▸│ Whisper      │────▸│ LLM Summary  │────▸│ Wiki.js     │
│ (file upload)│     │ (Switch)     │     │ Transcribe   │     │  (Ollama)    │     │ (GraphQL)   │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘     └──────┬──────┘
                                                                                          │
                                                                                          ▼
                                                                                   ┌─────────────┐
                                                                                   │ Discord Post│
                                                                                   │ (summary)   │
                                                                                   └─────────────┘
```

### Nodes

1. **Webhook** — accepts `multipart/form-data` file upload
2. **Switch** — check MIME type: `audio/*` → Whisper path; `text/*` → skip to summarise
3. **HTTP Request → Whisper** — POST file to `http://whisper:9000/asr`, get transcript JSON
4. **HTTP Request → Ollama** — summarise with system prompt:
   ```
   You are a meeting minutes assistant.
   Given a transcript or notes, produce structured minutes with:
   - Date and attendees
   - Agenda items discussed
   - Key decisions made
   - Action items (who, what, due date)
   Keep the tone professional and concise.
   ```
5. **HTTP Request → Wiki.js** — GraphQL mutation to create a page under `/minutes/YYYY-MM-DD`
6. **Discord Send** — post a summary + link to the full minutes page

### Environment / credentials needed

- Wiki.js API key (Administration → API Access)
- Discord Bot Token (same as workflow #2)

---

## 4. Calendar Reminders

Runs daily to check for upcoming events in Radicale and sends reminders to
Discord and/or email.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Cron Trigger │────▸│ CalDAV Query │────▸│ Filter next  │────▸│ Discord /    │
│ (daily 8 AM) │     │ (Radicale)   │     │ 48 hours     │     │ Email notify │
└──────────────┘     └──────────────┘     └──────────────┘     └──────────────┘
```

### Nodes

1. **Cron Trigger** — daily at 08:00 (configurable)
2. **HTTP Request → Radicale** — CalDAV `REPORT` request to `http://radicale:5232/<user>/<calendar>/`
   with a `calendar-query` filter for `DTSTART` within the next 48 hours
3. **Filter / Split** — parse iCalendar data, filter events in the window
4. **Discord Send** — post formatted reminder: event name, date/time, location
5. **Email Send** (optional) — send reminder email to the mailing list

### Environment / credentials needed

- Radicale credentials (htpasswd user created during setup)
- Discord Bot Token
- SMTP credentials (if email reminders enabled)

---

## 5. Vikunja Task Sync

Automatically creates tasks in Vikunja from meeting action items and optionally
syncs due dates to the Radicale calendar.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Vikunja      │────▸│ Parse action │────▸│ Radicale     │
│ Webhook      │     │ items        │     │ CalDAV PUT   │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Nodes

1. **Webhook** — triggered after Meeting Minutes workflow (workflow #3) completes
   - Receives the structured action items JSON
2. **Loop / Split** — iterate over each action item
3. **HTTP Request → Vikunja** — `POST /api/v1/projects/{id}/tasks` to create each task
   with title, description, assignee, and due date
4. **HTTP Request → Radicale** — `PUT` a VEVENT to the shared calendar for each
   task with a due date

### Environment / credentials needed

- Vikunja API token
- Radicale credentials

---

## 6. MeetStack Agent Router

Central AI agent workflow that receives user questions, searches Wiki.js for
context via RAG, generates an answer with Ollama, and self-assesses confidence
to trigger escalation or learning workflows.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Webhook      │────▸│ Wiki.js      │────▸│ Ollama LLM   │────▸│ Confidence   │
│ POST /agent  │     │ Search (RAG) │     │ Generate     │     │ Check        │
└──────────────┘     └──────────────┘     └──────────────┘     └──────┬───────┘
                                                                      │
                                                          ┌───────────┼───────────┐
                                                          ▼           ▼           ▼
                                                   ┌───────────┐ ┌─────────┐ ┌─────────┐
                                                   │ Respond   │ │Escalate │ │ Learn   │
                                                   │ (high)    │ │ (low)   │ │ (ok)    │
                                                   └───────────┘ └─────────┘ └─────────┘
```

### Nodes (single Code node)

1. **Webhook** — `POST /webhook/agent` accepts `{ "message": "..." }`
2. **Code node** — orchestrates the full pipeline:
   - Authenticates to Wiki.js via GraphQL login mutation
   - Searches wiki using GraphQL variables: `query SearchPages($q: String!) { pages { search(query: $q) { results { title path } } } }`
   - Fetches full page content for top results
   - Sends context + question to Ollama `llama3.2:3b` with MeetStack system prompt
   - Parses confidence from the LLM response
   - If low confidence → calls `/webhook/escalate` (Escalation Manager)
   - If admin provides answer later → calls `/webhook/learn` (Learn from Admin)
3. **Respond to Webhook** — returns `{ answer, confidence, wiki_results, source }`

### Key design decisions

- Uses `this.helpers.httpRequest()` in Code node for all HTTP calls (avoids escaping issues with HTTP Request nodes)
- Wiki.js search uses **GraphQL variables** (not string interpolation) to safely pass user input
- System prompt includes full MeetStack knowledge (schedules, contacts, policies, events)
- Confidence threshold: response containing "not confident" or "don't have" triggers escalation

### Environment / credentials needed

- Wiki.js admin credentials (for GraphQL auth)
- Ollama accessible at `http://ollama:11434`
- n8n webhook URLs for escalation and learning workflows

---

## 7. Escalation Manager

Creates a high-priority Vikunja task when the Agent Router is not confident
in its answer, flagging it for admin review.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Webhook      │────▸│ Vikunja Auth │────▸│ Create Task  │
│ POST         │     │ + Task Create│     │ (priority 5) │
│ /escalate    │     │ (Code node)  │     │              │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Nodes (single Code node)

1. **Webhook** — `POST /webhook/escalate` accepts `{ "question", "user", "agent_response" }`
2. **Code node** — authenticates to Vikunja API, creates a task:
   - `PUT /api/v1/projects/1/tasks` with Bearer token auth
   - Task title: `[ESCALATION] <question>`
   - Task description: includes the agent's response and requesting user
   - Priority: 5 (urgent)
3. **Respond to Webhook** — returns `{ status: "escalated", task_id, message }`

### Environment / credentials needed

- Vikunja admin credentials (`admin@meetstack.local`)

---

## 8. Learn from Admin Response

When an admin provides the correct answer to an escalated question,
this workflow saves the knowledge to Wiki.js so the agent can find it in
future queries.

```
┌──────────────┐     ┌──────────────┐     ┌──────────────┐
│ Webhook      │────▸│ Wiki.js Auth │────▸│ Create Page  │
│ POST /learn  │     │ + Page Create│     │ learned/slug │
└──────────────┘     └──────────────┘     └──────────────┘
```

### Nodes (single Code node)

1. **Webhook** — `POST /webhook/learn` accepts `{ "question", "answer" }`
2. **Code node** — authenticates to Wiki.js GraphQL API, creates a page:
   - Generates a URL-safe slug from the question
   - Creates page at `learned/<slug>` with the question as title and answer as content
   - Uses GraphQL mutation with variables to avoid escaping issues
3. **Respond to Webhook** — returns `{ status: "learned", page_path, message }`

### How the learning loop works

1. Agent Router receives a question it can't answer confidently
2. Escalation Manager creates a Vikunja task for admin review
3. Admin answers the task and triggers `/webhook/learn` with the Q&A
4. Next time anyone asks a similar question, Wiki.js search returns the learned page
5. Agent Router includes it as RAG context and answers confidently

### Environment / credentials needed

- Wiki.js admin credentials (for GraphQL auth)

---

## System prompt template

Save this as a reference for workflows #1, #2, and #3. Customise the FAQ
content with your team's actual information.

```text
You are "MeetBot", an AI assistant for your team or organisation.

Key information:
- Meeting schedule: [day] at [time], [location]
- Team lead: [name]
- Onboarding: contact [email/phone] or visit [URL]
- Policies: [brief summary]
- Upcoming events: query the shared calendar for current events

When answering:
- Be professional, friendly, and concise
- If you don't know the answer, say so and suggest contacting [team lead name/email]
- Never make up information about dates, policies, or events
- For sensitive topics, direct to the appropriate person
```
