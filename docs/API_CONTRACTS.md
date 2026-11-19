# API Contracts

## 1. Общие соглашения

### Формат данных
- Все запросы и ответы: `Content-Type: application/json`
- Идентификаторы (ID): целые числа (например, `"id": 15`) — по схеме БД MVP (`integer GENERATED ALWAYS AS IDENTITY`)
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
- **400 `invalid_request`** — не прошла валидация тела запроса, либо переданный ID не является целым положительным числом.
- **401 `invalid_credentials`** — неверный email или пароль при попытке входа в систему.
- **401 `unauthorized`** — токен отсутствует, истек, невалиден или имеет неправильную подпись.
- **403 `forbidden`** — пользователь аутентифицирован, но его `role` не позволяет выполнить это действие (например, студент пытается удалить группу).
- **404 `group_not_found`** — группы (курса практики) с таким `id` не существует в БД.
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
    "id": 15,
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
  "id": 15,
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

### 1.1. Роли
`STUDENT`, `CURATOR`, `ADMIN` (в БД хранятся в нижнем регистре: `student`, `curator`, `admin`).

| Роль | Права |
|---|---|
| `STUDENT` | Состоит ровно в одной группе. Видит только опубликованные задания своей группы и личные задания, сдаёт работы, видит опубликованные результаты |
| `CURATOR` | Ведёт свои группы: CRUD заданий, проверка сдач, оценивание, возврат на доработку |
| `ADMIN` | Работает через админ-панель: пользователи, группы, просмотр всего. Отдельной роли модератора нет |

Пользователей создаёт только `ADMIN`, самостоятельной регистрации нет.

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
- Загрузка: `multipart/form-data`, поле `file`. Один файл на сдачу: PDF, DOCX или ZIP, от 1 байта до 20 000 000 байт. Тип проверяется по содержимому файла, а не по расширению.
- Скачивание: бинарный ответ с заголовками `Content-Type` (исходный `mime_type`) и `Content-Disposition: attachment; filename*=UTF-8''<имя>`.
- В списках и карточках возвращается только блок `file` с метаданными (`original_name`, `mime_type`, `size_bytes`, `download_url`), без содержимого.

### 1.4. Коды ошибок
Формат ответа — RFC 7807, как в разделе 1.

- **400 `invalid_request`** — при ошибках валидации полей в ответ добавляется расширение `errors`, чтобы фронт подсветил поля формы:
  ```json
  {
    "type": "about:blank", "title": "Invalid request", "status": 400,
    "detail": "Проверьте заполнение полей", "code": "invalid_request",
    "instance": "/api/go/v1/assignments/12/publish",
    "errors": [ { "field": "deadline", "message": "Обязательно для публикации" } ]
  }
  ```
- **401 `invalid_refresh_token`** — refresh-токен отсутствует или истёк; фронт отправляет пользователя на страницу входа.
- **403 `user_inactive`** — учётная запись заблокирована (`is_active = false`).
- **404 `user_not_found`**, **`assignment_not_found`**, **`submission_not_found`**. Если студент запрашивает чужой ресурс, отвечать тоже 404.
- **409 `invalid_status_transition`** — действие недопустимо в текущем статусе (например, оценить сдачу, которая не в `under_review`).
- **409 `submission_already_exists`** — студент уже сдавал это задание. Сдача по заданию одна, повторной отправки нет.
- **409 `assignment_not_published`** — сдача невозможна: задание в черновике.
- **409 `deadline_passed`** — дедлайн прошёл; сдать работу после дедлайна нельзя.
- **409 `assignment_locked_field`** — после публикации нельзя менять получателя, после первой сдачи — `type`.
- **409 `user_has_related_data`** — нельзя сменить роль или группу пользователя, у которого есть задания или сдачи.
- **409 `login_taken`**, **`email_taken`** — логин или email уже заняты (сравнение без учёта регистра и пробелов по краям).
- **409 `group_not_empty`** — нельзя удалить группу, в которой есть студенты или задания.
- **413 `file_too_large`** — файл больше 20 000 000 байт.
- **415 `unsupported_file_type`** — файл не PDF, не DOCX и не ZIP.

### 1.5. Статусы

**Задание** (`assignment.status`): `draft` → `published`. Создаётся всегда в статусе `draft`. Студенты видят задание только после публикации.

**Тип задания** (`assignment.type`): `task` — задание, `report` — отчёт. По умолчанию `task`.

