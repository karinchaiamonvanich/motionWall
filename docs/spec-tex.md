# สเปก: ฟอร์แมตเท็กซ์เจอร์ `.tex`

สถานะเอกสาร: **ยืนยันแล้วเกือบทั้งหมด** (2026-10-28) — ผ่านการเดิน record chain ทั้ง library: **byte-exact 387/388 ไฟล์** จาก 33 .pkg (1,109 mip blobs: raw 207 / LZ4 903) เอกสารชุมชนเก่า (TEXV0) **ล้าสมัย** — ไฟล์ปัจจุบันเป็น TEXV0005

## ข้อค้นพบสำคัญ

- เอกสารชุมชนเก่าบอก magic `TEXV0` + format/flags/width/height แบบแบน — **ไฟล์จริงปัจจุบันไม่ใช่แบบนั้น**
- ไฟล์จริงเป็น **`TEXV0005\0`** (magic 9 bytes รวม NUL) แล้วเป็น **records** แบบ tagged

## โครงสร้าง TEXV0005 (ยืนยันแล้ว)

```
"TEXV0005\0"                        container magic (9 bytes)
record × n:
  "TEXI0001\0"                      image header
      u32 format                    pixel format enum (ตารางด้านล่าง)
      u32 unknown                   flags — พบ 0, 2, 6, 7, 34
      u32 width
      u32 height
      u32 width                     (ซ้ำ — คาด: dims ของ mip ใหญ่สุด)
      u32 height                    (ซ้ำ)
      u8[4] tail                    พบ `00 00 00 ff`
  "TEXB0004\0" หรือ "TEXB0003\0"    blob record (9 u32 หรือ 8 u32 ก่อน payload)
      TEXB0004: [1][0xFFFFFFFF][0][1][w][h][1]
      TEXB0003: [1][0xFFFFFFFF][3?][w][h][1]
      u32 uncompressedSize          ขนาดข้อมูลพิกเซลตาม format (ตาราง B/px)
      u32 compressedSize
      u8[compressedSize] payload    LZ4 block (raw เมื่อ comp == uncomp)
  ...mip ต่อไป (ไม่มี tag!) — header เปลือย 20 bytes:
      u32 width, u32 height, u32 flags?, u32 uncompressedSize, u32 compressedSize
      u8[compressedSize] payload    ทำซ้ำจนเจอ tag ถัดไปหรือจบไฟล์
  "TEXS0003\0"                      sprite-sheet descriptor (particle sheets)
      u32 count, u32 width, u32 height
      count × 32 bytes              float UV/rect metadata (สมมติฐานจากตัวอย่างเดียว)
```

## pixel format enum (ล็อกจากอัตราส่วน uncompressedSize / (w×h) — ตรงเป็นเลขจำนวนเต็มทุกไฟล์)

| format | B/px | ตีความ | นับไฟล์ |
|--------|------|--------|---------|
| 0 | 4 | RGBA8 ไม่บีบอัด (มี alpha — เหมาะกับ sprite) | 138 |
| 4 | 1 | single-channel (R8/L8) — mask | 75 |
| 7 | 0.5 | **BC1/DXT1** (block-compressed บน GPU) | 2 |
| 8 | 2 | 2 ช่อง (RG16/BGR565 family) — ยังไม่ระบุ | 71 |
| 9 | 1 | single-channel (R8/L8) — mask | 102 |

รวม 388 ไฟล์ tex (ตรงกับ blob version histogram 0003+0004 พอดี)

## สมมติฐานที่เหลือ (open items)

- ความต่างระหว่าง format 4 กับ 9 (ทั้งคู่ 1 B/px — อาจต่างที่ channel: R vs A vs Luminance) — ต้องเทียบภาพจริง
- format 8 เป็น RG หรือ 565 — ต้องเทียบภาพจริง
- ความหมาย bit ของ `unknown` ใน TEXI และ field คงที่ใน TEXB
- **outlier 1/388** (`3577990983/?? 1_00004.tex`): ท้ายไฟล์เป็น float table stride 28 bytes — variant ของ TEXS (particle sheet) จะถอดตอน M5 พอดี — parser ปัจจุบัน throw อย่างปลอดภัย
- ไฟล์ `.texzl` ยังไม่ได้ตรวจ

## แนวทางยืนยันที่ใช้

extract จาก .pkg ด้วย offset ที่ยืนยันแล้ว → hexdump header → จับคู่ค่าตัวเลขกับขนาดไฟล์จริง → เดิน record chain ทั้ง library ตรวจว่า byte ที่กินรวม = ขนาดไฟล์พอดี (เกณฑ์ byte-exact)
