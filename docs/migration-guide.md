# Migration Guide

## Replacing `qb-management`
1. Keep the official downloaded folder/resource name, for example `brah_bossmenu-main`.
2. Keep `provide 'qb-management'` enabled in `fxmanifest.lua`; this is what makes legacy replacement work without renaming the resource.
3. Stop old `qb-management` resource.
4. Start this resource after framework + `oxmysql`.
5. Verify `Config.Framework='auto'` unless forcing.

## Replacing `qb-gangmenu`
1. Keep `provide 'qb-gangmenu'` enabled.
2. Keep `Config.EnableGangMenu=true`.
3. Choose gang backend:
   - `Config.useinbuiltgangframes=true` to use framework gangs.
   - `false` to use internal QB/ESX gang tables.

## Replacing `esx_society`
1. Keep `provide 'esx_society'` enabled.
2. Validate `Config.Database.esx` schema keys if custom ESX DB.

## Data Safety
- All new tables are created with `CREATE TABLE IF NOT EXISTS`.
- Existing `bossmenu_accounts`, `bossmenu_ledger`, `bossmenu_audit`, `bossmenu_gangs`, `bossmenu_gang_members` are preserved.
- Organization enable/disable state is persisted in `bossmenu_org_state`.
- No required data wipe for upgrade.
