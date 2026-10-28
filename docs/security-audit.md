# Security Audit — 2026-10-28

ขอบเขต: โค้ดทั้งหมดใน repo (WPEParser, WPERenderer, WPELibrary, wpe-inspect, WPEApp) มองจากมุม "โค้ดของเราต้องประมวลผลไฟล์ที่ไม่น่าเชื่อถือ (untrusted input) จาก internet (workshop content) ได้อย่างปลอดภัย"

## พื้นที่เสี่ยงหลักและสิ่งที่ตรวจ

โมเดลภัยคุกคาม: ผู้ใช้เปิดไฟล์ .pkg/.tex ที่ดาวน์โหลดมา (อาจถูกแก้ไข/เป็นพิษ) — parser ต้องพังอย่างปลอดภัย (throw) ไม่ร่วง ไม่เขียนไฟล์หลุดขอบเขต ไม่กินหน่วยความจำจนเครื่องตาย

## ผลการตรวจ (แก้แล้วทั้งหมดในรอบนี้)

### 🔴 S-1: Path Traversal ใน `extractAll` (zip-slip) — พบและแก้แล้ว
- **อาการ:** `PkgArchive.extractAll` เขียนไฟล์ตาม path ใน entry table ตรง ๆ — .pkg ที่ถูกปรับแต่งให้มี entry path `../../.zshenv` หรือ `/Users/x/...` ทำให้เขียนไฟล์หลุดออกนอกโฟลเดอร์ปลายทาง
- **การแก้:** เพิ่ม `safeDestination(for:in:)` — ปฏิเสธ path ที่เป็น absolute, ขึ้นต้น `~`, มี `..`/`.` component, มี backslash หรือ NUL + ตรวจ symlink ที่ปลายทางก่อนเขียน (กัน overwrite ผ่าน symlink ที่วางไว้ก่อน)
- **ตัวทดสอบ:** `testPkgExtractRejectsTraversalPaths`

### 🟡 S-2: ระเบิดการจัดสรร (allocation bomb) ใน LZ4 — พบและแก้แล้ว
- **อาการ:** `LZ4.decompress(hintSize:)` รับ hintSize ตรงจาก field `uncompressedSize` ในไฟล์ (u32 สูงสุด ~4 GB) — `reserveCapacity` ตามค่านั้นทันที ทำให้ไฟล์เล็ก ๆ ที่ปรับแต่งหัวข้อสั่งให้ app กิน RAM 4 GB ได้
- **การแก้:** เพิ่มพารามิเตอร์ `maxOutputSize` (default 256 MiB — สูงกว่า mip จริงสุด 4K RGBA8 ≈ 33 MiB มาก) — ตรวจทั้งก่อน reserveCapacity และก่อน append ทุกครั้ง เกินแล้ว throw `outputTooLarge`
- **ตัวทดสอบ:** `testLZ4RejectsOversizedOutput`

## จุดที่ตรวจแล้วปลอดภัย (เหตุผลต่อจุด)

| จุด | เหตุผล |
|-----|---------|
| BinaryReader bounds | ทุก read มี `guard offset + count <= data.count` — Int 64-bit, ค่าสูงสุดจากไฟล์คือ u32 (4.29e9) บวกกันไม่ overflow |
| pkg entry bounds | `pathLen` จำกัด ≤ 4096, `entryCount` ≤ 100,000, `offset+size` ตรวจในตาราง + ตรวจซ้ำใน `data(for:from:)` |
| pkg path encoding | ปฏิเสธ non-UTF8 และ empty path — ไม่มีการส่ง bytes ดิบไปเป็น path |
| LZ4 match offset | `offset > 0` และ `≤ output.count` — ไม่อ่านก่อนต้น buffer, byte-at-a-time copy ทำงานกับ overlapping match ได้ถูกต้อง |
| LZ4 literal/match extension | loop ต่อยาวมี guard ตรวจ input ทุก byte — จบสวยเมื่อ input หมด |
| tex record chain | ทุก record ตรวจ dims/magic ก่อนเดินต่อ; continuation blob ตรวจ `comp <= remaining`; TEXS `count*32` คูณใน Int64 ไม่ overflow แล้ว readBytes โยน truncated ถ้าเกิน |
| TexFile tag discriminator | continuation header เริ่มด้วย u32 width (< 16384) — byte ที่สอง (< 0x40) ชนกับ 'E' (0x45) ไม่ได้ ไม่มี false positive ทางคณิตศาสตร์ |
| project.json | ใช้ JSONSerialization ของ Apple (รับ fragments) — ไม่มี eval/deserialization แบบอันตราย |
| WPEApp | ไม่มี network, ไม่มี privilege escalation, path จาก NSOpenPanel (ผู้ใช้เลือกเอง), ค่าที่ persist เป็น UserDefaults ของ app เอง — ไม่มี injection surface |
| VideoWallpaperEngine | ป้อนไฟล์ให้ AVFoundation (decoder ของระบบ, sandbox ในตัว) — เราไม่แปลง/ไม่เขียนทับไฟล์ต้นฉบับ |

## ข้อจำกัดของการตรวจครั้งนี้

- เป็นการตรวจด้วยตา + เขียนตัวทดสอบครอบกรณีโจมตีที่รู้จัก — ยังไม่รัน fuzzing อัตโนมัติ แผนต่อ: เพิ่ม fuzz target เล็ก ๆ (สุ่ม byte ใส่ parser) ใน CI ตอน M3
- decoder ของระบบ (LZ4 ของ Wallpaper Engine, AVFoundation, WebKit ในอนาคต M3) เป็นโค้ดของ Apple/ของคนอื่น — อยู่นอกขอบเขต แต่ M3 (WKWebView) จะต้องเพิ่มการกัน JavaScript ที่มาจาก web wallpaper แยกอีกระดับ (bridge แบบ allowlist)
