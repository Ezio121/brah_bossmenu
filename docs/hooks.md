# Hooks

Use:
- `exports['brah_bossmenu-main']:RegisterHook(name, eventName)`
- `exports['brah_bossmenu-main']:UnregisterHook(name, hookId)`

The official GitHub download runs as `brah_bossmenu-main` unless you rename the folder. Legacy event names such as `qb-management:server:hook` are still emitted for replacement compatibility.

Core emitted names include:
- `boss_menu_opened`
- `gang_menu_opened`
- `employee_hired`
- `employee_grade_updated`
- `employee_fired`
- `gang_member_hired`
- `gang_member_grade_updated`
- `gang_member_fired`
- `society_deposit`
- `society_withdraw`
- `suspicious_action`

Compatibility names include:
- `OnEmployeeHired`
- `OnEmployeeGradeUpdated`
- `OnEmployeeFired`
- `OnGangMemberHired`
- `OnGangMemberGradeUpdated`
- `OnGangMemberFired`
- `OnApplicationCreated`
- `OnApplicationAccepted`
- `OnApplicationRejected`
- `OnInvoiceCreated`
- `OnInvoicePaid`
- `OnGangNotorietyChanged`
- `OnGangContractAccepted`
- `OnGangContractCompleted`
- `OnGangContractFailed`
- `OnTaxPaid`
- `OnTaxFailed`

Additional operational hooks:
- `uniform_applied`
- `uniform_previewed`
- `territory_capture_started`
- `territory_capture_completed`
- `admin_org_disabled`
- `admin_org_enabled`
