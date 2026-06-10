# Migration Guide

## Replacing `qb-management`
1. Ensure this resource name remains `qb-management` or keep `provide 'qb-management'`.
2. Stop old `qb-management` resource.
3. Start this resource after framework + `oxmysql`.
4. Verify `Config.Framework='auto'` unless forcing.

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
