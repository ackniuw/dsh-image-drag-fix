# DSH 拖图被拒：根因与修复

> 适用：DeepSeek Harness Desktop 0.2.1（Windows）
> 症状：从 QQ / 微信 / 部分截图工具把图片拖进输入框，提示「仅支持 PNG、JPG、WebP、GIF 格式的图片」；但截图、另存为后再传就正常。

## 一句话根因

**不是格式不支持，是"浏览器报的类型"和"文件真实字节"不一致。**

- 浏览器按**扩展名**猜 `file.type`。QQ 拖出来的文件常见名实不符——实测 `1795233852895.jpeg` 实际是 `image/webp`。
- 前端只认四种 MIME，不认就抛错。
- 就算放行，宿主还会比对：声明 `jpeg`、字节 `webp` → `IMAGE_TYPE_MISMATCH`，拒。

## 涉及的两个文件

```
dsh/node_modules/@deepseek-ai/dsh-client-ui-conversation/lib/client.js   ← 前端
dsh/node_modules/@deepseek-ai/dsh-attachment-local/lib/index.js         ← 宿主校验（约 306 行）
```

宿主那行：

```js
if (detected.mediaType !== declaredMediaType)
  throw new AttachmentError("Declared image type does not match its bytes.", "IMAGE_TYPE_MISMATCH");
```

## 修法：不要相信 file.type

把 `encodeImage` 改成**无条件**走 canvas 重编码：

```js
async encodeImage(file) {
    try {
        return await encodeImageAsPng(file);   // 解码真实字节 → 重编码 PNG
    } catch {
        return {
            mediaType: imageMediaType(file.type),
            data: await base64ImageOf(file),
            ...file.name === "" ? {} : { name: file.name }
        };
    }
}

async function encodeImageAsPng(file) {        // 注意：模块级函数，别放进类里
    const bitmap = await createImageBitmap(file);
    const canvas = document.createElement("canvas");
    canvas.width = bitmap.width;
    canvas.height = bitmap.height;
    const ctx = canvas.getContext("2d");
    if (ctx === null) throw new Error("conversation: 2d canvas unavailable");
    ctx.drawImage(bitmap, 0, 0);
    if (typeof bitmap.close === "function") bitmap.close();
    const url = canvas.toDataURL("image/png");
    return {
        mediaType: "image/png",
        data: url.slice(url.indexOf(",") + 1),
        ...file.name === "" ? {} : { name: file.name }
    };
}
```

顺带放宽入口判断，让 `image/bmp`、空 MIME 之类也能走图片路径：

```js
function isImageMediaType(value) {
    return value === "" || value === void 0 ||
           value === "application/octet-stream" ||
           typeof value === "string" && value.toLowerCase().startsWith("image/");
}
```

## 操作步骤

### 1. 备份

```powershell
Copy-Item "D:\哈气肥鱼\resources\app.asar" "D:\哈气肥鱼\resources\app.asar.bak" -Force
```

> 路径改成你自己的安装目录，下同。

### 2. 解包

```powershell
npx --yes @electron/asar@3.2.10 extract "D:\哈气肥鱼\resources\app.asar" "D:\tmp\asar-work"
```

### 3. 改 client.js

按上文的代码改两处（`encodeImage` + 新增 `encodeImageAsPng` + `isImageMediaType`）。

建议再加诊断后缀，方便定位（可选）：

```js
case "IMAGE_TYPE_MISMATCH": return t("image.unsupportedType") + " [A]";  // 宿主：类型不符
```

### 4. 语法检查

```powershell
Copy-Item "D:\tmp\asar-work\dsh\node_modules\@deepseek-ai\dsh-client-ui-conversation\lib\client.js" "D:\tmp\check.mjs" -Force
node --check "D:\tmp\check.mjs"
```

### 5. 重打包

**不要用 `asar pack`**：`--unpack-dir` 在 Windows 上匹配不到反斜杠路径，会把本该解包的 243MB 文件塞进 asar（174MB → 417MB）。

用 `repack.py`（本仓库附带）：解析 header 的四个 uint32 → 换一个文件 → 重算所有 offset → 重建。产物大小与原包一致。

```powershell
python repack.py   # 改脚本里的 ASAR / NEWFILE / TARGET / OUT 四个路径
```

### 6. 替换

**必须由外部进程启动脚本**（双击 bat / 任务计划）。原因：从 DSH 内部 `Start-Process` 启动的进程与 DSH 共享 Job Object，杀 DSH 时自己也被连带杀掉。

`kill-and-swap.ps1`（本仓库附带）会：杀进程 → 等文件释放 → 备份 → 替换 → **python 读全文件验证** → 清 Chromium 缓存 → 启动。

### 7. 清缓存

`%APPDATA%\@deepseek-ai\dsh-desktop\` 下删 `Code Cache`、`Cache`、`GPUCache`、`GrShaderCache`、`DawnGraphiteCache`、`DawnWebGPUCache`。

V8 会把旧 JS 的编译结果缓存住，不清的话改了代码也不生效。

## 四个坑（都踩过）

| 坑 | 表现 | 解法 |
|---|---|---|
| Job Object | 脚本杀掉 DSH，自己也没了，日志写到一半断 | 由 bat / 任务计划等外部进程启动 |
| 验证扫错范围 | 好补丁被判失败并回滚 | `client.js` 在 asar 前进 19.5MB 处，必须读全文件搜锚点 |
| unpack-dir 失效 | asar 从 174MB 变 417MB | 用脚本手术，不用 `asar pack` |
| Code Cache | 改了文件、重启了，行为不变 | 清 `Code Cache` 等六个目录 |

## 验证

- [ ] `node --check` 通过
- [ ] 新 asar 含 `encodeImageAsPng`
- [ ] 替换后验证能搜到锚点
- [ ] 拖一张普通 PNG 成功
- [ ] **拖一张"扩展名 jpeg、实际 webp"的图成功**（关键用例）
- [ ] 一次拖多张也成功

## 局限

- **HEIC 不行**：浏览器解不了 HEIC，canvas 也没救。需要服务端转码（`pillow-heif`）。
- **升级会覆盖**：DSH 升级后 `app.asar` 换新，补丁消失，需重打。
- 本方案改的是本地安装目录，不涉及 DSH 源码分发。

## 免责

这是对本地安装文件的修改，用于让合法图片正常进入对话。修改前请备份 `app.asar`，出问题用备份还原。不同 DSH 版本函数名或行号可能变化，请以实际代码为准。
