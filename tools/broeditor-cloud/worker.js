// BroEditor 分享站 API（游戏内"上传 / 下载"界面使用）
//   GET    /packs?kind=&q=&sort=new|hot&offset=&ids=   列表（每页 PAGE 条，more = 还有下一页；q 也匹配完整 id；ids = 逗号分隔的 id）
//   GET    /packs/<id>[?peek]                     分享码正文（不带 peek 时下载数 +1）
//   GET    /packs/<id>/thumb                      缩略图 PNG
//   POST   /packs   {title, desc, author, kinds, contents, n, mod_ver, code, thumb(base64 PNG)} -> {id, token}
//   PUT    /packs/<id>   X-Token；正文字段同 POST，都可省略（省略 = 不变；code 与 kinds / contents / n 一起改；thumb: "" = 删除缩略图）
//   DELETE /packs/<id>   X-Token: 上传时返回的 token 或 ADMIN_KEY
// 每个 IP 每天：创建 LIMIT.create 次、修改 LIMIT.edit 次（记在 hits 表，删除包不返还）
const KINDS = ["character", "item", "weapon"];
const MAX = { title: 60, desc: 500, author: 40, contents: 2000, mod_ver: 20, code: 512 * 1024, thumb: 300 * 1024, body: 1024 * 1024 };
const LIMIT = { create: 5, edit: 20 };
const PAGE = 30;
const ID_RE = "[a-z2-9]{10}";
const ALPHABET = "abcdefghijkmnpqrstuvwxyz23456789";

const json = (o, status = 200) =>
	new Response(JSON.stringify(o), { status, headers: { "content-type": "application/json; charset=utf-8" } });

