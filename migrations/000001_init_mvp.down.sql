-- Откат начальной схемы MVP: удаляет 4 таблицы со всеми данными и файлами.
-- Для рабочей БД перед откатом нужна резервная копия.
-- Без CASCADE: внешние зависимости останавливают откат целиком.

BEGIN;
SET LOCAL search_path = pg_catalog, public;

DROP TABLE public.submissions;
DROP TABLE public.assignments;
ALTER TABLE public.users DROP CONSTRAINT users_group_fk;
DROP TABLE public.groups;
DROP TABLE public.users;

COMMIT;
