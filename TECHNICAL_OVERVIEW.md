# PM Tool v2 — Technical Overview

Tài liệu này viết cho một software engineer đọc code và review, không phải
cho end-user. Mọi khẳng định về hành vi code đều trích `file:dòng` thật —
đã đọc code trực tiếp trước khi viết, không suy đoán từ kiến trúc "thường
thấy". Chỗ nào không chắc 100% được đánh dấu **[CHƯA XÁC MINH]** thay vì
đoán. Chỗ nào code thực tế lệch với `docs/BEHAVIOR_CONTRACT.md` hoặc
`docs/ACCEPTANCE_v2.md` được nêu rõ, không che.

---

## 1. Kiến trúc tổng thể

### Sơ đồ tầng backend

```
api/  →  services/  →  repositories/  →  models/  (SQLAlchemy ORM)
              ↑
             ai/   (companion, context, planning, providers)
```

Xác nhận bằng import thật của bộ ba `tasks`:

| File | Import chính |
|---|---|
| `backend/api/tasks.py:10` | `from services import subtask_service, task_collaborator_service, task_service` |
| `backend/services/task_service.py:6-8` | `from models.task import Task`, `from repositories import task_repository`, `from repositories.task_repository import repository` |
| `backend/repositories/task_repository.py:6-7` | `from models.task import Task`, `from repositories.base import BaseRepository` |

`ai/` không phải một tầng ngang hàng nằm giữa `api/` và `services/` — nó là
**client của `services/`**, được gọi trực tiếp từ `api/` (route AI Planning
nằm ở `backend/api/planning_sessions.py`, gọi thẳng
`backend/ai/planning/planning.py`/`backend/ai/context/context_builder.py`),
và các module trong `ai/` gọi ngược vào `services/` khi cần đọc/ghi DB. Ví
dụ: `backend/ai/context/context_builder.py:16` —
`from services import document_service, planning_session_service`.

### Quy tắc phụ thuộc giữa các tầng + test enforce

**Quy tắc bị test chặn cứng:** `ai/` chỉ được import `services/`, KHÔNG
BAO GIỜ được import `repositories/` hoặc `models/` trực tiếp.

**Test:** `backend/tests/test_ai_boundary.py`, hàm
`test_ai_package_never_imports_repositories_or_models_directly` (dòng
38-53). Cơ chế: parse AST tĩnh (`ast.parse` + `ast.walk`) lấy toàn bộ
top-level import (`ast.Import`/`ast.ImportFrom` với `level == 0`, bỏ qua
relative import nội bộ) của mọi file `.py` dưới `backend/ai/`, so với tập
cấm `FORBIDDEN_TOP_LEVEL_MODULES = {"repositories", "models"}` (dòng 18):

```python
# backend/tests/test_ai_boundary.py:21-31
def _top_level_imports(file_path: pathlib.Path) -> set[str]:
    tree = ast.parse(file_path.read_text(encoding="utf-8"), filename=str(file_path))
    modules: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                modules.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.module and node.level == 0:
                modules.add(node.module.split(".")[0])
    return modules
```

Đây là 1 test bình thường trong suite mặc định (chạy mỗi lần `pytest`),
không phải linter riêng.

**Vì sao `ai/` nằm cùng process** (v1 tách thành `ai-service` riêng) —
trích nguyên văn docstring đầu file test
(`backend/tests/test_ai_boundary.py:1-11`):

> "In the old repo this was a network boundary (ai-service was a separate
> process, physically unable to import Backend's Python packages); now
> that everything runs in one process, nothing stops a stray
> `from repositories.task_repository import ...` inside ai/ except this
> test. It must run in CI and fail loudly the moment such an import
> appears."

**Đánh đổi thật** (suy trực tiếp từ đoạn trên):
- **Được:** bớt 1 network hop, bớt 1 process cần deploy/scale/monitor
  riêng — đơn giản hoá vận hành.
- **Mất:** ranh giới kiến trúc chuyển từ "vật lý không thể vi phạm" (khác
  process, khác interpreter) thành "chỉ còn 1 bài test giữ". Xoá/sửa
  `test_ai_boundary.py` là ranh giới biến mất ngay, không ai biết cho tới
  khi coupling AI↔DB gây ra sự cố thật.

Lưu ý: `pm_tool_mvp/` (repo v1) không được đọc trực tiếp trong lượt nghiên
cứu viết tài liệu này — mọi so sánh với v1 ở trên dựa trên trích dẫn có
sẵn trong comment/docstring của chính code v2.

**Quan sát thêm (không bị test chặn, nhưng nhất quán 100%):** `api/`
không bao giờ import `repositories` trực tiếp (0 kết quả grep), nhưng có
import `models` ở 6 file (`auth.py`, `deps.py`, `documents.py`,
`ideas.py`, `planning_sessions.py`, `projects.py`) — toàn bộ chỉ để
type-hint `User` cho `current_user: User = Depends(get_current_user)`,
không dùng để query DB. Ví dụ `backend/api/ideas.py:6` —
`from models.user import User`.

### Frontend — cấu trúc & ranh giới

```
frontend/src/
├── api/          # gọi HTTP thuần (fetch), KHÔNG chứa JSX/logic UI
├── components/   # UI thuần, chia theo domain
├── pages/        # 1 file/route, ghép api/ + components/ + state
├── hooks/        # useAuth.tsx (Context session), useLocale.ts
├── theme/        # antdTheme.ts
├── i18n/         # react-i18next + locales/en.json, vi.json
├── styles/       # tokens.css, global.css — design token CSS variable
├── types/        # interface TypeScript khớp Pydantic *Out schema
└── utils/        # hàm thuần, không gọi API, không JSX
```

State: **TanStack Query** cho server state — 1 `QueryClient` khởi tạo DUY
NHẤT tại `frontend/src/App.tsx:16` (`const queryClient = new
QueryClient();`), bọc app qua `<QueryClientProvider client={queryClient}>`
(dòng 22). **React Context** (`frontend/src/hooks/useAuth.tsx`) chỉ giữ
session/user hiện tại — không dùng Redux/Zustand hay state-management
library nào khác **[CHƯA XÁC MINH lại `package.json` trong lượt viết tài
liệu này — dựa trên các lần đọc `package.json` ở nhiều tác vụ trước trong
cùng phiên làm việc]**.

Ranh giới cụ thể: `frontend/src/api/tasks.ts` chỉ gọi `apiClient`, trả về
Promise thuần; `frontend/src/pages/KanbanPage.tsx` là nơi DUY NHẤT của
trang Kanban gọi `useQuery`/`queryClient.setQueryData` — các component
trong `components/kanban/*` (KanbanColumn, DraggableTaskCard, Swimlane)
không tự gọi API, chỉ nhận props/callback.

---

## 2. Cây thư mục có chú thích

### `backend/`

