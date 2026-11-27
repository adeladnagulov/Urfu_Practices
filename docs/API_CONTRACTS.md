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

#### POST /api/v1/auth/login
Аутентификация пользователя. При успешном входе возвращает JWT-токен, который необходимо передавать в заголовке `Authorization: Bearer <token>` при обращении к защищённым endpoint'ам.

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
  "expires_in": 1800, // 30 мин
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
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Неверный email или пароль",
  "code": "invalid_credentials",
  "instance": "/api/v1/auth/login"
}

#### GET /api/v1/auth/me
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
{
  "type": "about:blank",
  "title": "Unauthorized",
  "status": 401,
  "detail": "Токен отсутствует, истёк или недействителен",
  "code": "unauthorized",
  "instance": "/api/v1/auth/me"
}

### 2.3. Правила авторизации

- Все защищённые endpoint'ы требуют наличия валидного access-токена в заголовке Authorization: Bearer <access_token>.
- Сервер самостоятельно определяет пользователя и его роль по проверенному JWT.
- Административные endpoint'ы доступны только пользователям с ролью ADMIN.
- При обращении авторизованного пользователя без необходимых прав сервер возвращает 403 Forbidden.
- При истечении срока действия access-токена сервер возвращает 401 Unauthorized.
- При истечении токена клиент должен предложить пользователю повторную авторизацию.

### 2.4. Время жизни токена

Access-токен действителен в течение 1800 секунд (30 минут) с момента выдачи.

В текущей версии API refresh-токены не используются. Для продолжения работы после истечения access-токена пользователь должен пройти повторную авторизацию.

---

### 3. Общие правила для эндпоинтов фронтенда

#### 3.1. Роли
`STUDENT`, `CURATOR`, `ADMIN` (в БД хранятся в нижнем регистре: `student`, `curator`, `admin`).

| Роль | Права |
|---|---|
| `STUDENT` | Состоит ровно в одной группе. Видит только опубликованные задания своей группы и личные задания, сдаёт работы, видит опубликованные результаты |
| `CURATOR` | Ведёт свои группы: CRUD заданий, проверка сдач, оценивание, возврат на доработку |
| `ADMIN` | Работает через админ-панель: пользователи, группы, просмотр всего. Отдельной роли модератора нет |

Эндпоинты, доступные только админ-панели, находятся под `/api/v1/admin/...` (например, `GET /api/v1/reports` и `GET /api/v1/admin/reports`).

Пользователей создаёт только `ADMIN`, самостоятельной регистрации нет.

Сервер сам фильтрует данные по роли: фронт не должен получать чужие данные, даже если в запросе подставлен чужой `id`.

#### 3.2. Пагинация, сортировка, фильтры
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

#### 3.3. Файлы
- Загрузка: `multipart/form-data`, поле `file`. Один файл на сдачу: PDF, DOCX или ZIP, от 1 байта до 20 000 000 байт. Тип проверяется по содержимому файла, а не по расширению.
- Скачивание: бинарный ответ с заголовками `Content-Type` (исходный `mime_type`) и `Content-Disposition: attachment; filename*=UTF-8''<имя>`.
- В списках и карточках возвращается только блок `file` с метаданными (`original_name`, `mime_type`, `size_bytes`, `download_url`), без содержимого.

#### 3.4. Статусы

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

### 4. Дашборд

#### GET /api/v1/dashboard
Все данные главного экрана одним запросом для `STUDENT` и `CURATOR`. Структура ответа зависит от роли (`role`).

**Response 200 — STUDENT:**
```json
{
  "role": "STUDENT",
  "group": { "id": "…", "name": "Учебная практика 2026 · РИ-330944", "start_date": "2026-06-01", "end_date": "2026-06-28" },
  "counters": { "to_submit": 2, "overdue": 1, "on_review": 1, "graded": 3, "revision_required": 0, "total": 7 },
  "total_score": 37,
  "upcoming_deadlines": [
    {
      "assignment": { "id": "…", "title": "Отчёт о практике", "type": "report", "deadline": "2026-06-20T18:59:00Z" },
      "student_state": "not_submitted"
    }
  ],
  "recent_results": [
    { "submission_id": "…", "assignment_title": "Прототип ЛК", "decision": "accepted", "score": 12, "result_published_at": "2026-06-14T10:00:00Z" }
  ]
}
```
`total_score` — сумма опубликованных баллов студента.

