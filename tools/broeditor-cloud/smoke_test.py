"""工坊冒烟测试：上传 -> 列表 / 搜索 -> 下载 -> 缩略图 -> 修改 -> 错误令牌失败 -> 删除。
用法：python mods/tools/broeditor-cloud/smoke_test.py [base_url]
"""
import base64
import json
import sys
import urllib.error
import urllib.request

BASE = sys.argv[1] if len(sys.argv) > 1 else "https://broeditor-6myuzuteg3xe5jtk.mojimoon.top"
# 1x1 PNG
PNG = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")


def call(method, path, body=None, headers=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method, headers={"content-type": "application/json", "user-agent": "BroEditor-smoke", **(headers or {})})
    try:
        with urllib.request.urlopen(req) as r:
            return r.status, r.read()
    except urllib.error.HTTPError as e:
        return e.code, e.read()


st, raw = call("POST", "/packs", {"title": "smoke test", "desc": "d", "author": "t", "kinds": ["weapon", "bogus"], "contents": "Smoke Crossbow", "n": 1, "code": "BEA:zabc", "thumb": base64.b64encode(PNG).decode()})
assert st == 200, (st, raw)
up = json.loads(raw)
pid = up["id"]
try:
    st, raw = call("GET", "/packs?kind=weapon&q=Smoke")
    lst = json.loads(raw)
    hit = [p for p in lst["packs"] if p["id"] == pid]
    assert st == 200 and hit and hit[0]["kinds"] == "weapon" and hit[0]["thumb"] == 1, lst
    assert not [p for p in json.loads(call("GET", "/packs?kind=item&q=Smoke")[1])["packs"] if p["id"] == pid], "kind filter"
    assert [p for p in json.loads(call("GET", "/packs?q=" + pid)[1])["packs"] if p["id"] == pid], "search by id"
    assert [p["id"] for p in json.loads(call("GET", "/packs?ids=" + pid + ",bogus")[1])["packs"]] == [pid], "lookup by ids"
    assert call("GET", "/packs/" + pid + "?peek") == (200, b"BEA:zabc")
    assert json.loads(call("GET", "/packs?q=" + pid)[1])["packs"][0]["downloads"] == 0, "peek not counted"
    assert call("GET", "/packs/" + pid) == (200, b"BEA:zabc")
    assert call("GET", "/packs/" + pid + "/thumb") == (200, PNG)
    assert call("POST", "/packs", {"title": "x", "code": "nope"})[0] == 400
    assert call("DELETE", "/packs/" + pid, headers={"x-token": "wrong"})[0] == 403
    assert call("PUT", "/packs/" + pid, {"title": "x"}, headers={"x-token": "wrong"})[0] == 403
    assert call("PUT", "/packs/" + pid, {"title": " "}, headers={"x-token": up["token"]})[0] == 400
    st, raw = call("PUT", "/packs/" + pid, {"title": "smoke edited", "desc": "d2", "thumb": ""}, headers={"x-token": up["token"]})
    assert st == 200, (st, raw)
    p = json.loads(call("GET", "/packs?q=" + pid)[1])["packs"][0]
    assert (p["title"], p["desc"], p["contents"], p["thumb"]) == ("smoke edited", "d2", "Smoke Crossbow", 0) and p["updated"] >= p["created"], p
    assert call("GET", "/packs/" + pid + "/thumb")[0] == 404
    st, raw = call("PUT", "/packs/" + pid, {"code": "BEA:zdef", "kinds": ["item"], "contents": "Smoke Item", "n": 2}, headers={"x-token": up["token"]})
    assert st == 200, (st, raw)
    assert call("GET", "/packs/" + pid + "?peek") == (200, b"BEA:zdef")
    p = json.loads(call("GET", "/packs?q=" + pid)[1])["packs"][0]
    assert (p["kinds"], p["contents"], p["n"], p["title"]) == ("item", "Smoke Item", 2, "smoke edited"), p
finally:
    st, raw = call("DELETE", "/packs/" + pid, headers={"x-token": up["token"]})
assert st == 200, (st, raw)
assert call("GET", "/packs/" + pid)[0] == 404
print("smoke ok")