**Сдача** (`submission.status`):
```
загрузка файла → submitted
куратор взял на проверку → under_review
опубликован результат «принято» → graded
опубликован результат «на доработку» → revision_required
```
`graded` и `revision_required` — конечные статусы: повторной отправки и замены файла в MVP нет.

**Решение проверки** (`decision`): `accepted` | `revision_required`.

**Состояние задания для студента** (`student_state`, вычисляется сервером, не хранится): `not_submitted`, `overdue`, `submitted`, `under_review`, `revision_required`, `graded`. Используется для фильтров, бейджей и счётчиков на дашборде. Пока результат не опубликован, студент видит `under_review`.

### 1.6. Разработка
- CORS: разрешён origin фронта `http://localhost:5173` с `credentials` (нужно для refresh-cookie).
- Swagger-документация публикуется вместе с бэкендом.

---

### 2.1. Авторизация (продолжение)

#### POST /api/go/v1/auth/refresh
Обновление access-токена. При входе (`POST /auth/login`) сервер дополнительно ставит refresh-токен в cookie:
`Set-Cookie: refresh_token=…; HttpOnly; Secure; SameSite=Strict; Path=/api/go/v1/auth`.
Фронт вызывает `/auth/refresh`, когда получает `401 unauthorized`, и повторяет исходный запрос с новым токеном.

**Request:** тела нет, refresh-токен передаётся в cookie.

