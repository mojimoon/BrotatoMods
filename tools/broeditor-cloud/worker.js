// BroEditor 分享站 API（游戏内"上传 / 下载"界面使用）
//   GET    /packs?kind=&q=&sort=new|hot&offset=   列表（每页 PAGE 条，more = 还有下一页）
//   GET    /packs/<id>                            分享码正文（下载数 +1）
//   GET    /packs/<id>/thumb                      缩略图 PNG
//   POST   /packs   {title, desc, author, kinds, contents, n, mod_ver, code, thumb(base64 PNG)} -> {id, token}
//   DELETE /packs/<id>   X-Token: 上传时返回的 token 或 ADMIN_KEY
const KINDS = ["character", "item", "weapon"];
const MAX = { title: 60, desc: 500, author: 40, contents: 2000, mod_ver: 20, code: 512 * 1024, thumb: 300 * 1024, body: 1024 * 1024 };
const PER_DAY = 20;
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
		if (!thumb) await env.DB.prepare("UPDATE packs SET downloads = downloads + 1 WHERE id = ?").bind(id).run();
		return new Response(obj.body, {
			headers: thumb
				? { "content-type": "image/png", "cache-control": "public, max-age=86400" }
				: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" },
		});
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
	const q = str(p.get("q"), 60);
	if (q) {
		const like = `%${q.replace(/[\\%_]/g, "\\$&")}%`;
		where.push("(" + ["title", "descr", "author", "contents"].map((c) => `${c} LIKE ? ESCAPE '\\'`).join(" OR ") + ")");
		args.push(like, like, like, like);
	}
	const order = p.get("sort") === "hot" ? "downloads DESC, created DESC" : "created DESC";
	const offset = Math.max(0, parseInt(p.get("offset")) || 0);
	const sql =
		"SELECT id, title, descr AS desc, author, kinds, contents, n, thumb, mod_ver, created, downloads FROM packs" +
		(where.length ? " WHERE " + where.join(" AND ") : "") +
		` ORDER BY ${order} LIMIT ${PAGE + 1} OFFSET ${offset}`;
	const { results } = await env.DB.prepare(sql).bind(...args).all();
	return json({ packs: results.slice(0, PAGE), more: results.length > PAGE });
}

async function upload(req, env) {
	if ((+req.headers.get("content-length") || 0) > MAX.body) return json({ error: "too_large" }, 413);
	// IP 只存加盐哈希，用于每日上传限额
	const ip = await sha((req.headers.get("cf-connecting-ip") || "") + (env.ADMIN_KEY || ""));
	const now = Date.now();
	const { c } = await env.DB.prepare("SELECT COUNT(*) AS c FROM packs WHERE ip = ? AND created > ?").bind(ip, now - 86400e3).first();
	if (c >= PER_DAY) return json({ error: "rate_limited" }, 429);
	let b;
	try {
		b = await req.json();
	} catch {
		return json({ error: "bad_json" }, 400);
	}
	const title = str(b.title, MAX.title);
	if (!title) return json({ error: "no_title" }, 400);
	const code = typeof b.code === "string" ? b.code.trim() : "";
	if (!/^BE[A-Z0-9]*:/.test(code) || code.length > MAX.code) return json({ error: "bad_code" }, 400);
	const kinds = KINDS.filter((k) => Array.isArray(b.kinds) && b.kinds.includes(k));
	let png = null;
	if (b.thumb) {
		try {
			png = Uint8Array.from(atob(b.thumb), (ch) => ch.charCodeAt(0));
		} catch {
			return json({ error: "bad_thumb" }, 400);
		}
		const magic = [0x89, 0x50, 0x4e, 0x47];
		if (png.length > MAX.thumb || !magic.every((x, i) => png[i] === x)) return json({ error: "bad_thumb" }, 400);
	}
	const id = randomId(10);
	const token = randomId(24);
	await env.BUCKET.put(`packs/${id}`, code);
	if (png) await env.BUCKET.put(`thumbs/${id}`, png);
	await env.DB.prepare(
		"INSERT INTO packs (id, title, descr, author, kinds, contents, n, thumb, mod_ver, created, token, ip) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
	)
		.bind(id, title, str(b.desc, MAX.desc), str(b.author, MAX.author), kinds.join(","), str(b.contents, MAX.contents),
			Math.max(0, parseInt(b.n) || 0), png ? 1 : 0, str(b.mod_ver, MAX.mod_ver), now, await sha(token), ip)
		.run();
	return json({ id, token });
}

async function remove(req, env, id) {
	const row = await env.DB.prepare("SELECT token FROM packs WHERE id = ?").bind(id).first();
	if (!row) return json({ error: "not_found" }, 404);
	const t = req.headers.get("x-token") || "";
	if (!t || (t !== env.ADMIN_KEY && (await sha(t)) !== row.token)) return json({ error: "forbidden" }, 403);
	await env.BUCKET.delete([`packs/${id}`, `thumbs/${id}`]);
	await env.DB.prepare("DELETE FROM packs WHERE id = ?").bind(id).run();
	return json({ ok: true });
}
