# Exports

## Boss
- `OpenBossMenu(source, jobName?)`
- `IsBoss(source, jobName?)`
- `HasBossPermission(source, jobName, permission)`
- `GetEmployees(jobName)`
- `HireEmployee(jobName, targetSource, grade, actorIdentifier)`
- `FireEmployee(jobName, targetIdentifier, reason, actorIdentifier)`
- `AddSocietyMoney(jobName, amount, reason, actorIdentifier)`
- `RemoveSocietyMoney(jobName, amount, reason, actorIdentifier)`
- `GetSocietyBalance(jobName)`

## Gang
- `OpenGangMenu(source, gangName?)`
- `IsGangLeader(source, gangName?)`
- `HasGangPermission(source, gangName, permission)`
- `GetGangMembers(gangName)`
- `AddGangMember(gangName, targetSource, grade, actorIdentifier)`
- `RemoveGangMember(gangName, targetIdentifier, reason, actorIdentifier)`
- `GetGangNotoriety(gangName)`
- `AddGangNotoriety(gangName, amount, reason, actorIdentifier)`
- `RemoveGangNotoriety(gangName, amount, reason, actorIdentifier)`

## Common
- `RegisterHook(name, eventName)`
- `UnregisterHook(name, hookId)`
- `CreateAuditLog(orgType, orgName, action, actor, target, metadata)`
- `GetOrgConfig(orgType, orgName)`

## Integration
- `SubmitApplication(orgType, orgName, payload)`
- `CreateInvoice(orgType, orgName, payload, actor)`
- `SetInvoiceStatus(orgType, orgName, invoiceId, status, actor, note)`
