# qb-management Feature List (Current Script State)

Last audited: 2026-05-28

## Compatibility and Runtime
- [x] Framework auto-detection and support: `qb`, `qbox`, `esx`, `ox`
- [x] Runtime DB dependency: `oxmysql` only
- [x] Locale files loaded from `locales/en.lua`, `locales/es.lua`, `locales/de.lua`
- [x] NUI locale payload bridge with frontend translation helper and DOM localization pass
- [x] Resource replacement compatibility via `provide`:
- [x] `qb-management`
- [x] `qb-gangmenu`
- [x] `esx_society`
- [x] Static NUI runtime (`web/dist/*`, no runtime build requirement)
- [x] Legacy boss and gang compatibility events/callbacks retained for QB ecosystem paths

## Current Config Module State
- [x] `DynamicRanks` enabled
- [x] `RankPermissions` enabled
- [x] `EmployeeProfiles` enabled
- [x] `SalaryManagement` enabled
- [x] `Payroll` enabled
- [x] `BusinessInventory` enabled
- [x] `BusinessVault` enabled
- [x] `GangCashLocker` enabled
- [x] `Uniforms` enabled
- [x] `Applications` enabled
- [x] `Announcements` enabled
- [x] `AdminPanel` enabled
- [x] `Taxes` enabled
- [x] `BillsInvoices` enabled
- [x] `ScheduledTasks` enabled
- [x] `GangNotoriety` enabled
- [x] `GangMarkers` enabled
- [x] `GangGarages` enabled
- [x] `GangTerritories` enabled
- [x] `GangRackets` enabled
- [x] `GangGraffiti` enabled
- [x] `GangContracts` enabled
- [x] `Webhooks` module enabled in `Config.Modules`
- [x] `Analytics` enabled
- [x] `Cameras` enabled
- [x] `PublicAPI` enabled

## Security and Hardening
- [x] Server-authoritative action model
- [x] Session token requirement for post-open RPC actions
- [x] Session token TTL (`Config.Security.sessionTokenTtlSeconds`)
- [x] Request replay guard by request-id nonce window (`Config.Security.nonceTtlSeconds`)
- [x] Per-action rate limiting buckets
- [x] Strict server-side permission checks for management and module actions
- [x] Suspicious action detection and audit logging
- [x] Temporary lockout after repeated failed checks (`lockoutFailThreshold`, `lockoutSeconds`)
- [x] High-value money attempt detection and suspicious flagging
- [x] Organization spoof and invalid session checks
- [x] Configurable suspicious webhook gating (`webhookOnSuspiciousAction`)

## Boss and Gang Core
- [x] Boss menu open via command
- [x] Gang menu open via command
- [x] Marker zone based open for boss and gang
- [x] Optional target integration (`ox_target` / `qb-target`)
- [x] Employee/member listing (online + offline)
- [x] Nearby player listing and hire flow
- [x] Promote/demote by grade
- [x] Fire/remove flow with reason support
- [x] Society money deposit/withdraw with ledger
- [x] Gang mode finance separation logic retained
- [x] Built-in gang backend switch (`Config.useinbuiltgangframes`)
- [x] Built-in QB/ESX gang DB backend with multi-gang rank model
- [x] Legacy event entry compatibility (`qb-gangmenu:client:OpenMenu`)

## Ranks and Permissions
- [x] Dynamic rank CRUD
- [x] Rank grade update and metadata update
- [x] Rank reassignment flow
- [x] Rank delete validation flow
- [x] Per-rank permission matrix storage and mutation
- [x] Server-side permission enforcement for all gated actions

## Profiles, Salary, Payroll
- [x] Member profile read/update
- [x] Notes, strikes, metadata-backed profile storage
- [x] Profile activity tracking
- [x] Generate profile image flow (capture request/response pipeline)
- [x] Salary override system (grade or identifier)
- [x] Manual payroll run
- [x] Automatic payroll worker (`Config.Payroll.autoEnabled`)
- [x] Payroll partial-payment mode support (`Config.Payroll.allowPartial`)
- [x] Payroll run history storage

## Inventory and Stash
- [x] Organization inventory list/deposit/withdraw
- [x] Inventory action logs
- [x] Boss stash open action (`stash_open`)
- [x] Inventory integrations:
- [x] `ox_inventory`
- [x] `qb-inventory`
- [x] `ps-inventory`
- [x] `lj-inventory`
- [x] `qs-inventory`
- [x] DB fallback for unsupported/missing backends

## Uniforms
- [x] Uniform list/save/delete
- [x] Uniform preview/apply/restore pipeline
- [x] Clothing integration modes in config:
- [x] `qb-clothing`
- [x] `illenium-appearance`
- [x] `fivem-appearance`
- [x] `skinchanger`
- [x] Fallback direct ped component/prop application path

## Applications and Announcements
- [x] Application submit/list/decision backend
- [x] Public application submit event (`qb-management:server:SubmitApplication`)
- [x] Integration export: `SubmitApplication`
- [x] Announcement create/list backend
- [x] Optional phone integration notification hooks (`yseries`, `qb-phone`, `qs-smartphone`, custom)

## Finance, Taxes, Invoices
- [x] Society account internal fallback (`bossmenu_accounts`)
- [x] Banking compatibility modes configured (`qb-banking`, `Renewed-Banking`, `okokBanking`, `esx_addonaccount`, none/auto)
- [x] Taxes set/get/pay module actions
- [x] Tax recurring worker with grace/penalty handling
- [x] `ap-government` tax bridge integration support
- [x] Invoice create/status/list actions
- [x] Invoice and tax hook emission

