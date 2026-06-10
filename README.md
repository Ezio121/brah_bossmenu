# Brah Boss Menu

<p align="center">
  <img src="https://dummyimage.com/1200x300/111827/ffffff&text=Brah+Boss+Menu" alt="Brah Boss Menu Banner" />
</p>

<p align="center">
  <b>High-performance boss and gang management for FiveM</b><br>
  Rewritten for minimal runtime dependencies, strong server-side security, and multi-framework support.
</p>

<p align="center">
  <a href="https://github.com/Ezio121/brah_bossmenu">
    <img src="https://img.shields.io/badge/GitHub-brah__bossmenu-181717?style=for-the-badge&logo=github" alt="GitHub Repo">
  </a>
  <a href="https://discord.gg/fudBnzsyfp">
    <img src="https://img.shields.io/badge/Discord-Join%20Support-5865F2?style=for-the-badge&logo=discord&logoColor=white" alt="Discord">
  </a>
  <a href="https://paypal.me/thatonefalcon">
    <img src="https://img.shields.io/badge/Donate-PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white" alt="Donate with PayPal">
  </a>
</p>

---

## Overview

**Brah Boss Menu** is a lightweight, secure, and framework-flexible boss management system for FiveM servers.

It is designed as a modern replacement for legacy boss, gang, and society management resources while keeping compatibility with common existing resource names and entry events.

This resource focuses on:

- Minimal runtime dependencies
- Automatic framework detection
- Secure server-authoritative actions
- Boss and gang management
- Offline employee/member handling
- Society finance and audit trails
- Optional built-in gang backend for QB/ESX
- Replacement compatibility for existing resources

---

## Runtime Dependencies

Required:

- One supported framework:
  - `qb-core`
  - `es_extended`
  - `qbx_core`
  - `ox_core`
