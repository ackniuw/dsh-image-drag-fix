# repack.py — 在 asar 里原位替换一个文件并重建 header
# 用法：先把下面四个路径改成你自己的，然后 python repack.py
# 依赖：标准库，无第三方包
import struct, json, os, sys
ASAR = r"D:\哈气肥鱼\resources\app.asar"
NEWFILE = r"D:\tmp\asar-work\dsh\node_modules\@deepseek-ai\dsh-client-ui-conversation\lib\client.js"
TARGET = "dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js"
OUT = r"D:\tmp\app-new.asar"

with open(ASAR,"rb") as f:
    a, header_size, payload_size, json_len = struct.unpack("<4I", f.read(16))
    body_text = f.read(json_len).decode("utf-8")
    data_base = 8 + header_size
    tree = json.loads(body_text)
print(f"orig: header={header_size} payload={payload_size} json={json_len} data_base={data_base}")

rows=[]
def walk(node, path):
    for name, meta in node.items():
        cur=(path+"/"+name) if path else name
        if "files" in meta: walk(meta["files"], cur)
        elif meta.get("unpacked"): rows.append((cur,meta,True))
        elif "offset" in meta: rows.append((cur,meta,False))
walk(tree["files"],"")
packed=[r for r in rows if not r[2]]
t=[r for r in rows if r[0].replace("\\","/")==TARGET]
if not t: sys.exit("target not found")
tpath,tmeta,_=t[0]
new_bytes=open(NEWFILE,"rb").read()
print(f"packed={len(packed)} unpacked={len(rows)-len(packed)} old={int(tmeta['size'])} new={len(new_bytes)}")

with open(ASAR,"rb") as f:
    blobs={}
    for path,meta,_ in packed:
        f.seek(data_base+int(meta["offset"])); blobs[path]=f.read(int(meta["size"]))
blobs[tpath]=new_bytes

order=sorted(packed,key=lambda r:int(r[1]["offset"]))
cursor=0; new_off={}
for path,meta,_ in order:
    cursor += (-cursor)%4
    new_off[path]=cursor
    cursor += len(blobs[path])

for path,meta,kind in rows:
    if kind: continue
    if path==tpath: meta["size"]=len(new_bytes)
    meta["offset"]=str(new_off[path])

body=json.dumps(tree,ensure_ascii=False,separators=(",",":")).encode("utf-8")
pad=(-(4+len(body)))%4
payload_size=4+len(body)+pad
header_size=4+payload_size
new_data_base=8+header_size
print(f"new: header={header_size} payload={payload_size} json={len(body)} pad={pad} data_base={new_data_base}")

with open(OUT,"wb") as w:
    w.write(struct.pack("<4I",4,header_size,payload_size,len(body)))
    w.write(body); w.write(b"\x00"*pad)
    written=0
    for path,meta,_ in order:
        off=new_off[path]
        if written<off:
            w.write(b"\x00"*(off-written)); written=off
        w.write(blobs[path]); written+=len(blobs[path])
print(f"OUT {os.path.getsize(OUT)/1024/1024:.1f} MB (orig {os.path.getsize(ASAR)/1024/1024:.1f} MB)")