## Admin and Oversight
- [x] Admin org list and action panel backend
- [x] Add/remove org funds
- [x] Disable/enable org state
- [x] Force add/remove member
- [x] Force rank/grade set
- [x] Leader change
- [x] Internal gang deletion flow
- [x] Suspicious action view endpoint
- [x] Admin action export/log endpoint

## Markers, Garages, Analytics, Logs
- [x] Org marker CRUD
- [x] Gang marker CRUD
- [x] Org garage CRUD
- [x] Gang garage module path
- [x] Analytics endpoint with boss/gang summaries
- [x] Audit log query endpoint with filters
- [x] Scheduled task worker table + processing loop

## Gang Ecosystem
- [x] Gang notoriety set/add/remove/list actions
- [x] Territory list/begin/complete actions
- [x] Territory capture hooks and leaderboard path
- [x] Rackets list/upsert/upgrade/claim actions
- [x] Contract list/create/accept/complete actions with cooldown/active caps
- [x] Graffiti list/place/delete actions
- [x] World graffiti snapshot sync + live upsert/remove events
- [x] Graffiti anti-spam/limits/distance checks
- [x] Territory auto-claim from closed graffiti tag polygons
- [x] Polygon validation for tag-based territory capture:
- [x] Min/max vertices
- [x] Close distance
- [x] Max span
- [x] Min/max area
- [x] Point age window
- [x] Realistic runtime graffiti rendering (DUI texture + 3D sprite projection)
- [x] Graffiti texture cache cap and timed cleanup

## Cameras and CCTV
- [x] Camera module permission-gated list/open actions
- [x] Archetype and org-aware camera feed resolution
- [x] Camera provider integration modes:
- [x] `qb-policejob`
- [x] `esx_policejob`
- [x] `rcore_cctv`
- [x] `loaf_cctv`
- [x] `okokCCTV`
- [x] `tk_cctv`
- [x] `native`
- [x] `custom`
- [x] In-camera overlay/effect pipeline on client side

## Screenshot and Profile Capture Providers
- [x] Screenshot integration modes:
- [x] `screenshot-basic`
- [x] `screencapture`
- [x] `screenhost-basic`
- [x] `custom`
- [x] Auto provider fallback order
- [x] Capture size guard (`Config.Screenshots.maxBytes`)

## Hooks and Public API
- [x] Hook registration exports:
- [x] `RegisterHook`
- [x] `UnregisterHook`
- [x] Core hook emissions for boss/gang/member/finance/security flows
- [x] Compatibility hook names (`OnEmployee*`, `OnGangMember*`, `OnApplication*`, `OnInvoice*`, `OnTax*`, contract/notoriety events)
- [x] Public API exports:
- [x] Boss APIs (`OpenBossMenu`, `IsBoss`, `HasBossPermission`, employee + society APIs)
- [x] Gang APIs (`OpenGangMenu`, `IsGangLeader`, `HasGangPermission`, member + notoriety APIs)
- [x] Common APIs (`CreateAuditLog`, `GetOrgConfig`, framework/introspection exports)
- [x] Integration APIs (`SubmitApplication`, invoice helper exports)

## Webhook System
- [x] Business-level Discord webhook settings from the NUI
- [x] Admin-level global Discord webhook settings from the Admin Panel
- [x] One webhook per log type/category per business
- [x] One global admin webhook per log type/category
- [x] Supported categories: employee, gang, finance, inventory, admin, security, applications, territories, contracts
- [x] Persistent webhook settings table (`bossmenu_webhook_settings`)
- [x] URL validation for Discord webhook endpoints
- [x] Webhook management permission (`manage_webhooks`)
- [x] Admin global webhook settings gated by admin permission
- [x] Batched Discord delivery grouped by webhook URL/type/scope
- [x] Batch size/window config (`Config.Webhooks.batchSize`, `Config.Webhooks.batchWindowMs`)
- [x] Retry/backoff retained for failed Discord requests

## NUI and UX Surface
- [x] Sidebar sections:
- [x] Overview
- [x] Employees/Members
- [x] Ranks
- [x] Permissions
- [x] Inventory/Stash
- [x] Uniforms
- [x] Applications
- [x] Announcements
- [x] Markers
- [x] Garage
- [x] Taxes/Bills
- [x] Analytics
- [x] Logs
- [x] Gang Territories
- [x] Gang Rackets
- [x] Gang Contracts
- [x] Admin Panel
- [x] Modal-based reason/input flows
- [x] Toast notifications and action locking against double submit
- [x] Smart org archetype inference and archetype-themed UI labels/cards

## Dev and Debug Commands
- [x] `/bm_debug_org`
- [x] `/bm_test_audit`
- [x] `/bm_test_webhook`
- [x] `/bm_reload_permissions`
- [x] `/bm_migrate`
- [x] `/bm_seed_demo`
- [x] `/bm_clear_demo`

## Database Coverage
- [x] Core tables: accounts, ledger, audit
- [x] Optional/expansion tables present in migrations for:
- [x] ranks and permissions
- [x] profile and activity
- [x] salary and payroll
- [x] inventory and logs
- [x] uniforms
- [x] markers and garages
- [x] applications and announcements
- [x] admin actions and org state
- [x] taxes and invoices
- [x] scheduled tasks
- [x] gang notoriety, markers, territories, rackets, graffiti, contracts

## Known Constraints
- [!] Built-in custom gang backend is intended for QB/ESX path; QBox/OxCore rely on their gang/group primitives.
- [!] External integration behavior depends on each provider resource API and version.
- [!] Lua compile check (`luac`) is not available in this environment, so runtime validation must be done in-server.
