## Project Overview

This repository contains an ambitious enterprise-grade web platform designed to function as a browser-based operating environment.

The long-term vision is to provide an integrated workspace similar in capability to Google Workspace + Google Drive, while presenting the experience as a cohesive web-based operating system.

The platform will eventually include:

- Desktop-like operating system shell
- Window management
- Application launcher
- Taskbar / dock
- File manager
- Cloud storage
- Folder management
- File uploads/downloads
- File sharing
- Permissions
- File versioning
- Document editor
- Spreadsheet editor
- Presentation editor
- Image editor
- Flowchart/diagram editor
- Calculator
- Email
- Chat
- Notifications
- Search
- Collaboration
- Offline functionality
- Synchronization
- AI-powered productivity features
- Enterprise administration
- Organizations and teams
- Billing/subscriptions
- Audit logs
- Enterprise security
- Future third-party application support

The project should be treated as a serious long-term platform rather than a simple CRUD application.

---

# 1. Core Architectural Philosophy

## Primary principle

Build the application as a:

> Modular monolith with strong domain boundaries, designed so individual domains can later be extracted into independent services.

Do NOT start with a large microservice architecture.

The initial architecture should optimize for:

- Development speed
- Maintainability
- Strong boundaries
- Type safety
- Reliability
- Testability
- Offline support
- Future scalability
- Future service extraction

Avoid premature infrastructure complexity.

---

# 2. High-Level Architecture

The system should conceptually be divided into:

```text
                    WEB CLIENT
                        │
                        ▼
                 OS SHELL / PLATFORM
                        │
          ┌─────────────┼─────────────┐
          │             │             │
          ▼             ▼             ▼
       Identity       Files       Collaboration
          │             │             │
          ▼             ▼             ▼
     Organizations   Sharing      Documents
     Users           Search       Spreadsheets
     Teams           Versions     Presentations
     Billing                       Chat
                                   Email
                        │
                        ▼
                 INFRASTRUCTURE
                        │
        ┌───────────────┼────────────────┐
        │               │                │
        ▼               ▼                ▼
   PostgreSQL     Object Storage       Redis
        │
        ├───────────────┐
        │               │
        ▼               ▼
     pgvector       Search Engine
     (later)         (later)
```

---

# 3. OS Shell Architecture

The application should NOT be structured as a traditional SaaS dashboard.

Avoid:

```text
Dashboard
├── Drive
├── Docs
├── Sheets
├── Mail
└── Chat
```

Instead, build a platform shell:

```text
Operating Environment
│
├── Desktop
├── Window Manager
├── Application Launcher
├── Taskbar / Dock
├── Notification Center
├── Search
├── Clipboard
├── File System Abstraction
├── User Preferences
├── Authentication
├── Network State
├── Offline State
├── Sync Engine
│
└── Applications
    ├── Files
    ├── Documents
    ├── Spreadsheets
    ├── Presentations
    ├── Images
    ├── Diagrams
    ├── Mail
    ├── Chat
    ├── Calculator
    └── Future Applications
```

The OS shell is a first-class platform layer.

Applications should consume common platform capabilities rather than independently implementing them.

---

# 4. Platform APIs

The architecture should eventually expose internal platform APIs similar to:

```typescript
platform.files.open()
platform.files.save()
platform.files.share()

platform.windows.open()
platform.windows.close()

platform.notifications.show()

platform.clipboard.copy()
platform.clipboard.read()

platform.search.query()

platform.auth.currentUser()

platform.network.status()

platform.sync.status()
```

These APIs should provide a consistent interface to applications.

Future applications should be able to use platform capabilities without directly depending on infrastructure implementation details.

---

# 5. Frontend Architecture

Preferred frontend principles:

- TypeScript
- React
- Component-based architecture
- Strong type safety
- Accessible UI
- Responsive layout
- Desktop-first OS experience
- Offline-first foundations
- Clear separation of server state and client state

Recommended conceptual structure:

```text
src/
├── shell/
│   ├── desktop/
│   ├── window-manager/
│   ├── taskbar/
│   ├── launcher/
│   ├── notifications/
│   └── system-tray/
│
├── apps/
│   ├── files/
│   ├── documents/
│   ├── spreadsheets/
│   ├── presentations/
│   ├── image-editor/
│   ├── diagrams/
│   ├── mail/
│   ├── chat/
│   └── calculator/
│
├── platform/
│   ├── auth/
│   ├── api/
│   ├── sync/
│   ├── offline/
│   ├── storage/
│   └── realtime/
│
├── components/
└── design-system/
```

Do not put all frontend logic into one giant global state store.

Separate:

1. Server state
2. Application state
3. UI state
4. Offline/local state

---

# 6. State Management

Server state should be managed independently from UI state.

Server state includes:

- Files
- Users
- Organizations
- Teams
- Documents
- Permissions
- Messages
- Notifications
- Billing data

UI/application state includes:

- Current window
- Window position
- Selected files
- Open applications
- Sidebar state
- Theme
- Dialog state
- Temporary UI state

Do not use a single global store for everything.

---

# 7. Design System

The platform requires a unified design system.

Recommended architecture:

```text
Design Tokens
    ↓
Primitives
    ↓
Components
    ↓
OS Components
    ↓
Application Components
    ↓
Applications
```

Design tokens should define:

- Colors
- Typography
- Spacing
- Border radius
- Elevation
- Motion
- Icons
- Sizing
- Focus states
- Accessibility states

UI primitives should include:

- Button
- Input
- Select
- Menu
- Context menu
- Dialog
- Drawer
- Tooltip
- Popover
- Tabs
- Dropdown
- Toast
- Progress indicator

OS-specific components should include:

- Window
- Window controls
- Desktop
- Taskbar
- Dock
- Application launcher
- File grid
- File tree
- Context menu
- Notification
- System tray
- Command palette

All applications should share the same design language.

---

# 8. Design Philosophy

The interface should feel like a coherent operating environment rather than a collection of unrelated SaaS products.

Important UX principles:

- Consistent interactions
- Keyboard shortcuts
- Drag and drop
- Context menus
- Multi-selection
- Command palette
- Window management
- Clear loading states
- Clear offline states
- Clear synchronization states
- Clear error states
- Accessible interactions
- Predictable navigation

Applications should feel native to the platform.

---

# 9. Backend Architecture

The backend should initially be a modular monolith.

Recommended conceptual structure:

```text
src/
├── modules/
│   ├── identity/
│   ├── organizations/
│   ├── users/
│   ├── files/
│   ├── folders/
│   ├── sharing/
│   ├── permissions/
│   ├── documents/
│   ├── spreadsheets/
│   ├── presentations/
│   ├── chat/
│   ├── email/
│   ├── notifications/
│   ├── search/
│   ├── billing/
│   └── ai/
│
├── infrastructure/
│   ├── database/
│   ├── storage/
│   ├── redis/
│   ├── queue/
│   ├── email/
│   └── observability/
│
└── platform/
    ├── authentication/
    ├── authorization/
    ├── events/
    └── configuration/
```

Organize backend code primarily around business domains rather than technical layers.

Avoid creating a huge structure such as:

```text
controllers/
models/
services/
repositories/
utils/
```

with every domain mixed together.

Domain boundaries should remain obvious.

---

# 10. Database Strategy

## Primary database: PostgreSQL

PostgreSQL is the primary system of record.

Use PostgreSQL for:

- Users
- Organizations
- Teams
- Memberships
- Workspaces
- File metadata
- Folder metadata
- File permissions
- Sharing
- File versions metadata
- Documents metadata
- Comments
- Tasks
- Chat channels
- Chat messages
- Email metadata
- Notifications
- Billing
- Subscriptions
- Audit logs
- Application configuration

PostgreSQL should be treated as the authoritative transactional database.

---

# 11. Object Storage

Do NOT store large files directly inside PostgreSQL.

Use S3-compatible object storage for:

- Uploaded files
- Documents
- Images
- Videos
- Audio
- Attachments
- File versions
- Generated previews
- Thumbnails
- Exported documents
- Other binary assets

Examples:

- Amazon S3
- Cloudflare R2
- Google Cloud Storage
- Azure Blob Storage
- Other S3-compatible systems

PostgreSQL stores metadata and references to objects.

Example:

```text
PostgreSQL

files
├── id
├── organization_id
├── owner_id
├── filename
├── mime_type
├── size
├── version
├── parent_folder_id
└── object_storage_key
```

Object storage:

```text
bucket/
├── originals/
├── versions/
├── previews/
└── thumbnails/
```

---

# 12. Redis

Redis should NOT be the primary database.

Use Redis for:

- Cache
- Sessions where appropriate
- Rate limiting
- Temporary locks
- Presence
- Typing indicators
- Realtime ephemeral state
- Short-lived tokens
- Queue infrastructure
- Pub/Sub where appropriate

Data stored exclusively in Redis should generally be considered ephemeral/rebuildable unless explicitly designed otherwise.

---

# 13. Search

Initially use PostgreSQL capabilities for search.

Do not introduce a dedicated search engine prematurely.

PostgreSQL can handle:

- Basic file search
- Filename search
- Metadata search
- Initial full-text search
- Filtering

When search complexity and scale justify it, introduce OpenSearch or Elasticsearch.

Potential future search capabilities:

- Full document content search
- OCR search
- Email search
- Ranking
- Facets
- Autocomplete
- Semantic search

The search engine must NOT become the source of truth.

Architecture:

```text
PostgreSQL
    │
    ▼
Domain Event
    │
    ▼
Search Indexing Worker
    │
    ▼
Search Engine
```

---

# 14. Vector Search / AI

Do not introduce a dedicated vector database at the beginning.

Use PostgreSQL + pgvector initially if vector search is required.

Potential use cases:

- Semantic document search
- Similar files
- AI document retrieval
- Knowledge bases
- Recommendations
- AI assistants
- Context retrieval

Example:

```text
document
    ↓
chunk
    ↓
embedding
    ↓
pgvector
```

Only introduce a dedicated vector database when real scale or workload characteristics justify it.

---

# 15. Multi-Tenancy

The platform is intended for businesses and must therefore be designed as a multi-tenant system.

Use organizations/tenants as a fundamental concept.

Conceptually:

```text
Organization
│
├── Users
├── Teams
├── Workspaces
├── Files
├── Documents
├── Applications
└── Billing
```

Core entities should generally contain an organization/tenant identifier where appropriate.

Example:

```text
files
├── id
├── organization_id
├── owner_id
├── parent_folder_id
└── ...
```

---

# 16. Multi-Tenant Database Strategy

Initially use:

```text
Shared PostgreSQL Database
        +
tenant_id / organization_id
```

Do NOT create a separate database for every organization at the beginning.

Avoid:

```text
Company A → Database A
Company B → Database B
Company C → Database C
```

unless there is a specific enterprise isolation requirement.

For very large enterprise customers, dedicated databases/infrastructure may be introduced later.

---

# 17. Authorization

Authorization must be enforced server-side.

Do not rely on frontend permission checks.

The authorization model should conceptually answer:

```text
Can USER
    perform ACTION
    on RESOURCE
    within ORGANIZATION?
```

Consider:

- RBAC
- Resource permissions
- Team permissions
- Sharing permissions
- Organization-level administration
- Future ABAC if required

Permission logic should be centralized rather than scattered throughout individual controllers.

---

# 18. Offline Architecture

Offline support is a core architectural requirement.

Do not treat offline functionality as a later feature.

The frontend should have:

```text
UI
 │
 ▼
Local Data Layer
 │
 ├── IndexedDB
 └── Local Cache
 │
 ▼
Sync Engine
 │
 ▼
API
```

Recommended browser technologies:

- IndexedDB
- Service Worker
- Web Workers where useful
- Local caching
- Background synchronization where supported

---

# 19. Sync Model

User actions should be modeled as operations that can be synchronized.

