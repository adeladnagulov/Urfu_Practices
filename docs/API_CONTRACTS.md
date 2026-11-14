# API Contracts

## 1. Общие соглашения

### Формат данных
- Все запросы и ответы: `Content-Type: application/json`
- Идентификаторы (ID): `UUID v4` в виде строк (например, `"id": "550e8400-e29b-41d4-a716-446655440000"`)
- Даты и время: `ISO 8601` в UTC (например, `"2023-10-27T14:30:00Z"`)

### Формат ошибок
Все ошибки возвращаются со статусом HTTP 4xx или 5xx, заголовком `Content-Type: application/problem+json` и телом в формате RFC 7807:

- **type**: URI, обозначающий вид ошибки. По ссылке ничего открывать не нужно, это идентификатор.
- **title**: короткое имя вида ошибки, одинаковое для всех случаев одного type.
- **status**: HTTP-код, дублирует статус ответа.
- **detail**: что случилось в этом конкретном запросе, текст для человека.
- **instance**: путь запроса, на котором ошибка произошла.
- **code**: расширение стандарта: стабильный машиночитаемый код для фронтенда.

**Пример:**
```json
{
  "type": "about:blank",
  "title": "Teacher busy",
  "status": 409,
  "detail": "У преподавателя уже есть активная практика с этим студентом",
  "code": "teacher_busy",
  "instance": "/api/go/v1/practices"
}
```

**Список кодов ошибок:**
- **400 `invalid_request`** — не прошла валидация тела запроса, либо переданный ID не является валидным UUID.
- **401 `invalid_credentials`** — неверный email или пароль при попытке входа в систему.
- **401 `unauthorized`** — токен отсутствует, истек, невалиден или имеет неправильную подпись.
- **403 `forbidden`** — пользователь аутентифицирован, но его `role` не позволяет выполнить это действие (например, студент пытается удалить группу).
- **404 `practice_not_found`** — практики с таким `id` не существует в БД.
- **500 `internal_error`** — неожиданная ошибка на сервере. Детали не раскрываются.

### 2. Авторизация

#### POST /api/go/v1/auth/login
Аутентификация пользователя. При успешном входе возвращает JWT-токен, который необходимо передавать в заголовке `Authorization: Bearer <token>` во всех последующих запросах к сервисам.

**Request:**
```json
{
  "email": "student@uni.ru",
  "password": "SuperSecret123!"
}
```
**Response**
200 OK
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI1NW...xyz",
  "token_type": "Bearer",
  "expires_in": 86400,
  "user": {
    "id": "550e8400-e29b-41d4-a716-446655440000",
    "email": "student@uni.ru",
    "full_name": "Иванов Иван Иванович",
    "role": "STUDENT"
  }
}
```
**Ошибки**
401 invalid_credentials — неверный email или пароль
Пример
{"type": "...", "title": "Unauthorized", "status": 401, "detail": "Неверный email или пароль", "code": "invalid_credentials", "instance": "/api/go/v1/auth/login"}

#### GET /api/go/v1/auth/me
Получить информацию о текущем пользователе по валидному JWT-токену.

**Заголовок**
Authorization: Bearer <token>

**Response**
200 OK
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT"
}
```
**Ошибки**
401 unauthorized — токен отсутствует, истек или невалиден.
Пример
{"type": "...", "title": "Unauthorized", "status": 401, "detail": "Токен отсутствует, истек или невалиден", "code": "unauthorized", "instance": "/api/go/v1/auth/me"}

---

> **Дополнения фронтенда (черновик).** Всё ниже — предложения фронтенда: какие эндпоинты нужны интерфейсу. Схемы БД пока нет, поэтому поля примерные; названия и форму ответа можно менять, если сохраняется смысл. Соглашения взяты из разделов выше: UUID, snake_case, RFC 7807, префикс `/api/go/v1`.
> Колонка «Приоритет» в сводной таблице (раздел 13): **MVP** — без этого не собрать первую версию; **Позже** — нужно, чтобы заранее заложить UI.

### 1.1. Роли
`STUDENT`, `CURATOR`, `ADMIN`.