```
backend/
├── main.py                    # FastAPI app instance, đăng ký router, CORS + auth middleware
├── alembic.ini, alembic/      # Alembic config + env.py (đọc DATABASE_URL từ Settings, không từ URL tĩnh trong .ini) + versions/ (2 migration — xem mục 3)
├── pytest.ini                 # marker "real_llm", addopts = -m "not real_llm"
├── pyproject.toml             # cấu hình ruff (linter)
│
├── core/
│   ├── config.py              # Settings (Pydantic) — DATABASE_URL, OPENAI_API_KEY, JWT secret, MAX_UPLOAD_SIZE_BYTES,...
│   ├── security.py            # hash_password/verify_password (bcrypt), create_access_token/decode_access_token (JWT)
│   ├── auth_middleware.py     # middleware xác thực TOÀN APP — chặn 401 mặc định trừ PUBLIC_PATHS (xem mục 4c)
│   ├── errors.py              # AppError, NotFoundError — exception domain dùng chung services/
│   └── logging.py             # cấu hình logging chuẩn
│
├── db/
│   ├── base.py                 # SQLAlchemy declarative Base
│   └── session.py              # engine, SessionLocal, get_db() — FastAPI dependency sinh/đóng Session
│
├── models/                     # SQLAlchemy ORM — 1 file/bảng, xem mục 3
│   ├── mixins.py                # UUIDPKMixin, TimestampMixin
│   ├── enums.py                 # 4 enum: TaskStatus, TaskPriority, IdeaStatus, PlanningSessionStatus
│   └── {user,project,phase,task,subtask,sprint,task_collaborator,uploaded_document,idea,planning_session}.py
│
├── schemas/                    # Pydantic — request/response DTO, KHÔNG phải ORM
│
├── repositories/                # CRUD thuần, không chứa business rule
│   ├── base.py                  # BaseRepository generic (get/list/create/update/delete)
│   └── {model}_repository.py    # phần lớn chỉ `repository = BaseRepository(Model)`
│
├── services/                    # Business rule + transaction (db.commit() nằm ở đây)
│   └── {idea,phase,planning_session,approve_planning_session,project,sprint,subtask,task,task_collaborator,user,auth,document}_service.py
│
├── ai/                           # Chỉ được import services/ (test_ai_boundary.py enforce)
│   ├── types.py                  # Protocol dùng chung (PlanningSessionLike, UploadedDocumentLike) để tránh phải import models/ cho type hint
│   ├── providers/openai_provider.py   # gọi OpenAI thật, complete_json(), xử lý lỗi 429/502/503/4xx
│   ├── companion/companion.py         # chat tự do trước planning chính thức — reply()/reply_stream() (SSE)
│   ├── context/context_builder.py     # build_context() — phân loại 7 field theo 5 nhãn
│   └── planning/{deadline_gate,planning}.py   # has_deadline_signal(), generate() — 1 lệnh gọi LLM duy nhất
│
├── api/                          # FastAPI router — 1 file/resource, KHÔNG chứa business logic
│   └── {auth,deps,documents,health,ideas,phases,planning_sessions,projects,sprints,tasks,users}.py
│
├── scripts/                      # script vận hành thủ công [CHƯA XÁC MINH nội dung cụ thể]
│
└── tests/                        # ~30+ file, tên theo domain (test_ideas.py, test_tasks.py, test_planning_generate.py,
                                   # test_context_builder.py, test_ai_boundary.py, test_cascade_and_restrict.py,
                                   # test_approve.py, test_documents.py, test_openai_provider.py,...) — xem mục 7
```

### `frontend/src/`

```
frontend/src/
├── App.tsx                    # QueryClientProvider + BrowserRouter + route definitions
├── main.tsx                   # ReactDOM.createRoot — điểm vào ứng dụng
│
├── api/                        # gọi HTTP thuần, không JSX
│   ├── client.ts                # apiClient: get/post/patch/delete/postStream/postForm — wrapper fetch dùng chung, gắn JWT
│   ├── token.ts                  # đọc/ghi JWT vào localStorage
│   ├── sse.ts                    # parse Server-Sent Events (dùng cho companion-reply/stream)
│   └── {auth,documents,ideas,phases,planningSessions,projects,sprints,tasks,users}.ts
│
├── components/
│   ├── ai/          # CompanionChat, ContextPanel, ProposalEditor, IdeaComposer, IdeaList — UI AI Planning, tự viết (không AntD)
│   ├── common/       # PageHeader, EmptyState, Panel, StatusBadge, PriorityTag, BlockedTag — dùng lại nhiều trang
│   ├── dashboard/    # StatCard, MyTasksList, MyProjectsPanel, ProjectStageTracker
│   ├── gantt/         # GanttChart, GanttRow — tự viết, không dùng thư viện Gantt ngoài
│   ├── kanban/        # KanbanColumn, TaskCard, DraggableTaskCard, Swimlane, QuickAddTask — tự viết + @dnd-kit/core
│   ├── layout/        # AppShell (sidebar fixed + thu gọn), LocaleSwitcher
│   └── sprints/       # SprintCard, SprintTaskList
│
├── pages/             # 1 file/route: DashboardPage, KanbanPage, SprintsPage (gồm cả tab Gantt), AiPlanningPage, LoginPage
├── hooks/             # useAuth.tsx (Context session), useLocale.ts
├── i18n/              # index.ts (react-i18next init) + locales/{en,vi}.json
├── styles/            # tokens.css (design token), global.css
├── theme/             # antdTheme.ts
├── types/             # kanban.ts, planning.ts — interface TypeScript khớp Pydantic *Out schema
└── utils/             # hàm thuần: gantt.ts, phases.ts, sprints.ts, tasks.ts
```

`frontend/tests/` — ~25 file test (Vitest + Testing Library), tên khớp
component/luồng đang test (`IdeaList.test.tsx`, `KanbanColumn.test.tsx`,
`AppShell.test.tsx`, `ProposalEditor.test.tsx`,
`companionReplyStream.test.ts`,...).

---

## 3. Mô hình dữ liệu

### Bảng & cột chính

| Model | Bảng | Cột chính | FK (`ON DELETE`) | Constraint khác |
|---|---|---|---|---|
| `User` (`backend/models/user.py:8-20`) | `users` | `email` String(255) NOT NULL UNIQUE index; `name` NOT NULL; `password_hash` NOT NULL | — | — |
| `Project` (`project.py:10-45`) | `projects` | `name` NOT NULL; `description`/`summary`/`objective`/`current_context`/`constraints`/`ai_notes` Text nullable | `created_by`→users **SET NULL**; `manager_id`→users **SET NULL** | — |
| `Phase` (`phase.py:10-27`) | `phases` | `title` NOT NULL; `start_date`/`end_date` Date nullable | `project_id`→projects **CASCADE** NOT NULL | **KHÔNG có cột `status`** (xem bên dưới) |
| `Task` (`task.py:14-70`) | `tasks` | `title` NOT NULL; `status` String(20) default `"todo"`; `blocked` Boolean default `False`; `blocked_reason` Text nullable | `project_id`→projects **CASCADE** NOT NULL; `phase_id`→phases **SET NULL**; `sprint_id`→sprints **SET NULL**; `owner_id`→users **RESTRICT** NOT NULL | `CheckConstraint` cho status/priority |
| `Subtask` (`subtask.py:8-22`) | `subtasks` | `title` NOT NULL; `done` Boolean default `False`; `position` Integer default `0` | `task_id`→tasks **CASCADE** NOT NULL | **KHÔNG có** `start_date`/`end_date`/`assignee` |
| `Sprint` (`sprint.py:10-22`) | `sprints` | `name` NOT NULL; `start_date`/`end_date` Date **NOT NULL** (khác Task/Phase — không nullable) | `project_id`→projects **CASCADE** NOT NULL | `CheckConstraint("end_date >= start_date")` |
| `TaskCollaborator` (`task_collaborator.py:8-25`) | `task_collaborators` | không có cột nghiệp vụ, chỉ 2 FK | `task_id`→tasks **CASCADE**; `user_id`→users **CASCADE** | `UniqueConstraint(task_id, user_id)` |
| `UploadedDocument` (`uploaded_document.py:10-37`) | `uploaded_documents` | `filename` NOT NULL; `file_type` String(10) NOT NULL; `storage_path` Text NOT NULL; `extracted_text` Text nullable | `project_id`→projects **CASCADE** nullable; `uploaded_by`→users **SET NULL** | **KHÔNG có `planning_session_id`** — liên kết ngược qua `PlanningSession.document_ids` (JSONB array) |
| `Idea` (`idea.py:11-39`) | `ideas` | `content` Text NOT NULL; `status` default `"noted"` | `created_by`→users **RESTRICT** NOT NULL | `CheckConstraint` cho status |
| `PlanningSession` (`planning_session.py:12-61`) | `planning_sessions` | `status` default `"in_progress"`; `messages` JSONB default `[]`; `final_proposal` JSONB nullable; `document_ids` JSONB default `[]`; `planning_context` JSONB nullable | `project_id`→projects **SET NULL**; `idea_id`→ideas **SET NULL**; `created_by`→users **RESTRICT** NOT NULL | `CheckConstraint` cho status |