Conceptually:

```text
User Action
    ↓
Local State Updated
    ↓
Operation Added To Sync Queue
    ↓
Attempt Server Synchronization
    ↓
Success
    OR
Failure / Offline
```

When offline:

```text
User Action
    ↓
Local State Updated
    ↓
Pending Operation
    ↓
UI Indicates Offline/Pending
```

When connectivity returns:

```text
Network Restored
    ↓
Sync Queue
    ↓
Server
    ↓
Reconcile Local State
```

---

# 20. Offline UI

Offline and failed operations must be first-class UI states.

Use operation states such as:

```text
idle
pending
processing
success
failed
retrying
offline
```

The user should always understand:

1. What happened
2. Why it happened
3. Whether their work was saved
4. Whether the operation will retry
5. What they can do

Example:

```text
Uploading...
[████████░░] 80%
```

or:

```text
Could not upload

You are offline. Your change is saved locally
and will be synchronized when you reconnect.

[Retry]
```

Errors should appear near the relevant operation where practical.

Do not rely only on a generic global error toast.

---

# 21. Collaboration

Documents, spreadsheets, presentations, and other collaborative applications should be designed around a synchronization model from the beginning.

Investigate:

- CRDT
- Operational Transformation
- Realtime synchronization
- Conflict resolution
- Offline editing
- Version history

CRDT-based collaboration should be strongly considered for offline-first collaborative editing.

The exact implementation should be selected based on the editor technology and workload.

---

# 22. Realtime Architecture

Use WebSockets or SSE where appropriate.

Realtime functionality may include:

- Chat messages
- Presence
- Typing indicators
- Collaboration
- Notifications
- File operation updates
- Sync state
- Document changes

Conceptually:

```text
Client
  ↕
Realtime Gateway
  ↕
Domain/Application Layer
  ↕
PostgreSQL / Redis
```

Redis may be used for ephemeral realtime state and coordination.

---

# 23. Background Jobs

Long-running or expensive operations must not block normal API requests.

Use background workers for:

- Thumbnail generation
- Image processing
- Video processing
- OCR
- Virus scanning
- Document conversion
- Search indexing
- AI processing
- Email sending
- Notifications
- File cleanup
- Data exports
- Import processing

Conceptually:

```text
API
 │
 ▼
Queue
 │
 ├── Thumbnail Worker
 ├── OCR Worker
 ├── Virus Scan Worker
 ├── Search Worker
 ├── AI Worker
 └── Notification Worker
```

---

# 24. Domain Events

Use domain events to decouple background processing.

Examples:

```text
FileUploaded
FileDeleted
FileShared
FileRenamed
FileVersionCreated
DocumentUpdated
UserInvited
MessageSent
SubscriptionChanged
```

Example:

```text
FileUploaded
    │
    ├── Thumbnail Generator
    ├── Virus Scanner
    ├── Search Indexer
    ├── Audit Logger
    └── AI Processor
```

Domain events should be designed carefully and should not become an uncontrolled event-bus architecture.

---

# 25. Microservices Strategy

Do NOT immediately split the platform into dozens of microservices.

Start with a modular monolith.

Potential future services may include:

```text
Identity Service
File Service
Collaboration Service
Search Service
Notification Service
AI Service
Billing Service
```

Extract a module into a service only when there is a concrete reason such as:

- Independent scaling requirement
- Independent deployment requirement
- Infrastructure isolation
- Reliability isolation
- Team ownership
- Significant workload difference
- Security boundary

The modular architecture must make service extraction possible without requiring a rewrite.

---

# 26. Email Architecture

Email is a separate domain.

If the platform eventually provides a full email service, account for:

- SMTP
- IMAP
- Mail queues
- Delivery
- Spam filtering
- Attachments
- Mailbox storage
- Search
- Threading
- Retention
- Compliance

Email metadata can use PostgreSQL.

Email attachments should use object storage.

Email search may eventually use a dedicated search engine.

Do not allow email requirements to distort the architecture of the rest of the platform.

---

