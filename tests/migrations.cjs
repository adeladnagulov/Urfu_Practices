// Isolated integration tests. PGLITE_MODULE can point to a temporary installation.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { createHash } = require('node:crypto');
const { PGlite } = require(process.env.PGLITE_MODULE || '@electric-sql/pglite');
const dir = path.resolve(__dirname, '../migrations');
const up = fs.readFileSync(path.join(dir, '000001_init_mvp.up.sql'), 'utf8');
const down = fs.readFileSync(path.join(dir, '000001_init_mvp.down.sql'), 'utf8');
const verify = fs.readFileSync(path.join(dir, 'verify.sql'), 'utf8');
// Extracted from the actual drawio table cells, not from the migration SQL.
const schema = JSON.parse(fs.readFileSync(path.join(__dirname, 'schema.expected.json'), 'utf8').replace(/^\uFEFF/, ''));
const db = new PGlite();
let checks = 0;
function equal(actual, expected, label) { assert.deepEqual(actual, expected, label); checks++; }
async function fails(action, codes, constraint) {
  await assert.rejects(action, error => {
    assert.ok([codes].flat().includes(error.code), `${error.code}: ${error.message}`);
    if (constraint) assert.equal(error.constraint, constraint, error.message);
    return true;
  });
  checks++;
}
async function insert(table, record) {
  const keys = Object.keys(record);
  const result = await db.query(
    `INSERT INTO public.${table} (${keys.join(', ')}) VALUES (${keys.map((_, i) => `$${i + 1}`).join(', ')}) RETURNING id`,
    Object.values(record)
  );
  return result.rows[0].id;
}
async function tables() {
  return (await db.query("SELECT tablename FROM pg_tables WHERE schemaname = 'public' ORDER BY tablename")).rows.map(row => row.tablename);
}
async function main() {
  const diagram = fs.readFileSync(path.join(__dirname, '../schema', schema.source));
  equal(createHash('sha256').update(diagram).digest('hex').toUpperCase(), schema.sha256, 'included diagram matches source manifest');
  await db.exec(up);
  const expectedTables = Object.keys(schema.tables).sort();
  equal(await tables(), expectedTables, 'four MVP tables');
  const columns = (await db.query("SELECT table_name, column_name, data_type, is_nullable, identity_generation FROM information_schema.columns WHERE table_schema = 'public' ORDER BY table_name, ordinal_position")).rows;
  equal(columns.length, 42, '42 fields');
  const typeMap = { int: 'integer', text: 'text', bool: 'boolean', timestamptz: 'timestamp with time zone', date: 'date', bytea: 'bytea', bigint: 'bigint' };
  for (const [table, fields] of Object.entries(schema.tables)) {
    equal(columns.filter(c => c.table_name === table).map(c => ({ name: c.column_name, type: c.data_type, nullable: c.is_nullable === 'YES' })),
      fields.map(c => ({ ...c, type: typeMap[c.type] })), `${table} agrees with drawio`);
  }
  equal(columns.filter(c => c.identity_generation === 'ALWAYS').map(c => `${c.table_name}.${c.column_name}`).sort(), expectedTables.map(t => `${t}.id`), 'four ALWAYS identities');
  const fks = (await db.query("SELECT conname, confdeltype, confupdtype FROM pg_constraint WHERE contype = 'f' AND connamespace = 'public'::regnamespace ORDER BY conname")).rows;
  equal(fks.map(c => c.conname), ['assignments_curator_fk', 'assignments_group_fk', 'assignments_student_fk', 'groups_curator_fk', 'submissions_assignment_fk', 'submissions_curator_fk', 'submissions_student_fk', 'users_group_fk'], 'eight FKs');
  equal(fks.every(c => c.confdeltype === 'r' && c.confupdtype === 'r'), true, 'FK actions RESTRICT');

  const user = { full_name: 'Иван Иванов', login: ' Curator ', email: 'Curator@uni.test ', password_hash: '$argon2id$fixture-only', role: 'curator' };
  const curator = await insert('users', user);
  equal(Number.isInteger(curator) && curator > 0, true, 'database-generated integer identity');
  equal((await db.query('SELECT is_active FROM public.users WHERE id=$1', [curator])).rows[0].is_active, true, 'active by default');
  await fails(() => insert('users', { ...user, id: 1000, login: 'manual', email: 'manual@uni.test' }), '428C9');
  await fails(() => insert('users', { ...user, login: 'cURAtor', email: 'different@uni.test' }), '23505', 'users_login_ci_uq');
  await fails(() => insert('users', { ...user, login: 'different', email: ' curator@UNI.TEST' }), '23505', 'users_email_ci_uq');
  for (const [field, constraint] of [['full_name', 'users_full_name_nonempty'], ['login', 'users_login_nonempty'], ['email', 'users_email_nonempty'], ['password_hash', 'users_password_hash_nonempty']]) {
    await fails(() => insert('users', { ...user, login: 'different', email: 'different@uni.test', [field]: ' ' }), '23514', constraint);
  }
  await fails(() => insert('users', { ...user, login: 'different', email: 'different@uni.test', role: 'teacher' }), '23514', 'users_role_allowed');
  await fails(() => insert('users', { ...user, login: 'different', email: 'different@uni.test', role: 'student' }), '23514', 'users_role_group_consistent');
  const groupRecord = { name: 'Практика', start_date: '2026-11-01', end_date: '2026-12-31', curator_id: curator };
  const group = await insert('groups', groupRecord);
  await fails(() => insert('groups', { ...groupRecord, end_date: '2026-10-31' }), '23514', 'groups_dates_ordered');
  await fails(() => insert('groups', { ...groupRecord, name: '' }), '23514', 'groups_name_nonempty');
  await fails(() => insert('groups', { ...groupRecord, curator_id: -1 }), '23503', 'groups_curator_fk');
  const studentRecord = { ...user, login: 'student', email: 'student@uni.test', role: 'student', group_id: group };
  const student = await insert('users', studentRecord);
  await fails(() => insert('users', { ...studentRecord, login: 'different', email: 'different@uni.test', role: 'admin' }), '23514', 'users_role_group_consistent');
  await fails(() => insert('users', { ...studentRecord, login: 'different', email: 'different@uni.test', group_id: -1 }), '23503', 'users_group_fk');
  for (const whitespace of ['\t', '\r\n', ' \t\r\n ']) {
    await fails(() => insert('users', { ...user, login: 'different', email: 'different@uni.test', full_name: whitespace }), '23514', 'users_full_name_nonempty');
    await fails(() => insert('groups', { ...groupRecord, name: whitespace }), '23514', 'groups_name_nonempty');
  }

  const draft = { curator_id: curator, title: 'Черновик' };
  const draftId = await insert('assignments', draft);
  equal((await db.query('SELECT status, type, description, deadline, criteria, published_at, group_id, student_id FROM public.assignments WHERE id=$1', [draftId])).rows[0],
    { status: 'draft', type: 'task', description: null, deadline: null, criteria: null, published_at: null, group_id: null, student_id: null }, 'incomplete draft');
  await fails(() => insert('assignments', { ...draft, group_id: group, student_id: student }), '23514', 'assignments_at_most_one_recipient');
  const assignmentRecord = { ...draft, description: 'Описание', deadline: '2026-11-30T18:00:00Z', criteria: 'Критерии', status: 'published', created_at: '2026-11-17T09:00:00Z', published_at: '2026-11-17T10:00:00Z', group_id: group };
  const assignment = await insert('assignments', assignmentRecord);
  const personal = await insert('assignments', { ...assignmentRecord, group_id: null, student_id: student, type: 'report' });
  for (const field of ['description', 'deadline', 'criteria', 'published_at', 'group_id']) {
    await fails(() => insert('assignments', { ...assignmentRecord, [field]: null }), '23514', 'assignments_publication_complete');
  }
  for (const field of ['description', 'criteria']) {
    await fails(() => insert('assignments', { ...assignmentRecord, [field]: ' ' }), '23514', 'assignments_publication_complete');
  }
  for (const whitespace of ['\t', '\r\n', ' \t\r\n ']) {
    await fails(() => insert('assignments', { ...draft, title: whitespace }), '23514', 'assignments_title_nonempty');
    for (const field of ['description', 'criteria']) {
      await fails(() => insert('assignments', { ...assignmentRecord, [field]: whitespace }), '23514', 'assignments_publication_complete');
    }
  }
  await db.exec('BEGIN');
  await insert('assignments', { ...assignmentRecord, description: '\nОписание с форматированием\n', criteria: '\tКритерии\r\n' });
  checks++;
  await db.exec('ROLLBACK');
  await fails(() => insert('assignments', { ...assignmentRecord, status: 'draft' }), '23514', 'assignments_publication_complete');
  await fails(() => insert('assignments', { ...assignmentRecord, published_at: '2026-11-17T08:00:00Z' }), '23514', 'assignments_publication_time');
  await fails(() => insert('assignments', { ...draft, title: ' ' }), '23514', 'assignments_title_nonempty');
  await fails(() => insert('assignments', { ...draft, type: 'exam' }), '23514', 'assignments_type_allowed');
  await fails(() => insert('assignments', { ...draft, status: 'archived' }), '23514');
  for (const [field, constraint] of [['curator_id', 'assignments_curator_fk'], ['group_id', 'assignments_group_fk'], ['student_id', 'assignments_student_fk']]) {
    await fails(() => insert('assignments', { ...draft, [field]: -1 }), '23503', constraint);
  }

  const submission = { assignment_id: assignment, student_id: student, submitted_at: '2026-11-18T10:00:00Z', original_name: 'Работа.pdf', file_data: Buffer.from([0, 1, 255]), mime_type: 'application/pdf', size_bytes: 3, curator_id: curator };
  const id = await insert('submissions', submission);
  equal((await db.query('SELECT status, score, feedback, decision, graded_at, result_published_at FROM public.submissions WHERE id=$1', [id])).rows[0],
    { status: 'submitted', score: null, feedback: null, decision: null, graded_at: null, result_published_at: null }, 'submission without a review');
  equal(Array.from((await db.query('SELECT file_data FROM public.submissions WHERE id=$1', [id])).rows[0].file_data), [0, 1, 255], 'bytea preserves binary bytes');
  await fails(() => insert('submissions', submission), '23505', 'submissions_assignment_student_unique');
  const probe = { ...submission, assignment_id: personal };
  for (const field of ['assignment_id', 'student_id', 'curator_id', 'file_data', 'original_name', 'mime_type', 'size_bytes']) {
    await fails(() => insert('submissions', { ...probe, [field]: null }), '23502');
  }
  for (const [field, constraint] of [['assignment_id', 'submissions_assignment_fk'], ['student_id', 'submissions_student_fk'], ['curator_id', 'submissions_curator_fk']]) {
    await fails(() => insert('submissions', { ...probe, [field]: -1 }), '23503', constraint);
  }
  await fails(() => insert('submissions', { ...probe, original_name: ' ' }), '23514', 'submissions_original_name_nonempty');
  await fails(() => insert('submissions', { ...probe, mime_type: ' ' }), '23514', 'submissions_mime_type_nonempty');
  for (const whitespace of ['\t', '\r\n', ' \t\r\n ']) {
    await fails(() => insert('submissions', { ...probe, original_name: whitespace }), '23514', 'submissions_original_name_nonempty');
    await fails(() => insert('submissions', { ...probe, mime_type: whitespace }), '23514', 'submissions_mime_type_nonempty');
  }
  await fails(() => insert('submissions', { ...probe, size_bytes: 2 }), '23514', 'submissions_file_size_matches');
  await fails(() => insert('submissions', { ...probe, file_data: Buffer.alloc(0), size_bytes: 0 }), '23514', 'submissions_file_size_allowed');
  await fails(() => insert('submissions', { ...probe, status: 'missing' }), '23514');

  // Allowed states from the diagram. Exhaust all 256 NULL/non-NULL combinations.
  const allowed = new Set([
    ['submitted', null, false, false, false, false],
    ['under_review', null, false, false, false, false],
    ['under_review', 'accepted', true, false, true, false],
    ['under_review', 'accepted', true, true, true, false],
    ['under_review', 'revision_required', false, true, true, false],
    ['under_review', 'revision_required', true, true, true, false],
    ['graded', 'accepted', true, false, true, true],
    ['graded', 'accepted', true, true, true, true],
    ['revision_required', 'revision_required', false, true, true, true],
    ['revision_required', 'revision_required', true, true, true, true]
  ].map(row => JSON.stringify(row)));
  let acceptedStates = 0;
  for (const status of ['submitted', 'under_review', 'graded', 'revision_required']) {
    for (const decision of [null, 'accepted', 'revision_required', 'invalid']) {
      for (let bits = 0; bits < 16; bits++) {
        const flags = [0, 1, 2, 3].map(bit => Boolean(bits & (1 << bit)));
        const key = JSON.stringify([status, decision, ...flags]);
        await db.exec('BEGIN');
        try {
          let error;
          try {
            await insert('submissions', { ...probe, status, decision, score: flags[0] ? 0 : null, feedback: flags[1] ? 'Комментарий' : null, graded_at: flags[2] ? '2026-11-18T11:00:00Z' : null, result_published_at: flags[3] ? '2026-11-18T12:00:00Z' : null });
          } catch (caught) { error = caught; }
          equal(!error, allowed.has(key), `result state ${key}`);
          if (error) assert.equal(error.code, '23514', error.message);
          else acceptedStates++;
        } finally { await db.exec('ROLLBACK'); }
      }
    }
  }
  equal(acceptedStates, allowed.size, 'all ten valid state shapes accepted');
  const review = { ...probe, status: 'under_review', decision: 'accepted', score: 0, graded_at: '2026-11-18T11:00:00Z' };
  await fails(() => insert('submissions', { ...review, score: -1 }), '23514', 'submissions_score_nonnegative');
  await fails(() => insert('submissions', { ...review, graded_at: '2026-11-18T09:00:00Z' }), '23514', 'submissions_grading_time');
  await fails(() => insert('submissions', { ...review, status: 'graded', result_published_at: '2026-11-18T10:30:00Z' }), '23514', 'submissions_result_publication_time');
  for (const feedback of ['', ' ', '\t', '\r\n', ' \t\r\n ']) {
    await fails(() => insert('submissions', { ...review, decision: 'revision_required', feedback }), '23514', 'submissions_decision_consistent');
  }
  await db.exec('BEGIN');
  await insert('submissions', { ...review, decision: 'revision_required', feedback: '\nИсправить оформление\n' });
  checks++;
  await db.exec('ROLLBACK');

  // Actual bytea values on both sides of the 20 MB boundary; return only ID.
  for (const [bytes, valid] of [[1, true], [20000000, true], [20000001, false]]) {
    await db.exec('BEGIN');
    const action = () => db.query("INSERT INTO public.submissions (assignment_id, student_id, original_name, file_data, mime_type, size_bytes, curator_id) VALUES ($1, $2, 'boundary.pdf', convert_to(repeat('x', $3), 'UTF8'), 'application/pdf', $3, $4) RETURNING id", [personal, student, bytes, curator]);
    try {
      if (valid) { await action(); checks++; }
      else await fails(action, '23514', 'submissions_file_size_allowed');
    } finally { await db.exec('ROLLBACK'); }
  }

  // Real workflow: prepare privately, then publish result and status together.
  await db.query("UPDATE public.submissions SET status='under_review' WHERE id=$1", [id]);
  await db.query("UPDATE public.submissions SET decision='accepted', score=0, graded_at=$1 WHERE id=$2", ['2026-11-18T11:00:00Z', id]);
  equal((await db.query('SELECT status, score, result_published_at FROM public.submissions WHERE id=$1', [id])).rows[0], { status: 'under_review', score: 0, result_published_at: null }, 'prepared zero score is not published');
  await db.query("UPDATE public.submissions SET status='graded', result_published_at=$1 WHERE id=$2", ['2026-11-18T12:00:00Z', id]);
  await fails(() => insert('submissions', submission), '23505', 'submissions_assignment_student_unique');
  const revisionId = await insert('submissions', probe);
  await db.query("UPDATE public.submissions SET status='under_review' WHERE id=$1", [revisionId]);
  await db.query("UPDATE public.submissions SET status='revision_required', decision='revision_required', feedback='Уточнить выводы', graded_at=$1, result_published_at=$2 WHERE id=$3", ['2026-11-18T11:00:00Z', '2026-11-18T12:00:00Z', revisionId]);
  await fails(() => insert('submissions', probe), '23505', 'submissions_assignment_student_unique');
  equal((await db.query('SELECT count(*)::int AS n FROM public.submissions WHERE file_data=$1', [submission.file_data])).rows[0].n, 2, 'identical file bytes allowed in different submissions');
  for (const [table, value] of [['users', curator], ['users', student], ['groups', group], ['assignments', assignment], ['assignments', personal]]) {
    await fails(() => db.query(`DELETE FROM public.${table} WHERE id=$1`, [value]), ['23503', '23001']);
  }
  await db.exec(verify); checks++;
  for (const constraint of ['submissions_file_size_matches', 'submissions_file_size_allowed']) {
    await db.exec('BEGIN');
    await db.exec(`ALTER TABLE public.submissions DROP CONSTRAINT ${constraint}`);
    await fails(() => db.exec(verify), 'P0001');
    await db.exec('ROLLBACK');
  }
  const schemaMutations = [
    'ALTER TABLE public.users ALTER COLUMN full_name DROP NOT NULL',
    'ALTER TABLE public.submissions ALTER COLUMN score TYPE bigint',
    'ALTER TABLE public.users ALTER COLUMN id SET GENERATED BY DEFAULT',
    'ALTER TABLE public.groups DROP CONSTRAINT groups_curator_fk; ALTER TABLE public.groups ADD CONSTRAINT groups_curator_fk FOREIGN KEY (curator_id) REFERENCES public.groups(id) ON UPDATE RESTRICT ON DELETE RESTRICT',
    'DROP INDEX public.users_group_idx; CREATE INDEX users_group_idx ON public.users(email)',
    'ALTER TABLE public.submissions DROP CONSTRAINT submissions_assignment_student_unique',
    'ALTER TABLE public.submissions DROP CONSTRAINT submissions_file_size_matches; ALTER TABLE public.submissions ADD CONSTRAINT submissions_file_size_matches CHECK (size_bytes = octet_length(file_data)) NOT VALID'
  ];
  for (const mutation of schemaMutations) {
    await db.exec('BEGIN');
    await db.exec(mutation);
    await fails(() => db.exec(verify), 'P0001');
    await db.exec('ROLLBACK');
  }
  const defaults = [
    { table: 'users', column: 'is_active', incorrect: 'false' },
    { table: 'users', column: 'created_at', incorrect: "'2000-01-01T00:00:00Z'::timestamptz" },
    { table: 'groups', column: 'description', incorrect: "'Unexpected description'" },
    { table: 'assignments', column: 'type', incorrect: "'report'" },
    { table: 'assignments', column: 'status', incorrect: "'published'" },
    { table: 'assignments', column: 'created_at', incorrect: "'2000-01-01T00:00:00Z'::timestamptz" },
    { table: 'submissions', column: 'status', incorrect: "'under_review'" },
    { table: 'submissions', column: 'submitted_at', incorrect: "'2000-01-01T00:00:00Z'::timestamptz" }
  ];
  for (const { table, column, incorrect } of defaults) {
    for (const change of ['DROP DEFAULT', `SET DEFAULT ${incorrect}`]) {
      await db.exec('BEGIN');
      await db.exec(`ALTER TABLE public.${table} ALTER COLUMN ${column} ${change}`);
      await assert.rejects(() => db.exec(verify), error => {
        assert.equal(error.code, 'P0001');
        assert.ok(error.message.includes('DEFAULT'), error.message);
        assert.ok(error.message.includes(`${table}.${column}`), error.message);
        return true;
      });
      checks++;
      await db.exec('ROLLBACK');
    }
  }
  // Nullable result fields must retain their absent-value semantics.
  await db.exec('BEGIN');
  await db.exec('ALTER TABLE public.submissions ALTER COLUMN score SET DEFAULT 0');
  await fails(() => db.exec(verify), 'P0001');
  await db.exec('ROLLBACK');
  // pg_attrdef also stores generated expressions; these are not DEFAULTs.
  await db.exec('BEGIN');
  await db.exec('ALTER TABLE public.users DROP COLUMN is_active; ALTER TABLE public.users ADD COLUMN is_active boolean GENERATED ALWAYS AS (true) STORED NOT NULL');
  await fails(() => db.exec(verify), 'P0001');
  await db.exec('ROLLBACK');
  await db.exec(verify); checks++;
  await fails(() => db.exec(up), 'P0001');
  await db.exec('ROLLBACK');
  equal((await db.query('SELECT count(*)::int AS n FROM public.submissions')).rows[0].n, 2, 'repeat up preserves data');
  await db.exec('CREATE VIEW public.external_dependency AS SELECT id FROM public.groups');
  await fails(() => db.exec(down), '2BP01');
  await db.exec('ROLLBACK');
  equal(await tables(), expectedTables, 'failed down is atomic');
  equal((await db.query('SELECT count(*)::int AS n FROM public.submissions')).rows[0].n, 2, 'failed down restores submission data');
  equal((await db.query("SELECT count(*)::int AS n FROM pg_constraint WHERE conrelid='public.users'::regclass AND conname='users_group_fk'")).rows[0].n, 1, 'failed down restores users_group_fk');
  await db.exec('DROP VIEW public.external_dependency');
  await db.exec(down);
  equal(await tables(), [], 'down removes all four tables');
  equal((await db.query("SELECT count(*)::int AS n FROM pg_sequences WHERE schemaname='public'")).rows[0].n, 0, 'owned identity sequences removed');
  // A legacy-style six-table UUID database must fail acceptance explicitly.
  for (const table of ['users', 'groups', 'assignments', 'submissions', 'grades', 'submission_files']) {
    await db.exec(`CREATE TABLE public.${table} (id uuid PRIMARY KEY)`);
  }
  await fails(() => db.exec(verify), 'P0001');
  await db.exec('ROLLBACK');
  for (const table of ['users', 'groups', 'assignments', 'submissions', 'grades', 'submission_files']) {
    await db.exec(`DROP TABLE public.${table}`);
  }
  await db.exec('CREATE TABLE public.grades (id integer)');
  await fails(() => db.exec(up), 'P0001');
  await db.exec('ROLLBACK');
  equal(await tables(), ['grades'], 'old scheme conflict does not create partial MVP tables');
  await db.exec('DROP TABLE public.grades');
  await db.exec(up);
  equal(await tables(), expectedTables, 'up works again after down');
  await db.exec(down);
  const engine = (await db.query('SELECT version() AS version')).rows[0].version;
  console.log(JSON.stringify({ result: 'passed', checks, stateCombinations: 256, engine, source: schema.source, sourceSha256: schema.sha256 }, null, 2));
}
main().catch(error => { console.error(error); process.exitCode = 1; }).finally(() => db.close());