Mọi model dùng `UUIDPKMixin` (`id` String(36), UUID sinh bằng
`uuid.uuid4()` ở tầng Python — **không phải cột UUID native của
Postgres**, giữ schema portable). Đa số dùng thêm `TimestampMixin`
(`created_at`/`updated_at`) — ngoại lệ: `TaskCollaborator` và
`UploadedDocument` **không có** `TimestampMixin`.

### Quan hệ

```
User ──< Project (created_by, manager_id — cả 2 SET NULL)
User ──< Task (owner_id — RESTRICT, không xoá được User đang sở hữu Task)
Project ──< Phase ──< Task ──< Subtask
Project ──< Sprint ──< Task (gán qua sprint_id, không sở hữu — SET NULL)
Task ──< TaskCollaborator >── User (many-to-many phụ, owner riêng)
Project ──< UploadedDocument (CASCADE)
Idea ──< PlanningSession (idea_id, SET NULL) ── document_ids (JSONB, KHÔNG phải FK) >── UploadedDocument
PlanningSession ──> Project (project_id, gán sau khi Approve)
```

### Enum (`backend/models/enums.py`, toàn văn — chỉ 4 enum trong file)

| Enum | Giá trị |
|---|---|
| `TaskStatus` | `todo`, `in_progress`, `in_review`, `done` |
| `TaskPriority` | `high`, `medium`, `low` |
| `IdeaStatus` | `noted`, `planning`, `archived` |
| `PlanningSessionStatus` | `companion`, `in_progress`, `proposed`, `approved`, `rejected` |

> **⚠️ Lệch với `docs/BEHAVIOR_CONTRACT.md`:** mục H.2 khẳng định
> `models/enums.py:22-24` có `ActivityEntityType.ATTACHMENT`. Đã đọc trực
> tiếp `backend/models/enums.py` (36 dòng, toàn văn ở trên) — **không có
> `ActivityEntityType` hay bất kỳ enum thứ 5 nào**.
> `grep -rn "ActivityEntityType" backend/` (loại `__pycache__`) → **0 kết
> quả** trong toàn bộ `backend/`. Đây là lệch thật, đã xác minh 2 lần độc
> lập. Không rõ enum đã bị xoá sau khi contract ghi lại hay contract trích
> sai từ đầu — **[CHƯA XÁC MINH lý do lệch]**.

### `Phase.status` — rollup động, không lưu DB

`Phase` model (`backend/models/phase.py:10-15`) không có cột `status`.
Docstring ngay trong model:

> "No `status` column here on purpose: Phase status is always a dynamic
> rollup computed from its child Tasks at request time... Storing it
> would let it drift out of sync with the actual tasks."

Hàm tính (`backend/services/phase_service.py:21-29`):

```python
def compute_status(tasks: list[Task]) -> str:
    if not tasks:
        return STATUS_NO_TASKS                # "no_tasks"
    statuses = {task.status for task in tasks}
    if statuses == {TaskStatus.DONE.value}:
        return STATUS_DONE                     # "done"
    if statuses == {TaskStatus.TODO.value}:
        return STATUS_TODO                     # "todo"
    return STATUS_IN_PROGRESS                  # mọi trường hợp còn lại
```

Thuật toán: lấy **tập hợp (set)** status của mọi Task con → so khớp
CHÍNH XÁC với `{"done"}` hoặc `{"todo"}` → không khớp cả 2 (rỗng, trộn
lẫn, hoặc 100% task đang `in_review`) → fallback `"in_progress"`. Đây là
lý do **`in_review` không bao giờ xuất hiện ở cấp Phase** — kể cả khi
100% task con `in_review`.

> **⚠️ Lệch tên hàm với `docs/BEHAVIOR_CONTRACT.md`:** contract mục B.3(b)
> ghi `PhaseService._compute_status_from_tasks()`. Code thật là
> **`compute_status()`** — hàm cấp module, không phải method của class
> (không tồn tại class `PhaseService` trong file — xác nhận
> `grep -n "class PhaseService" backend/services/phase_service.py` ra 0
> kết quả). Lệch thuần tên gọi, thuật toán mô tả đúng.

`has_blocked_task()` (`phase_service.py:32-33`) tính độc lập, chỉ
`any(task.blocked for task in tasks)` — không phụ thuộc status.

### Trường KHÔNG tồn tại dù hay tưởng có

- **`Subtask`**: không có `start_date`, `end_date`, `assignee` — dù JSON
  đề xuất AI (`SubtaskProposalIn`, `backend/schemas/planning_session.py`)
  CÓ field `assignee`. Khi Approve tạo Subtask thật
  (`backend/services/approve_planning_session_service.py:109-112`),
  `assignee` trong JSON bị bỏ hoàn toàn, chỉ `title`/`done` được ghi.
- **`Phase`**: không có `status` (đã nói ở trên).
- **`UploadedDocument`**: không có `planning_session_id` — liên kết 1
  chiều ngược từ `PlanningSession.document_ids`.
- **`final_proposal["consider"]`** và **`final_proposal["planning_summary"]`**:
  tồn tại trong JSON `final_proposal` nhưng không map vào cột DB nào khi
  Approve. Comment `approve_planning_session_service.py:114` xác nhận rõ
  với `consider`; với `planning_summary` là **suy luận từ đọc code** (vòng
  lặp Approve chỉ đọc `proposal["project"]`/`proposal["phases"]`) — **[CHƯA
  XÁC MINH bằng comment tường minh cho riêng `planning_summary`]**.

### Alembic

Chỉ **2 migration**, chạy bằng `alembic upgrade head` (script_location =
`alembic`, `backend/alembic.ini:6`). URL DB lấy từ
`get_settings().database_url` tại `backend/alembic/env.py:18`, không dùng
URL tĩnh trong `alembic.ini`.

| Revision | Nội dung |
|---|---|
| `24b76749b74f_initial_schema_baseline.py` | Baseline rỗng/tối thiểu |
| `24b1c9e60a80_domain_model_user_project_phase_task_....py` | Tạo TOÀN BỘ 10 bảng domain cùng lúc trong 1 migration (213 dòng) |

Migration đáng chú ý nhất là `24b1c9e60a80` — migration DUY NHẤT dựng
toàn bộ schema nghiệp vụ. Không có migration nhỏ lẻ nào thêm cột cho các
tính năng gần đây (Delete Idea, Planning Summary) vì cả 2 đều không cần
cột DB mới: Delete dùng giá trị enum `archived` có sẵn từ đầu, Planning
Summary nằm trong JSONB `final_proposal` đã tồn tại sẵn.

---

## 4. Luồng request điển hình

### a) Kéo thả Kanban đổi status task

```
Frontend event                : frontend/src/pages/KanbanPage.tsx handleDragEnd()
  → validate cùng swimlane     : so sánh laneId + status qua DragData trong handleDragEnd
  → optimistic update          : handleDragStatusChange() — queryClient.setQueryData(queryKey,
                                  {...previous, items: map(...)}) — cache React Query đổi NGAY,
                                  trước khi PATCH resolve
  → gọi API                    : frontend/src/api/tasks.ts:14-16 updateTaskStatus(taskId, status)
  → HTTP                       : PATCH /tasks/{task_id}
Backend route                  : backend/api/tasks.py:56-59 update_task()
  → service                    : backend/services/task_service.py:76-92 update_task()
        changes = payload.model_dump(exclude_unset=True)   # dòng 78
        _validate_blocked(prospective_blocked, prospective_reason)  # dòng 87 — blocked luôn được
                                                                       re-check độc lập với status
        repository.update(db, task, **changes)             # dòng 89
        db.commit()                                        # dòng 90 ← transaction kết thúc, DUY NHẤT
  → repository (generic)       : backend/repositories/base.py — update() set THẲNG mọi field
                                  trong kwargs, kể cả None (PATCH có thể clear field optional)
Rollback khi lỗi (frontend)    : handleDragStatusChange() catch block
        queryClient.setQueryData(queryKey, previous);  # phục hồi ĐÚNG snapshot trước khi kéo,
                                                          không phải chỉ set lại field status
        void message.error(...);                        # AntD toast, không phải Alert banner
```

