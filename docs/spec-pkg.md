# สเปก: คอนเทนเนอร์ `.pkg` (Wallpaper Engine)

สถานะเอกสาร: **ยืนยันแล้ว** (2026-10-28) — ตรวจกับไฟล์จริง `scene.pkg` จาก workshop item 3481807485 (27/27 entries parse สำเร็จ, ทุก entry in-bounds, data region ต่อเนื่อง)

## ข้อกำหนดการใช้งาน

- ใช้เฉพาะไฟล์ `.pkg` ของวอลเปเปอร์ที่ผู้ใช้เป็นเจ้าของสิทธิ์ (ซื้อ/subscriber ด้วยตัวเอง หรือสร้างเอง)
- เครื่องมือเป็น reader เท่านั้น ไม่เกี่ยวข้องกับ DRM หรือการแจกจ่ายไฟล์ของผู้อื่น

## โครงสร้าง (ยืนยันแล้ว)

```
u32 versionStringLength              e.g. 8
u8[len] versionString                "PKGV0022" (ไฟล์ปัจจุบัน)
u32 entryCount
entry × entryCount:
    u32 pathLength
    u8[len] path                     UTF-8, separator '/'
    u32 offset                       RELATIVE จากต้น data region (ไม่ใช่ absolute!)
    u32 size
dataStart = ตำแหน่งท้ายตาราง
data region: blob เดียวต่อเนื่อง  entries ชี้เป็น relative offset
```

ข้อเท็จจริงที่ยืนยันแล้ว:
- ทุก integer เป็น little-endian
- **ไม่มี crc32 ต่อ entry** (ต่างจากที่เอกสารชุมชนเก่าเคยระบุ)
- offset เป็น **relative จาก dataStart** — พิสูจน์จาก entry แรกที่มี offset = 0 และ entry ต่อ ๆ กันต่อเนื่องพอดี (offset[n+1] == offset[n] + size[n])
- ไม่มี packageLength field — ขนาดตาราง = 4 + verLen + 4 + Σ(4 + pathLen + 8)
- version string รูปแบบ `PKGV####` (เจอ `PKGV0022`) — parser ตรวจ prefix `PKGV` แล้วเก็บทั้ง string ไว้
- entry ที่พบจริงในไฟล์ตัวอย่าง: `.tex`, `scene.json`, `.json` (models/materials/effects), `.vert`, `.frag` (**shader source ฝังใน pkg**), `.mp3`
- เนื้อหาภายใน .pkg ไม่ถูก compress ที่ระดับคอนเทนเนอร์ (compress อยู่ใน .tex เอง)

## ไฟล์ประกอบในโฟลเดอร์วอลเปเปอร์ (ยืนยันแล้วจากตัวอย่าง)

- `project.json` — manifest (ดู spec-project-json.md)
- `scene.json` — อยู่ **ใน .pkg** (ไม่ใช่ไฟล์แยกในโฟลเดอร์)
- `preview.gif/jpg`
- `shaders/blobsSM40/*.dxs` — **คอมไพล์ shader แล้ว** (DXBC, per-combo variants) — ฝั่ง macOS ไม่ใช้ แต่ .vert/.frag source ใน .pkg ใช้ได้

## วิธียืนยันที่ใช้

PowerShell parser ชั่วคราว + hexdump เทียบทีละ field กับไฟล์จริง; จากนั้น fixtures ใน unit test สร้างตาม layout นี้ (`Tests/WPEParserTests/WPEParserTests.swift: buildPkg`)
