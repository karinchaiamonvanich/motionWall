# wall — Wallpaper Engine-compatible player สำหรับ macOS

โปรเจกต์ clean-room เพื่อ interoperability: เล่นวอลเปเปอร์ของ Wallpaper Engine บน macOS โดยเขียน parser/renderer ใหม่ทั้งหมดจากการวิเคราะห์ฟอร์แมตไฟล์ — ไม่คัดลอกโค้ดจากโปรเจกต์ใด รองรับเฉพาะไฟล์วอลเปเปอร์ที่ผู้ใช้มีสิทธิ์ใช้งานอยู่แล้ว (subscribe ด้วยตัวเอง หรือสร้างเอง) ไม่มีส่วนใดเกี่ยวกับการเลี่ยง DRM หรือการยืนยันตัวตนของ Steam

**สนใจเฉพาะ format?** เอกสารสเปกใน [`docs/`](docs/) เขียนจากการพิสูจน์ไฟล์จริงและแยก "ยืนยันแล้ว" กับ "สมมติฐาน" ชัดเจน — ใช้อ้างอิงได้แม้จะไม่ใช้โค้ดของเรา

## สถานะ (2026-10-28)

| Milestone | ความคืบหน้า |
|-----------|-------------|
| **M1** — parser CLI + สเปกฟอร์แมต | ✅ เสร็จ — พิสูจน์กับ library จริง 43 ไอเทม: 33/33 .pkg parse สำเร็จ (1,703 entries), .tex record chain byte-exact 387/388 ไฟล์ (1,109 mip blobs) |
| **M2** — video wallpaper | 🔧 โค้ดครบ รอ build/test บน macOS (CI) |
| **M3** — web wallpaper (WKWebView + JS bridge) | ยังไม่เริ่ม |
| **M4** — scene renderer พื้นฐาน (Metal) | ยังไม่เริ่ม |
| **M5** — effects, shaders, particles | ยังไม่เริ่ม |
| **M6** — แอปเต็มรูป | ยังไม่เริ่ม |

รายละเอียดเกณฑ์ผ่านทั้งหมด: [docs/roadmap.md](docs/roadmap.md)

## สิ่งที่รองรับตอนนี้

- แตก/ตรวจสอบไฟล์ `.pkg` และ `.tex` ของ Wallpaper Engine รุ่นปัจจุบัน (`PKGV0022`, `TEXV0005`)
- เล่นวิดีโอวอลเปเปอร์เต็มหน้าจอเดสก์ท็อป ข้ามจอ วนลูปเนียน (AVPlayerLooper) ทำงานอยู่ใต้ไอคอนเดสก์ท็อป ข้าม Space ได้ หยุดเมื่อถูกบัง/เครื่องหลับ
- สแกนโฟลเดอร์ library แบบไม่ต้องมี Steam บนเครื่อง (ชี้ไปที่ `steamapps/workshop/content/431960` หรือโฟลเดอร์ไหนก็ได้ที่มี `project.json` ข้างใน)

## โครงสร้างโปรเจกต์

```
Sources/
  WPEParser/          library — ฟอร์แมต parser (ไม่พึ่ง dependency ภายนอก)
    BinaryReader.swift      little-endian reader (มี peekBytes)
    PkgArchive.swift        คอนเทนเนอร์ .pkg (ตารางไฟล์ + extract, กัน zip-slip)
    TexFile.swift           เท็กซ์เจอร์ .tex (TEXI / TEXB0003·0004 / mip continuation / TEXS)
    LZ4.swift               LZ4 block decompressor เขียนจาก format spec สาธารณะ (มี output cap)
    ProjectJSON.swift       manifest ของวอลเปเปอร์ (general.properties)
  WPERenderer/        backend ต่อประเภทวอลเปเปอร์
    WallpaperEngine.swift       protocol กลาง + UnsupportedWallpaperError
    VideoWallpaperEngine.swift  AVQueuePlayer + AVPlayerLooper + AVPlayerLayer
  WPELibrary/         สแกนโฟลเดอร์ library หา project.json
  wpe-inspect/        CLI สำรวจ/ตรวจสอบไฟล์
  WPEApp/             executable `wallpaper-mac` — status bar app (AppKit)
    DesktopWallpaperWindow.swift  borderless window ระดับ desktop ต่อจอ
    WallpaperDirector.swift       จัดการ window/engine ต่อจอ + lifecycle
    AppDelegate.swift             เมนู status bar, เลือก library, mute, quit
Tests/
  WPEParserTests/     unit tests พร้อม byte fixtures ที่สร้างเอง (+ security cases)
  WPERendererTests/   tests การสแกน library
docs/                 สเปกฟอร์แมต + roadmap + compliance + security audit
```

## Build (macOS 13+, Swift 5.9+ / Xcode 15+)

```sh
swift build          # คอมไพล์ทุก target
swift test           # unit tests (parser + library scan)
swift run wpe-inspect        # CLI
swift run wallpaper-mac      # แอปเล่นวอลเปเปอร์
```

รองรับทั้ง Apple Silicon และ Intel — CI รันทั้งสองสถาปัตยกรรม (`.github/workflows/ci.yml`)

