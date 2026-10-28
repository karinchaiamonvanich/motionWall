# Roadmap — Wallpaper Engine-compatible player สำหรับ macOS

หลักการ: clean-room, interoperability เท่านั้น, รองรับเฉพาะไฟล์ที่ผู้ใช้มีสิทธิ์อยู่แล้ว, ทำทีละ milestone พร้อมเกณฑ์ผ่านที่ตรวจสอบได้

## M1 — CLI parser + เอกสารสเปก (ปัจจุบัน)

- [x] Swift Package แยกโมดูล: `WPEParser` (library) + `wpe-inspect` (CLI)
- [x] Parser: `.pkg` (ตาราง + extract — ไม่มี crc32 ในฟอร์แมตจริง), `.tex` (TEXV0005 records + LZ4 payload), `project.json`
- [x] LZ4 block decompressor เขียนเองจาก format spec สาธารณะ
- [x] เอกสารสเปก: spec-pkg / spec-tex / spec-project-json (+ กรอบ scene/effects)
- [x] Unit tests ครอบ parser ทุกตัว (สร้าง byte fixture เอง)

**เกณฑ์ผ่าน:**
1. `swift test` ผลครบทุก test บน macOS 13+ (Apple Silicon และ Intel) — *ค้างรอ (ไม่มี Swift บนเครื่อง Windows ที่เขียนโค้ด)*
2. ~~รันกับ `.pkg`/`.tex` จริง~~ — **ผ่านแล้ว**: 33/33 pkg, 1,703 entries in-bounds + contiguous, record chain ของ .tex เดิน byte-exact **387/388 ไฟล์** (1,109 mip blobs)
3. ~~อัปเดตเอกสาร~~ — **เสร็จแล้ว**: layout .pkg (PKGV0022, offset relative, ไม่มี crc), TEXV0005 (TEXI/TEXB/continuation mips/TEXS), pixel format enum 5 ค่าล็อกด้วย B/px ratio, general.properties — ยืนยันทั้งหมดใน docs/ และ fixtures ใน test สร้างตาม layout จริง

## M2 — Video wallpaper (โค้ดเขียนครบ รอทดสอบบน Mac)

- [x] `WPERenderer`: protocol `WallpaperEngine` + `VideoWallpaperEngine` (`AVQueuePlayer` + `AVPlayerLooper` + `AVPlayerLayer`, resizeAspectFill, mute default)
- [x] `WPELibrary`: `LibraryStore` สแกนโฟลเดอร์หา `project.json` (ไม่ต้องมี Steam), `UnsupportedWallpaperError` สำหรับ type ที่ไม่รองรับ (`application` = Windows-only)
- [x] `WPEApp` (`wallpaper-mac`): `DesktopWallpaperWindow` (borderless, level ใต้ desktop-icon, ignoresMouseEvents, canJoinAllSpaces + stationary + ignoresCycle), `WallpaperDirector` (1 window+engine ต่อ NSScreen, occlusion → pause/resume, sleep/wake, didChangeScreenParameters → reapply), `AppDelegate` + NSStatusItem (เลือก library, รายการ video, mute toggle, stop, quit), จำ library path + last wallpaper + mute ใน UserDefaults
- [ ] เกณฑ์ผ่าน: video วนต่อเนื่อง ≥ 1 ชม. ไม่ memory creep, สลับ Space ไม่หลุด, ทำงานข้ามเครื่อง Apple Silicon/Intel — *รอ `swift run wallpaper-mac` บน Mac*

**หมายเหตุ M2:** หลายจอใช้ engine แยกต่อจอ (CALayer อยู่ได้ window เดียว) — sync ข้ามจอยังไม่เนียนระดับเฟรม เป็น refinement ภายหลัง

## M3 — Web wallpaper

- `WKWebView` + JS bridge จำลอง API ยอดนิยมที่ content ใช้ (audio listener, property listener, wallpaper loader event)

**เกณฑ์ผ่าน:** web wallpaper ตัวที่ใช้ audio visualization ตอบสนองเสียงจริง (หลังขอสิทธิ์ผู้ใช้ตามกลไก macOS)

## M4 — Scene renderer พื้นฐาน

- ก่อนเริ่ม: วิเคราะห์ scene.json จาก fixtures จริง แล้วเขียน spec-scene-json.md ใหม่ (ยืนยันแล้ว/สมมติฐาน)
- **การตัดสินใจสถาปัตยกรรมที่ต้องเสนอทางเลือกก่อน:** วิธีแปล/run shader (glslang+SPIRV-Cross / translator เอง / MoltenVK) — ดู spec-effects-shaders.md
- Metal render graph: โหลด .tex ขึ้น GPU (BC formats เนทีฟ), วาด objects ตามลำดับ, camera + parallax

**เกณฑ์ผ่าน:** scene ง่าย (3–4 layer + parallax) เทียบตรงกับ Wallpaper Engine ฝั่ง Windows ที่เปิดไฟล์เดียวกัน

## M5 — Effects, shaders, particles

- implement effects ตามลำดับความถี่ที่พบใน library จริง, particle system, pass chaining

**เกณฑ์ผ่าน:** 10 วอลเปเปอร์ scene ยอดนิยมของ He เปิดแล้วไม่ผิดเพี้ยนจาก Windows ในลักษณะที่เห็นได้

## M6 — แอปเต็มรูป

- SwiftUI library UI (import โฟลเดอร์ของ He — ไม่ต้องมี Steam บน macOS), ตั้งค่าต่อวอลเปเปอร์ (จาก `properties`), launch at login (SMAppService), ประหยัดพลังงาน (หยุด/ลด FPS เมื่อถูกบัง / ใช้แบต / จอดับ — ตรวจด้วย `NSWindow.occlusionState` + `ProcessInfo.thermalState` + battery notifications)
- Audio visualization ผ่าน ScreenCaptureKit/Core Audio ตามกลไกของ macOS

**เกณฑ์ผ่าน:** ติดตั้ง .app แล้วใช้ต่อวันได้, พลังงาน idle เทียบเคียง Wallpaper Engine ฝั่ง Windows

## กติกาการทำงาน

- ไม่ข้าม milestone, ไม่รวมงานทั้งหมดในครั้งเดียว
- ไม่แน่ใจเรื่องฟอร์แมต → เขียนเครื่องมือสำรวจ (เช่น `wpe-inspect` เพิ่ม subcommand) มายืนยัน ไม่เดาเอง
- อ้างอิงโปรเจกต์โอเพนซอร์สเฉพาะ "ข้อเท็จจริงของฟอร์แมต": RePKG = MIT (ปลอดภัย), linux-wallpaperengine = GPL-3.0 (ห้ามคัดลอกโค้ด), WallpaperExtractor = Apache-2.0 (ปลอดภัย)
