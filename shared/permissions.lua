BossPermissions = BossPermissions or {
    open_menu = true,
    view_employees = true,
    hire_employee = true,
    fire_employee = true,
    promote_employee = true,
    demote_employee = true,
    edit_ranks = true,
    edit_permissions = true,
    view_finance = true,
    deposit_money = true,
    withdraw_money = true,
    approve_withdrawals = true,
    view_ledger = true,
    view_inventory = true,
    deposit_items = true,
    withdraw_items = true,
    lock_inventory = true,
    manage_uniforms = true,
    manage_applications = true,
    create_announcements = true,
    manage_markers = true,
    manage_garage = true,
    view_analytics = true,
    manage_bills = true,
    manage_taxes = true,
    view_cameras = true,
    manage_webhooks = true,
}

GangPermissions = GangPermissions or {
    open_menu = true,
    view_members = true,
    invite_member = true,
    kick_member = true,
    promote_member = true,
    demote_member = true,
    edit_ranks = true,
    edit_permissions = true,
    manage_stash = true,
    manage_cash_locker = true,
    manage_markers = true,
    manage_garage = true,
    view_notoriety = true,
    manage_territories = true,
    start_rackets = true,
    manage_graffiti = true,
    accept_contracts = true,
    create_announcements = true,
    view_activity_logs = true,
    view_cameras = true,
    manage_webhooks = true,
}

function GetKnownPermissions(orgType)
    if orgType == 'gang' then
        return GangPermissions
    end
    return BossPermissions
end
