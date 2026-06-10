# Brah Boss Menu

High-performance boss management rewritten for minimal runtime dependencies.

## Runtime Dependencies
- Framework: one of `qb-core`, `es_extended`, `qbx_core`, or `ox_core`
- [`oxmysql`](https://github.com/overextended/oxmysql)

## Supported Frameworks
- QBCore
- ESX (new)
- QBox
- OxCore

Framework selection is automatic by default (`Config.Framework = 'auto'`) and can be forced in `config.lua`.

## Features
- Refer featurelist.md

## Security Model
- Server-authoritative actions only
- Short-lived session token required for every post-open action
- Per-action rate limiting buckets
- Full server-side permission checks before every management/finance action
- Input sanitization and numeric bound checks on all write actions

## Database Tables
Created automatically on startup:
- `bossmenu_accounts`
- `bossmenu_ledger`
- `bossmenu_audit`
- `bossmenu_webhook_settings`
- Plus Phase expansion tables (`bossmenu_*`) for ranks, permissions, profiles, payroll, inventory, uniforms, applications, admin, taxes/invoices, gang systems.

## Configuration
Edit `config.lua`:
- `Config.Framework`
- `Config.MinBossGrade`
- `Config.useinbuiltgangframes` (`true` = framework gang data, `false` = built-in gang backend for QB/ESX)
- `Config.BossMenus`
- `Config.GangMenus`
- `Config.Security`
- `Config.Performance`
- `Config.Database` (offline query schema per framework, especially useful for custom OxCore schemas)

## Built-In Gang Backend (QB/ESX)
When `Config.useinbuiltgangframes = false`, the script uses internal gang tables:
- `bossmenu_gangs`
- `bossmenu_gang_members`

This mode is fully managed inside this resource and still keeps legacy menu entry events compatible.

## Resource Replacement Compatibility
The manifest includes `provide` declarations for legacy resources:
- `qb-management`
- `qb-gangmenu`
- `esx_society`

## Dev Commands (Debug)
Available only when `Config.Debug = true` and caller has admin/ACE:
- `/bm_debug_org boss|gang <name>`
- `/bm_test_audit`
- `/bm_test_webhook`
- `/bm_reload_permissions`
- `/bm_migrate`
- `/bm_seed_demo`
- `/bm_clear_demo`