async function sha(s) {
	const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
	return [...new Uint8Array(b)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

const randomId = (n) => [...crypto.getRandomValues(new Uint8Array(n))].map((x) => ALPHABET[x % 32]).join("");
const str = (v, n) => (typeof v === "string" ? v.trim().slice(0, n) : "");

export default {
	async fetch(req, env) {
		try {
			return await route(req, env);
		} catch (e) {
			console.error(e);
			return json({ error: "server" }, 500);
		}
	},
};

async function route(req, env) {
	const url = new URL(req.url);
	const m = url.pathname.match(new RegExp(`^/packs(?:/(${ID_RE}))?(/thumb)?/?$`));
	if (!m || (m[2] && !m[1])) return json({ error: "not_found" }, 404);
	const [, id, thumb] = m;
	if (!id) {
		if (req.method === "GET") return list(url, env);
		if (req.method === "POST") return upload(req, env);
	} else if (req.method === "GET") {
		const obj = await env.BUCKET.get(`${thumb ? "thumbs" : "packs"}/${id}`);
		if (!obj) return json({ error: "not_found" }, 404);
		if (!thumb && !url.searchParams.has("peek")) await env.DB.prepare("UPDATE packs SET downloads = downloads + 1 WHERE id = ?").bind(id).run();
		return new Response(obj.body, {
			headers: thumb
				? { "content-type": "image/png", "cache-control": "public, max-age=86400" }
				: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
		});
	} else if (req.method === "PUT" && !thumb) {
		return edit(req, env, id);
	} else if (req.method === "DELETE" && !thumb) {
		return remove(req, env, id);
	}
	return json({ error: "method" }, 405);
}

async function list(url, env) {
	const p = url.searchParams;
	const where = [];
	const args = [];
	if (KINDS.includes(p.get("kind"))) {
		where.push("(',' || kinds || ',') LIKE ?");
		args.push(`%,${p.get("kind")},%`);
	}
	// ids=a,b,c：按 id 取（已下载的包检查更新）
	const ids = (p.get("ids") || "").split(",").filter((x) => new RegExp(`^${ID_RE}$`).test(x)).slice(0, 100);
	if (ids.length) {
		where.push(`id IN (${ids.map(() => "?").join(",")})`);
		args.push(...ids);
	}
	const q = str(p.get("q"), 60);
	if (q) {
		const like = `%${q.replace(/[\\%_]/g, "\\$&")}%`;
		where.push("(id = ? OR " + ["title", "descr", "author", "contents"].map((c) => `${c} LIKE ? ESCAPE '\\'`).join(" OR ") + ")");
		args.push(q.toLowerCase(), like, like, like, like);
	}
	const order = p.get("sort") === "hot" ? "downloads DESC, created DESC" : "created DESC";
	const offset = Math.max(0, parseInt(p.get("offset")) || 0);
	const sql =
		"SELECT id, title, descr AS desc, author, kinds, contents, n, thumb, mod_ver, created, updated, downloads FROM packs" +
		(where.length ? " WHERE " + where.join(" AND ") : "") +
		` ORDER BY ${order} LIMIT ${Math.max(PAGE, ids.length) + 1} OFFSET ${offset}`;
	const { results } = await env.DB.prepare(sql).bind(...args).all();
	const n = Math.max(PAGE, ids.length);
	return json({ packs: results.slice(0, n), more: results.length > n });
}

// IP 只存加盐哈希；超出当天限额返回 false，否则记一次
async function hit(req, env, act) {
	const ip = await sha((req.headers.get("cf-connecting-ip") || "") + (env.ADMIN_KEY || ""));
	const now = Date.now();
	await env.DB.prepare("DELETE FROM hits WHERE at < ?").bind(now - 86400e3).run();
	const { c } = await env.DB.prepare("SELECT COUNT(*) AS c FROM hits WHERE ip = ? AND act = ?").bind(ip, act).first();
	if (c >= LIMIT[act]) return null;
	await env.DB.prepare("INSERT INTO hits (ip, act, at) VALUES (?, ?, ?)").bind(ip, act, now).run();
	return ip;
}

async function body(req) {
	if ((+req.headers.get("content-length") || 0) > MAX.body) return { err: json({ error: "too_large" }, 413) };
	try {
		const b = await req.json();
		return b && typeof b === "object" ? { b } : { err: json({ error: "bad_json" }, 400) };
	} catch {
		return { err: json({ error: "bad_json" }, 400) };
	}
}

const badCode = (code) => !/^BE[A-Z0-9]*:/.test(code) || code.length > MAX.code;
const kindsOf = (b) => KINDS.filter((k) => Array.isArray(b.kinds) && b.kinds.includes(k)).join(",");

// base64 PNG -> 字节；格式不对返回 false
function png(t) {
	let bytes;
	try {
		bytes = Uint8Array.from(atob(t), (ch) => ch.charCodeAt(0));
	} catch {
		return false;
	}
	const magic = [0x89, 0x50, 0x4e, 0x47];
	return bytes.length <= MAX.thumb && magic.every((x, i) => bytes[i] === x) ? bytes : false;
}

async function upload(req, env) {
	const { b, err } = await body(req);
	if (err) return err;
	const title = str(b.title, MAX.title);
	if (!title) return json({ error: "no_title" }, 400);
	const code = typeof b.code === "string" ? b.code.trim() : "";
	if (badCode(code)) return json({ error: "bad_code" }, 400);
	const thumb = b.thumb ? png(b.thumb) : null;
	if (thumb === false) return json({ error: "bad_thumb" }, 400);
	const ip = await hit(req, env, "create");
	if (!ip) return json({ error: "rate_limited" }, 429);
	const id = randomId(10);
	const token = randomId(24);
	const now = Date.now();
	await env.BUCKET.put(`packs/${id}`, code);
	if (thumb) await env.BUCKET.put(`thumbs/${id}`, thumb);
	await env.DB.prepare(
		"INSERT INTO packs (id, title, descr, author, kinds, contents, n, thumb, mod_ver, created, updated, token, ip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
	)
		.bind(id, title, str(b.desc, MAX.desc), str(b.author, MAX.author), kindsOf(b), str(b.contents, MAX.contents),
			Math.max(0, parseInt(b.n) || 0), thumb ? 1 : 0, str(b.mod_ver, MAX.mod_ver), now, now, await sha(token), ip)
		.run();
	return json({ id, token });
}

async function owned(req, env, id) {
	const row = await env.DB.prepare("SELECT token FROM packs WHERE id = ?").bind(id).first();
	if (!row) return json({ error: "not_found" }, 404);
	const t = req.headers.get("x-token") || "";
	if (!t || (t !== env.ADMIN_KEY && (await sha(t)) !== row.token)) return json({ error: "forbidden" }, 403);
	return null;
}

async function edit(req, env, id) {
	const denied = await owned(req, env, id);
	if (denied) return denied;
	const { b, err } = await body(req);
	if (err) return err;
	const set = {};
	if ("title" in b) {
		set.title = str(b.title, MAX.title);
		if (!set.title) return json({ error: "no_title" }, 400);
	}
	if ("desc" in b) set.descr = str(b.desc, MAX.desc);
	if ("author" in b) set.author = str(b.author, MAX.author);
	if ("mod_ver" in b) set.mod_ver = str(b.mod_ver, MAX.mod_ver);
	const code = typeof b.code === "string" ? b.code.trim() : null;
	if (code !== null) {
		if (badCode(code)) return json({ error: "bad_code" }, 400);
		set.kinds = kindsOf(b);
		set.contents = str(b.contents, MAX.contents);
		set.n = Math.max(0, parseInt(b.n) || 0);
	}
	let thumb = null;
	if ("thumb" in b) {
		thumb = b.thumb ? png(b.thumb) : "";
		if (thumb === false) return json({ error: "bad_thumb" }, 400);
		set.thumb = thumb ? 1 : 0;
	}
	if (!(await hit(req, env, "edit"))) return json({ error: "rate_limited" }, 429);
	if (code !== null) await env.BUCKET.put(`packs/${id}`, code);
	if (thumb) await env.BUCKET.put(`thumbs/${id}`, thumb);
	else if (thumb === "") await env.BUCKET.delete(`thumbs/${id}`);
	set.updated = Date.now();
	const cols = Object.keys(set);
	await env.DB.prepare(`UPDATE packs SET ${cols.map((c) => c + " = ?").join(", ")} WHERE id = ?`).bind(...cols.map((c) => set[c]), id).run();
	return json({ ok: true, updated: set.updated });
}

async function remove(req, env, id) {
	const denied = await owned(req, env, id);
	if (denied) return denied;
	await env.BUCKET.delete([`packs/${id}`, `thumbs/${id}`]);
	await env.DB.prepare("DELETE FROM packs WHERE id = ?").bind(id).run();
	return json({ ok: true });
}