# 27. Editors

The platform may eventually contain:

- Document editor
- Spreadsheet editor
- Presentation editor
- Image editor
- Diagram/flowchart editor

Do not automatically build every editor engine from scratch.

Evaluate existing mature open-source libraries and editor engines where appropriate.

The platform's value should increasingly come from:

- Integration
- Unified storage
- Collaboration
- Sharing
- Offline support
- Search
- AI
- Platform APIs
- Enterprise administration

rather than unnecessarily rebuilding every underlying editing primitive.

---

# 28. Security

Security must be designed from the beginning.

The platform should eventually support:

- Authentication
- MFA
- Authorization
- RBAC
- Organization administration
- Resource permissions
- Secure sharing
- Session management
- Audit logs
- Encryption
- Rate limiting
- Data retention
- Enterprise SSO
- SCIM
- Compliance controls
- Security monitoring

Never assume frontend checks provide security.

All security-sensitive operations must be validated server-side.

---

# 29. Observability

Build observability into the platform from the beginning.

The system should eventually provide:

- Structured logging
- Metrics
- Distributed tracing
- Error tracking
- Performance monitoring
- Audit events
- Background job monitoring

A future administrator/developer should be able to trace:

```text
Request
 ↓
Authentication
 ↓
Authorization
 ↓
Application Domain
 ↓
Database / Storage
 ↓
Background Job
 ↓
Result
```

Errors should contain enough contextual information to diagnose failures without exposing sensitive data.

---

# 30. Recommended Initial Technology Architecture

Unless there is a strong project-specific reason otherwise, the initial architecture should roughly be:

```text
Frontend
────────
React
TypeScript
Tailwind CSS
Headless UI primitives
IndexedDB
Service Worker
WebSocket / SSE

Backend
───────
TypeScript backend
Modular monolith
REST and/or GraphQL
WebSocket gateway

Database
────────
PostgreSQL

File Storage
────────────
S3-compatible object storage

Cache / Realtime / Jobs
───────────────────────
Redis

Search
──────
PostgreSQL initially
OpenSearch later if justified

AI Vector Search
────────────────
pgvector initially

Offline
───────
IndexedDB + Service Worker + Sync Engine
```

Specific libraries/frameworks can change if there is a compelling technical reason. Preserve the architectural principles even when technology choices change.

---

# 31. Recommended Storage Architecture

The initial storage architecture should be:

```text
                       PLATFORM
                          │
          ┌───────────────┼────────────────┐
          │               │                │
          ▼               ▼                ▼
    PostgreSQL       Object Storage       Redis
    ──────────       ──────────────       ─────
    Core data        User files           Cache
    Metadata         Documents            Sessions
    Permissions      Images               Presence
    Users            Videos               Queues
    Organizations    Attachments           Realtime
    Messages         Versions
    Billing
    Audit
          │
          ├───────────────┐
          │               │
          ▼               ▼
       pgvector       OpenSearch
       (later)         (later)
          │               │
          ▼               ▼
          AI             Search
```

Browser:

```text
Browser
   │
   ├── IndexedDB
   │      ↓
   │   Offline State
   │
   ├── Service Worker
   │
   └── Sync Engine
          ↓
         API
```

---

# 32. Development Methodology

Do not attempt to build the entire product simultaneously.

Develop vertical slices.

Recommended progression:

## Phase 1 — Platform Foundation

Build:

- Authentication
- Organizations
- Users
- OS shell
- Window manager
- Application launcher
- File system abstraction
- File upload/download
- Basic permissions
- Basic sharing
- Notifications
- Offline state
- Sync foundations

## Phase 2 — Drive

Build:

- Folders
- File manager
- File grid/list
- Upload manager
- Download manager
- Search
- Trash
- File versions
- Sharing
- Permissions
- File preview
- Offline files

## Phase 3 — Documents

Build:

- Document editor
- Autosave
- Version history
- Sharing
- Comments
- Realtime collaboration
- Offline editing
- Conflict handling

## Phase 4 — Productivity Applications

Build:

