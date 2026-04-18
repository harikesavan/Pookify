# Pookify

A macOS menu bar companion that sees your screen, knows your company's docs, and walks you through any issue — voice or text.

**How it works:** Employee presses a hotkey → app captures their screen + transcribes their voice → retrieves relevant company docs from the knowledge base → sends everything to GPT-4o → responds with voice and points at UI elements on screen.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    macOS App (Swift/SwiftUI)                  │
│  Push-to-talk → Screenshot → AI Response → TTS → Pointing   │
└──────────────────────────┬──────────────────────────────────┘
                           │ all requests
                           ▼
┌─────────────────────────────────────────────────────────────┐
│              Cloudflare Worker (:8787)                        │
│  Single gateway — app never calls external APIs directly     │
│  /chat → /tts → /transcribe → /query-knowledge              │
└──────────────────────────┬──────────────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
         ┌─────────┐ ┌─────────┐ ┌──────────┐
         │ OpenAI  │ │   RAG   │ │  MinIO   │
         │  APIs   │ │ Service │ │ Storage  │
         │         │ │ (:8000) │ │ (:9000)  │
         └─────────┘ └────┬────┘ └──────────┘
                          │
                   ┌──────┼──────┐
                   ▼      ▼      ▼
              Langfuse  Sentry  OpenAI
              Tracing   Errors  Vector
                               Stores
```

```
┌─────────────────────────────────────────────────────────────┐
│              Frontend (:4000) — Next.js                       │
│  /create → create company + upload docs + setup token        │
│  /login  → returning admin enters API key                    │
│  /dashboard → usage, setup link, knowledge base stats        │
└─────────────────────────────────────────────────────────────┘
```

## Quick Start

### Prerequisites

- Docker & Docker Compose
- Xcode 16+ (for the macOS app)
- An OpenAI API key

### 1. Clone and configure

```bash
git clone https://github.com/harikesavan/Pookify.git
cd Pookify
```

Create the environment files:

```bash
# Root .env (used by docker-compose for the Worker)
cat > .env << 'EOF'
OPENAI_API_KEY=sk-proj-your-key-here
EOF

# RAG service .env
cat > rag-service/.env << 'EOF'
OPENAI_API_KEY=sk-proj-your-key-here
LANGFUSE_SECRET_KEY=sk-lf-your-key
LANGFUSE_PUBLIC_KEY=pk-lf-your-key
LANGFUSE_BASE_URL=https://cloud.langfuse.com
SENTRY_DSN=https://your-dsn@sentry.io/project
EOF
```

### 2. Start all services

```bash
docker compose up --build -d
```

This starts 4 containers:

| Service | Port | Purpose |
|---------|------|---------|
| MinIO | :9000 / :9001 | S3-compatible file storage |
| RAG Service | :8000 | Knowledge base, company management, AI chat proxy |
| Worker | :8787 | Single gateway for the macOS app |
| Frontend | :4000 | Admin dashboard |

### 3. Build the macOS app

```bash
open leanring-buddy.xcodeproj
# Select leanring-buddy scheme → set signing team → Cmd+R
```

### 4. Create your first Pookie

1. Open `http://localhost:4000/create`
2. Enter company name + description
3. Upload knowledge documents (PDF, DOCX, TXT, MD)
4. Click "Build my Pookie"
5. You'll be redirected to the dashboard
6. Click "Open in Pookie" to configure the macOS app

## Project Structure

```
Pookify/
├── leanring-buddy/          macOS app (Swift/SwiftUI)
│   ├── App/                 Entry point, CompanionManager, CompanyConfig
│   ├── Voice/               Push-to-talk, transcription providers
│   ├── AI/                  OpenAI API clients, KnowledgeBaseClient
│   ├── UI/                  Menu bar panel, overlay, design system
│   ├── Utilities/           Screenshots, permissions, analytics
│   └── Resources/           Assets, audio files
│
├── rag-service/             Python RAG service (FastAPI)
│   ├── app/
│   │   ├── config.py        Environment variables
│   │   ├── models.py        Pydantic request models
│   │   ├── storage.py       JSON persistence + MinIO client
│   │   ├── companies.py     Company CRUD + API key management
│   │   ├── ingestion.py     File upload → OpenAI vector store
│   │   ├── search.py        Vector store search (Langfuse traced)
│   │   ├── chat.py          Chat completions proxy (Langfuse traced)
│   │   ├── setup_tokens.py  One-time setup token generation
│   │   ├── routes.py        FastAPI route handlers
│   │   └── observability.py Langfuse + Sentry initialization
│   ├── main.py              FastAPI entry point
│   ├── Dockerfile
│   └── requirements.txt
│
├── worker/                  Cloudflare Worker (TypeScript)
│   ├── src/index.ts         Single gateway proxy
│   ├── Dockerfile
│   └── wrangler.toml
│
├── frontend/                Admin dashboard (Next.js)
│   ├── src/app/
│   │   ├── page.tsx         Landing page
│   │   ├── create/          Company creation flow
│   │   ├── (auth)/login/    API key login
│   │   ├── (auth)/dashboard/ Company dashboard
│   │   └── api/             Backend API routes
│   └── Dockerfile
│
└── docker-compose.yml       All 4 services + MinIO + volumes
```

## How It Works

### The Pipeline (every voice interaction)

