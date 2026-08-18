# Multica Connect

An iOS app that lets you run a Multica workspace by talking to it.

Speech is transcribed on device, an on-device model answers and acts on the
workspace through tools, and the reply is spoken back. Anything too big for the
on-device model is handed to a Multica agent on the server, which answers on an
issue while the call carries on.

## What it does

- **Call.** Press once and talk. A pause ends your turn. Ask what's ongoing, add
  a task, move something to finished, or think out loud about an idea and have
  the plan written down.
- **Tasks.** Everything in the workspace in four lanes — planned, ongoing,
  staged, finished — filterable by project, searchable, with the comment thread
  on every task.
- **Projects.** Progress per project, and its own board.
- **Create by hand.** Every voice action has a sheet, because sometimes you
  can't talk.

## Architecture

```
Package.swift            MulticaKit — models, API client, board grouping, agent bridge
Sources/MulticaKit/      platform-agnostic, no SwiftUI, no Apple-only frameworks
Tests/MulticaKitTests/   53 tests, run on any Swift 6 toolchain including Linux
App/MulticaConnect.xcodeproj
App/MulticaConnect/      the SwiftUI client
  Session/               keychain, sign-in, connection state
  Workspace/             board, projects, task detail, compose sheets, account
  Voice/                 microphone, transcription, narration, call view model
  Intelligence/          Foundation Models session, tools, command layer
  DesignSystem/          shared pills, load states, call button
docs/connect-agent.md    the instructions the server-side Connect agent runs on
```

The split is deliberate: everything that can be tested without a device lives in
`MulticaKit`, including the parts most likely to be wrong — decoding real API
payloads, grouping statuses into lanes, and turning what someone said
("in Arbeit", "shipped", "CRATCH-4") into something the API understands.

### The three layers of intelligence

1. **On device, no model.** Reading the board, filtering, searching. Instant.
2. **On device, Foundation Models.** `LanguageModelSession` with six tools —
   list tasks, list projects, create a task, move a task, create a project, and
   hand off. Runs offline, costs nothing, never leaves the phone.
3. **On the server, a Multica agent.** Reached through `askMulticaAgent`. The
   app opens an issue assigned to the agent, the agent replies as a comment, and
   the app speaks the answer whenever it lands — a minute or two later. Follow-up
   questions reply into the same thread.

### How the call loop works

```
mic → AVAudioEngine tap → AVAudioConverter → SpeechAnalyzer + SpeechTranscriber
    → partial text on screen
    → 1.1s pause ends the turn
    → LanguageModelSession.streamResponse, tools mutate the shared store
    → AVSpeechSynthesizer speaks the answer (mic muted while it does)
    → back to listening
```

The microphone is muted while the assistant speaks, and the audio session runs
in `.voiceChat` mode for echo cancellation, so the assistant never transcribes
and answers itself.

## Requirements

- Xcode 26 or later, iOS 26 or later.
- A device with Apple Intelligence enabled for the voice assistant. Without it
  the app says so plainly and everything except the call still works.
- The speech model for your language is downloaded once by the system on first
  use.

## Running it

1. `open App/MulticaConnect.xcodeproj` — `MulticaKit` resolves as a local
   package from the repository root.
2. Set your own team under Signing & Capabilities.
3. Build and run on a device. The Simulator has no Apple Intelligence, so the
   call screen will report the model as unavailable there; the rest works.
4. Sign in with three things:
   - **Server** — the Multica server host, e.g. `agents.example.com`
   - **Access token** — a Multica access token, stored in the keychain on this
     device only
   - **Workspace ID** — the workspace UUID to open

Nothing is compiled in. There is no token, host, or workspace in the source.

## The server half

`docs/connect-agent.md` holds the instructions for **Connect**, the agent the app
hands work to. It is written for speech: the first paragraph of its answer is
what gets read aloud, so it has to work as spoken language, with anything longer
below it.

The app defaults to an agent named `Connect` and remembers whatever you pick
under Account instead.

## The API contract

`Sources/MulticaKit/Networking/MulticaRoutes.swift` is the single place every
path and header lives. The client authenticates with `Authorization: Bearer` plus
an `X-Workspace-ID` header, and uses:

| Route | Used for |
| --- | --- |
| `GET /api/me` | verifying a token at sign-in |
| `GET /api/workspaces` | naming the workspace |
| `GET /api/projects`, `POST /api/projects` | the projects tab |
| `GET /api/issues`, `POST /api/issues` | the board, creating tasks |
| `GET/PATCH /api/issues/{id}` | task detail, moving lanes |
| `GET/POST /api/issues/{id}/comments` | the thread, and the agent bridge |
| `GET /api/agents` | who work can be handed to |

Unknown statuses and priorities decode to a labelled fallback rather than
failing a whole page, so a server that grows a new status will not blank the
board.

Sub-tasks are derived from the issues already loaded rather than fetched from
`/api/issues/{id}/children`, so an agent's drafted plan shows up on the parent
without an extra round trip and without depending on that endpoint's grouping.

## Tests

```
swift test
```

53 tests covering payload decoding against real API shapes, the requests the
client puts on the wire, lane grouping and ordering, the spoken digest, the
agent conversation round trip, and speech term parsing in English and German.

The SwiftUI layer is not covered — it needs a Mac with Xcode to build at all.