- Spreadsheet
- Presentation
- Diagram/flowchart
- Image editor

## Phase 5 — Communication

Build:

- Chat
- Email
- Calendar
- Tasks
- Notifications

## Phase 6 — AI

Build:

- AI search
- Summarization
- Classification
- Extraction
- Generation
- Automation
- AI assistants
- Agents

AI should become a platform capability rather than merely a standalone chatbot.

---

# 33. AI Architecture

AI should eventually provide cross-application capabilities.

Conceptually:

```text
AI Platform
│
├── Search
├── Summarization
├── Generation
├── Classification
├── Extraction
├── Translation
├── Analysis
├── Automation
└── Agents
```

AI should be able to interact with platform permissions.

For example, an AI agent must not retrieve a document the current user cannot access.

AI authorization must inherit the platform's security model.

---

# 34. Enterprise Architecture

Because the long-term target includes businesses, enterprise requirements must influence foundational design.

Consider:

- Organizations
- Workspaces
- Teams
- Roles
- Permissions
- SSO
- MFA
- SCIM
- Audit logs
- Retention
- Data governance
- Enterprise administration
- Billing
- Usage limits
- Storage quotas
- API access
- Security policies

Do not add enterprise architecture as an afterthought.

---

# 35. Coding Principles

When implementing new functionality:

1. Prefer simple solutions.
2. Preserve existing domain boundaries.
3. Avoid unnecessary abstractions.
4. Do not introduce infrastructure without a concrete requirement.
5. Keep modules independently understandable.
6. Keep business logic out of UI components where possible.
7. Keep authorization server-side.
8. Make errors explicit.
9. Make asynchronous operations observable.
10. Design new features with offline behavior in mind.
11. Prefer idempotent operations where appropriate.
12. Write tests for critical business logic.
13. Avoid duplicated business rules.
14. Prefer typed interfaces.
15. Do not silently swallow errors.
16. Do not introduce breaking architectural changes without evaluating their impact.
17. Keep `.env.example` in sync with `.env`.

## Configuration rule

Whenever a `.env` file changes, update the matching `.env.example` in the same
change.

`.env` files are never committed, so `.env.example` is the only description of
what the service needs. A variable that exists only in someone's local `.env`
does not exist for anyone else: the next checkout, the next environment and CI
will all be missing it, and the failure appears far from its cause.

This applies to every service that has an env file — the root Compose
configuration, the API, the SMTP gateway and the UI.

Rules:

1. Adding, renaming or removing a variable in `.env` means the same edit to
   `.env.example`.
2. Adding a variable to configuration code (for example a new key in the
   validated environment schema) means adding it to `.env.example`, with its
   default, even when nothing sets it yet.
3. `.env.example` carries placeholders and safe defaults only — never a real
   secret, credential or production hostname.
4. Mark whether a variable is required. A required variable has no default and
   the service must refuse to start without it; everything else documents its
   built-in default.
5. Do not delete a variable from `.env.example` while any code still reads it.

Check the four pairs before committing:

```sh
./scripts/check-env.sh          # report drift; non-zero exit if out of sync
./scripts/check-env.sh --fix    # create missing .env files, append missing keys
```

The check reports both directions, and they mean different things: a key in
`.env.example` but not `.env` falls back to its default, while a key in `.env`
but not `.env.example` is undocumented configuration that will not survive a
fresh checkout.

---

# 36. Error Handling

Errors must be explicit and actionable.

Avoid generic errors such as:

```text
Something went wrong.
```

Prefer:

```text
Upload failed

The connection was interrupted while uploading
"project-report.pdf".

Your local copy is safe.

[Retry]
```

Errors should distinguish between:

- Validation errors
- Permission errors
- Authentication errors
- Network errors
- Offline state
- Conflict errors
- Server errors
- Storage errors
- Rate limiting
- Background processing failures

---

# 37. API Design

APIs should be:

- Versionable
- Typed
- Predictable
- Idempotent where appropriate
- Secure
- Observable
- Explicit about errors

