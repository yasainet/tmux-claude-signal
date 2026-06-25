# Decisions

不可逆な技術選定と包括判断のみを 1 行で残す。
詳細は spec / commit / コードを参照する。

## 2026-06-25 running spinner

- running は window-status-format 軸のスピナーで表現する。
- 過去削除した bg 色は再採用しない。
- 有効化は `@claude-signal-running-frames` の opt-in。
- 詳細は `docs/superpowers/specs/2026-06-25-running-spinner-design.md`。