## การใช้งาน

### แอป (M2)

```sh
swift run wallpaper-mac
```

จะมีไอคอนใน status bar:

1. **Choose Library Folder…** — ชี้ไปที่โฟลเดอร์แม่ที่มีโฟลเดอร์วอลเปเปอร์อยู่ข้างใน (เช่น `steamapps/workshop/content/431960`)
2. เลือกวิดีโอจากรายการ — เล่นทันทีเป็นวอลเปเปอร์ (mute ไว้ตามค่าเริ่มต้น)
3. **Muted** — toggle เสียง
4. **Stop Wallpaper** — หยุดและปิดหน้าต่างวอลเปเปอร์

แอปจำ library path, วอลเปเปอร์ที่เลือกไว้ และสถานะ mute — เปิดครั้งถัดไปเล่นต่ออัตโนมัติ ปิดโปรแกรมด้วย Quit

### CLI

```sh
# รายชื่อไฟล์ใน .pkg ของวอลเปเปอร์
swift run wpe-inspect pkg path/to/123456789.pkg --list

# แตกไฟล์ออกมา (ปฏิเสธ path แบบ path-traversal อัตโนมัติ)
swift run wpe-inspect pkg path/to/123456789.pkg --extract out/

# อ่าน header .tex (พิมพ์ format/ขนาด/LZ4 พร้อม hexdump เทียบ)
swift run wpe-inspect tex path/to/image.tex --json

# อ่าน manifest ของวอลเปเปอร์
swift run wpe-inspect project path/to/wallpaper-folder/
```

## เอกสารสเปกฟอร์แมต

| ไฟล์ | เนื้อหา | สถานะ |
|------|---------|-------|
| [spec-pkg.md](docs/spec-pkg.md) | คอนเทนเนอร์ `.pkg` (PKGV0022, entry table, data blob) | ยืนยันครบ |
| [spec-tex.md](docs/spec-tex.md) | เท็กซ์เจอร์ `.tex` (TEXV0005 records, pixel format enum, LZ4) | ยืนยัน 387/388 ไฟล์ |
| [spec-project-json.md](docs/spec-project-json.md) | manifest (`general.properties`, property types) | ยืนยันหลัก |
| [spec-scene-json.md](docs/spec-scene-json.md) | โครง scene.json (camera, objects, effects) | กรอบเบื้องต้น — ลงลึกตอน M4 |
| [spec-effects-shaders.md](docs/spec-effects-shaders.md) | GLSL ฝังใน pkg, COMBO preprocessor | กรอบเบื้องต้น — ตัดสินใจสถาปัตยกรรม shader ตอน M4 |
| [roadmap.md](docs/roadmap.md) | milestones และเกณฑ์ผ่าน | — |
| [license-compliance.md](docs/license-compliance.md) | การปฏิบัติตาม license ของทุกแหล่งอ้างอิง | ตรวจ 2026-10-28 |
| [security-audit.md](docs/security-audit.md) | ผลตรวจช่องโหว่ + การแก้ | ตรวจ 2026-10-28 |

เอกสารทุกฉบับแยก "ยืนยันแล้ว" (มีหลักฐานจากไฟล์จริง) กับ "สมมติฐาน" (ยังพิสูจน์ไม่จบ) — ข้อความที่เป็นสมมติฐานจะถูกพิสูจน์ด้วยเครื่องมือสำรวจก่อนยกระดับเป็นข้อยืนยัน ไม่เดาเอง

## License และการอ้างอิง

- โค้ดทั้งหมดเผยแพร่ภายใต้ [MIT License](LICENSE) — เขียนใหม่ทั้งหมด (clean-room) ไม่มีโค้ดจาก Wallpaper Engine หรือโปรเจกต์อื่น
- แหล่งอ้างอิง (ข้อเท็จจริงของฟอร์แมตเท่านั้น): [RePKG](https://github.com/notscuffed/repkg) (MIT), [linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) (GPL-3.0 — ใช้เป็นข้อมูลพฤติกรรมเท่านั้น, ห้ามคัดลอกโค้ด), LZ4 block format spec สาธารณะ
- รายละเอียดข้อผูกพันทีละตัว: [docs/license-compliance.md](docs/license-compliance.md)
- โปรเจกต์นี้ไม่มีความเกี่ยวข้องกับผู้พัฒนา Wallpaper Engine — เครื่องหมายการค้าเป็นของเจ้าของเดิม

## ความปลอดภัย

parser ถูกออกแบบให้ประมวลผลไฟล์จาก internet (workshop) ซึ่งถือเป็น untrusted input: ตรวจ bounds ทุกการอ่าน, จำกัดขนาด allocation, กัน path traversal ตอน extract — รายละเอียดผล audit: [docs/security-audit.md](docs/security-audit.md)

พบช่องโหว่? เปิด issue เลย — สำหรับ repo แบบนี้ความเสี่ยงต่ำ (อ่านไฟล์ที่ผู้ใช้เลือกเอง) แต่เราแก้เร็วอยู่แล้ว