Chỉ 1 `db.commit()` duy nhất (`task_service.py:90`) — không có transaction
lồng nhau. Optimistic update thuần client-side; không có transaction DB
nào tương ứng cho tới khi PATCH thật sự chạy tới `db.commit()`.

### b) AI Planning end-to-end

| Bước | Route/hàm | File:dòng | Schema/DTO |
|---|---|---|---|
| Tạo Idea | `POST /ideas/` → `create_idea()` | `backend/services/idea_service.py:38` | `IdeaCreate` in → `Idea` model out |
| Start planning | `start_planning()` | `backend/services/idea_service.py:85` | seed `messages[0]` qua `create_for_idea()`, `backend/services/planning_session_service.py:63-75` |
| Companion chat (SSE) | `POST /{id}/companion-reply/stream` | `backend/api/planning_sessions.py:90-91` → `companion.reply_stream()` (`backend/ai/companion/companion.py:104`) | Frontend parse SSE thủ công: `frontend/src/api/sse.ts` (`streamSse()`) — không dùng `EventSource` gốc vì cần POST + header Bearer |
| Build context | `POST /{id}/build-context` | `backend/api/planning_sessions.py:188-189` → `context_builder.build_context()` (`backend/ai/context/context_builder.py:122`) | Trả `dict \| None`, lưu vào `PlanningSession.planning_context` (JSONB) |
| Generate | `POST /{id}/generate` | `backend/api/planning_sessions.py:203-204` → `planning.generate()` (`backend/ai/planning/planning.py:262`) | dict thô từ LLM → `_validate_proposal()` → lưu `final_proposal` (JSONB) qua `set_final_proposal()` |
| Approve | `POST /{id}/approve` | `backend/services/approve_planning_session_service.py:49 approve()` | Đọc `final_proposal` dict thô (KHÔNG re-validate qua Pydantic — tin tưởng nó đã hợp lệ từ generate()), build `Project`/`Phase`/`Task`/`Subtask` thật |

Trích seed `messages[0]` (`planning_session_service.py:70-76`):

```python
return repository.create(
    db, idea_id=idea.id, created_by=idea.created_by, status=STATUS_COMPANION,
    messages=[{"role": "user", "content": idea.content, "timestamp": _now_iso()}],
)
```

Transaction của Approve: `db.add()` cho project/phase/task/subtask rải
trong vòng lặp, `db.flush()` sau mỗi insert cha để lấy `id` cho con, nhưng
**`db.commit()` chỉ gọi 1 lần** (`approve_planning_session_service.py:126`).
Bất kỳ exception nào trước dòng 126 → `except Exception` (dòng 127) bắt
hết → `db.rollback()` (dòng 135) — không có bản ghi mồ côi nào, kể cả
phase/task hợp lệ tạo trước lỗi.

Điểm đáng chú ý: `final_proposal["consider"]` (và `planning_summary`)
không map vào cột DB nào — comment tại
`approve_planning_session_service.py:114` nói rõ nó ở lại trong JSONB làm
tài liệu tham khảo, không có đích trong structured data model.

### c) Auth

```
POST /auth/login (backend/api/auth.py)
  → auth_service.authenticate(db, email, password)
       user không tồn tại hoặc sai password → CÙNG 1 lỗi 401 (không tiết lộ email có tồn tại)
  → core/security.py create_access_token(subject=user.id)
       payload = {"sub": user.id, "iat": now, "exp": now + expire_minutes}
       jwt.encode(..., settings.jwt_secret_key, algorithm="HS256")
  → trả TokenResponse{access_token}
```

**Xác thực request sau — nằm ở middleware toàn app, KHÔNG phải
`Depends()` per-router:**

```python
# backend/core/auth_middleware.py:23  — public path duy nhất
PUBLIC_PATHS = frozenset({"/health", "/health/db", "/auth/login"})

# backend/core/auth_middleware.py:30-55  auth_middleware(), chạy TRƯỚC mọi route
async def auth_middleware(request: Request, call_next):
    if request.method == "OPTIONS" or request.url.path in PUBLIC_PATHS:
        return await call_next(request)
    ...
    payload = decode_access_token(token)        # dòng 40
    user = user_repository.get_by_id(db, user_id) if user_id else None   # dòng 47
    ...
    request.state.user = user                    # dòng 54
    return await call_next(request)
```

`backend/api/deps.py:6-16` `get_current_user()` **không tự decode JWT** —
nó chỉ đọc `request.state.user` middleware đã gán sẵn:

```python
def get_current_user(request: Request) -> User:
    """The actual 401 gate lives in core/auth_middleware.py (so a router
    that forgets to add this dependency is still protected by default) —
    this just hands back the User object the middleware already resolved.
    """
    user = getattr(request.state, "user", None)
    if user is None:
        raise HTTPException(status_code=401, detail="Not authenticated")
```

Thiết kế cố ý: 1 router mới quên `Depends(get_current_user)` vẫn bị chặn
401 mặc định, vì middleware chạy vô điều kiện trừ `PUBLIC_PATHS`. Comment
đầu `auth_middleware.py` nói thẳng đây là sửa 1 bug thiết kế của repo cũ
("every route open unless someone remembered to gate it").

Không có route đăng ký công khai (`grep -rn "register" backend/api/*.py`
→ rỗng). Cách tạo user ban đầu: **[CHƯA XÁC MINH — không nằm trong phạm
vi file đã đọc]**.

---

## 5. Tầng AI — chi tiết nhất

### `generate()` — 1 lệnh gọi LLM duy nhất, JSON lồng nhau

`backend/ai/planning/planning.py:262` `generate()`. Comment đầu file
(dòng 1-15) khẳng định: **đúng 1 lệnh gọi LLM mỗi lần invoke** — nhánh
nhỏ (chưa có deadline signal) chỉ hỏi 1 câu; nhánh lớn (đã có deadline)
để chính LLM quyết `action="propose"|"ask"`.

System prompt thật (`_GENERATE_SYSTEM_PROMPT`, `planning.py:104-140`,
trích các rule chính):

```
Rules you must always follow:
1. If proposing: compute REAL, concrete start_date and end_date (YYYY-MM-DD)
   for EVERY phase and EVERY task...
2. Never invent a person's name...
...
8. When proposing, also write "planning_summary": a list of 3-5 short
   strings, each ONE point. Cover exactly these: the project's goal, how
   you understood the PM's request, an overview of the plan and its
   timeline, risks or assumptions you made, and anything the PM should
   specifically review before approving.
9. {language_instruction}

Respond with a JSON object shaped like this example:
{"action": "propose", "question": null,
"project": {"name": "...", "manager": null, "start_date": null, "end_date": null},
"consider": ["..."],
"planning_summary": ["...", "...", "..."],
"phases": [{"name": "...", "start_date": "2026-01-01", "end_date": "2026-01-14",
"tasks": [{"name": "...", "assignee": null, "status": "todo",
"start_date": "2026-01-01", "end_date": "2026-01-05",
"subtasks": [{"name": "...", "assignee": null}]}]}]}
```

**Vì sao không tách nhiều lệnh gọi LLM riêng cho từng giai đoạn (kiểu
BMAD):** comment đầu file KHÔNG nhắc tới "BMAD" hay so sánh tường minh
với kiến trúc cũ — **[CHƯA XÁC MINH lý do lịch sử]**. Chỉ có thể mô tả
kiến trúc hiện tại: 1 lệnh gọi duy nhất giữ tính nhất quán giữa các
phase/task (cùng 1 lượt suy luận của model cho toàn bộ conversation),
tránh chi phí/độ trễ của N lệnh gọi tuần tự, tránh vấn đề đồng bộ ngữ
cảnh giữa các lệnh gọi tách rời.

