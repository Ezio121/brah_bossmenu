# Admin Guide

## Admin Access
Admin panel actions require:
- `Config.Modules.AdminPanel=true`
- One of:
  - ACE: `bossmenu.admin`
  - `Config.AdminCheck(source, playerState)` returning `true`
  - fallback job name `admin`

## Debug Commands
Require `Config.Debug=true` and admin/console:
- `/bm_debug_org boss|gang <name>`
- `/bm_test_audit`
- `/bm_test_webhook`
- `/bm_reload_permissions`
- `/bm_migrate`
- `/bm_seed_demo`
- `/bm_clear_demo`

## Security
- Repeated suspicious actions trigger temporary lockout.
- Tuning:
  - `Config.Security.lockoutFailThreshold`
  - `Config.Security.lockoutSeconds`

## Admin Panel Actions
Available via NUI/admin RPC:
- List organizations (jobs + gangs)
- Add/remove funds
- Enable/disable organization state
- Force add/remove member
- Force grade set
- Change leader (promotes target to top known grade)
- Delete internal gang backend data (requires confirm token)
- Query suspicious actions
- Export filtered logs