- [`oxmysql`](https://github.com/overextended/oxmysql)

No heavy dependency stack. No unnecessary runtime bloat.

---

## Supported Frameworks

Brah Boss Menu supports the following frameworks:

| Framework | Status |
|---|---|
| QBCore | Supported |
| ESX | Supported |
| QBox | Supported |
| OxCore | Supported |

Framework selection is automatic by default:

```lua
Config.Framework = 'auto'
````

You can also force a framework manually in `config.lua`.

---

## Features

> Full feature details are available in `featurelist.md`.

Core highlights:

* Boss menu support
* Gang menu support
* Online and offline employee/member lists
* Hire, fire, promote, and demote actions
* Society account support
* Deposit and withdraw management
* Ledger tracking
* Audit logging
* Permission checks
* Session-based action security
* Per-action rate limiting
* Optional built-in gang backend
* Legacy resource replacement compatibility
* Debug/dev commands for testing and migration

---

## Security Model

Brah Boss Menu is built around a server-authoritative security model.

Every sensitive action is validated server-side.

Security features include:

* Server-authoritative actions only
* Short-lived session token required for every post-open action
* Per-action rate limiting buckets
* Full server-side permission checks before every management action
* Full server-side permission checks before every finance action
* Input sanitization
* Numeric bound checks on all write actions
* Audit rows for important actions

The client is treated as untrusted.

---

## Database Tables

The resource automatically creates required database tables on startup.

Main tables:

```txt
bossmenu_accounts
bossmenu_ledger
bossmenu_audit
bossmenu_webhook_settings
```

Additional phase expansion tables are also created using the `bossmenu_*` prefix for systems such as:

* Ranks
* Permissions
* Profiles
* Payroll
* Inventory
* Uniforms
* Applications
* Admin tools
* Taxes and invoices
* Gang systems

---

## Configuration

Edit `config.lua` to configure the resource.

Important options:

```lua
Config.Framework = 'auto'
Config.MinBossGrade = 4

Config.useinbuiltgangframes = true

Config.BossMenus = {}
Config.GangMenus = {}

Config.Security = {}
Config.Performance = {}
Config.Database = {}
```

### Important Config Entries

| Config                        | Description                                       |
| ----------------------------- | ------------------------------------------------- |
| `Config.Framework`            | Auto-detect or force a specific framework         |
| `Config.MinBossGrade`         | Minimum grade required for boss access            |
| `Config.useinbuiltgangframes` | Use framework gang data or internal gang backend  |
| `Config.BossMenus`            | Boss menu locations                               |
| `Config.GangMenus`            | Gang menu locations                               |
| `Config.Security`             | Session, rate limit, and action security settings |
| `Config.Performance`          | Performance-related settings                      |
| `Config.Database`             | Offline query schema per framework                |

`Config.Database` is especially useful for servers using custom OxCore or heavily modified framework schemas.

---

## Built-In Gang Backend

For QB/ESX servers, Brah Boss Menu can use an internal gang backend.

Set:

```lua
Config.useinbuiltgangframes = false
```

When disabled, the script uses internal gang tables:

```txt
bossmenu_gangs
bossmenu_gang_members
```

This mode is fully managed inside the resource while still keeping legacy gang menu entry events compatible.

Use this if your server does not want to rely on framework-native gang data.

---

## Resource Replacement Compatibility

The manifest includes `provide` declarations for common legacy resources:

```txt
qb-management
qb-gangmenu
esx_society
```

This allows Brah Boss Menu to act as a drop-in style replacement for servers migrating away from older management resources.

---

## Dev Commands

Debug commands are available only when:

```lua
Config.Debug = true
```

The caller must also have admin/ACE permission.

Available commands:

```txt
/bm_debug_org boss|gang <name>
/bm_test_audit
/bm_test_webhook
/bm_reload_permissions
/bm_migrate
/bm_seed_demo
/bm_clear_demo
```

These commands are intended for development, testing, migration, and troubleshooting.

Do not enable debug mode on production servers unless you know what you are doing.

---

## Installation

1. Download or clone the resource:

```bash
git clone https://github.com/Ezio121/brah_bossmenu.git
```

2. Place the resource in your server resources folder.

Example:

```txt
resources/[standalone]/brah_bossmenu
```

3. Ensure required dependencies are started before this resource.

Example:

```cfg
ensure oxmysql
ensure qb-core
ensure brah_bossmenu
```

For ESX, QBox, or OxCore, ensure your framework resource instead of `qb-core`.

4. Edit `config.lua`.

5. Start your server.

6. Check your server console for database setup and framework detection messages.

---

## Example `server.cfg`

### QBCore

```cfg
ensure oxmysql
ensure qb-core
ensure brah_bossmenu
```

### ESX

```cfg
ensure oxmysql
ensure es_extended
ensure brah_bossmenu
```

### QBox

```cfg
ensure oxmysql
ensure qbx_core
ensure brah_bossmenu
```

### OxCore

```cfg
ensure oxmysql
ensure ox_core
ensure brah_bossmenu
```

---

## Recommended Use

Brah Boss Menu is ideal for servers that want:

* A modern boss menu
* A secure management backend
* Multi-framework compatibility
* Offline member management
* Society finance tracking
* Gang management
* Reduced dependency bloat
* A replacement path for older resources

---

## Support

Need help, want to report a bug, or want to suggest a feature?

Join the Discord:

[![Join Discord](https://img.shields.io/badge/Discord-Join%20the%20Community-5865F2?style=for-the-badge&logo=discord&logoColor=white)](https://discord.gg/fudBnzsyfp)

Or open an issue on GitHub:

[GitHub Issues](https://github.com/Ezio121/brah_bossmenu/issues)

---

## Donate

This resource is released for free.

If it helps your server, saves you development time, or replaces a paid resource for you, donations are appreciated but never required.

[![Donate with PayPal](https://img.shields.io/badge/Donate-PayPal-00457C?style=for-the-badge&logo=paypal&logoColor=white)](https://paypal.me/thatonefalcon)

---

## Contributing

Pull requests, suggestions, bug reports, and improvements are welcome.

Before contributing:

* Keep changes clean and focused
* Avoid adding unnecessary dependencies
* Maintain server-side validation for sensitive actions
* Test across supported frameworks when possible
* Follow the existing style and structure

---

## Roadmap

Planned or expandable systems include:

* Advanced rank permissions
* Payroll management
* Employee profiles
* Gang profile systems
* Inventory-related management
* Uniform management
* Applications
* Admin tools
* Taxes and invoices
* Expanded webhook settings
* More framework-specific schema options

---

## Credits

Created by **BrahCorp / Falcon**.

Repository:

https://github.com/Ezio121/brah_bossmenu

---

## License

This project is released as a free FiveM resource.

Please check the repository license file for usage terms.