### Validate response LLM

`_validate_proposal()` (`planning.py:237-250`) gọi các hàm con
`_validate_project()`, `_validate_phase()`, `_validate_task()`,
`_validate_subtask()` — mỗi hàm raise `PlanningValidationError`
(subclass `AppError`, `status_code=422`) nếu field bắt buộc sai
kiểu/rỗng. Router (`backend/api/planning_sessions.py:203-207`) không tự
bắt lỗi này — nó propagate lên tầng xử lý lỗi chung của app, tự động trả
422 cho client.

**Ngoại lệ cố ý — `planning_summary` xử lý lenient**, khác hẳn
`consider`/`phases` (`planning.py:237-247`):

```python
summary_raw = data.get("planning_summary", [])
if not isinstance(summary_raw, list):
    summary_raw = []
```

Thiếu hoặc sai kiểu → âm thầm thành `[]`, KHÔNG raise, KHÔNG làm hỏng cả
proposal — khác `consider`/`phases`, vốn raise cứng nếu sai kiểu (dòng
238-240, 248-250).

### Context Builder — nhãn thật là 5 giá trị, không phải 3

> **Lệch với cách mô tả phổ biến ("3 tier FACT/USER_INPUT/INFERENCE"):**
> `VALID_LABELS` thật trong code có **5** giá trị:
> ```python
> # backend/ai/context/context_builder.py:30
> VALID_LABELS = {"FACT", "USER_INPUT", "INFERENCE", "ASSUMPTION", "UNKNOWN"}
> ```

Điều kiện sinh từng nhãn (system prompt trong `context_builder.py`):
- `FACT`: nói nguyên văn trong tài liệu đính kèm (trích dẫn được).
- `USER_INPUT`: PM nói trực tiếp trong hội thoại, không có tài liệu backing.
- `INFERENCE`: suy luận hợp lý từ việc kết hợp nhiều điều đã nói.
- `ASSUMPTION`: thiếu thông tin, model tự đoán hợp lý (phải trung thực là
  đang đoán).
- `UNKNOWN`: không nhắc tới đâu cả, model không đủ tự tin để suy luận.
  **Rule cứng:** nếu `label="UNKNOWN"` thì `value` BẮT BUỘC `null`.

"3 tier" là cách **frontend gộp nhóm để hiển thị**, không phải số nhãn
thật ở backend — xác nhận tại `frontend/src/components/ai/ContextPanel.tsx`:

```ts
if (field.label === "FACT" || field.label === "USER_INPUT") { ... }          // tier "Confirmed"
else if (field.label === "INFERENCE" || field.label === "ASSUMPTION") { ... } // tier "AI inferred"
// còn lại (UNKNOWN) → tier "Not yet captured"
```

Kết luận: **5 nhãn ở backend, gộp thành 3 tier hiển thị ở UI**. Nếu tài
liệu nào nói "chỉ có 3 nhãn" là lẫn lộn giữa nhãn (backend) và tier (UI).

### `build_context()` nuốt lỗi, trả `None` theo thiết kế

Docstring đầu file (`context_builder.py:1-8`):

> "Must NEVER hang the main pipeline: every error calling the LLM or
> validating its response is caught here and swallowed, returning None
> with only a warning logged. The one exception is 'session not found'..."

```python
# backend/ai/context/context_builder.py:122-142 (rút gọn)
def build_context(db: Session, session_id: str, locale: str) -> dict | None:
    session = planning_session_service.get_session_or_404(db, session_id)  # NGOÀI try — 404 vẫn propagate
    try:
        ...
        raw_result = complete_json(...)
        return _validate_shape(raw_result)
    except (LLMError, ContextValidationError):
        logger.warning("Context Builder failed for session %s — returning None...")
        return None
```

**Đánh đổi:** Context Builder là bước làm giàu ngữ cảnh TUỲ CHỌN trước
`generate()`, không phải bước bắt buộc — `generate()` không phụ thuộc
vào context đã build. Raise lỗi ở đây sẽ chặn đứng cả luồng AI Planning
chỉ vì 1 bước phụ trợ; đổi lại PM thấy "No context extracted" ở UI thay
vì lỗi cứng.

### Ask vs propose — ai quyết

Gate cứng (không phải LLM quyết): `deadline_gate.has_deadline_signal()`
(`backend/ai/planning/deadline_gate.py`) quét từ khoá cố định/regex
ngày/pattern khoảng thời gian tương đối trên TOÀN BỘ lịch sử message.

```python
# backend/ai/planning/planning.py:262-268 (rút gọn)
if not deadline_gate.has_deadline_signal(session.messages):
    question = _ask_for_deadline(session, documents, locale)   # nhánh nhỏ, chỉ hỏi
    return planning_session_service.record_ai_question(db, session, question)
...
result = _call_llm(prompt, ...)      # nhánh lớn — CHỈ chạy khi ĐÃ có deadline signal
action = result.get("action")        # LLM tự quyết "propose" hay "ask" tiếp
```

Rule cố định (`deadline_gate`) chỉ quyết định có được phép hỏi LLM ở
nhánh lớn hay không. Một khi đã ở nhánh lớn, chọn `propose` hay `ask`
(hỏi thêm chi tiết khác) hoàn toàn do LLM tự quyết — không có logic nào
ép nó phải propose ngay cả khi deadline đã rõ.

### Xử lý lỗi LLM — retry policy chính xác

`backend/ai/providers/openai_provider.py`:

| Lỗi | Xử lý | Vị trí |
|---|---|---|
| `RateLimitError` (429) | Raise `LLMQuotaExceededError` ngay, **không retry** | `openai_provider.py:100-101` |
| `AuthenticationError` (401/403 do key sai) | Raise `LLMConfigError` ngay | `openai_provider.py:103-104` |
| `APIConnectionError` (mất kết nối) | Retry tối đa **2 lần** (`_MAX_RETRIES=2`, dòng 44), backoff cố định **1.5s** (`_RETRY_BACKOFF_SECONDS=1.5`, dòng 45), hết lần → `LLMResponseError` | `openai_provider.py:106-113` |
| `APIStatusError` status ∈ `{502, 503}` (`_RETRYABLE_STATUS_CODES`, dòng 46) | Retry tối đa 2 lần, cùng backoff 1.5s | `openai_provider.py:115-123` |
| `APIStatusError` status khác (400, 403,...) | Raise `LLMResponseError` ngay, **không retry** | `openai_provider.py:124-126` |

### SSE streaming — chỉ 1 chỗ duy nhất

Grep xác nhận CHỈ `companion-reply` có bản stream:
`backend/api/planning_sessions.py:90` — `POST /{session_id}/companion-reply/stream`.
`generate()` KHÔNG có route `/generate/stream` nào (`planning_sessions.py:203`
chỉ có `POST /{session_id}/generate` thường).

Lý do — **suy luận từ cấu trúc dữ liệu, không phải trích dẫn comment trực
tiếp trong code** **[CHƯA XÁC MINH bằng comment]**: companion reply là
văn bản hội thoại tự do, stream từng token có ý nghĩa hiển thị dần;
`generate()` trả JSON lồng nhau (phases→tasks→subtasks) — stream từng
phần JSON chưa đóng ngoặc không có ý nghĩa hiển thị cho tới khi toàn bộ
object hợp lệ.

### `planning_summary` — trường mới, cơ chế fallback

- Thêm ở rule 8 trong prompt (`planning.py:124-128`, đã trích ở trên).
- Validate lenient — khác `consider` (đã nói ở trên, `planning.py:243-247,257`).
- Frontend fallback (`frontend/src/components/ai/ProposalEditor.tsx:151-165`):