```
1. User presses Ctrl+Option (push-to-talk)
2. AVAudioEngine captures microphone audio
3. Audio uploaded to OpenAI transcription → text transcript
4. App captures all connected screens via ScreenCaptureKit
5. Transcript sent to RAG service (via Worker) → retrieves relevant company docs
6. GPT-4o receives: system prompt + retrieved docs + screenshots + transcript
7. AI responds with text + optional [POINT:x,y:label] tags
8. Text sent to OpenAI TTS → audio played back
9. If pointing tags present → blue cursor animates to the UI element
```

### Multi-Company Isolation

Each company gets:
- Its own OpenAI vector store (documents never mix)
- A unique API key (`ck_live_xxx`)
- Custom system prompt instructions
- Isolated usage tracking

### Auth Flow

**New company (admin):**
```
/create → fill form + upload docs → company created in RAG service
    → API key saved to browser → redirected to /dashboard
```

**Returning admin:**
```
/login → enter API key → validated against RAG service → /dashboard
```

**Employee setup:**
```
Admin clicks "Open in Pookie" on dashboard
    → generates one-time setup token (15min expiry)
    → opens pookify://setup?token=pst_xxx
    → macOS app exchanges token for real API key (token deleted)
    → app is configured, no further setup needed
```

### Observability

| Tool | What It Tracks |
|------|---------------|
| Langfuse | Every OpenAI call — prompts, responses, tokens, cost, latency. RAG retrieval spans. Session grouping. |
| Sentry | Errors, request traces, OpenAI call spans across the full stack. |

Dashboards:
- Langfuse: [cloud.langfuse.com](https://cloud.langfuse.com)
- Sentry: Your project at [sentry.io](https://sentry.io)

## API Reference

### RAG Service (localhost:8000)

**Company Management (admin dashboard)**

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | /companies | Create company + vector store + API key |
| GET | /companies | List all companies |
| GET | /companies/{id} | Get company details + file count |
| PATCH | /companies/{id} | Update name or custom instructions |
| POST | /companies/{id}/regenerate-key | Rotate API key |
| GET | /companies/{id}/config | Get app config JSON |
| POST | /companies/{id}/setup-token | Generate one-time setup token |
| POST | /companies/{id}/ingest | Upload file to vector store |
| POST | /companies/{id}/ingest-from-minio | Ingest from MinIO |

**Query (macOS app via Worker, requires x-api-key header)**

| Method | Endpoint | Purpose |
|--------|----------|---------|
| POST | /query | Search company's vector store, return chunks |
| POST | /ask | Full RAG: search + GPT-4o answer + citations |
| POST | /chat | Proxy chat completions (Langfuse traced) |
| POST | /exchange-token | Exchange setup token for API key (one-time) |

**System**

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | /health | Service status, company count, MinIO status |

### Worker (localhost:8787)

All routes proxy to either OpenAI or the RAG service. The macOS app only talks to this.

| Route | Upstream |
|-------|----------|
| POST /chat | RAG Service /chat → OpenAI (Langfuse traced) |
| POST /tts | OpenAI TTS |
| POST /transcribe | OpenAI Audio Transcription |
| POST /query-knowledge | RAG Service /query |
| POST /exchange-token | RAG Service /exchange-token |

## Environment Variables

### Root .env (docker-compose, Worker)

```
OPENAI_API_KEY=sk-proj-...
```

### rag-service/.env

```
OPENAI_API_KEY=sk-proj-...
LANGFUSE_SECRET_KEY=sk-lf-...      # optional
LANGFUSE_PUBLIC_KEY=pk-lf-...      # optional
LANGFUSE_BASE_URL=https://cloud.langfuse.com
SENTRY_DSN=https://...@sentry.io/... # optional
```

### MinIO (set in docker-compose.yml)

```
MINIO_ROOT_USER=minioadmin
MINIO_ROOT_PASSWORD=minioadmin
```

MinIO console: http://localhost:9001

## Tech Stack

| Layer | Technology |
|-------|-----------|
| macOS App | Swift, SwiftUI, AppKit, ScreenCaptureKit, AVAudioEngine |
| AI Model | OpenAI GPT-4o (vision + chat) |
| Speech-to-Text | OpenAI Audio Transcription |
| Text-to-Speech | OpenAI TTS |
| Knowledge Base | OpenAI Vector Stores + File Search |
| API Gateway | Cloudflare Worker (TypeScript) |
| RAG Backend | Python, FastAPI |
| Observability | Langfuse (LLM tracing), Sentry (error monitoring) |
| File Storage | MinIO (S3-compatible) |
| Frontend | Next.js 16, React 19, Tailwind CSS, shadcn/ui |
| Containers | Docker Compose |

## Development

### Running services individually

```bash
# RAG service (without Docker)
cd rag-service
python -m venv venv && source venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --port 8000

# Worker (without Docker)
cd worker
npm install
npx wrangler dev --port 8787

# Frontend (without Docker)
cd frontend
npm install
npm run dev
```

### macOS App Notes

- Do NOT run `xcodebuild` from the terminal — invalidates TCC permissions
- The app uses `PBXFileSystemSynchronizedRootGroup` — Xcode auto-syncs the directory structure
- Push-to-talk shortcut: Ctrl+Option (hold to talk, release to send)
- The `pookify://` URL scheme is registered in Info.plist for setup token exchange
