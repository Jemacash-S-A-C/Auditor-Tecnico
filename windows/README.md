# Jemacash Auditor (Windows)

## 1) Empaquetar a EXE

```powershell
cd tools/auditor/windows
powershell -ExecutionPolicy Bypass -File .\build-auditor.ps1
```

Salida esperada:
- `tools/auditor/windows/dist/Jemacash-Auditor.exe`

## 2) Firmar digitalmente (opcional recomendado)

Requisitos:
- Certificado `.pfx`
- `signtool.exe` (Windows SDK)

```powershell
cd tools/auditor/windows
powershell -ExecutionPolicy Bypass -File .\sign-auditor.ps1 `
  -ExePath .\dist\Jemacash-Auditor.exe `
  -PfxPath C:\ruta\certificado.pfx `
  -PfxPassword "TU_PASSWORD"
```

## 3) Ejecución del auditor

El binario/script requiere estos parámetros:
- `ApiUrl`
- `GuaranteeId`
- `AccessToken`

Ejemplo (script):

```powershell
.\Jemacash-Auditor.ps1 -ApiUrl "http://localhost:3000" -GuaranteeId "UUID" -AccessToken "JWT"
```

## 4) Autoeliminación

El auditor se autoelimina al terminar (bloque `finally`), incluso si falla el envío.