```tsx
{draft.planning_summary && draft.planning_summary.length > 0 ? (
  <div className="proposal-editor__summary">
    <h3>{t("aiPlanning.proposal.summaryHeading")}</h3>   {/* "Planning Summary" */}
    ...
  </div>
) : (
  draft.consider.length > 0 && (
    <div className="proposal-editor__consider">
      <h3>{t("aiPlanning.proposal.considerHeading")}</h3> {/* "AI notes" — tên field cũ */}
      ...
```

Proposal cũ (tạo trước khi có `planning_summary`) → field không tồn tại
trong JSONB đã lưu → rơi vào nhánh `else`, hiện lại đúng heading "AI
notes" đọc từ `consider` như hành vi trước đây.

---

## 6. Frontend

### TanStack Query — cache key, invalidate, optimistic update, rollback

Cache key đặt theo mảng phân cấp `[domain, "project"?, projectId]`, ví dụ
`frontend/src/pages/KanbanPage.tsx:80`:

```ts
const tasksQuery = useQuery({ queryKey: ["tasks", "project", projectId], ... });
```

Sau mutation thường (Quick Add, dropdown đổi status không qua kéo thả),
`invalidateQueries` gọi thẳng để buộc refetch (`KanbanPage.tsx:103-104`):

```ts
queryClient.invalidateQueries({ queryKey: ["tasks", "project", projectId] }),
queryClient.invalidateQueries({ queryKey: ["phases", projectId] }),
```

Riêng đường kéo thả dùng optimistic update thật qua `setQueryData`
(`KanbanPage.tsx:129-135`):

```ts
const queryKey = ["tasks", "project", projectId] as const;
const previous = queryClient.getQueryData<Page<Task>>(queryKey);
if (!previous) return;
queryClient.setQueryData<Page<Task>>(queryKey, {
  ...previous,
  items: previous.items.map((task) => (task.id === taskId ? { ...task, status } : task)),
});
```

Rollback khi PATCH lỗi: phục hồi **đúng snapshot đã lưu**, không phải
tính lại (`KanbanPage.tsx:144-145`):

```ts
queryClient.setQueryData(queryKey, previous);
void message.error(err instanceof ApiError ? err.message : t("kanban.errors.generic"));
```

### Ranh giới AntD vs tự viết

Ràng buộc thiết kế ghi rõ trong `docs/DESIGN_DIRECTION.md:106-130`, mục
**"Phân vùng AntD vs tự viết (QUAN TRỌNG NHẤT)"**:

> **AntD gần như nguyên bản, chỉ đổi theme token** — áp dụng cho mọi màn
> hình CRUD chuẩn: `Table`, `Form`, `Modal`, `Drawer`, `DatePicker`,
> `Select`, `Filter`.
> **Tự viết hoàn toàn, KHÔNG ép AntD:** Kanban board, Gantt timeline, AI
> Planning (chat + proposal), AI Companion. Lý do: bản cũ (`pm_tool_mvp`)
> đã đi qua đúng vòng lặp này — 8 vòng chỉnh CSS AntD vẫn chưa ưng.

Xác nhận thật bằng grep import AntD, khớp đúng tài liệu:

| Thư mục/file | Import AntD |
|---|---|
| `frontend/src/components/gantt/*.tsx` | Không có (0 kết quả) |
| `frontend/src/components/kanban/{KanbanColumn,Swimlane,TaskCard,DraggableTaskCard}.tsx` | Không có |
| `frontend/src/components/ai/{ProposalEditor,ContextPanel}.tsx` | Không có |
| `frontend/src/components/kanban/QuickAddTask.tsx` | `Button, Input, Select` (form nhập liệu — đúng nhóm CRUD) |
| `frontend/src/components/ai/CompanionChat.tsx` | Chỉ `Upload` |
| `frontend/src/components/ai/IdeaList.tsx` | Chỉ `Modal` (confirm xoá) |
| `frontend/src/pages/KanbanPage.tsx`, `SprintsPage.tsx` | `Select`, `Alert`, `message`, `Tabs` (page chrome) |

### Design token

`frontend/src/styles/tokens.css` (toàn bộ 114 dòng) chia nhóm: Surfaces,
Panel (`--bg-app`/`--bg-surface`/`--bg-sunken`), Text, Borders, Accent, AI
accent, Status (4 giá trị `Task.status`), Priority, Blocked, Typography (5
vai trò ngữ nghĩa — xem comment `tokens.css:74-84`), Spacing, Shape,
Depth (shadow), Motion.

Không hardcode hex trong component:
`grep -rn "#[0-9a-fA-F]\{3,6\}" frontend/src/components --include="*.css"`
(loại `tokens.css`) → **0 kết quả**.

**Cảnh báo AntD `ConfigProvider` không parse được `var(--x)`** — bằng
chứng thật ở `frontend/src/theme/antdTheme.ts:1-13`:

```ts
// AntD derives its full palette (hover/active states, tints) from these
// seed tokens using real color math (@ant-design/colors) — passing a raw
// `var(--accent)` string breaks that derivation silently (the button
// rendered black instead of the accent color, caught while verifying token
// propagation in Bước 6). ...
function cssVar(name: string): string {
  return getComputedStyle(document.documentElement).getPropertyValue(name).trim();
}
```

Theme object build 1 lần lúc mount qua `useState(buildAntdTheme)`
(`frontend/src/App.tsx:19`) — token đổi lúc runtime (không xảy ra trong
app này) sẽ không tự cập nhật cho AntD tới khi reload. Riêng cảnh báo
console cụ thể của `Modal.confirm` ("Static function can not consume
context like dynamic theme") **[CHƯA XÁC MINH có ghi thành comment ở đâu
trong code hay không]** — 2 chỗ gọi `Modal.confirm`
(`frontend/src/pages/AiPlanningPage.tsx:169`,
`frontend/src/components/ai/IdeaList.tsx:86`) không có comment giải
thích tại chỗ; cảnh báo này chỉ quan sát được qua console lúc chạy thật
(Playwright), không phải trích dẫn code.

### i18n

Cấu trúc: `frontend/src/i18n/index.ts`, `locale.ts`, `locales/en.json`,
`locales/vi.json`.

Quy tắc **"AI trả lời theo i18n hiện tại của UI, KHÔNG theo ngôn ngữ user
gõ"** được implement và giải thích ngay tại `frontend/src/hooks/useLocale.ts:11-14`:

```ts
// Single source of truth for "which locale is the app in right now" — both
// the UI's displayed language AND the `locale` sent on every AI request
// (Companion/Planning) read from here, never from what the user happens to
// type (docs/DESIGN_DIRECTION.md mục "Ngôn ngữ").
export function useLocale(): UseLocaleResult {
  const { i18n } = useTranslation();
  const locale = (i18n.language === "vi" ? "vi" : "en") as Locale;
```

Điểm gọi thật: `AiPlanningPage.tsx:36` (`const { locale } = useLocale();`)
truyền vào `buildContext`, `generatePlan`, `companionReplyStream` — cả
các lời gọi API AI đều lấy `locale` từ hook UI, không có chỗ nào phân
tích ngôn ngữ nội dung tin nhắn PM gõ.

### Kéo thả `@dnd-kit`

`DndContext` đặt tại `frontend/src/pages/KanbanPage.tsx:239` (bọc TOÀN
BỘ danh sách swimlane, không phải từng swimlane riêng — bắt buộc để
`onDragEnd` so sánh được `laneId` giữa 2 swimlane khác nhau).

Giới hạn kéo thả trong cùng swimlane (`KanbanPage.tsx:168`):

```ts
if (activeData.laneId !== overData.laneId) return;
```

`CardDragSensor` (kế thừa `PointerSensor`) để dropdown `<select>` vẫn
click được (`KanbanPage.tsx:44-50`):

```ts
class CardDragSensor extends PointerSensor {
  ...
  if (target?.closest("select, button, a, input, textarea")) return false;
```

---

## 7. Testing