**Response 200 — CURATOR:**
```json
{
  "role": "CURATOR",
  "groups": [ { "id": "…", "name": "Учебная практика 2026 · РИ-330944", "students_count": 25 } ],
  "counters": { "awaiting_review": 8, "under_review": 2, "drafts": 1, "published_assignments": 5 },
  "review_queue": [
    { "submission_id": "…", "student": { "id": "…", "full_name": "Мария Орлова" }, "assignment_title": "Отчёт", "submitted_at": "2026-06-15T10:42:00Z" }
  ],
  "upcoming_deadlines": [ { "id": "…", "title": "Отчёт", "deadline": "2026-06-20T18:59:00Z" } ]
}
```

#### GET /api/v1/admin/dashboard
Главный экран админ-панели.

**Response 200:**
```json
{
  "role": "ADMIN",
  "counters": { "groups": 4, "active_groups": 2, "students": 96, "curators": 5, "awaiting_review": 14 }
}
```

---

### 5. Пользователи (админ-панель)

#### GET /api/v1/admin/users
Экран «Участники».

**Query:** `role`, `group_id`, `is_active`, `search` (поиск по ФИО, логину и email), `page`, `page_size`, `sort` (`full_name`, `-created_at`).

**Response 200:**
```json
{
  "items": [
    {
      "id": "…",
      "login": "ivanov",
      "email": "student@uni.ru",
      "full_name": "Иванов Иван Иванович",
      "role": "STUDENT",
      "is_active": true,
      "group": { "id": "…", "name": "Учебная практика 2026 · РИ-330944" },
      "created_at": "2026-09-01T08:00:00Z"
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```

#### POST /api/v1/admin/users
**Request:**
```json
{
  "login": "ivanov",
  "email": "student@uni.ru",
  "full_name": "Иванов Иван Иванович",
  "role": "STUDENT",
  "group_id": "…",
  "password": "TempPassword123!"
}
```
`group_id` обязателен для `STUDENT` и должен быть `null` для `CURATOR` и `ADMIN`. Поэтому порядок заполнения такой: куратор → группа → студенты.
**Response** `201 Created` — объект пользователя.
**Ошибки:** `409 login_taken`, `409 email_taken`, `400 invalid_request`, `404 group_not_found`.

#### GET /api/v1/admin/users/{id}
**Response** `200 OK` — объект пользователя. **Ошибки:** `404 user_not_found`.

#### PATCH /api/v1/admin/users/{id}
Изменение ФИО, email, роли, группы студента, блокировка.
```json
{ "full_name": "…", "email": "…", "role": "STUDENT", "group_id": "…", "is_active": false }
```
**Response** `200 OK` — обновлённый пользователь.
**Ошибки:** `409 user_has_related_data` — смена роли или группы при наличии заданий или сдач; `409 email_taken`.

#### POST /api/v1/admin/users/{id}/reset-password
```json
{ "new_password": "TempPassword456!" }
```
**Response:** `204 No Content`

---

### 6. Группы (курсы практики)

Группа — это курс практики: даты, один куратор и студенты. Студент состоит ровно в одной группе (её задаёт `group_id` пользователя), куратор может вести несколько групп.

#### GET /api/v1/groups
`ADMIN` получает все группы, `CURATOR` — те, которые он ведёт, `STUDENT` — свою.

**Query:** `curator_id`, `active` (идёт сейчас), `search`, `page`, `page_size`.

