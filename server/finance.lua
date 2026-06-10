FinanceModule = FinanceModule or {}

local function fmCleanText(value, maxLen)
    local out = tostring(value or '')
    out = out:gsub('[\r\n\t]', ' ')
    out = out:gsub('%s%s+', ' ')
    out = out:gsub('^%s+', ''):gsub('%s+$', '')
    if maxLen and #out > maxLen then
        out = out:sub(1, maxLen)
    end
    return out
end

local function fmMaxAmount()
    local value = Config.Security and (Config.Security.maxMoneyActionAmount or Config.Security.maxAmount) or 5000000
    return tonumber(value) or 5000000
end

local function fmAudit(orgType, orgName, action, actor, target, metadata)
    if AuditModule and AuditModule.Write then
        AuditModule.Write(orgType, orgName, ('%s:%s'):format(orgType, action), actor, target, metadata or {})
        return
    end
    MySQL.insert.await([[INSERT INTO bossmenu_audit (job, action, actor_identifier, target_identifier, payload)
        VALUES (?, ?, ?, ?, ?)]], {
        orgName,
        ('%s:%s'):format(orgType, action),
        actor,
        target,
        metadata and json.encode(metadata) or nil
    })
end

local function fmResourceStarted(name)
    local state = GetResourceState(tostring(name or ''))
    return state == 'started' or state == 'starting'
end

local function fmTaxIntegration()
    local wanted = fmCleanText(Config.Integrations and Config.Integrations.tax or 'none', 32):lower()
    if wanted == 'none' or wanted == '' then
        return 'none'
    end
    if wanted == 'auto' then
        if fmResourceStarted('ap-government') then
            return 'ap-government'
        end
        return 'none'
    end
    if wanted == 'ap-government' or wanted == 'ap_government' then
        return 'ap-government'
    end
    return 'none'
end

local function fmBridgeTaxPayment(orgType, orgName, amount, actor)
    local backend = fmTaxIntegration()
    if backend ~= 'ap-government' then
        return
    end
    if not fmResourceStarted('ap-government') then
        fmAudit(orgType, orgName, 'tax_bridge_ap_government_failed', actor, nil, {
            amount = tonumber(amount) or 0,
            reason = 'resource_not_started'
        })
        return
    end
    local taxLabel = fmCleanText(Config.TaxSettings and Config.TaxSettings.apGovernmentLabel or 'Business', 64)
    if taxLabel == '' then taxLabel = 'Business' end

    local ok, err = pcall(function()
        exports['ap-government']:addCityhallFunds(taxLabel, tonumber(amount) or 0)
    end)

    if ok then
        fmAudit(orgType, orgName, 'tax_bridge_ap_government', actor, nil, {
            amount = tonumber(amount) or 0,
            label = taxLabel
        })
    else
        fmAudit(orgType, orgName, 'tax_bridge_ap_government_failed', actor, nil, {
            amount = tonumber(amount) or 0,
            label = taxLabel,
            error = tostring(err)
        })
    end
end

function FinanceModule.IsEnabled()
    return Config.Modules and Config.Modules.BusinessVault ~= false
end

function FinanceModule.IsPayrollEnabled()
    return Config.Modules and Config.Modules.Payroll == true
end

function FinanceModule.IsTaxEnabled()
    return Config.Modules and Config.Modules.Taxes == true
end

function FinanceModule.IsInvoiceEnabled()
    return Config.Modules and Config.Modules.BillsInvoices == true
end