### Số lượng test

| | Số lượng | Nguồn |
|---|---|---|
| Backend mặc định (loại `real_llm`) | **165 passed, 7 deselected** | `pytest -q`, chạy thật trong phiên làm việc này (Bước 5 typography) |
| Backend `real_llm` riêng | **7 passed** | `pytest -m real_llm -q`, cùng phiên |
| Frontend | **134 passed** (25 test file) | `npx vitest run --run`, chạy thật cùng phiên |

Backend không tách unit/integration/e2e bằng thư mục — tất cả nằm phẳng
trong `backend/tests/`, phân biệt duy nhất qua marker `real_llm`. Top file
theo số hàm `def test_` (đếm tĩnh, không tính test sinh từ
`@pytest.mark.parametrize`): `test_planning_session_edit.py` (13),
`test_ideas.py` (13), `test_tasks.py` (12), `test_approve.py` (11),
`test_auth.py` (10), `test_planning_generate.py` (9),
`test_documents.py` (9), `test_context_builder.py` (8),
`test_projects.py`/`test_openai_provider.py`/`test_companion.py`/
`test_cascade_and_restrict.py` (7 mỗi file).

### Marker `real_llm`

Nguyên văn `backend/pytest.ini`:

```ini
[pytest]
pythonpath = .
testpaths = tests
markers =
    real_llm: hits the real OpenAI API (costs quota, can be flaky) — excluded from the default run; use -m real_llm to run these on their own
addopts = -m "not real_llm"
```

Comment thừa nhận flaky trực tiếp trong test
(`backend/tests/test_context_builder.py:213-215`, khớp với việc test
`test_build_context_real_llm_labels_fact_user_input_and_unknown_correctly`
đã fail-rồi-pass-ngay-lần-sau khi verify thủ công trong 1 phiên trước —
xem `docs/ACCEPTANCE_v2.md`):

```python
# Marked `real_llm`: excluded from the default CI run (flaky by nature of
# calling a real model — see Bước 9 nghiệm thu), run manually/periodically
# instead: `pytest -m real_llm`.
```

### Cô lập DB test

`backend/tests/conftest.py:20-38` — chặn cứng NGAY từ đầu file (trước
khi import bất kỳ module app nào): nếu `TEST_DATABASE_URL` không được
set, hoặc trùng với `DATABASE_URL` → `pytest.exit()` với message giải
thích rõ (comment dòng 9-17: từng có sự cố thật xoá mất dữ liệu demo dev).

Cô lập KHÔNG dùng transaction-per-test (không SAVEPOINT/rollback bọc
quanh mỗi test) mà là **TRUNCATE toàn bộ bảng sau mỗi test**
(`conftest.py:126-141`):

```python
@pytest.fixture
def db() -> Generator[Session, None, None]:
    session = SessionLocal()
    try:
        yield session
    finally:
        session.rollback()
        session.close()
        table_names = ", ".join(Base.metadata.tables.keys())
        with engine.begin() as conn:
            conn.execute(text(f"TRUNCATE TABLE {table_names} RESTART IDENTITY CASCADE"))
```

### Test đáng chú ý về mặt kỹ thuật

`backend/tests/test_cascade_and_restrict.py::test_deleting_user_who_owns_a_task_is_restricted`
(dòng 131-162) assert đúng **SQLSTATE 23503**, không bắt `IntegrityError`
chung chung:

```python
assert exc_info.value.orig.sqlstate == "23503"
```

**Lý do (đã verify trực tiếp — dòng 208 của cùng file):** một
`IntegrityError` trần trụi vẫn "pass" ngay cả khi `owner_id`'s `ON DELETE`
bị cấu hình sai thành `SET NULL` thay vì `RESTRICT` — Postgres khi đó cố
null hoá cột `owner_id` (NOT NULL), raise SQLSTATE **23502**
(not_null_violation) thay vì 23503 (foreign_key_violation) — sai hoàn
toàn điều test tuyên bố kiểm tra, nhưng generic `except IntegrityError`
vẫn không phân biệt được. Test song sinh ngay bên dưới
(`test_deleting_user_via_orm_session_hits_client_side_cascade_not_the_db_constraint`,
dòng 177-208) ghi lại đúng: xoá qua `session.delete(user)` (ORM) kích
hoạt cascade phía client SQLAlchemy TRƯỚC KHI chạm DB, cũng ra 23502 dù
constraint RESTRICT ở DB chưa hề bị đụng — document lại để không nhầm
thành bug schema.

### Chỗ đang thiếu test

- **B.2** (`blocked` độc lập với `status`): đúng trong code (đã verify
  thủ công qua kéo thả Kanban ở phiên trước — psql xác nhận
  `blocked`/`blocked_reason` không đổi khi status đổi), nhưng **không có
  test tự động** canh giữ regression này.
- **F.6** (phân biệt 500 config-lỗi-key vs 502 response-lỗi-tạm-thời):
  nửa provider đã có test (`test_missing_api_key_raises_config_error`,
  `test_rejected_api_key_raises_config_error` trong
  `test_openai_provider.py`), nhưng router
  (`backend/api/planning_sessions.py`) không có handler riêng phân biệt 2
  loại — cả 2 rơi vào exception handler chung, cùng trả 500.
- Tự phát hiện thêm: `frontend/src/components/gantt/*.tsx` không có
  handler tương tác nào (xem mục 9) — test tương ứng (nếu có) khả năng chỉ
  test render tĩnh, không test tương tác **[CHƯA XÁC MINH nội dung chính
  xác của `GanttChart.test.tsx`/`GanttRow.test.tsx`]**.

---

## 8. Những quyết định kỹ thuật và đánh đổi

### GPT-only, bỏ Gemini

Quyết định + lý do ghi thẳng trong docstring
(`backend/ai/providers/openai_provider.py:1-23`):

> "The one LLM abstraction for the whole app — GPT only. The old repo had
> two client modules (core/llm.py for Gemini, plus core/llm_fallback.py
> for ChatGPT) with provider-selection logic bleeding into the skills
> that called them. This is deliberately a single module: one provider,
> one retry policy, one place to change if the model or SDK ever
> changes... The old repo's response to 429 was an immediate fallback to
> a second provider (Gemini -> ChatGPT); GPT is now the only provider, so
> there is nothing left to fall back to."

Xác nhận không còn remnant Gemini nào:
`grep -rln "[Gg]emini" backend/ai/ backend/core/` chỉ khớp chính file
này (2 dòng comment giải thích lịch sử, không phải code Gemini thật).
**Chi phí phải trả:** mất khả năng fallback provider khi GPT bị 429 —
đổi lại bằng `LLMQuotaExceededError` riêng biệt để caller báo "thử lại
sau" thay vì giả vờ fallback.

### RAG không port sang v2

`grep -rn "rag\|pgvector\|embedContent" backend/` (loại `.venv`) → không
route/service/bảng nào. `docs/ACCEPTANCE_v2.md` (mục E.1-E.10, toàn bộ
KHÔNG PORT) nêu lý do: v1 build đủ 6 bước kiến trúc RAG nhưng **không
tính năng nào ở v1 thực sự dùng nó** — cô lập hoàn toàn, port sang v2 sẽ
là port dead code.

### Không có activity/audit log — ⚠️ phát hiện lệch với docs

`docs/BEHAVIOR_CONTRACT.md` mục H.2 khẳng định `models/enums.py:22-24`
có `ActivityEntityType.ATTACHMENT`. Đã đọc trực tiếp toàn bộ
`backend/models/enums.py` (35 dòng, trích đầy đủ ở mục 3) — **không có
`ActivityEntityType`, không có class `Activity`/`Attachment` ở bất kỳ
đâu**: `grep -rln "Attachment\|Activity" . --include="*.py"` (loại
`.venv`/`__pycache__`) → **0 file** trong toàn repo. Xác minh độc lập 2
lần (2 lượt nghiên cứu khác nhau cho cùng 1 kết quả). Không rõ model đã
bị xoá sau khi contract ghi lại, hay trích dẫn gốc sai từ đầu —
**[CHƯA XÁC MINH lý do lệch — cần người biết lịch sử repo xác nhận]**.
Đây là điểm cần sửa lại trong `docs/BEHAVIOR_CONTRACT.md`, không phải
lỗi trong code hiện tại.

