---
name: project_english_coach_hook
description: UserPromptSubmit hook for English Coach — location, logic, and PowerShell encoding lessons learned
metadata:
  type: project
---

Hook đã được tạo và hoạt động đúng.

**Files:**
- `.claude/hooks/english-coach-reminder.ps1` — hook script
- `.claude/settings.local.json` — đăng ký hook (không commit vào git)
- `.claude/rules/99-english-coach.md` — rule cho Claude

**Logic hook:**
- Trigger khi: `hasEnglish AND NOT hasVietnamese`
- Toàn tiếng Anh → inject reminder → Claude chạy grammar check
- Hỗn hợp hoặc toàn tiếng Việt → không trigger

**Why:** User chỉ muốn grammar check khi message hoàn toàn bằng tiếng Anh.

**How to apply:** Nếu cần sửa rule trigger, sửa cả `99-english-coach.md` VÀ `english-coach-reminder.ps1` để giữ đồng bộ.

**PowerShell pipe encoding — lesson learned:**
- `[Console]::OutputEncoding` KHÔNG ảnh hưởng pipe encoding
- `$OutputEncoding` mới là biến kiểm soát encoding khi pipe sang native process
- `[System.Text.Encoding]::UTF8` có BOM (`EF BB BF`) làm `ConvertFrom-Json` fail
- Dùng `New-Object System.Text.UTF8Encoding $false` cho UTF-8 no BOM
- Đọc stdin bằng `[Console]::OpenStandardInput()` + `StreamReader(UTF8)` để tránh OEM codepage
