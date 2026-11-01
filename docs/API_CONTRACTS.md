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