### JWT stateless, không có `/auth/register` công khai

`grep -rn "register" backend/api/auth.py` → rỗng. Xem chi tiết cơ chế
JWT tại mục 4c — `create_access_token()`/`decode_access_token()`
(`backend/core/security.py:44,51,56`), thuật toán `HS256`, thời hạn
`60*24` phút = 24 giờ (`backend/core/config.py:32-34`).

### `Phase.status` tính động thay vì lưu cached

Tham chiếu mục 3 — không có cột `status` trong `backend/models/phase.py`,
tính lại từ `Task` con mỗi lần fetch qua `compute_status()`
(`backend/services/phase_service.py:21-29`).

### `generate()` không stream

Tham chiếu mục 5 — chỉ endpoint `companion-reply/stream`
(`backend/api/planning_sessions.py:90`) có bản `/stream`; `generate()`
luôn trả JSON một lần vì cấu trúc lồng nhau phases→tasks→subtasks không
có điểm cắt "stream từng phần" có ý nghĩa hiển thị.

---

## 9. Hạn chế đã biết và nợ kỹ thuật

### 2 mục CHƯA trong `docs/ACCEPTANCE_v2.md`

| Mục | Rule | Ảnh hưởng thực tế |
|---|---|---|
| **B.2** | `blocked` độc lập với `status` | Đúng trong code, không có test tự động canh giữ — 1 regression tương lai (ví dụ ai đó gộp `blocked` vào enum `status`) sẽ không bị CI bắt |
| **F.6** | Router phân biệt 500 (config sai key) vs 502 (lỗi response tạm thời) | Client hiện nhận HTTP 500 generic cho CẢ 2 trường hợp — không phân biệt được "sửa `.env`" với "thử lại sau" |

### 23 mục KHÔNG PORT — nhóm theo chủ đề

| Nhóm | Số mục | Chi tiết | Có thể cần lại sau? |
|---|---|---|---|
| RAG toàn bộ | 10 | Kiến trúc 6 bước, chunking, embedding Gemini, pgvector, retriever, ingest CLI | Có — nếu cần trả lời câu hỏi dựa trên tài liệu dự án (hiện `UploadedDocument.extracted_text` chỉ nhồi thẳng vào prompt, không semantic search) |
| Dual-provider LLM | 4 | ChatGPT là provider chính (không phải fallback), Gemini→ChatGPT fallback, REST-qua-httpx riêng | Không — GPT-only đơn giản hơn, chỉ cần lại nếu OpenAI outage kéo dài |
| Luồng cũ ConfirmBreakdown/agent-breakdown | 3 | Đã thay hoàn toàn bằng Approve | Không — đã có luồng thay thế hoạt động |
| `consider` không map model | 1 | AI note tự do, chỉ lưu JSONB, không map sang cột nào | Không — hành vi cố ý |
| Audit log / Attachment | 2 | Không có `Activity`/audit-log; `Attachment` — nhưng xem phát hiện lệch docs ở mục 8: model này KHÔNG tồn tại trong code hiện tại | Có thể cần — hữu ích nếu nhiều PM cùng sửa 1 project |
| Role/permission | 2 | Không có employee/manager/admin, single-tier auth | Có thể cần — nếu mở rộng tổ chức lớn hơn |
| RAG re-ingest trigger | 1 | Hệ quả trực tiếp của việc bỏ RAG | Không (đi kèm nhóm RAG) |

Tổng: 10+4+3+1+2+2+1 = 23, khớp con số trong `docs/ACCEPTANCE_v2.md`.

### Deploy / Dark mode / Gantt editing

- **Chưa deploy production**: `grep -in "deploy"` trên
  `.github/workflows/ci.yml`, `docker-compose.yml`, cả 2 `Dockerfile` →
  0 kết quả. CI hiện chỉ chạy test. `docker-compose.yml` ở root là stack
  DEV (postgres + backend + frontend cùng 1 file, không tách môi
  trường). Repo hiện CÓ remote GitHub thật
  (`origin https://github.com/dtdat0194/cvpm.git`) — khác ghi nhận "không
  có remote" ở một thời điểm trước đó trong lịch sử dự án; remote đã được
  thêm vào giữa chừng.
- **Chưa có dark mode**: `grep -rn "data-theme\|prefers-color-scheme"
  frontend/src/` chỉ ra 2 dòng comment trong `tokens.css` nhắc kế hoạch
  tương lai, không có block `[data-theme="dark"]` thật nào. Quyết định có
  chủ đích — `docs/DESIGN_DIRECTION.md:134-148`.
- **Gantt chưa sửa được task**: `frontend/src/components/gantt/GanttChart.tsx`
  và `GanttRow.tsx` — `grep "onClick\|onChange\|onDrag"` → **0 kết quả**.
  Component hoàn toàn read-only, chỉ nhận `phases`/`tasks` qua props và
  render thanh ngang.

### Nợ kỹ thuật tự phát hiện khi đọc code

- **Bundle JS không code-split**: build thật (chạy trong phiên trước, Bước
  5) —
  ```
  dist/assets/index-BFY6T0MZ.js   1,008.60 kB │ gzip: 323.02 kB
  (!) Some chunks are larger than 500 kB after minification.
  ```
  Vite dùng cấu hình mặc định, không có `build.rollupOptions.output.manualChunks`
  — Kanban + Gantt + AI Planning + Dashboard + Sprints nằm chung 1 bundle
  JS ~1MB, không lazy-load theo route.
- **Không có TODO/FIXME tường minh nào trong code**: `grep -rn
  "TODO\|FIXME" backend frontend/src` (loại `.venv`) chỉ khớp nhầm chuỗi
  `TaskStatus.TODO`. Không có nợ kỹ thuật nào đánh dấu tường minh — nhưng
  cũng có nghĩa nợ thật (như lệch docs mục H.2) không được ghi nhận ở
  đâu, chỉ lộ ra khi đọc chéo docs với code.
- **Docs lệch code (mục H.2 — `ActivityEntityType`)**: xem chi tiết mục
  8. Đây là nợ TÀI LIỆU thật — cần 1 lượt rà soát lại toàn bộ
  `docs/BEHAVIOR_CONTRACT.md` mục H đối chiếu với code hiện tại, vì nếu 1
  trích dẫn sai thì các trích dẫn khác cùng mục cũng cần kiểm tra lại
  (chưa làm trong phạm vi tài liệu này).

---

## Tự rà soát cuối cùng

Đã đọc lại toàn bộ tài liệu, đối chiếu từng khẳng định với trích dẫn
`file:dòng`. Các điểm được đánh dấu **[CHƯA XÁC MINH]** rải trong bài
(lý do lịch sử "1 lệnh gọi LLM duy nhất" không tách BMAD; lý do
`generate()` không stream chỉ là suy luận cấu trúc, không phải comment
trực tiếp; cách tạo user ban đầu khi không có `/auth/register`; nội dung
`backend/scripts/`; phạm vi chính xác của `GanttChart.test.tsx`) — đều là
những chỗ không tìm được bằng chứng trực tiếp trong code/comment, cố ý
để nguyên thay vì đoán. 2 phát hiện lệch quan trọng nhất giữa docs và
code thật (mục H.2 `ActivityEntityType` không tồn tại; tên hàm
`compute_status()` khác `PhaseService._compute_status_from_tasks()` ghi
trong contract) đã được xác minh độc lập từ 2 lượt đọc code khác nhau
cho cùng kết quả, và nhấn mạnh lại trong mục 8-9 thay vì chỉ nhắc 1 lần.
