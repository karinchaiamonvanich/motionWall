# สเปก: `scene.json` — โครงสร้าง scene

สถานะเอกสาร: **ยืนยันแล้วระดับโครงสร้าง** (2026-10-28) — ถอดจาก `scene.json` จริง (16,097 bytes, จาก workshop item 3481807485) รายละเอียด field ระดับลึก (effect bindings, particles) ยังต้องวิเคราะห์ต่อใน M4

## โครงสร้างระดับบน (ยืนยันแล้ว)

```json
{
  "version": 1,
  "camera": {
    "eye":    "0.00000 0.00000 0.00000",
    "center": "0.00000 0.00000 -1.00000",
    "up":     "0.00000 1.00000 0.00000"
  },
  "general": {
    "ambientcolor": "0.30000 0.30000 0.30000",
    "clearcolor": "0.70000 0.70000 0.70000",
    "clearenabled": true,
    "bloom": false, "bloomstrength": 2.0, "bloomthreshold": 0.65,
    "bloomhdriterations": 8, "bloomhdrstrength": 2.0, "bloomhdrthreshold": 1.0, ...,
    "cameraparallax": false, "cameraparallaxamount": 0.5,
    "cameraparallaxdelay": 0.1, "cameraparallaxmouseinfluence": 0.5,
    "camerashake": false, "camerashakeamplitude": 0.5, ...,
    "fov": 50.0, "nearz": 0.01, "farz": 10000.0,
    "orthogonalprojection": {"width": 7680, "height": 4320},
    "hdr": false, "zoom": 1.0,
    "gravitydirection": "0.00000 -1.00000 0.00000", "gravitystrength": 1.0,
    "winddirection": "0.70700 0.70700 0.00000", "windenabled": false, "windstrength": 1.0
  },
  "objects": [ ... ]
}
```

## ข้อเท็จจริงที่ยืนยันแล้ว

- vector เขียนเป็น **string** "x y z" ไม่ใช่ array
- `camera` เป็น look-at (eye/center/up)
- `general` รวมทุก global setting: bloom (แบบ LDR และ HDR แยก), parallax (amount/delay/mouseinfluence), camera shake, fov + near/far z + orthogonal projection override, gravity/wind (สำหรับ particles), hdr toggle
- `objects` เป็น array, แต่ละ object มี `name`, `effects[]` (นับได้ 0–4 ต่อ object), และ **object ซ้อนกันได้** (field `object` ลูก) — tree structure
- object อ้าง asset ผ่าน path ใน .pkg เช่น `models/[Dsfr] xxx_resized.json`, `materials/...tex`

## หัวข้อที่ยังต้องถอด (M4)

1. schema เต็มของ object (transform/origin/scale/rotation, image binding, color)
2. schema ของ `effects[]` — จากตัวอย่างจริงพบ `{"file": "effects/pulse/effect.json", "id": 509, "name": "", "passes": [{"combos": ..., "shader": "effects/pulse", "blending": "normal", "depthtest": "disabled"...}]}` (อ่านจาก materials/effects/pulse.json ที่ฝังใน pkg)
3. ลำดับการวาด (implicit ตามลำดับ array หรือ explicit z)
4. parallax: `cameraparallax*` คุมกล้อง, ผลต่อ object layer ยังต้องทดสอบ
5. particles + audio binding (`g_AudioSpectrum16*` uniforms เห็นแล้วใน shader source)

## วิธีการ (clean-room)

ถอดจากไฟล์ content ของผู้ใช้เอง + ทดลองสร้าง minimal scene ใน Wallpaper Engine editor ฝั่ง Windows แล้ว diff scene.json — ไม่อ่านโค้ด/decompile ของ Valve
