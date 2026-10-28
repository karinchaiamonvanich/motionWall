# สเปก: Effects & Shaders

สถานะเอกสาร: **ยืนยันแล้วระดับรูปแบบ** (2026-10-28) — อ่าน shader source จริงจากใน .pkg (`shaders/effects/pulse.vert/.frag` ฯลฯ) รายละเอียด pass chaining รอ M5

## ข้อเท็จจริงจากไฟล์จริง (ยืนยันแล้ว)

- **Shader source (GLSL) ฝังอยู่ใน .pkg** — path `shaders/effects/*.vert`, `shaders/effects/*.frag`, `shaders/workshop/<id>/effects/*.vert/.frag` ไม่ต้อง decompile .dxs เลย
- ภาษา GLSL แบบเก่า: ใช้ `attribute`/`varying` (GLSL 120-era), ไม่เห็น `#version` ในตัวอย่าง
- Uniform เป็นกลุ่ม `g_*` เช่น `g_ModelViewProjectionMatrix`, `g_Texture1Resolution`, `g_Time`
- **Uniform มี metadata แปะใน comment ท้ายบรรทัด**:
  ```glsl
  uniform float g_PulseSpeed; // {"material":"speed","label":"ui_editor_properties_pulse_speed","default":3,"range":[0,10]}
  ```
  → ระบบ UI/property binding อ่านจาก comment ได้โดยตรง
- **ระบบ COMBO**: header `[COMBO] {...}` + preprocessor `#if MASK`, `#if AUDIOPROCESSING` — shader ถูกคอมไพล์เป็นหลาย variants; นี่คือที่มาของ `shaders/blobsSM40/*.dxs` (DXBC compiled per-combo) ฝั่ง macOS เราจะคอมไพล์ GLSL → MSL เองตาม combos ที่ scene ใช้
- Audio: `uniform float g_AudioSpectrum16Left[16]` / `Right[16]` + `g_AudioFrequencyMin/Max`, `g_AudioPower` — โครง audio visualization ชัดเจน
- Material json (`materials/effects/pulse.json`) อ้าง pass: `{"passes":[{"shader":"effects/pulse","blending":"normal","depthtest":"disabled",...}]}`

## ทางเลือกการรัน shader บน macOS (ตัดสินใจก่อน M4 — ตอนนี้มีข้อมูลมากขึ้น)

| ทางเลือก | ประเมินใหม่หลังเห็นของจริง |
|----------|---------------------------|
| A. glslang → SPIR-V → MSL (SPIRV-Cross) | ยังเป็นตัวเลือกหลัก — GLSL ที่เห็นเป็น subset เก่า ๆ ตรงกับจุดแข็งของ glslang |
| B. translator เอง (subset) | น่าสนใจขึ้น: syntax ที่ใช้จริงแคบ (attribute/varying/uniform + #if combo) — ถ้า inventory ทั้ง library แล้ว syntax เล็กพอ อาจไม่ต้องพา C++ dependency |
| C. MoltenVK | ยิ่งไม่จำเป็น — source GLSL อยู่ใน pkg แล้ว ไม่มีเหตุผลพา Vulkan layer |

แผน: รวม `.vert/.frag` ทั้งหมดจาก library ของ He มาวัด syntax coverage ก่อนตัดสินใจ A หรือ B (จะเสนอพร้อมข้อมูลจริงก่อนเริ่ม M4)

## หัวข้อที่ต้องถอดต่อ (M5)

1. รายการ effect builtin + material json ครบทุกตัว (blending modes มีอะไรบ้าง)
2. กลไก combos: ใครกำหนดค่า #if (material json? scene.json?)
3. include system ของ shader (ถ้ามี)
4. render target chain ระหว่าง passes
