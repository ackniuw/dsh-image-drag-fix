#!/usr/bin/env python3
"""
img2png — 把任意图片转成 PNG，让 DSH 附件通道能收。

为什么需要它：
  DSH 只接收 image/png、image/jpeg、image/gif、image/webp 四种。
  bmp / tiff / heic / heif / avif / jfif / 无后缀魔数不符的图，会在上传口被拒。

用法：
  python img2png.py <文件或目录> [输出目录]
  不给输出目录时，落在 <脚本所在目录>/../artifacts/inbox_png/

特性：
  - 不缩放、不改变像素尺寸（像素画的铁律：整数像素，禁止重采样）
  - 保留透明通道
  - Pillow 认不出的格式，自动用 ffmpeg 兜底
  - 同名目标已存在时自动加 _1 _2 后缀，不覆盖
"""
import os
import sys
import subprocess
import shutil

try:
    from PIL import Image
except ImportError:
    print("ERROR: 缺 Pillow。装：python -m pip install pillow", file=sys.stderr)
    sys.exit(2)

SUPPORTED_BY_DSH = {".png", ".jpg", ".jpeg", ".gif", ".webp"}
RASTER_EXT = {
    ".png", ".jpg", ".jpeg", ".jpe", ".jfif", ".gif", ".webp", ".bmp", ".dib",
    ".tif", ".tiff", ".heic", ".heif", ".avif", ".ico", ".tga", ".ppm", ".pgm",
}


def unique_path(path):
    if not os.path.exists(path):
        return path
    stem, ext = os.path.splitext(path)
    i = 1
    while True:
        cand = f"{stem}_{i}{ext}"
        if not os.path.exists(cand):
            return cand
        i += 1


def convert_one(src, outdir):
    base = os.path.splitext(os.path.basename(src))[0]
    dst = unique_path(os.path.join(outdir, base + ".png"))

    # 1) Pillow 直读
    try:
        with Image.open(src) as im:
            im.load()
            has_alpha = im.mode in ("RGBA", "LA") or (
                im.mode == "P" and "transparency" in im.info
            )
            out = im.convert("RGBA" if has_alpha else "RGB")
            out.save(dst, "PNG", optimize=False)
            return ("pillow", dst, out.size, im.mode)
    except Exception as e_pil:
        pass

    # 2) ffmpeg 兜底（heic / avif / 少见的封装）
    ff = shutil.which("ffmpeg")
    if ff:
        cmd = [ff, "-y", "-loglevel", "error", "-i", src, "-frames:v", "1", dst]
        r = subprocess.run(cmd, capture_output=True)
        if r.returncode == 0 and os.path.exists(dst):
            with Image.open(dst) as im:
                return ("ffmpeg", dst, im.size, "n/a")

    return ("failed", None, None, str(e_pil))


def main():
    args = [a for a in sys.argv[1:] if a.strip()]
    if not args:
        print(__doc__)
        return 1
    src = args[0]
    here = os.path.dirname(os.path.abspath(__file__))
    outdir = args[1] if len(args) > 1 else os.path.join(here, "..", "artifacts", "inbox_png")
    outdir = os.path.abspath(outdir)
    os.makedirs(outdir, exist_ok=True)

    if os.path.isdir(src):
        files = [
            os.path.join(src, f) for f in sorted(os.listdir(src))
            if os.path.splitext(f)[1].lower() in RASTER_EXT
        ]
    else:
        files = [src]

    if not files:
        print(f"没找到图片：{src}")
        return 1

    ok = fail = 0
    for f in files:
        ext = os.path.splitext(f)[1].lower()
        engine, dst, size, mode = convert_one(f, outdir)
        if dst:
            ok += 1
            skip = "  (本来就是 DSH 支持的格式，转不转都行)" if ext in SUPPORTED_BY_DSH else ""
            print(f"OK  [{engine}] {os.path.basename(f)} -> {dst}  {size[0]}x{size[1]} {mode}{skip}")
        else:
            fail += 1
            print(f"FAIL {os.path.basename(f)}  ({mode})")

    print(f"\n合计 {len(files)} 张：成功 {ok}，失败 {fail}；输出目录 {outdir}")
    return 0 if fail == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