**Response 200:**
```json
{
  "items": [
    {
      "id": "…",
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

#### POST /api/v1/admin/groups
```json
{
  "name": "Учебная практика 2026 · РИ-330944",
  "description": "",
  "start_date": "2026-06-01",
  "end_date": "2026-06-28",
  "curator_id": "…"
}
```
**Response** `201 Created`. **Ошибки:** `400 invalid_request` (например, `end_date` раньше `start_date` или `curator_id` указывает не на куратора).

#### GET /api/v1/groups/{id}
**Response** `200 OK` — объект группы. **Ошибки:** `404 group_not_found`.

#### PATCH /api/v1/admin/groups/{id}
Изменение полей, в том числе смена куратора (`curator_id`).

#### DELETE /api/v1/admin/groups/{id}
**Response:** `204 No Content`. **Ошибки:** `409 group_not_empty`.

#### GET /api/v1/groups/{id}/students (ADMIN, куратор группы)
Состав группы. Нужен для выбора личного получателя задания и для ведомости. Студент добавляется в группу через `POST /admin/users` или `PATCH /admin/users/{id}` с `group_id`.
```json
[ { "id": "…", "full_name": "Мария Орлова", "email": "orlova@uni.ru" } ]
```

---

### 7. Задания

#### GET /api/v1/assignments
Страница заданий с фильтрами.
- `STUDENT` получает только опубликованные задания своей группы и личные. В каждом элементе есть `my_submission` и `student_state`.
- `CURATOR` получает свои задания, включая черновики. В каждом элементе есть `stats`.

**Query:** `group_id`, `status` (`draft` | `published`), `type`, `student_state`, `deadline_from`, `deadline_to` (для календаря дедлайнов), `search`, `sort` (`deadline`, `-created_at`), `page`, `page_size`.

**Response 200 (STUDENT):**
```json
{
  "items": [
    {
      "id": "…",
      "title": "Отчёт о выполненной работе",
      "description": "Опишите выполненные задачи…",
      "type": "report",
      "status": "published",
      "deadline": "2026-06-20T18:59:00Z",
      "criteria": "Полнота, оформление, выводы",
      "curator": { "id": "…", "full_name": "Анна Петрова" },
      "group": { "id": "…", "name": "Учебная практика 2026" },
      "student": null,
      "created_at": "2026-06-01T09:00:00Z",
      "published_at": "2026-06-02T09:00:00Z",
      "student_state": "under_review",
      "my_submission": { "id": "…", "status": "under_review", "submitted_at": "2026-06-15T10:42:00Z" }
    }
  ],
  "total": 1, "page": 1, "page_size": 20
}
```
**Поле `stats` для CURATOR:**
```json
"stats": { "recipients": 25, "not_submitted": 5, "submitted": 8, "under_review": 2, "revision_required": 1, "graded": 9 }
```

#### POST /api/v1/assignments (CURATOR)
Создание задания. Всегда в статусе `draft`. Для черновика обязательно только поле `title`.
```json
{
  "title": "Отчёт о выполненной работе",
  "description": "…",
  "type": "report",
  "deadline": "2026-06-20T18:59:00Z",
  "criteria": "…",
  "group_id": "…",
  "student_id": null
}
```
Получатель — **либо** вся группа (`group_id`), **либо** один студент (`student_id`), но не оба сразу. В черновике оба поля могут быть пустыми. Группа должна быть группой куратора, студент — состоять в такой группе.
**Response** `201 Created` — объект задания. **Ошибки:** `403 forbidden` (чужая группа), `400 invalid_request`.

#### GET /api/v1/assignments/{id}
Карточка задания (модалка «Подробности задания»). Помимо полей задания, возвращается блок `permissions`, по которому фронт показывает или скрывает кнопки:
```json
"permissions": { "can_edit": true, "can_delete": true, "can_publish": true, "can_submit": false }
```
**Ошибки:** `404 assignment_not_found`.

#### PATCH /api/v1/assignments/{id} (CURATOR — автор)
Тело то же, что при создании; передаются только изменённые поля. **Ошибки:** `409 assignment_locked_field`.

#### DELETE /api/v1/assignments/{id} (CURATOR — автор)
Удалить можно только черновик. **Ошибки:** `409 invalid_status_transition`.

#### POST /api/v1/assignments/{id}/publish (CURATOR — автор)
Переход `draft` → `published`. Сервер проверяет, что заполнены `description`, `deadline`, `criteria` и получатель (`group_id` или `student_id`); при незаполненных полях — `400 invalid_request` с перечнем полей в `detail`. Время публикации (`published_at`) ставит сервер.
**Response** `200 OK` — опубликованное задание.

#### GET /api/v1/assignments/{id}/submissions (CURATOR, ADMIN)
Таблица на экране задания у куратора: **все** получатели, включая тех, кто ещё не сдал.

**Query:** `student_state`.
```json
[
  {
    "student": { "id": "…", "full_name": "Мария Орлова" },
    "student_state": "submitted",
    "submission": { "id": "…", "status": "submitted", "submitted_at": "2026-06-15T10:42:00Z", "score": null }
  },
  {
    "student": { "id": "…", "full_name": "Денис Соколов" },
    "student_state": "not_submitted",
    "submission": null
  }
]
```

#### POST /api/v1/assignments/{id}/submissions (STUDENT)
Сдача работы (форма с drag&drop). Тело — `multipart/form-data`, поле `file`. Проверяющим сервер назначает куратора группы студента.

Заголовок `Idempotency-Key: <uuid>` защищает от дублей при повторной отправке формы.
**Response** `201 Created` — объект сдачи (см. раздел 8) со статусом `submitted`.
**Ошибки:** `409 submission_already_exists`, `409 assignment_not_published`, `409 deadline_passed`, `413 file_too_large`, `415 unsupported_file_type`.

---

### 8. Сдачи и проверка

#### GET /api/v1/submissions
- `STUDENT` — свои сдачи.
- `CURATOR` — сдачи, где он проверяющий. Очередь «ждут проверки»: `?status=submitted`.

**Query:** `status`, `assignment_id`, `group_id`, `student_id`, `sort` (`-submitted_at`), `page`, `page_size`.

#### GET /api/v1/submissions/{id}
Подробности сдачи (модалка «Подробности проверки»).
```json
{
  "id": "…",
  "assignment": { "id": "…", "title": "Отчёт", "type": "report", "deadline": "2026-06-20T18:59:00Z" },
  "student": { "id": "…", "full_name": "Иванов Иван Иванович" },
  "curator": { "id": "…", "full_name": "Анна Петрова" },
  "status": "graded",
  "submitted_at": "2026-06-15T10:42:00Z",
  "file": {
    "original_name": "Отчёт.pdf",
    "mime_type": "application/pdf",
    "size_bytes": 1048576,
    "download_url": "/api/v1/submissions/{id}/file"
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

#### GET /api/v1/submissions/{id}/file
Скачивание файла (автор сдачи, проверяющий куратор, админ). Ответ — бинарный, см. раздел 3.3.

#### POST /api/v1/submissions/{id}/take (CURATOR — проверяющий)
Взять сдачу на проверку: `submitted` → `under_review`. Просмотр сдачи (GET) статус не меняет. Повторный вызов возвращает `200` без изменений.

#### PUT /api/v1/submissions/{id}/review (CURATOR — проверяющий)
Сохранить результат проверки без публикации: студент его пока не видит. Работает только в статусе `under_review`, сохранённый результат можно перезаписать до публикации. Время проверки (`graded_at`) ставит сервер.
```json
{ "decision": "accepted", "score": 9, "feedback": "Хорошо, добавьте выводы" }
```
- `decision`: `accepted` | `revision_required`;
- при `accepted` поле `score` обязательно: целое число ≥ 0;
- при `revision_required` поле `feedback` обязательно.

#### POST /api/v1/submissions/{id}/review/publish (CURATOR — проверяющий)
Опубликовать результат студенту: `under_review` → `graded` (при `accepted`) или `revision_required`. Время публикации (`result_published_at`) ставит сервер. Можно передать то же тело, что в `PUT /review`, чтобы сохранить и опубликовать одним запросом. Опубликованный результат не меняется.
**Response** `200 OK` — сдача. **Ошибки:** `409 invalid_status_transition`, `400 invalid_request`.

---

### 9. Оценки и ведомость

#### GET /api/v1/grades/my (STUDENT)
Страница «Оценки» студента. Возвращаются только опубликованные результаты.
```json
{
  "summary": { "total_score": 37, "graded_count": 4, "revision_required_count": 1, "assignments_count": 6 },
  "items": [
    {
      "assignment": { "id": "…", "title": "Прототип ЛК", "type": "task" },
      "submission_id": "…",
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

#### GET /api/v1/grades/sheet?group_id={id} (куратор группы, ADMIN)
Ведомость группы: матрица «студенты × задания».
```json
{
  "group": { "id": "…", "name": "Учебная практика 2026" },
  "assignments": [ { "id": "…", "title": "Прототип ЛК" }, { "id": "…", "title": "Отчёт" } ],
  "rows": [
    {
      "student": { "id": "…", "full_name": "Иванов Иван" },
      "cells": [
        { "assignment_id": "…", "assigned": true, "student_state": "graded", "submission_id": "…", "score": 12 },
        { "assignment_id": "…", "assigned": true, "student_state": "under_review", "submission_id": "…", "score": null }
      ],
      "total_score": 12
    }
  ]
}
```
Если `assigned: false`, задание этому студенту не назначено, и в ячейке выводится «Не назначено». В ячейках только опубликованные баллы.

#### GET /api/v1/grades/export (куратор группы, ADMIN)
Выгрузка ведомости в Excel.
**Query:** `group_id`, `format` (`xlsx` | `csv`).
**Response** `200 OK` — файл; `Content-Type: application/vnd.openxmlformats-officedocument.spreadsheetml.sheet` или `text/csv`.

---

### 10. После MVP

В схеме БД MVP для этих функций таблиц нет. Эндпоинты зафиксированы, чтобы заранее заложить UI; детали — когда появятся таблицы.

#### Апелляции
Апелляция — просьба студента пересмотреть опубликованную оценку. Студент подаёт её из карточки сдачи после `graded`, админ разбирает в админ-панели и либо оставляет оценку, либо выставляет новую.
- `POST /api/v1/submissions/{id}/appeals` (STUDENT) — `{ "reason": "Не учтён раздел 3 отчёта" }`.
- `GET /api/v1/appeals`, `GET /api/v1/appeals/{id}` (STUDENT — свои); `GET /api/v1/admin/appeals` (все). Статусы: `submitted` → `under_review` → `accepted` | `rejected`.
- `POST /api/v1/admin/appeals/{id}/resolve` — `{ "decision": "accepted", "new_score": 8, "comment": "Раздел 3 засчитан" }`.

#### Уведомления
- `GET /api/v1/notifications?unread=true` — `{ "unread_count": 3, "items": [ { "id", "type", "title", "text", "entity": { "type", "id" }, "is_read", "created_at" } ] }`. Типы: `assignment_published`, `result_published`, `deadline_soon`.
- `POST /api/v1/notifications/read` — `{ "ids": ["…", "…"] }` или `{ "all": true }`.

#### Журнал действий (админ-панель)
- `GET /api/v1/admin/audit-logs?action=&actor_id=&from=&to=` — создание и изменение заданий, публикация результатов, смена ролей, вход. Элемент: `{ "id", "action", "actor": { "id", "full_name" }, "entity": { "type", "id" }, "changes", "created_at" }`.

---

### 11. Сводная таблица эндпоинтов

Все пути указаны относительно `/api/v1`.

| Метод | Путь | Роли | Описание | Приоритет |
|---|---|---|---|---|
| POST | /auth/login | все | Вход | MVP |
| GET | /auth/me | все | Текущий пользователь | MVP |
| GET | /dashboard | STUDENT, CURATOR | Главный экран по роли | MVP |
| GET | /groups, /groups/{id} | все | Список и карточка групп | MVP |
| GET | /groups/{id}/students | CURATOR | Состав группы | MVP |
| GET, POST | /assignments | все / CURATOR | Список заданий, создание черновика | MVP |
| GET, PATCH, DELETE | /assignments/{id} | все / CURATOR | Карточка, правка, удаление черновика | MVP |
| POST | /assignments/{id}/publish | CURATOR | Публикация задания | MVP |
| GET | /assignments/{id}/submissions | CURATOR | Все получатели задания и их сдачи | MVP |
| POST | /assignments/{id}/submissions | STUDENT | Сдача работы (файл) | MVP |
| GET | /submissions | STUDENT, CURATOR | Список сдач, очередь проверки | MVP |
| GET | /submissions/{id} | все | Подробности сдачи и результата | MVP |
| GET | /submissions/{id}/file | все | Скачивание файла сдачи | MVP |
| POST | /submissions/{id}/take | CURATOR | Взять сдачу на проверку | MVP |
| PUT | /submissions/{id}/review | CURATOR | Сохранить результат без публикации | MVP |
| POST | /submissions/{id}/review/publish | CURATOR | Опубликовать результат студенту | MVP |
| GET | /grades/my | STUDENT | Мои оценки и общий балл | MVP |
| GET | /grades/sheet | CURATOR, ADMIN | Ведомость «студенты × задания» | MVP |
| GET | /grades/export | CURATOR, ADMIN | Выгрузка ведомости в Excel/CSV | Позже |
| GET | /admin/dashboard | ADMIN | Главный экран админ-панели | MVP |
| GET, POST | /admin/users | ADMIN | Список и создание пользователей | MVP |
| GET, PATCH | /admin/users/{id} | ADMIN | Карточка, правка, блокировка | MVP |
| POST | /admin/users/{id}/reset-password | ADMIN | Сброс пароля | MVP |
| POST | /admin/groups | ADMIN | Создание группы | MVP |
| PATCH, DELETE | /admin/groups/{id} | ADMIN | Правка и удаление группы | MVP |
| POST | /submissions/{id}/appeals | STUDENT | Подача апелляции | Позже |
| GET | /appeals, /appeals/{id} | STUDENT | Свои апелляции | Позже |
| GET | /admin/appeals | ADMIN | Все апелляции | Позже |
| POST | /admin/appeals/{id}/resolve | ADMIN | Решение по апелляции | Позже |
| GET | /notifications | все | Список уведомлений | Позже |
| POST | /notifications/read | все | Отметить прочитанными | Позже |
| GET | /admin/audit-logs | ADMIN | Журнал действий | Позже |