Avoid leaking infrastructure details into public application APIs.

For example, application code should not need to know whether a file is stored in S3, R2, or another object store.

---

# 38. File Architecture

A file should be treated as metadata + one or more stored objects.

Conceptually:

```text
File
│
├── Metadata
│   ├── ID
│   ├── Name
│   ├── Type
│   ├── Size
│   ├── Owner
│   ├── Organization
│   └── Folder
│
├── Permissions
│
├── Versions
│
└── Object Storage
    ├── Original
    ├── Version 1
    ├── Version 2
    ├── Preview
    └── Thumbnail
```

Do not couple the domain model directly to a specific storage provider.

---

# 39. File Upload Architecture

Large file uploads should eventually support:

- Multipart upload
- Resumable uploads
- Progress reporting
- Cancellation
- Retry
- Offline interruption handling
- Integrity verification
- Background processing

The frontend should not assume an upload always succeeds immediately.

Model uploads as asynchronous operations.

---

# 40. Versioning

Important user content should support version history where appropriate.

Examples:

- Documents
- Spreadsheets
- Presentations
- Files

Versioning should allow:

```text
Version 1
Version 2
Version 3
Current Version
```

Do not overwrite valuable user content without considering recovery/versioning requirements.

---

# 41. Testing Strategy

Testing should exist at multiple levels.

## Unit tests

For:

- Business logic
- Permissions
- Validation
- Data transformations
- Synchronization algorithms

## Integration tests

For:

- Database
- Storage
- APIs
- Authentication
- Background jobs

## End-to-end tests

For:

- Login
- File upload
- File sharing
- Document editing
- Offline behavior
- Synchronization
- Collaboration

Critical user workflows should have automated end-to-end coverage.

---

# 42. Performance Principles

Performance is important because the platform will contain many applications.

Avoid:

- Loading entire file lists unnecessarily
- Loading large documents into memory unnecessarily
- Blocking the main thread with expensive computation
- Unbounded realtime subscriptions
- Excessive API calls
- Large global state updates

Use:

- Pagination
- Virtualized lists
- Lazy loading
- Code splitting
- Background workers
- Caching
- Incremental synchronization
- Streaming where appropriate

---

# 43. Accessibility

Accessibility is a platform requirement.

The OS shell should support:

- Keyboard navigation
- Focus management
- Screen readers
- Proper ARIA semantics
- Reduced motion
- Sufficient contrast
- Visible focus states
- Keyboard shortcuts with discoverable alternatives

Do not build the OS shell entirely around mouse interaction.

---

# 44. Mobile and Responsive Behavior

The desktop experience is primary because the product behaves like an operating system.

However, the architecture should allow mobile/tablet interfaces.

Do not force the desktop window manager onto small screens.

Instead:

```text
Desktop
→ Window-based OS experience

Tablet
→ Adaptive application experience

Mobile
→ Mobile-native navigation model
```

The underlying platform APIs should remain shared.

---

# 45. Architecture Decision Rule

When making an architectural decision, prefer this order:

1. Correctness
2. Security
3. Maintainability
4. Simplicity
5. Developer productivity
6. Performance
7. Scalability
8. Operational complexity

Do not sacrifice simplicity for hypothetical future scale.

But do not make decisions that make future scaling impossible.

---

# 46. Technology Introduction Rule

Before adding a new database, framework, service, queue, or infrastructure component, answer:

1. What problem does it solve?
2. Can the current architecture solve the problem?
3. What operational complexity does it introduce?
4. What failure modes does it introduce?
5. Does the project currently need it?
6. Can it be added later?
7. Does it create vendor lock-in?
8. Does it make local development harder?

Prefer fewer technologies when they satisfy the requirements.

---

# 47. Initial Database Decision

The default database architecture is:

```text
PostgreSQL
+
Object Storage
+
Redis
+
IndexedDB
```

Additional systems should be introduced only when justified:

```text
OpenSearch
    → advanced search

pgvector
    → vector/AI retrieval

Dedicated vector DB
    → only at significant scale

Kafka/event streaming
    → only when event streaming requirements justify it

Analytics warehouse
    → when analytics workloads should be separated
```

