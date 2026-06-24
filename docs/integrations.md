# Integrations

## Inventory
Config:
- `Config.Integrations.inventory = 'auto' | 'qb-inventory' | 'ox_inventory' | 'qs-inventory' | 'none'`

Behavior:
- `ox_inventory`: stash-backed deposit/withdraw with fallback-safe rollback.
- `qb-inventory` / `qs-inventory`: best-effort stash bridge with DB mirror + audit.

Fallback:
- Internal org inventory tables (`bossmenu_org_inventory`, `bossmenu_org_inventory_logs`) remain authoritative for analytics/logging.

## Clothing / Uniforms
Config:
- `Config.Integrations.clothing = 'auto' | 'qb-clothing' | 'illenium-appearance' | 'fivem-appearance' | 'skinchanger' | 'none'`

Behavior:
- Uniform list/save/delete plus server-triggered `preview/apply/restore`.
- Client attempts native integration apply first, then raw component/prop fallback.

Fallback:
- JSON uniform storage in `bossmenu_org_uniforms` with direct ped component application.

## Banking
Config:
- `Config.Integrations.banking = 'auto' | 'qb-banking' | 'Renewed-Banking' | 'okokBanking' | 'esx_addonaccount' | 'none'`

Fallback:
- Internal society account table: `bossmenu_accounts`.

## Phone
Config:
- `Config.Integrations.phone = 'none' | 'yseries' | 'qb-phone' | 'qs-smartphone' | 'custom'`

Behavior:
- Application status and announcement notifications attempt phone delivery by identifier when integration is available.

## Discord Webhooks
Config:
- `Config.Webhooks.enabled`
- `Config.Webhooks.batchWindowMs`
- `Config.Webhooks.batchSize`
- `Config.Webhooks.urls`

Behavior:
- Business leaders with `manage_webhooks` can configure one Discord webhook per log type from the Webhooks page.
- Admins can configure global catch-all webhooks per log type from the Admin Panel.
- Events are batched by webhook URL, scope, and type before delivery to reduce Discord rate-limit pressure.
- Legacy config webhooks still work and are sent alongside stored business/admin webhook settings.

## Target
Config:
- `Config.Integrations.target = 'auto' | 'ox_target' | 'qb-target' | 'none'`

Also legacy:
- `Config.UseTarget`
- `Config.TargetResource`