| Роль | Права |
|---|---|
| `STUDENT` | Видит только свои опубликованные задания и свои оценки, загружает работы, подаёт апелляции |
| `CURATOR` | CRUD заданий в своих практиках, просмотр сдач, оценивание, возврат на доработку |
| `ADMIN` | Пользователи и роли, практики, просмотр всего, разбор апелляций, логи, выгрузка оценок |

Сервер сам фильтрует данные по роли: фронт не должен получать чужие данные, даже если в запросе подставлен чужой `id`.

### 1.2. Пагинация, сортировка, фильтры
Все списки принимают параметры `?page=1&page_size=20` (максимум 100) и возвращают:
```json
{
  "items": [],
  "total": 42,
  "page": 1,
  "page_size": 20
}
```
Сортировка: `?sort=deadline` (по возрастанию) или `?sort=-deadline` (по убыванию). Множественный фильтр передаётся через запятую: `?status=submitted,under_review`.

### 1.3. Файлы
- Загрузка: `multipart/form-data`, поле `file`. Разрешены PDF, DOCX и ZIP размером до 20 МБ; тип проверяется по содержимому файла, а не по расширению.
- Скачивание: бинарный ответ с заголовком `Content-Disposition: attachment; filename*=UTF-8''<имя>`. Фронт берёт исходное имя файла из этого заголовка.
- В списках и карточках возвращается только `file` с метаданными (`original_name`, `mime_type`, `size_bytes`, `uploaded_at`, `download_url`), без содержимого.

### 1.4. Дополнительные коды ошибок
Формат ответа тот же, RFC 7807.

- **400 `invalid_request`** — уже есть. Дополнение: при ошибках валидации полей добавлять расширение `errors`, чтобы фронт подсветил поля формы:
  ```json
  {
    "type": "about:blank", "title": "Invalid request", "status": 400,
    "detail": "Проверьте заполнение полей", "code": "invalid_request",
    "instance": "/api/go/v1/assignments",
    "errors": [ { "field": "max_score", "message": "Должно быть целым числом больше 0" } ]
  }
  ```
- **403 `user_inactive`** — учётная запись заблокирована (`is_active = false`).
- **404 `user_not_found`**, **`assignment_not_found`**, **`submission_not_found`**, **`appeal_not_found`**. Если студент запрашивает чужой ресурс, отвечать тоже 404.
- **409 `invalid_status_transition`** — действие недопустимо в текущем статусе (например, оценить сдачу, которая не в `under_review`).
- **409 `submission_already_exists`** — у студента уже есть активная сдача по этому заданию.
- **409 `assignment_not_published`** — сдача невозможна: задание в черновике.
- **409 `deadline_passed`** — дедлайн прошёл, поздняя сдача запрещена.
- **409 `assignment_locked_field`** — после первой сдачи нельзя менять `max_score`, а после публикации — получателей.
- **409 `appeal_window_closed`** — срок подачи апелляции истёк.
- **409 `email_taken`** — email уже занят.
- **409 `practice_not_empty`** — нельзя удалить практику, в которой есть студенты или задания.
- **413 `file_too_large`** — файл больше 20 МБ.
- **415 `unsupported_file_type`** — файл не PDF, не DOCX и не ZIP.

### 1.5. Статусы

**Задание** (`assignment.status`): `draft` → `published`. Создаётся всегда в статусе `draft`. Студенты видят задание только после публикации.

**Тип задания** (`assignment.type`): `task` — задание, `report` — отчёт.

**Сдача** (`submission.status`) — по ТЗ:
```
загрузка файла → submitted
куратор взял на проверку → under_review
опубликована оценка → graded
возврат на доработку → revision
revision → студент перезагрузил файл → submitted
```

**Состояние задания для студента** (`student_state`, вычисляется сервером, не хранится): `not_submitted`, `overdue`, `submitted`, `under_review`, `revision`, `graded`. Используется для фильтров, бейджей и счётчиков на дашборде. Считается на бэке, чтобы у фронта не было расхождений.

**Апелляция** (`appeal.status`): `submitted` → `under_review` → `accepted` | `rejected`.

---

### 2.1. Авторизация — дополнения

#### POST /api/go/v1/auth/logout
Выход. Если токены не хранятся на сервере, эндпоинт нужен хотя бы для журнала входов и выходов; фронт в любом случае удаляет токен у себя.

