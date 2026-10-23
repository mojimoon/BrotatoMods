-- 分享包索引；分享码在 R2 packs/<id>，缩略图在 R2 thumbs/<id>
CREATE TABLE IF NOT EXISTS packs (
	id TEXT PRIMARY KEY,
	title TEXT NOT NULL,
	descr TEXT NOT NULL DEFAULT '',
	author TEXT NOT NULL DEFAULT '',
	kinds TEXT NOT NULL DEFAULT '',		-- 逗号分隔：character,item,weapon
	contents TEXT NOT NULL DEFAULT '',	-- 包内对象名称（显示 / 搜索用）
	n INTEGER NOT NULL DEFAULT 0,
	thumb INTEGER NOT NULL DEFAULT 0,
	mod_ver TEXT NOT NULL DEFAULT '',
	created INTEGER NOT NULL,
	updated INTEGER NOT NULL DEFAULT 0,	-- 最后修改时间（创建时 = created）
	downloads INTEGER NOT NULL DEFAULT 0,
	token TEXT NOT NULL,			-- sha256(删除令牌)
	ip TEXT NOT NULL			-- sha256(IP + 盐)，创建者
);
CREATE INDEX IF NOT EXISTS packs_created ON packs (created);
CREATE INDEX IF NOT EXISTS packs_hot ON packs (downloads, created);
CREATE INDEX IF NOT EXISTS packs_ip ON packs (ip, created);
-- 限流记录（创建 / 修改），只保留 24 小时
CREATE TABLE IF NOT EXISTS hits (ip TEXT NOT NULL, act TEXT NOT NULL, at INTEGER NOT NULL);
CREATE INDEX IF NOT EXISTS hits_ip ON hits (ip, act, at);
-- 旧库加列（只需执行一次）：ALTER TABLE packs ADD COLUMN updated INTEGER NOT NULL DEFAULT 0;
