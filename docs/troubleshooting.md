# Troubleshooting

## NUI opens but actions fail
- Check server console for `rpc error`.
- Verify session lockout state (`Config.Security.lockout*`).
- Ensure permissions for the acting grade are enabled.

## Gang menu inaccessible
- Confirm `Config.EnableGangMenu=true`.
- If using custom gangs, set `Config.useinbuiltgangframes=false` and framework is QB/ESX.
- Check admin org state: disabled organizations cannot open management menus.

## Finance not visible
- Gang mode intentionally hides standard society finance.
- Boss mode requires finance permissions (`view_finance`, `deposit_money`, `withdraw_money`).

## DB errors
- Ensure `oxmysql` is started.
- Run `/bm_migrate` (with `Config.Debug=true` and admin).
- Validate DB user has `CREATE` and `ALTER` rights.

## Webhooks not posting
- Enable both:
  - `Config.Modules.Webhooks=true`
  - `Config.Webhooks.enabled=true`
- Set category URL under `Config.Webhooks.urls`.

## Uniform apply not working
- Verify `Config.Modules.Uniforms=true`.
- Confirm clothing integration mode under `Config.Integrations.clothing`.
- If third-party clothing exports differ, fallback raw component apply still works for freemode peds.