**Response:** `204 No Content`

#### PATCH /api/go/v1/auth/me
Редактирование своего профиля. Роль и практику пользователь сам не меняет.

**Request:**
```json
{ "full_name": "Иванов Иван Иванович" }
```
**Response** `200 OK` — тот же объект, что возвращает `GET /auth/me`.

#### POST /api/go/v1/auth/change-password
**Request:**
```json
{ "current_password": "OldSecret123!", "new_password": "NewSecret456!" }
```
**Response:** `204 No Content`
**Ошибки:** `401 invalid_credentials` — неверный текущий пароль; `400 invalid_request` — слабый новый пароль.

#### Дополнение к ответу `GET /auth/me`
Чтобы фронт при старте сразу построил навигацию, удобно получать в ответе ещё и практики:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT",
  "is_active": true,
  "practices": [
    { "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7", "name": "Учебная практика 2026 · РИ-330944" }
  ]
}
```
Для `STUDENT` это практики, где он участник; для `CURATOR` — практики, которые он ведёт; для `ADMIN` — пустой массив.

---

### 3. Дашборд

#### GET /api/go/v1/dashboard
Все данные главного экрана одним запросом. Структура ответа зависит от роли (`role`).

**Response 200 — STUDENT:**
```json
{
  "role": "STUDENT",
  "counters": { "to_submit": 2, "overdue": 1, "on_review": 1, "graded": 3, "total": 7 },
  "score": { "total": 37, "max": 52, "average_percent": 71.2 },
  "upcoming_deadlines": [
    {
      "assignment": { "id": "…", "title": "Отчёт о практике", "type": "report", "deadline": "2026-06-20T18:59:00Z", "max_score": 10 },
      "student_state": "not_submitted"
    }
  ],
  "recent_results": [
    { "submission_id": "…", "assignment_title": "Прототип ЛК", "score": 12, "max_score": 15, "published_at": "2026-06-14T10:00:00Z" }
  ]
}
```

**Response 200 — CURATOR:**
```json
{
  "role": "CURATOR",
  "practices": [ { "id": "…", "name": "Учебная практика 2026 · РИ-330944", "students_count": 25 } ],
  "counters": { "awaiting_review": 8, "in_my_review": 2, "drafts": 1, "published_assignments": 5 },
  "review_queue": [
    { "submission_id": "…", "student": { "id": "…", "full_name": "Мария Орлова" }, "assignment_title": "Отчёт", "submitted_at": "2026-06-15T10:42:00Z" }
  ],
  "upcoming_deadlines": [ { "id": "…", "title": "Отчёт", "deadline": "2026-06-20T18:59:00Z" } ]
}
```

**Response 200 — ADMIN:**
```json
{
  "role": "ADMIN",
  "counters": { "practices": 4, "active_practices": 2, "students": 96, "curators": 5, "awaiting_review": 14, "open_appeals": 2 }
}
```

---

### 4. Пользователи (ADMIN)

#### GET /api/go/v1/users
Экран «Участники». Пользователь с ролью `CURATOR` получает только студентов своих практик.

**Query:** `role`, `practice_id`, `is_active`, `search` (поиск по ФИО и email), `page`, `page_size`, `sort` (`full_name`, `-created_at`).

**Response 200:**
```json
{
  "items": [
    {
      "id": "550e8400-e29b-41d4-a716-446655440000",
      "email": "student@uni.ru",
      "full_name": "Иванов Иван Иванович",
      "role": "STUDENT",
      "is_active": true,
      "created_at": "2026-09-01T08:00:00Z"
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```

#### POST /api/go/v1/users
**Request:**
```json
{
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT",
  "password": "TempPassword123!"
}
```
**Response** `201 Created` — объект пользователя.
**Ошибки:** `409 email_taken`, `400 invalid_request`.

#### GET /api/go/v1/users/{id}
**Response** `200 OK` — объект пользователя вместе с его практиками. **Ошибки:** `404 user_not_found`.

#### PATCH /api/go/v1/users/{id}
Изменение ФИО, email, роли, блокировка. Смена роли записывается в журнал действий (раздел 11).
```json
{ "full_name": "…", "email": "…", "role": "CURATOR", "is_active": false }
```
**Response** `200 OK` — обновлённый пользователь.

#### POST /api/go/v1/users/{id}/reset-password
```json
{ "new_password": "TempPassword456!" }
```
**Response:** `204 No Content`

---

### 5. Практики (курсы-группы)

Практика — это курс с датами, куратором и составом студентов (на схеме «Курсы практики»).

#### GET /api/go/v1/practices
`ADMIN` получает все практики, `CURATOR` — свои, `STUDENT` — те, где он участник.

**Query:** `curator_id`, `active` (идёт сейчас), `search`, `page`, `page_size`.

**Response 200:**
```json
{
  "items": [
    {
      "id": "7c9e6679-7425-40de-944b-e07fc1f90ae7",
      "name": "Учебная практика 2026 · РИ-330944",
      "description": "Учебная практика ИРИТ-РТФ",
      "start_date": "2026-06-01",
      "end_date": "2026-06-28",
      "curator": { "id": "…", "full_name": "Анна Петрова" },
      "students_count": 25,
      "assignments_count": 4
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```

#### POST /api/go/v1/practices (ADMIN)
```json
{
  "name": "Учебная практика 2026 · РИ-330944",
  "description": "…",
  "start_date": "2026-06-01",
  "end_date": "2026-06-28",
  "curator_id": "…"
}
```
**Response** `201 Created`. **Ошибки:** `400 invalid_request` (например, `end_date` раньше `start_date`, или `curator_id` указывает не на куратора).

#### GET /api/go/v1/practices/{id}
**Response** `200 OK` — объект практики. **Ошибки:** `404 practice_not_found`.

#### PATCH /api/go/v1/practices/{id} (ADMIN)
Изменение полей, в том числе смена куратора (`curator_id`).

#### DELETE /api/go/v1/practices/{id} (ADMIN)
**Response:** `204 No Content`. **Ошибки:** `409 practice_not_empty`.

#### GET /api/go/v1/practices/{id}/students (ADMIN, CURATOR этой практики)
Состав практики. Нужен для выбора получателя задания и для ведомости.
```json
[ { "id": "…", "full_name": "Мария Орлова", "email": "orlova@uni.ru" } ]
```

#### POST /api/go/v1/practices/{id}/students (ADMIN)
Добавление студентов в практику.
```json
{ "student_ids": ["…", "…"] }
```
**Response:** `204 No Content`.

#### DELETE /api/go/v1/practices/{id}/students/{student_id} (ADMIN)
**Response:** `204 No Content`.

---

### 6. Задания

#### GET /api/go/v1/assignments
Страница заданий с фильтрами.
- `STUDENT` получает только опубликованные задания, адресованные ему (всей практике или лично). В каждом элементе есть `my_submission` и `student_state`.
- `CURATOR` получает свои задания, включая черновики. В каждом элементе есть `stats`.

**Query:** `practice_id`, `status` (`draft` | `published`), `type`, `student_state`, `deadline_from`, `deadline_to` (для календаря дедлайнов), `search`, `sort` (`deadline`, `-created_at`), `page`, `page_size`.

**Response 200 (STUDENT):**
```json
{
  "items": [
    {
      "id": "9b2f…",
      "title": "Отчёт о выполненной работе",
      "description": "Опишите выполненные задачи…",
      "type": "report",
      "status": "published",
      "deadline": "2026-06-20T18:59:00Z",
      "max_score": 10,
      "criteria": "Полнота, оформление, выводы",
      "practice": { "id": "…", "name": "Учебная практика 2026" },
      "curator": { "id": "…", "full_name": "Анна Петрова" },
      "published_at": "2026-06-02T09:00:00Z",
      "student_state": "under_review",
      "my_submission": { "id": "…", "status": "under_review", "submitted_at": "2026-06-15T10:42:00Z", "score": null }
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```
**Поле `stats` для CURATOR:**
```json
"stats": { "recipients": 25, "not_submitted": 5, "submitted": 8, "under_review": 2, "revision": 1, "graded": 9 }
```

#### POST /api/go/v1/assignments (CURATOR)
Создание задания. Всегда в статусе `draft`. Для черновика обязательно только поле `title`.
```json
{
  "practice_id": "…",
  "title": "Отчёт о выполненной работе",
  "description": "…",
  "type": "report",
  "deadline": "2026-06-20T18:59:00Z",
  "max_score": 10,
  "criteria": "…",
  "student_ids": []
}
```
Пустой `student_ids` означает «всей практике»; список ID — только этим студентам. Каждый из них должен состоять в практике.
**Response** `201 Created` — объект задания. **Ошибки:** `403 forbidden` (чужая практика), `400 invalid_request`.

#### GET /api/go/v1/assignments/{id}
Карточка задания (модалка «Подробности задания»). Помимо полей задания, возвращается блок `permissions`, по которому фронт показывает или скрывает кнопки:
```json
"permissions": { "can_edit": true, "can_delete": true, "can_publish": true, "can_submit": false }
```
**Ошибки:** `404 assignment_not_found`.

#### PATCH /api/go/v1/assignments/{id} (CURATOR — автор)
Тело то же, что при создании; передаются только изменённые поля. **Ошибки:** `409 assignment_locked_field`.

#### DELETE /api/go/v1/assignments/{id} (CURATOR — автор)
Удалить можно только черновик. **Ошибки:** `409 invalid_status_transition`.

#### POST /api/go/v1/assignments/{id}/publish (CURATOR — автор)
Переход `draft` → `published`. Сервер проверяет, что заполнены `description`, `deadline`, `max_score > 0` и `criteria`; незаполненные поля возвращаются в `errors`. Время публикации (`published_at`) ставит сервер.
**Response** `200 OK` — опубликованное задание.

#### GET /api/go/v1/assignments/{id}/submissions (CURATOR, ADMIN)
Таблица на экране задания у куратора: **все** получатели, включая тех, кто ещё не сдал.

**Query:** `student_state`.
```json
[
  {
    "student": { "id": "…", "full_name": "Мария Орлова" },
    "student_state": "submitted",
    "submission": { "id": "…", "status": "submitted", "submitted_at": "2026-06-15T10:42:00Z", "is_late": false, "score": null }
  },
  {
    "student": { "id": "…", "full_name": "Денис Соколов" },
    "student_state": "not_submitted",
    "submission": null
  }
]
```

#### POST /api/go/v1/assignments/{id}/submissions (STUDENT)
Сдача работы (форма с drag&drop). Тело — `multipart/form-data`:
- `file` — обязательно;
- `comment` — необязательно, до 3000 символов.

Заголовок `Idempotency-Key: <uuid>` защищает от дублей при повторной отправке формы.
**Response** `201 Created` — объект сдачи (см. раздел 7) со статусом `submitted`.
**Ошибки:** `409 submission_already_exists`, `409 assignment_not_published`, `409 deadline_passed`, `413 file_too_large`, `415 unsupported_file_type`.

---

### 7. Сдачи и проверка

#### GET /api/go/v1/submissions
- `STUDENT` — свои сдачи (экран «История сдач»).
- `CURATOR` — сдачи по своим практикам. Очередь «ждут проверки»: `?status=submitted`.

**Query:** `status`, `assignment_id`, `practice_id`, `student_id`, `reviewer_id` (`me` — сдачи, которые проверяю я), `sort` (`-submitted_at`), `page`, `page_size`.

#### GET /api/go/v1/submissions/{id}
Подробности сдачи (модалка «Подробности проверки»).
```json
{
  "id": "…",
  "assignment": { "id": "…", "title": "Отчёт", "type": "report", "deadline": "2026-06-20T18:59:00Z", "max_score": 10 },
  "student": { "id": "…", "full_name": "Иванов Иван Иванович" },
  "status": "graded",
  "submitted_at": "2026-06-15T10:42:00Z",
  "is_late": false,
  "comment": "Отчёт по выполненным задачам",
  "file": {
    "original_name": "Отчёт.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 1048576,
    "uploaded_at": "2026-06-15T10:42:00Z",
    "download_url": "/api/go/v1/submissions/…/file"
  },
  "review": {
    "score": 9,
    "feedback": "Хорошо, добавьте выводы",
    "reviewer": { "id": "…", "full_name": "Анна Петрова" },
    "graded_at": "2026-06-16T12:00:00Z",
    "published_at": "2026-06-16T12:00:00Z"
  },
  "permissions": { "can_take": false, "can_review": false, "can_reupload": false, "can_appeal": true }
}
```
Студент получает `review: null`, пока результат не опубликован.

#### GET /api/go/v1/submissions/{id}/file
Скачивание файла (автор сдачи, куратор, админ). Ответ — бинарный, см. раздел 1.3.

#### PUT /api/go/v1/submissions/{id}/file (STUDENT — автор)
Повторная загрузка файла после возврата на доработку (по ТЗ: «при revision студент может перезагрузить файл»). Работает только в статусе `revision`; статус меняется на `submitted`, предыдущий результат проверки сохраняется в истории.
Тело — `multipart/form-data`: `file`, `comment`.
**Ошибки:** `409 invalid_status_transition`, `413 file_too_large`, `415 unsupported_file_type`.

#### POST /api/go/v1/submissions/{id}/take (CURATOR)
Взять сдачу на проверку: `submitted` → `under_review`, проверяющим становится текущий куратор. Вынесено в отдельный POST, чтобы простой просмотр сдачи (GET) не менял её статус. Повторный вызов тем же куратором возвращает `200` без изменений.

#### PUT /api/go/v1/submissions/{id}/review (CURATOR)
Сохранить результат проверки без публикации: студент его пока не видит. Работает только в статусе `under_review`.
```json
{ "decision": "accepted", "score": 9, "feedback": "Хорошо, добавьте выводы" }
```
- `decision`: `accepted` | `revision`;
- при `accepted` поле `score` обязательно: целое число от 0 до `max_score`;
- при `revision` поле `feedback` обязательно.

#### POST /api/go/v1/submissions/{id}/review/publish (CURATOR)
Опубликовать результат студенту: `under_review` → `graded` или `revision`. Можно передать то же тело, что в `PUT /review`, чтобы сохранить и опубликовать одним запросом.
**Response** `200 OK` — сдача. **Ошибки:** `409 invalid_status_transition`, `400 invalid_request`.

#### GET /api/go/v1/submissions/{id}/history
История попыток и проверок по сдаче (экран «Сравнить оценки попыток»).
```json
[
  { "attempt": 1, "submitted_at": "…", "file": { "original_name": "v1.pdf", "download_url": "…" }, "decision": "revision", "score": null, "feedback": "Добавьте выводы", "published_at": "…" },
  { "attempt": 2, "submitted_at": "…", "file": { "original_name": "v2.pdf", "download_url": "…" }, "decision": "accepted", "score": 9, "feedback": "Отлично", "published_at": "…" }
]
```

---

### 8. Оценки и ведомость

#### GET /api/go/v1/grades/my (STUDENT)
Страница «Оценки» студента. Возвращаются только опубликованные результаты.
```json
{
  "summary": { "total_score": 37, "total_max_score": 52, "average_percent": 71.2, "graded_count": 4, "assignments_count": 6 },
  "items": [
    {
      "assignment": { "id": "…", "title": "Прототип ЛК", "type": "task", "max_score": 15 },
      "submission_id": "…",
      "status": "graded",
      "score": 12,
      "feedback": "Инструкция понятная",
      "published_at": "2026-06-14T10:00:00Z"
    }
  ]
}
```

#### GET /api/go/v1/grades/sheet?practice_id={id} (CURATOR своей практики, ADMIN)
Ведомость практики: матрица «студенты × задания».
```json
{
  "practice": { "id": "…", "name": "Учебная практика 2026" },
  "assignments": [ { "id": "a1", "title": "Прототип ЛК", "max_score": 15 }, { "id": "a2", "title": "Отчёт", "max_score": 10 } ],
  "rows": [
    {
      "student": { "id": "…", "full_name": "Иванов Иван" },
      "cells": [
        { "assignment_id": "a1", "assigned": true, "student_state": "graded", "submission_id": "…", "score": 12 },
        { "assignment_id": "a2", "assigned": true, "student_state": "under_review", "submission_id": "…", "score": null }
      ],
      "total_score": 12,
      "total_max_score": 25
    }
  ]
}
```
Если `assigned: false`, задание этому студенту не назначено, и в ячейке выводится «Не назначено».

#### GET /api/go/v1/grades/export (CURATOR, ADMIN)
Выгрузка оценок в Excel.
**Query:** `practice_id`, `format` (`xlsx` | `csv`), `from`, `to`.
**Response** `200 OK` — файл; `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` или `text/csv`.

#### PATCH /api/go/v1/submissions/{id}/score (ADMIN)
Ручное изменение оценки администратором (по бизнес-процессу: «Изменение оценок работ»). Изменение пишется в журнал.
```json
{ "score": 10, "reason": "Исправление ошибки при вводе" }
```

---

### 9. Апелляции (по ТЗ)

Подать апелляцию можно только после `graded`, в течение N дней (значение настраивается, см. раздел 12).

#### POST /api/go/v1/submissions/{id}/appeals (STUDENT — автор)
```json
{ "reason": "Не учтён раздел 3 отчёта" }
```
**Response** `201 Created` — апелляция. **Ошибки:** `409 appeal_window_closed`, `409 invalid_status_transition` (сдача не в `graded`, или апелляция уже подана).

#### GET /api/go/v1/appeals
`STUDENT` получает свои апелляции, `ADMIN` — все.
**Query:** `status`, `practice_id`, `page`, `page_size`.
```json
{
  "items": [
    {
      "id": "…",
      "submission": { "id": "…", "assignment_title": "Отчёт", "student": { "id": "…", "full_name": "Иванов Иван" } },
      "reason": "Не учтён раздел 3 отчёта",
      "status": "submitted",
      "old_score": 6,
      "new_score": null,
      "resolution_comment": null,
      "created_at": "…",
      "resolved_at": null
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```

#### GET /api/go/v1/appeals/{id}
**Ошибки:** `404 appeal_not_found`.

#### POST /api/go/v1/appeals/{id}/resolve (ADMIN)
```json
{ "decision": "accepted", "new_score": 8, "comment": "Раздел 3 засчитан" }
```
`decision` принимает значения `accepted` | `rejected`. При `accepted` поле `new_score` обязательно.

---

### 10. Уведомления

#### GET /api/go/v1/notifications
**Query:** `unread` (true/false), `page`, `page_size`.
```json
{
  "unread_count": 3,
  "items": [
    {
      "id": "…",
      "type": "review_published",
      "title": "Работа проверена",
      "text": "«Отчёт» — 9 из 10",
      "entity": { "type": "submission", "id": "…" },
      "is_read": false,
      "created_at": "…"
    }
  ],
  "total": 3, "page": 1, "page_size": 20
}
```
Типы уведомлений (`type`): `assignment_published`, `review_published`, `deadline_soon`, `appeal_resolved`.

#### POST /api/go/v1/notifications/read
```json
{ "ids": ["…"] }
```
или `{ "all": true }`. **Response:** `204 No Content`.

---

### 11. Журнал действий (ADMIN, по ТЗ)

#### GET /api/go/v1/audit-logs
По ТЗ логируются: создание и изменение заданий, оценок, смена ролей, вход.
**Query:** `action`, `actor_id`, `entity_type`, `from`, `to`, `page`, `page_size`.
```json
{
  "items": [
    {
      "id": "…",
      "action": "role_changed",
      "actor": { "id": "…", "full_name": "Админ" },
      "entity": { "type": "user", "id": "…" },
      "changes": { "role": { "from": "STUDENT", "to": "CURATOR" } },
      "created_at": "…"
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```
Значения `action`: `login`, `assignment_created`, `assignment_updated`, `assignment_published`, `review_published`, `score_changed`, `role_changed`, `user_created`, `appeal_resolved`.

---

### 12. Настройки системы (ADMIN)

#### GET /api/go/v1/settings · PATCH /api/go/v1/settings
По ТЗ поздняя сдача и срок апелляции настраиваются.
```json
{
  "allow_late_submission": false,
  "appeal_window_days": 3,
  "max_file_size_bytes": 20000000,
  "allowed_file_types": ["pdf", "docx", "zip"]
}
```
Поля `max_file_size_bytes` и `allowed_file_types` только для чтения: фронт показывает их в подсказке у формы загрузки.

---

### 13. Сводная таблица эндпоинтов

| Метод | Путь | Роли | Приоритет |
|---|---|---|---|
| POST | /auth/login | все | MVP (есть) |
| GET | /auth/me | все | MVP (есть) |
| POST | /auth/logout | все | MVP |
| PATCH | /auth/me | все | MVP |
| POST | /auth/change-password | все | Позже |
| GET | /dashboard | все | MVP |
| GET, POST | /users | ADMIN (GET — ещё CURATOR) | MVP |
| GET, PATCH | /users/{id} | ADMIN | MVP |
| POST | /users/{id}/reset-password | ADMIN | MVP |
| GET, POST | /practices | все / ADMIN | MVP |
| GET, PATCH, DELETE | /practices/{id} | все / ADMIN | MVP |
| GET, POST | /practices/{id}/students | ADMIN, CURATOR / ADMIN | MVP |
| DELETE | /practices/{id}/students/{student_id} | ADMIN | MVP |
| GET, POST | /assignments | все / CURATOR | MVP |
| GET, PATCH, DELETE | /assignments/{id} | все / CURATOR | MVP |
| POST | /assignments/{id}/publish | CURATOR | MVP |
| GET | /assignments/{id}/submissions | CURATOR, ADMIN | MVP |
| POST | /assignments/{id}/submissions | STUDENT | MVP |
| GET | /submissions | все | MVP |
| GET | /submissions/{id} | все | MVP |
| GET | /submissions/{id}/file | все | MVP |
| PUT | /submissions/{id}/file | STUDENT | MVP (по ТЗ) |
| POST | /submissions/{id}/take | CURATOR | MVP |
| PUT | /submissions/{id}/review | CURATOR | MVP |
| POST | /submissions/{id}/review/publish | CURATOR | MVP |
| GET | /submissions/{id}/history | все | Позже |
| GET | /grades/my | STUDENT | MVP |
| GET | /grades/sheet | CURATOR, ADMIN | MVP |
| GET | /grades/export | CURATOR, ADMIN | Позже |
| PATCH | /submissions/{id}/score | ADMIN | Позже |
| POST | /submissions/{id}/appeals | STUDENT | MVP (по ТЗ) |
| GET | /appeals, /appeals/{id} | STUDENT, ADMIN | MVP (по ТЗ) |
| POST | /appeals/{id}/resolve | ADMIN | MVP (по ТЗ) |
| GET | /notifications | все | Позже |
| POST | /notifications/read | все | Позже |
| GET | /audit-logs | ADMIN | MVP (по ТЗ) |
| GET, PATCH | /settings | все / ADMIN | Позже |

---

### 14. Открытые вопросы к бэкенду

1. **Роли.** В ТЗ указан `moderator`, в аналитике — `admin`. Здесь используется `ADMIN`. Нужна ли отдельная роль `MODERATOR` (разбор апелляций и логи без управления пользователями)?
2. **Админ-панель.** Это отдельный сервис (`backend-admin`)? Если да, какой у неё префикс: `/api/admin/v1/...`? Тогда разделы 4, 5 (запись), 11 и 12 переедут туда.
3. **Срок жизни токена.** Сейчас токен действует 24 часа, refresh-токена нет. Это нормально для MVP? Если нужен refresh, предлагаем `POST /auth/refresh` с refresh-токеном в httpOnly cookie.
4. **Ошибка `teacher_busy`.** Пример с ней («у преподавателя уже есть активная практика с этим студентом») предполагает, что практика — это пара «куратор + студент». В аналитике практика — это курс с группой студентов. Какая модель правильная?
5. **Поздняя сдача.** Это глобальная настройка (`settings.allow_late_submission`) или флаг у каждого задания?
6. **Средний балл.** Как считать: сумма баллов / сумма максимумов или среднее процентов по заданиям? Как округлять?
7. **Регистрация.** Пользователей создаёт админ, или нужна самостоятельная регистрация (`POST /auth/register`)? Вход через УрФУ (SSO) — позже?
8. **CORS.** Разрешить origin фронта в dev-режиме (`http://localhost:5173`) и прислать ссылку на Swagger, когда он появится.