**Response** `200 OK` (приходит новая refresh-cookie):
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9…",
  "token_type": "Bearer",
  "expires_in": 900
}
```
**Ошибки:** `401 invalid_refresh_token`.

#### POST /api/go/v1/auth/logout
Выход: сервер очищает refresh-cookie.

**Response:** `204 No Content`

#### PATCH /api/go/v1/auth/me
Редактирование своего профиля. Роль, группу и логин пользователь сам не меняет.

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

#### Расширенный ответ `GET /auth/me`
В ответе также возвращаются логин и группы пользователя — по ним фронт строит навигацию при старте:
```json
{
  "id": 15,
  "login": "ivanov",
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT",
  "is_active": true,
  "group": { "id": 3, "name": "Учебная практика 2026 · РИ-330944" },
  "curated_groups": []
}
```
- `STUDENT`: `group` — его группа, `curated_groups` пустой.
- `CURATOR`: `group` = `null`, `curated_groups` — группы, которые он ведёт.
- `ADMIN`: `group` = `null`, `curated_groups` пустой.

---

### 3. Дашборд

#### GET /api/go/v1/dashboard
Все данные главного экрана одним запросом. Структура ответа зависит от роли (`role`).

**Response 200 — STUDENT:**
```json
{
  "role": "STUDENT",
  "group": { "id": 3, "name": "Учебная практика 2026 · РИ-330944", "start_date": "2026-06-01", "end_date": "2026-06-28" },
  "counters": { "to_submit": 2, "overdue": 1, "on_review": 1, "graded": 3, "revision_required": 0, "total": 7 },
  "total_score": 37,
  "upcoming_deadlines": [
    {
      "assignment": { "id": 21, "title": "Отчёт о практике", "type": "report", "deadline": "2026-06-20T18:59:00Z" },
      "student_state": "not_submitted"
    }
  ],
  "recent_results": [
    { "submission_id": 40, "assignment_title": "Прототип ЛК", "decision": "accepted", "score": 12, "result_published_at": "2026-06-14T10:00:00Z" }
  ]
}
```
`total_score` — сумма опубликованных баллов студента.

**Response 200 — CURATOR:**
```json
{
  "role": "CURATOR",
  "groups": [ { "id": 3, "name": "Учебная практика 2026 · РИ-330944", "students_count": 25 } ],
  "counters": { "awaiting_review": 8, "under_review": 2, "drafts": 1, "published_assignments": 5 },
  "review_queue": [
    { "submission_id": 41, "student": { "id": 16, "full_name": "Мария Орлова" }, "assignment_title": "Отчёт", "submitted_at": "2026-06-15T10:42:00Z" }
  ],
  "upcoming_deadlines": [ { "id": 21, "title": "Отчёт", "deadline": "2026-06-20T18:59:00Z" } ]
}
```

**Response 200 — ADMIN:**
```json
{
  "role": "ADMIN",
  "counters": { "groups": 4, "active_groups": 2, "students": 96, "curators": 5, "awaiting_review": 14 }
}
```

---

### 4. Пользователи (ADMIN)

#### GET /api/go/v1/users
Экран «Участники». Пользователь с ролью `CURATOR` получает только студентов своих групп.

**Query:** `role`, `group_id`, `is_active`, `search` (поиск по ФИО, логину и email), `page`, `page_size`, `sort` (`full_name`, `-created_at`).

**Response 200:**
```json
{
  "items": [
    {
      "id": 15,
      "login": "ivanov",
      "email": "student@uni.ru",
      "full_name": "Иванов Иван Иванович",
      "role": "STUDENT",
      "is_active": true,
      "group": { "id": 3, "name": "Учебная практика 2026 · РИ-330944" },
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
  "login": "ivanov",
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT",
  "group_id": 3,
  "password": "TempPassword123!"
}
```
`group_id` обязателен для `STUDENT` и должен быть `null` для `CURATOR` и `ADMIN`. Поэтому порядок заполнения такой: куратор → группа → студенты.
**Response** `201 Created` — объект пользователя.
**Ошибки:** `409 login_taken`, `409 email_taken`, `400 invalid_request`, `404 group_not_found`.

#### GET /api/go/v1/users/{id}
**Response** `200 OK` — объект пользователя. **Ошибки:** `404 user_not_found`.

#### PATCH /api/go/v1/users/{id}
Изменение ФИО, email, роли, группы студента, блокировка.
```json
{ "full_name": "…", "email": "…", "role": "STUDENT", "group_id": 4, "is_active": false }
```
**Response** `200 OK` — обновлённый пользователь.
**Ошибки:** `409 user_has_related_data` — смена роли или группы при наличии заданий или сдач; `409 email_taken`.

#### POST /api/go/v1/users/{id}/reset-password
```json
{ "new_password": "TempPassword456!" }
```
**Response:** `204 No Content`

---

### 5. Группы (курсы практики)

Группа — это курс практики: даты, один куратор и студенты. Студент состоит ровно в одной группе (её задаёт `group_id` пользователя), куратор может вести несколько групп.

#### GET /api/go/v1/groups
`ADMIN` получает все группы, `CURATOR` — те, которые он ведёт, `STUDENT` — свою.

**Query:** `curator_id`, `active` (идёт сейчас), `search`, `page`, `page_size`.

**Response 200:**
```json
{
  "items": [
    {
      "id": 3,
      "name": "Учебная практика 2026 · РИ-330944",
      "description": "Учебная практика ИРИТ-РТФ",
      "start_date": "2026-06-01",
      "end_date": "2026-06-28",
      "curator": { "id": 7, "full_name": "Анна Петрова" },
      "students_count": 25,
      "assignments_count": 4
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```

#### POST /api/go/v1/groups (ADMIN)
```json
{
  "name": "Учебная практика 2026 · РИ-330944",
  "description": "",
  "start_date": "2026-06-01",
  "end_date": "2026-06-28",
  "curator_id": 7
}
```
**Response** `201 Created`. **Ошибки:** `400 invalid_request` (например, `end_date` раньше `start_date` или `curator_id` указывает не на куратора).

#### GET /api/go/v1/groups/{id}
**Response** `200 OK` — объект группы. **Ошибки:** `404 group_not_found`.

#### PATCH /api/go/v1/groups/{id} (ADMIN)
Изменение полей, в том числе смена куратора (`curator_id`).

#### DELETE /api/go/v1/groups/{id} (ADMIN)
**Response:** `204 No Content`. **Ошибки:** `409 group_not_empty`.

#### GET /api/go/v1/groups/{id}/students (ADMIN, куратор группы)
Состав группы. Нужен для выбора личного получателя задания и для ведомости. Студент добавляется в группу через `POST /users` или `PATCH /users/{id}` с `group_id`.
```json
[ { "id": 16, "full_name": "Мария Орлова", "email": "orlova@uni.ru" } ]
```

---

### 6. Задания

#### GET /api/go/v1/assignments
Страница заданий с фильтрами.
- `STUDENT` получает только опубликованные задания своей группы и личные. В каждом элементе есть `my_submission` и `student_state`.
- `CURATOR` получает свои задания, включая черновики. В каждом элементе есть `stats`.

**Query:** `group_id`, `status` (`draft` | `published`), `type`, `student_state`, `deadline_from`, `deadline_to` (для календаря дедлайнов), `search`, `sort` (`deadline`, `-created_at`), `page`, `page_size`.

**Response 200 (STUDENT):**
```json
{
  "items": [
    {
      "id": 21,
      "title": "Отчёт о выполненной работе",
      "description": "Опишите выполненные задачи…",
      "type": "report",
      "status": "published",
      "deadline": "2026-06-20T18:59:00Z",
      "criteria": "Полнота, оформление, выводы",
      "curator": { "id": 7, "full_name": "Анна Петрова" },
      "group": { "id": 3, "name": "Учебная практика 2026" },
      "student": null,
      "created_at": "2026-06-01T09:00:00Z",
      "published_at": "2026-06-02T09:00:00Z",
      "student_state": "under_review",
      "my_submission": { "id": 40, "status": "under_review", "submitted_at": "2026-06-15T10:42:00Z" }
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```
**Поле `stats` для CURATOR:**
```json
"stats": { "recipients": 25, "not_submitted": 5, "submitted": 8, "under_review": 2, "revision_required": 1, "graded": 9 }
```

#### POST /api/go/v1/assignments (CURATOR)
Создание задания. Всегда в статусе `draft`. Для черновика обязательно только поле `title`.
```json
{
  "title": "Отчёт о выполненной работе",
  "description": "…",
  "type": "report",
  "deadline": "2026-06-20T18:59:00Z",
  "criteria": "…",
  "group_id": 3,
  "student_id": null
}
```
Получатель — **либо** вся группа (`group_id`), **либо** один студент (`student_id`), но не оба сразу. В черновике оба поля могут быть пустыми. Группа должна быть группой куратора, студент — состоять в такой группе.
**Response** `201 Created` — объект задания. **Ошибки:** `403 forbidden` (чужая группа), `400 invalid_request`.

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
Переход `draft` → `published`. Сервер проверяет, что заполнены `description`, `deadline`, `criteria` и получатель (`group_id` или `student_id`); незаполненные поля возвращаются в `errors`. Время публикации (`published_at`) ставит сервер.
**Response** `200 OK` — опубликованное задание.

#### GET /api/go/v1/assignments/{id}/submissions (CURATOR, ADMIN)
Таблица на экране задания у куратора: **все** получатели, включая тех, кто ещё не сдал.

**Query:** `student_state`.
```json
[
  {
    "student": { "id": 16, "full_name": "Мария Орлова" },
    "student_state": "submitted",
    "submission": { "id": 41, "status": "submitted", "submitted_at": "2026-06-15T10:42:00Z", "score": null }
  },
  {
    "student": { "id": 17, "full_name": "Денис Соколов" },
    "student_state": "not_submitted",
    "submission": null
  }
]
```

#### POST /api/go/v1/assignments/{id}/submissions (STUDENT)
Сдача работы (форма с drag&drop). Тело — `multipart/form-data`, поле `file`. Проверяющим сервер назначает куратора группы студента.

Заголовок `Idempotency-Key: <uuid>` защищает от дублей при повторной отправке формы.
**Response** `201 Created` — объект сдачи (см. раздел 7) со статусом `submitted`.
**Ошибки:** `409 submission_already_exists`, `409 assignment_not_published`, `409 deadline_passed`, `413 file_too_large`, `415 unsupported_file_type`.

---

### 7. Сдачи и проверка

#### GET /api/go/v1/submissions
- `STUDENT` — свои сдачи.
- `CURATOR` — сдачи, где он проверяющий. Очередь «ждут проверки»: `?status=submitted`.

**Query:** `status`, `assignment_id`, `group_id`, `student_id`, `sort` (`-submitted_at`), `page`, `page_size`.

#### GET /api/go/v1/submissions/{id}
Подробности сдачи (модалка «Подробности проверки»).
```json
{
  "id": 40,
  "assignment": { "id": 21, "title": "Отчёт", "type": "report", "deadline": "2026-06-20T18:59:00Z" },
  "student": { "id": 15, "full_name": "Иванов Иван Иванович" },
  "curator": { "id": 7, "full_name": "Анна Петрова" },
  "status": "graded",
  "submitted_at": "2026-06-15T10:42:00Z",
  "file": {
    "original_name": "Отчёт.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 1048576,
    "download_url": "/api/go/v1/submissions/40/file"
  },
  "result": {
    "decision": "accepted",
    "score": 9,
    "feedback": "Хорошо, добавьте выводы",
    "graded_at": "2026-06-16T12:00:00Z",
    "result_published_at": "2026-06-16T12:00:00Z"
  },
  "permissions": { "can_take": false, "can_review": false, "can_publish": false }
}
```
Студент получает `result: null`, пока результат не опубликован.

#### GET /api/go/v1/submissions/{id}/file
Скачивание файла (автор сдачи, проверяющий куратор, админ). Ответ — бинарный, см. раздел 1.3.

#### POST /api/go/v1/submissions/{id}/take (CURATOR — проверяющий)
Взять сдачу на проверку: `submitted` → `under_review`. Просмотр сдачи (GET) статус не меняет. Повторный вызов возвращает `200` без изменений.

#### PUT /api/go/v1/submissions/{id}/review (CURATOR — проверяющий)
Сохранить результат проверки без публикации: студент его пока не видит. Работает только в статусе `under_review`, сохранённый результат можно перезаписать до публикации. Время проверки (`graded_at`) ставит сервер.
```json
{ "decision": "accepted", "score": 9, "feedback": "Хорошо, добавьте выводы" }
```
- `decision`: `accepted` | `revision_required`;
- при `accepted` поле `score` обязательно: целое число ≥ 0;
- при `revision_required` поле `feedback` обязательно.

#### POST /api/go/v1/submissions/{id}/review/publish (CURATOR — проверяющий)
Опубликовать результат студенту: `under_review` → `graded` (при `accepted`) или `revision_required`. Время публикации (`result_published_at`) ставит сервер. Можно передать то же тело, что в `PUT /review`, чтобы сохранить и опубликовать одним запросом. Опубликованный результат не меняется.
**Response** `200 OK` — сдача. **Ошибки:** `409 invalid_status_transition`, `400 invalid_request`.

---

### 8. Оценки и ведомость

#### GET /api/go/v1/grades/my (STUDENT)
Страница «Оценки» студента. Возвращаются только опубликованные результаты.
```json
{
  "summary": { "total_score": 37, "graded_count": 4, "revision_required_count": 1, "assignments_count": 6 },
  "items": [
    {
      "assignment": { "id": 22, "title": "Прототип ЛК", "type": "task" },
      "submission_id": 40,
      "status": "graded",
      "decision": "accepted",
      "score": 12,
      "feedback": "Инструкция понятная",
      "result_published_at": "2026-06-14T10:00:00Z"
    }
  ]
}
```
`total_score` — общая оценка: сумма опубликованных баллов.

#### GET /api/go/v1/grades/sheet?group_id={id} (куратор группы, ADMIN)
Ведомость группы: матрица «студенты × задания».
```json
{
  "group": { "id": 3, "name": "Учебная практика 2026" },
  "assignments": [ { "id": 22, "title": "Прототип ЛК" }, { "id": 21, "title": "Отчёт" } ],
  "rows": [
    {
      "student": { "id": 15, "full_name": "Иванов Иван" },
      "cells": [
        { "assignment_id": 22, "assigned": true, "student_state": "graded", "submission_id": 40, "score": 12 },
        { "assignment_id": 21, "assigned": true, "student_state": "under_review", "submission_id": 43, "score": null }
      ],
      "total_score": 12
    }
  ]
}
```
Если `assigned: false`, задание этому студенту не назначено, и в ячейке выводится «Не назначено». В ячейках только опубликованные баллы.

#### GET /api/go/v1/grades/export (куратор группы, ADMIN)
Выгрузка ведомости в Excel.
**Query:** `group_id`, `format` (`xlsx` | `csv`).
**Response** `200 OK` — файл; `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` или `text/csv`.

---

### 9. После MVP

В схеме БД MVP для этих функций таблиц нет. Эндпоинты зафиксированы, чтобы заранее заложить UI; детали — когда появятся таблицы.

#### Апелляции
Апелляция — просьба студента пересмотреть опубликованную оценку. Студент подаёт её из карточки сдачи после `graded`, админ разбирает в админ-панели и либо оставляет оценку, либо выставляет новую.
- `POST /api/go/v1/submissions/{id}/appeals` (STUDENT) — `{ "reason": "Не учтён раздел 3 отчёта" }`.
- `GET /api/go/v1/appeals`, `GET /api/go/v1/appeals/{id}` (STUDENT — свои, ADMIN — все). Статусы: `submitted` → `under_review` → `accepted` | `rejected`.
- `POST /api/go/v1/appeals/{id}/resolve` (ADMIN) — `{ "decision": "accepted", "new_score": 8, "comment": "Раздел 3 засчитан" }`.

#### Уведомления
- `GET /api/go/v1/notifications?unread=true` — `{ "unread_count": 3, "items": [ { "id", "type", "title", "text", "entity": { "type", "id" }, "is_read", "created_at" } ] }`. Типы: `assignment_published`, `result_published`, `deadline_soon`.
- `POST /api/go/v1/notifications/read` — `{ "ids": [1, 2] }` или `{ "all": true }`.

#### Журнал действий (ADMIN)
- `GET /api/go/v1/audit-logs?action=&actor_id=&from=&to=` — создание и изменение заданий, публикация результатов, смена ролей, вход. Элемент: `{ "id", "action", "actor": { "id", "full_name" }, "entity": { "type", "id" }, "changes", "created_at" }`.

---

### 10. Сводная таблица эндпоинтов

Все пути указаны относительно `/api/go/v1`.

| Метод | Путь | Роли | Описание | Приоритет |
|---|---|---|---|---|
| POST | /auth/login | все | Вход, выдача токенов | MVP |
| GET | /auth/me | все | Текущий пользователь и его группы | MVP |
| POST | /auth/refresh | все | Обновление access-токена | MVP |
| POST | /auth/logout | все | Выход | MVP |
| PATCH | /auth/me | все | Редактирование своего профиля | MVP |
| POST | /auth/change-password | все | Смена своего пароля | Позже |
| GET | /dashboard | все | Данные главного экрана по роли | MVP |
| GET, POST | /users | ADMIN (GET — ещё CURATOR) | Список и создание пользователей | MVP |
| GET, PATCH | /users/{id} | ADMIN | Карточка, редактирование, блокировка | MVP |
| POST | /users/{id}/reset-password | ADMIN | Сброс пароля пользователю | MVP |
| GET, POST | /groups | все / ADMIN | Список и создание групп | MVP |
| GET, PATCH, DELETE | /groups/{id} | все / ADMIN | Карточка, правка, удаление группы | MVP |
| GET | /groups/{id}/students | ADMIN, CURATOR | Состав группы | MVP |
| GET, POST | /assignments | все / CURATOR | Список заданий, создание черновика | MVP |
| GET, PATCH, DELETE | /assignments/{id} | все / CURATOR | Карточка, правка, удаление черновика | MVP |
| POST | /assignments/{id}/publish | CURATOR | Публикация задания | MVP |
| GET | /assignments/{id}/submissions | CURATOR, ADMIN | Все получатели задания и их сдачи | MVP |
| POST | /assignments/{id}/submissions | STUDENT | Сдача работы (файл) | MVP |
| GET | /submissions | все | Список сдач, очередь проверки | MVP |
| GET | /submissions/{id} | все | Подробности сдачи и результата | MVP |
| GET | /submissions/{id}/file | все | Скачивание файла сдачи | MVP |
| POST | /submissions/{id}/take | CURATOR | Взять сдачу на проверку | MVP |
| PUT | /submissions/{id}/review | CURATOR | Сохранить результат без публикации | MVP |
| POST | /submissions/{id}/review/publish | CURATOR | Опубликовать результат студенту | MVP |
| GET | /grades/my | STUDENT | Мои оценки и общий балл | MVP |
| GET | /grades/sheet | CURATOR, ADMIN | Ведомость «студенты × задания» | MVP |
| GET | /grades/export | CURATOR, ADMIN | Выгрузка ведомости в Excel/CSV | Позже |
| POST | /submissions/{id}/appeals | STUDENT | Подача апелляции | Позже |
| GET | /appeals, /appeals/{id} | STUDENT, ADMIN | Список и карточка апелляций | Позже |
| POST | /appeals/{id}/resolve | ADMIN | Решение по апелляции | Позже |
| GET | /notifications | все | Список уведомлений | Позже |
| POST | /notifications/read | все | Отметить уведомления прочитанными | Позже |
| GET | /audit-logs | ADMIN | Журнал действий | Позже |

---

### 11. Открытые вопросы

1. **Префикс админ-панели.** Если админ-панель — отдельный сервис (`backend-admin`), какой у неё префикс? Тогда эндпоинты `ADMIN` из разделов 4, 5, 8 и 9 переедут туда.