function FinanceModule.SetSalaryOverride(orgType, orgName, payload, actor)
    local grade = payload and tonumber(payload.grade) or nil
    local identifier = fmCleanText(payload and payload.identifier, 80)
    if identifier == '' then identifier = nil end
    local salaryType = fmCleanText(payload and payload.salaryType, 24)
    local salaryAmount = math.max(0, tonumber(payload and payload.salaryAmount) or 0)
    if salaryAmount > fmMaxAmount() then
        return false, 'Salary too high'
    end
    if salaryType == '' then salaryType = 'custom' end
    if salaryType ~= 'framework' and salaryType ~= 'custom' and salaryType ~= 'unpaid' then
        salaryType = 'custom'
    end
    if salaryType == 'unpaid' then salaryAmount = 0 end
    if identifier == nil and grade == nil then
        return false, 'Provide grade or identifier'
    end

    MySQL.insert.await([[INSERT INTO bossmenu_salary_overrides (org_type, org_name, identifier, grade, salary_type, salary_amount, updated_by)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], {
        orgType, orgName, identifier, grade, salaryType, salaryAmount, actor
    })
    fmAudit(orgType, orgName, 'salary_override_set', actor, identifier, {
        grade = grade,
        salaryType = salaryType,
        salaryAmount = salaryAmount
    })
    TriggerEvent('qb-management:server:hook', 'salary_updated', {
        orgType = orgType,
        orgName = orgName,
        identifier = identifier,
        grade = grade,
        salaryType = salaryType,
        salaryAmount = salaryAmount,
        actor = actor
    })
    return true
end

function FinanceModule.GetSalaryOverride(orgType, orgName, identifier, grade)
    local row = nil
    if identifier and identifier ~= '' then
        row = MySQL.single.await([[SELECT salary_type, salary_amount
            FROM bossmenu_salary_overrides
            WHERE org_type = ? AND org_name = ? AND identifier = ?
            ORDER BY id DESC LIMIT 1]], { orgType, orgName, identifier })
    end
    if row then
        return row
    end
    if grade ~= nil then
        row = MySQL.single.await([[SELECT salary_type, salary_amount
            FROM bossmenu_salary_overrides
            WHERE org_type = ? AND org_name = ? AND identifier IS NULL AND grade = ?
            ORDER BY id DESC LIMIT 1]], { orgType, orgName, tonumber(grade) or 0 })
    end
    return row
end

function FinanceModule.RunPayroll(orgType, orgName, employees, balanceGetter, balanceRemove, actor, mode)
    if not FinanceModule.IsPayrollEnabled() then
        return false, 'Payroll disabled'
    end
    employees = type(employees) == 'table' and employees or {}
    local total = 0
    local payouts = {}
    for _, employee in ipairs(employees) do
        local identifier = employee.identifier
        local level = tonumber(employee.grade and employee.grade.level) or 0
        local override = FinanceModule.GetSalaryOverride(orgType, orgName, identifier, level)
        local salaryType = override and override.salary_type or 'framework'
        local salary = tonumber(override and override.salary_amount) or 0
        if salaryType == 'unpaid' then
            salary = 0
        end
        if salary > 0 then
            payouts[#payouts + 1] = { identifier = identifier, amount = salary }
            total = total + salary
        end
    end

    local balance = tonumber(balanceGetter and balanceGetter(orgName) or 0) or 0
    local paidCount, failedCount = 0, 0
    local partialAllowed = Config.Payroll and Config.Payroll.allowPartial == true

    if total > balance and not partialAllowed then
        MySQL.insert.await([[INSERT INTO bossmenu_payroll_runs (org_type, org_name, run_type, total_amount, paid_count, failed_count, status, metadata, created_by)
            VALUES (?, ?, ?, ?, 0, ?, 'failed', ?, ?)]], {
            orgType, orgName, mode or 'manual', total, #payouts, json.encode({ reason = 'insufficient_funds' }), actor
        })
        fmAudit(orgType, orgName, 'payroll_failed', actor, nil, { reason = 'insufficient_funds', total = total, balance = balance })
        return false, 'Insufficient funds for payroll'
    end

    for _, payout in ipairs(payouts) do
        if balance >= payout.amount then
            local removed = balanceRemove and balanceRemove(orgName, payout.amount) or false
            if removed then
                balance = balance - payout.amount
                paidCount = paidCount + 1
            else
                failedCount = failedCount + 1
            end
        else
            failedCount = failedCount + 1
        end
    end

    local status = failedCount > 0 and (paidCount > 0 and 'partial' or 'failed') or 'completed'
    MySQL.insert.await([[INSERT INTO bossmenu_payroll_runs (org_type, org_name, run_type, total_amount, paid_count, failed_count, status, metadata, created_by)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], {
        orgType,
        orgName,
        mode or 'manual',
        total,
        paidCount,
        failedCount,
        status,
        json.encode({ payouts = payouts }),
        actor
    })
    fmAudit(orgType, orgName, 'payroll_run', actor, nil, {
        total = total,
        paidCount = paidCount,
        failedCount = failedCount,
        status = status
    })
    TriggerEvent('qb-management:server:hook', 'payroll_run', {
        orgType = orgType,
        orgName = orgName,
        total = total,
        paidCount = paidCount,
        failedCount = failedCount,
        status = status,
        actor = actor
    })
    return true, {
        total = total,
        paidCount = paidCount,
        failedCount = failedCount,
        status = status
    }
end

function FinanceModule.GetTaxAccount(orgType, orgName)
    local row = MySQL.single.await([[SELECT org_type, org_name, balance_due, next_due_at, grace_ends_at, metadata, updated_at
        FROM bossmenu_tax_accounts
        WHERE org_type = ? AND org_name = ?
        LIMIT 1]], { orgType, orgName })
    if not row then
        return {
            org_type = orgType,
            org_name = orgName,
            balance_due = 0,
            next_due_at = nil,
            grace_ends_at = nil,
            metadata = {},
            updated_at = nil
        }
    end
    row.balance_due = tonumber(row.balance_due) or 0
    row.metadata = (type(row.metadata) == 'string' and json.decode(row.metadata)) or row.metadata or {}
    return row
end

function FinanceModule.PayTaxDue(orgType, orgName, payload, actor)
    if not FinanceModule.IsTaxEnabled() then
        return false, 'Taxes disabled'
    end

    local tax = FinanceModule.GetTaxAccount(orgType, orgName)
    local due = math.max(0, tonumber(tax.balance_due) or 0)
    if due <= 0 then
        return false, 'No due taxes'
    end

    local amount = tonumber(payload and payload.amount) or due
    amount = math.floor(amount)
    if amount <= 0 then
        return false, 'Invalid tax amount'
    end
    if amount > due then
        amount = due
    end

    MySQL.insert.await('INSERT IGNORE INTO bossmenu_accounts (job, balance) VALUES (?, 0)', { orgName })
    local affected = MySQL.update.await('UPDATE bossmenu_accounts SET balance = balance - ? WHERE job = ? AND balance >= ?', {
        amount, orgName, amount
    })
    if (affected or 0) < 1 then
        fmAudit(orgType, orgName, 'tax_failed', actor, nil, { amount = amount, reason = 'insufficient_funds' })
        TriggerEvent('qb-management:server:hook', 'OnTaxFailed', {
            orgType = orgType,
            orgName = orgName,
            amount = amount,
            reason = 'insufficient_funds',
            actor = actor
        })
        return false, 'Insufficient funds for tax payment'
    end

    local remaining = math.max(0, due - amount)
    MySQL.update.await([[UPDATE bossmenu_tax_accounts
        SET balance_due = ?, updated_at = NOW()
        WHERE org_type = ? AND org_name = ?]], {
        remaining, orgType, orgName
    })

    fmAudit(orgType, orgName, 'tax_paid', actor, nil, {
        amount = amount,
        remaining = remaining
    })
    fmBridgeTaxPayment(orgType, orgName, amount, actor)
    TriggerEvent('qb-management:server:hook', 'OnTaxPaid', {
        orgType = orgType,
        orgName = orgName,
        amount = amount,
        remaining = remaining,
        actor = actor
    })

    return true, {
        paid = amount,
        remaining = remaining,
        tax = FinanceModule.GetTaxAccount(orgType, orgName)
    }
end

function FinanceModule.CreateInvoice(orgType, orgName, payload, actor)
    if not FinanceModule.IsInvoiceEnabled() then
        return false, 'Invoices disabled'
    end
    local targetType = fmCleanText(payload and payload.targetType, 16)
    local targetIdentifier = fmCleanText(payload and payload.targetIdentifier, 80)
    local targetOrg = fmCleanText(payload and payload.targetOrg, 64)
    local amount = tonumber(payload and payload.amount) or 0
    local reason = fmCleanText(payload and payload.reason, 255)
    if amount <= 0 or amount > fmMaxAmount() then
        return false, 'Invalid amount'
    end
    if targetType ~= 'player' and targetType ~= 'organization' then
        return false, 'Invalid target type'
    end
    if targetType == 'player' and targetIdentifier == '' then
        return false, 'Missing player target'
    end
    if targetType == 'organization' and targetOrg == '' then
        return false, 'Missing organization target'
    end

    local invoiceId = MySQL.insert.await([[INSERT INTO bossmenu_bills_invoices (org_type, org_name, issuer_identifier, target_identifier, target_org_type, target_org_name, amount, reason, status, metadata)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'unpaid', ?)]], {
        orgType,
        orgName,
        actor,
        targetIdentifier ~= '' and targetIdentifier or nil,
        targetType == 'organization' and orgType or nil,
        targetType == 'organization' and (targetOrg ~= '' and targetOrg or nil) or nil,
        amount,
        reason ~= '' and reason or nil,
        json.encode({
            targetType = targetType,
            targetIdentifier = targetIdentifier ~= '' and targetIdentifier or nil,
            targetOrg = targetOrg ~= '' and targetOrg or nil
        })
    })
    fmAudit(orgType, orgName, 'invoice_created', actor, targetIdentifier ~= '' and targetIdentifier or targetOrg, {
        invoiceId = invoiceId,
        amount = amount,
        targetType = targetType
    })
    TriggerEvent('qb-management:server:hook', 'OnInvoiceCreated', {
        orgType = orgType,
        orgName = orgName,
        invoiceId = invoiceId,
        amount = amount,
        targetType = targetType,
        actor = actor
    })
    return true, { invoiceId = invoiceId }
end

function FinanceModule.UpdateInvoiceStatus(orgType, orgName, invoiceId, status, actor, note)
    local cleanStatus = fmCleanText(status, 24)
    if cleanStatus ~= 'pending' and cleanStatus ~= 'paid' and cleanStatus ~= 'cancelled' and cleanStatus ~= 'failed' then
        return false, 'Invalid status'
    end
    local row = MySQL.single.await([[SELECT id, amount, target_identifier, target_org_name, status
        FROM bossmenu_bills_invoices
        WHERE id = ? AND org_type = ? AND org_name = ? LIMIT 1]], {
        tonumber(invoiceId) or 0, orgType, orgName
    })
    if not row then
        return false, 'Invoice not found'
    end
    local mapped = cleanStatus == 'pending' and 'unpaid' or cleanStatus
    MySQL.update.await('UPDATE bossmenu_bills_invoices SET status = ?, updated_at = NOW() WHERE id = ?', {
        mapped, row.id
    })
    fmAudit(orgType, orgName, 'invoice_status', actor, row.target_identifier or row.target_org_name, {
        invoiceId = row.id,
        status = mapped,
        note = fmCleanText(note, 255)
    })
    if mapped == 'paid' then
        TriggerEvent('qb-management:server:hook', 'OnInvoicePaid', {
            orgType = orgType,
            orgName = orgName,
            invoiceId = row.id,
            amount = tonumber(row.amount) or 0,
            actor = actor
        })
    end
    return true
end

function FinanceModule.ListInvoices(orgType, orgName, status, limit)
    local where = { 'org_type = ?', 'org_name = ?' }
    local params = { orgType, orgName }
    local cleanStatus = fmCleanText(status, 24)
    if cleanStatus ~= '' and cleanStatus ~= 'all' then
        where[#where + 1] = 'status = ?'
        params[#params + 1] = cleanStatus
    end
    local nLimit = tonumber(limit) or 200
    if nLimit < 1 then nLimit = 1 end
    if nLimit > 1000 then nLimit = 1000 end
    params[#params + 1] = nLimit
    local sql = ([[SELECT id, issuer_identifier, target_identifier, target_org_type, target_org_name, amount, reason, status, metadata, created_at, updated_at
        FROM bossmenu_bills_invoices
        WHERE %s
        ORDER BY id DESC
        LIMIT ?]]):format(table.concat(where, ' AND '))
    local rows = MySQL.query.await(sql, params) or {}
    for i = 1, #rows do
        rows[i].metadata = (type(rows[i].metadata) == 'string' and json.decode(rows[i].metadata)) or rows[i].metadata or {}
    end
    return rows
end

function FinanceModule.SetTaxAccount(orgType, orgName, payload, actor)
    if not FinanceModule.IsTaxEnabled() then
        return false, 'Taxes disabled'
    end
    local amountDue = math.max(0, tonumber(payload and payload.amountDue) or 0)
    local dueAt = fmCleanText(payload and payload.dueAt, 30)
    local graceAt = fmCleanText(payload and payload.graceEndsAt, 30)
    local metadata = type(payload and payload.metadata) == 'table' and payload.metadata or {}
    metadata.updatedBy = actor
    MySQL.insert.await([[INSERT INTO bossmenu_tax_accounts (org_type, org_name, balance_due, next_due_at, grace_ends_at, metadata)
        VALUES (?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE balance_due = VALUES(balance_due), next_due_at = VALUES(next_due_at), grace_ends_at = VALUES(grace_ends_at), metadata = VALUES(metadata), updated_at = NOW()]], {
        orgType, orgName, amountDue, dueAt ~= '' and dueAt or nil, graceAt ~= '' and graceAt or nil, json.encode(metadata)
    })
    fmAudit(orgType, orgName, 'tax_account_set', actor, nil, {
        amountDue = amountDue,
        dueAt = dueAt,
        graceEndsAt = graceAt
    })
    return true
end
