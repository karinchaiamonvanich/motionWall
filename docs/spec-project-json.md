# สเปก: `project.json` — manifest ของวอลเปเปอร์

สถานะเอกสาร: **ยืนยันแล้วระดับโครงสร้าง** (2026-10-28) — ตรวจกับไฟล์จริง (workshop item 3481807485, type scene)

## โครงสร้าง (จากไฟล์จริง)

```json
{
  "type": "scene",                 // scene | video | web | application
  "title": "...",
  "file": "scene.json",            // ไฟล์ entry ตาม type
  "preview": "preview.gif",
  "contentrating": "Everyone",
  "ratingsex": "none",
  "ratingviolence": "none",
  "tags": ["Anime"],
  "version": 1,
  "visibility": "public",
  "workshopid": "3481807485",
  "workshopurl": "steam://url/CommunityFilePage/3481807485",
  "general": {
    "supportsaudioprocessing": true,
    "properties": { ... }          // ← properties อยู่ใน "general" (ยืนยันแล้ว)
  }
}
```

**หมายเหตุสำคัญ:** เอกสารเก่า/ความเข้าใจแรกว่า `properties` อยู่ระดับราก — ไฟล์จริงอยู่ที่ `general.properties` parser รองรับทั้งสองตำแหน่ง (ใน general ก่อน, root เป็น fallback)

## `general.properties` — ค่าที่ผู้ใช้ปรับได้ (จากไฟล์จริง)

ประเภทที่เจอจริงแล้ว:

| type | fields ที่พบ | ตัวอย่างจริง |
|------|--------------|--------------|
| `color` | index, order, text, value ("r g b") | schemecolor = "0.5411764705882353 0.8 1" |
| `bool` | index, order, text, value | shake = true |
| `slider` | index, order, text, value, min, max, step, precision, **fraction** | audioeffectsstrength: min 0, max 4, step 0.1, precision 2, fraction true |
| `group` | index, order, text, value ("") | หัวข้อจัดกลุ่มใน UI (ไม่มีค่าตรง ๆ) |

- `text` เป็น locale key (เช่น `ui_browse_properties_scheme_color`) — UI ต้องมีตารางแปล หรือ fallback ใช้ key ตรง ๆ
- `index` กำหนดลำดับการประกาศ uniform ฝั่ง shader binding (ตรวจเพิ่มใน M4/M5)
- ประเภทอื่น ๆ จากเอกสารชุมชน (combo/text/customized) ยังรอไฟล์จริงมายืนยัน

## ประเภทวอลเปเปอร์ × สิ่งที่ต้องรองรับ

| type | renderer | สถานะรองรับ |
|------|----------|-------------|
| `scene` | Metal render graph (scene.json อยู่ใน .pkg) | M4–M5 |
| `video` | AVPlayerLooper / AVSampleBufferDisplayLayer | M2 |
| `web` | WKWebView + JS bridge | M3 |
| `application` | ไม่รองรับ (โปรแกรม Windows แยกต่างหาก) | แจ้งผู้ใช้ชัดเจน |

## แนวทางยืนยันต่อ

1. เก็บ `project.json` จริงจากทั้ง 4 ประเภทมาเป็น fixtures
2. `wpe-inspect project` จะรายงาน field ที่ยังไม่ได้ model — นำมาเติมเอกสารนี้
