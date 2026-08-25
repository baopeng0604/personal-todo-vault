/**
 * 从 data.json 迁移分类和任务到 todo.db
 */
const fs = require('fs');
const path = require('path');
const initSqlJs = require('./sql-wasm.js');

const DB_FILE = path.join(__dirname, 'todo.db');

async function main() {
  const data = JSON.parse(fs.readFileSync(path.join(__dirname, 'data.json'), 'utf-8'));

  const SQL = await initSqlJs({ locateFile: f => path.join(__dirname, f) });
  const db = new SQL.Database();

  // 建表
  db.run(`CREATE TABLE IF NOT EXISTS categories (
    id TEXT PRIMARY KEY, name TEXT NOT NULL, icon TEXT DEFAULT '📋', sort_order INTEGER DEFAULT 0)`);
  db.run(`CREATE TABLE IF NOT EXISTS todos (
    id TEXT PRIMARY KEY, title TEXT NOT NULL, completed INTEGER DEFAULT 0,
    category_id TEXT, progress INTEGER DEFAULT 0, created_at TEXT NOT NULL,
    reminder_enabled INTEGER DEFAULT 0, reminder_time TEXT DEFAULT '', creator_email TEXT DEFAULT '')`);
  db.run(`CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT)`);

  // 迁移分类
  db.run('DELETE FROM categories');
  for (const cat of data.categories) {
    db.run('INSERT INTO categories (id, name, icon, sort_order) VALUES (?, ?, ?, ?)',
      [cat.id, cat.name, cat.icon, cat.order ?? 0]);
  }
  console.log(`迁移了 ${data.categories.length} 个分类`);

  // 迁移任务
  db.run('DELETE FROM todos');
  for (const todo of data.todos) {
    db.run(`INSERT INTO todos (id, title, completed, category_id, progress, created_at, reminder_enabled, reminder_time, creator_email)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [todo.id, todo.title, todo.completed ? 1 : 0,
       todo.categoryId || 'cat_default', todo.progress || 0,
       todo.createdAt || '', todo.reminderEnabled ? 1 : 0,
       todo.reminderTime || '', todo.creatorEmail || '']);
  }
  console.log(`迁移了 ${data.todos.length} 个任务`);

  // 保存
  const buf = Buffer.from(db.export());
  fs.writeFileSync(DB_FILE, buf);
  console.log('已写入:', DB_FILE);

  // 验证
  const cats = db.exec('SELECT * FROM categories ORDER BY sort_order');
  const [{ values: rows }] = cats;
  console.log('验证分类:', rows.map(r => `${r[2]}(${r[1]})`).join(', '));

  db.close();
}

main().catch(e => { console.error(e); process.exit(1); });