---

# 48. What NOT To Do

Do NOT:

- Start with dozens of microservices.
- Create one database per customer.
- Store large binary files in PostgreSQL.
- Use Redis as the primary source of truth.
- Introduce Kafka without a real need.
- Introduce Elasticsearch immediately.
- Introduce a dedicated vector database immediately.
- Build every editor engine from scratch without evaluating existing technology.
- Make offline support an afterthought.
- Trust frontend authorization.
- Put every frontend state variable into one global store.
- Couple application logic directly to infrastructure vendors.
- Scatter permission logic throughout the codebase.
- Hide network failures from users.
- Swallow asynchronous errors.
- Introduce abstractions solely for hypothetical future requirements.

---

# 49. Definition of Done for Features

A feature should not be considered complete merely because the happy path works.

For significant features, evaluate:

```text
✓ Happy path
✓ Loading state
✓ Empty state
✓ Validation
✓ Permission handling
✓ Authentication handling
✓ Network failure
✓ Offline behavior
✓ Retry behavior
✓ Error UI
✓ Accessibility
✓ Performance
✓ Logging/observability
✓ Tests
```

Where offline functionality is not supported, the UI should explicitly explain that the feature requires an internet connection.

---

# 50. Agent Instructions

When working on this repository, the coding agent must:

1. Read this CLAUDE.md before making architectural changes.
2. Preserve the modular architecture.
3. Prefer existing project patterns over introducing new patterns.
4. Avoid unnecessary dependencies.
5. Avoid unnecessary infrastructure.
6. Keep domain boundaries clear.
7. Consider multi-tenancy for new persistent resources.
8. Consider authorization for every resource-accessing feature.
9. Consider offline behavior for user-facing operations.
10. Consider failure states, not only successful execution.
11. Keep file metadata and file contents separate.
12. Use PostgreSQL as the default source of truth.
13. Use object storage for binary files.
14. Use Redis for appropriate ephemeral/cache/realtime workloads.
15. Keep search and AI infrastructure decoupled from core transactional storage.
16. Do not introduce microservices unless there is a concrete architectural reason.
17. Do not replace existing architecture merely because another technology is fashionable.
18. Prefer incremental, testable changes.
19. Do not make destructive database/schema changes without explicit consideration of existing data.
20. When uncertain, choose the simplest architecture that preserves the long-term platform boundaries.
21. Update `.env.example` in the same change as any `.env` or configuration-schema
    change, and verify with `./scripts/check-env.sh` (see §35, Configuration rule).

---

# 51. Architectural North Star

The ultimate architecture should evolve toward:

```text
                         WEB OS PLATFORM
                                │
                ┌───────────────┴────────────────┐
                │                                │
          OS SHELL                         PLATFORM APIs
                │                                │
       ┌────────┼────────┐              ┌────────┼────────┐
       │        │        │              │        │        │
     Files    Docs     Apps           Auth     Search    Sync
       │        │        │              │        │        │
       └────────┼────────┘              └────────┼────────┘
                │                                │
                └──────────────┬─────────────────┘
                               │
                         DOMAIN MODULES
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
       Identity              Files             Collaboration
          │                    │                    │
       Users               Sharing              Docs
       Teams               Versions             Sheets
       Billing             Permissions           Slides
                                                Chat
                                                Email
                               │
                               ▼
                         INFRASTRUCTURE
                               │
          ┌────────────────────┼────────────────────┐
          │                    │                    │
     PostgreSQL          Object Storage           Redis
          │
          ├───────────────┬───────────────────────┐
          │               │                       │
       pgvector       Search Engine          Analytics
       (later)          (later)                (later)
```

The platform should remain cohesive from the user's perspective even if parts of the backend eventually become independent services.

The user should experience:

> **One operating environment containing many integrated applications.**

The architecture should therefore prioritize **platform consistency, domain boundaries, offline capability, security, and incremental scalability** over premature distributed-system complexity.
