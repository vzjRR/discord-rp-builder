# التثبيت بأمر واحد

إذا ما لقيت `Install-MangoNazlet.bat`، أو ما تبي تحمّل وتفك ضغط يدويًا،
هذا الأمر يسوي كل شي: يحمّل، يفك الضغط، ويشغّل المثبّت.

## الخطوات

1. اضغط **زر ويندوز**، اكتب `powershell`
2. كليك يمين على **Windows PowerShell** ← **Run as administrator**
3. الصق هذا السطر كامل واضغط Enter:

```powershell
$ProgressPreference='SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; $t="$env:TEMP\mn"; Remove-Item $t -Recurse -Force -EA 0; New-Item -ItemType Directory $t -Force | Out-Null; Invoke-WebRequest 'https://github.com/vzjRR/discord-rp-builder/archive/refs/heads/claude/gta5-ice-cream-shop-xy13vb.zip' -OutFile "$t\m.zip"; Expand-Archive "$t\m.zip" $t -Force; & (Get-ChildItem $t -Recurse -Filter 'Install-MangoNazlet.ps1' | Select-Object -First 1).FullName
```

بيحمّل آخر نسخة، ويفحص سيرفرك، وينسخ المورد، ويعدّل `server.cfg`.

**لو `ox_lib` ناقص** بيسألك إذا تبيه يحمّله ويركّبه لك — اضغط Enter وخلاص.
لو تبيه يركّبه بدون سؤال، أضف `-InstallOxLib` في نهاية الأمر.

## لو سيرفرك مو في `C:\FiveMServer`

أضف المسار في نهاية الأمر:

```powershell
... | Select-Object -First 1).FullName -ServerPath 'D:\my-server'
```

## تبي تشوف وش بيسوي قبل ما يسوي؟

نفس الأمر، بس أضف `-WhatIf` في النهاية:

```powershell
... | Select-Object -First 1).FullName -WhatIf
```

يعرض كل خطوة بدون ما يغيّر أي ملف.

---

## ليش ما لقيت ملف الـ .bat؟

**السبب الأشهر: ويندوز يخفي الامتدادات.** بتشوف ملفين بنفس الاسم
`Install-MangoNazlet` — واحد فيه ترس ⚙️ (هذا الـ .bat) وواحد أزرق (الـ .ps1).

لإظهار الامتدادات: افتح أي مجلد ← **View** ← فعّل **File name extensions**.

**السبب الثاني:** نزّلت الـ ZIP قبل ما يُضاف الملف. الأمر فوق يحمّل آخر نسخة
دائمًا فما تواجه هذي المشكلة.

**السبب الثالث:** بعض برامج الحماية تحذف ملفات `.bat` المحمّلة من الإنترنت.
الأمر فوق ما يحتاج `.bat` أصلاً.
