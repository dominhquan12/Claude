# English Coach — Hướng dẫn bật lại

Thư mục này chứa toàn bộ setup English Coach hook. Hiện tại đã được **tắt** để tiết kiệm token.

## Các file trong thư mục

| File | Mục đích |
|------|----------|
| `99-english-coach.md` | Rule cho Claude — copy vào `.claude/rules/` để bật |
| `english-coach-reminder.ps1` | Hook script — copy vào `.claude/hooks/` để bật |
| `project_english_coach_hook.md` | Memory file — copy vào `.claude/memory/` để bật |

## Cách bật lại

**Bước 1** — Copy rule file vào rules:
```
copy .claude\english-coach\99-english-coach.md .claude\rules\99-english-coach.md
```

**Bước 2** — Copy hook script vào hooks:
```
copy .claude\english-coach\english-coach-reminder.ps1 .claude\hooks\english-coach-reminder.ps1
```

**Bước 3** — Thêm hook vào `.claude/settings.local.json`:
```json
"hooks": {
  "UserPromptSubmit": [
    {
      "matcher": "",
      "hooks": [
        {
          "type": "command",
          "command": "powershell -NoProfile -File .claude/hooks/english-coach-reminder.ps1"
        }
      ]
    }
  ]
}
```

**Bước 4** — Thêm lại vào `.claude/MEMORY.md`:
```
- [English Coach Hook](memory/project_english_coach_hook.md) — UserPromptSubmit hook tại .claude/hooks/, trigger chỉ khi toàn tiếng Anh, PowerShell encoding lessons
```

## Logic hoạt động

- Trigger khi message **toàn tiếng Anh** (không có ký tự tiếng Việt)
- Claude sẽ: (1) grammar check, (2) trả lời câu hỏi
- Hỗn hợp Việt-Anh hoặc toàn tiếng Việt → không trigger
