<h1 align="center">Scoop</h1>

<!--<img src="scoop.png" alt="Long live Scoop!"/>-->
<p align="center">
        <a href="https://github.com/ScoopInstaller/Scoop#what-does-scoop-do">Features</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop#installation">Installation</a>
        |
        <a href="https://github.com/ScoopInstaller/Scoop/wiki">Documentation</a>
</p>

---

<p align="center">
    <a href="https://github.com/ScoopInstaller/Scoop">
        <img src="https://img.shields.io/github/languages/code-size/ScoopInstaller/Scoop.svg" alt="Code Size" />
    </a>
    <a href="https://github.com/ScoopInstaller/Scoop">
        <img src="https://img.shields.io/github/repo-size/ScoopInstaller/Scoop.svg" alt="Repository size" />
    </a>
    <a href="https://github.com/ScoopInstaller/Scoop/actions/workflows/ci.yml">
        <img src="https://github.com/ScoopInstaller/Scoop/actions/workflows/ci.yml/badge.svg" alt="Scoop Core CI Tests" />
    </a>
    <a href="https://discord.gg/s9yRQHt">
        <img src="https://img.shields.io/badge/chat-on%20discord-7289DA.svg" alt="Discord Chat" />
    </a>
    <a href="./LICENSE">
        <img src="https://img.shields.io/badge/license-UNLICENSE%20or%20MIT-blue" alt="License" />
    </a>
</p>

Scoop is a command-line installer for Windows.

## What does Scoop do?

Scoop installs apps from the command line with a minimal amount of friction. It:

- Eliminates [User Account Control](https://learn.microsoft.com/windows/security/application-security/application-control/user-account-control/) (UAC) prompt notifications.
- Hides the graphical user interface (GUI) of wizard-style installers.
- Prevents polluting the `PATH` environment variable. Normally, this variable gets cluttered as different apps are installed on the device.
- Avoids unexpected side effects from installing and uninstalling apps.
- Resolves and installs dependencies automatically.
- Performs all the necessary steps to get an app to a working state.

Scoop is quite script-friendly. Your environment can become the way you like by using repeatable setups. For example:

```console
scoop install sudo
sudo scoop install 7zip git openssh --global
scoop install aria2 curl grep sed less touch
scoop install python ruby go perl
```

If you have built software that you would like others to use, Scoop is an alternative to building an installer (like MSI or InnoSetup). You just need to compress your app to a `.zip` file and provide a JSON manifest that describes how to install it.

## Installation

Run the following commands from a regular (non-admin) PowerShell terminal to install Scoop:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
```

**Note**: The first command makes your device allow running the installation and management scripts. This is necessary because Windows 10 client devices restrict execution of any PowerShell scripts by default.

It will install Scoop to its default location:

`C:\Users\<YOUR USERNAME>\scoop`

You can find the complete documentation about the installer, including advanced installation configurations, in [ScoopInstaller/Install](https://github.com/ScoopInstaller/Install). Please create new issues there if you have questions about the installation.

## Multi-connection downloads with `aria2`

Scoop can utilize [`aria2`](https://github.com/aria2/aria2) to use multi-connection downloads. Simply install `aria2` through Scoop and it will be used for all downloads afterward.

```console
scoop install aria2
```

By default, `scoop` displays a warning when running `scoop install` or `scoop update` while `aria2` is enabled. This warning can be suppressed by running `scoop config aria2-warning-enabled false`.

You can tweak the following `aria2` settings with the `scoop config` command:

- aria2-enabled (default: true)
- aria2-warning-enabled (default: true)
- [aria2-retry-wait](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-retry-wait) (default: 2)
- [aria2-split](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-s) (default: 5)
- [aria2-max-connection-per-server](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-x) (default: 5)
- [aria2-min-split-size](https://aria2.github.io/manual/en/html/aria2c.html#cmdoption-k) (default: 5M)
- [aria2-options](https://aria2.github.io/manual/en/html/aria2c.html#options) (default: )

## Inspiration

- [Homebrew](https://brew.sh/)
- [Sub](https://signalvnoise.com/posts/3264-automating-with-convention-introducing-sub)

## What sort of apps can Scoop install?

The apps that are most likely to get installed fine with Scoop are those referred to as "portable" apps. These apps are compressed files which can run standalone after being extracted. This type of apps does not produce side effects like changing the Windows Registry or placing files outside the app directory.

Scoop also supports installer files and their uninstallation methods. Likewise, it can handle single-file apps and PowerShell scripts. These do not even need to be compressed. See the [runat](https://github.com/ScoopInstaller/Main/blob/master/bucket/runat.json) package for an example: it is simply a GitHub gist.

### Contribute to this project

If you would like to improve Scoop by adding features or fixing bugs, please read our [Contributing Guide](https://github.com/ScoopInstaller/.github/blob/main/.github/CONTRIBUTING.md).

### Support this project

If you find Scoop useful and would like to support the ongoing development and maintenance of this project, you can donate here:

- [PayPal](https://www.paypal.com/cgi-bin/webscr?cmd=_s-xclick&hosted_button_id=DM2SUH9EUXSKJ) (one-time donations)

## Known application buckets

The following buckets are known to Scoop:

- [main](https://github.com/ScoopInstaller/Main) - Default bucket which contains popular non-GUI apps.
- [extras](https://github.com/ScoopInstaller/Extras) - Apps that do not fit the main bucket's [criteria](https://github.com/ScoopInstaller/Scoop/wiki/Criteria-for-including-apps-in-the-main-bucket).
- [games](https://github.com/Calinou/scoop-games) - Open-source and freeware video games and game-related tools.
- [nerd-fonts](https://github.com/matthewjberger/scoop-nerd-fonts) -  Nerd Fonts.
- [nirsoft](https://github.com/ScoopInstaller/Nirsoft) - A collection of over 250+ apps from [Nirsoft](https://nirsoft.net).
- [sysinternals](https://github.com/niheaven/scoop-sysinternals) - The Sysinternals suite from [Microsoft](https://learn.microsoft.com/sysinternals/).
- [java](https://github.com/ScoopInstaller/Java) - A collection of Java development kits (JDKs) and Java runtime engines (JREs), Java's virtual machine debugging tools and Java based runtime engines.
- [nonportable](https://github.com/ScoopInstaller/Nonportable) - Non-portable apps (may trigger UAC prompts).
- [php](https://github.com/ScoopInstaller/PHP) - Installers for most versions of PHP.
- [versions](https://github.com/ScoopInstaller/Versions) - Alternative versions of apps found in other buckets.

The `main` bucket is installed by default. You can make use of more buckets by typing:

```console
scoop bucket add <name>
```

For example, to add the `extras` bucket, type:

```console
scoop bucket add extras
```

You would be able to install apps from the `extras` bucket now.

### Managed catalogs

Scoop can restrict new installations to an approved set of buckets. The policy lives in a bucket repository, so the people who control what goes into the catalog also control the policy, and every user picks up changes with `scoop update`. Put a `policy.json` at the root of the bucket:

```json
{
    "allowedBuckets": { "ENV": "https://git.example.com/it/scoop-env" },
    "allowBucketChanges": false,
    "allowPublicBucketDiscovery": false,
    "defaultBucket": "ENV"
}
```

Then, on each machine, add the bucket and name it as the policy source:

```powershell
scoop bucket add ENV https://git.example.com/it/scoop-env
scoop config policyBucket ENV
```

With this policy, Scoop ignores local buckets outside the allowlist, rejects explicit references to them, and rejects standalone manifests from URLs or paths. It also prevents bucket additions and removals, disables known-bucket listing and remote search, and resolves unqualified app names from `ENV` first. Apps installed before the policy from another source can still be listed, inspected, and uninstalled, but `scoop status` reports them as `Source not allowed` and they are not updated.

A bucket that contains `policy.json` changes nothing until `policyBucket` names it. The policy bucket is always allowed. If it is missing or its `policy.json` cannot be read, Scoop fails closed: only the policy bucket can be used or added, and public discovery is off, which is also the bootstrap path on a new machine.

The same four settings can be placed directly in `config.json` instead, and are used as the fallback for any key the policy omits. `allowedBuckets` accepts a list of names, an object pinning each name to a repository, or on the command line a comma-separated string such as `ENV,internal` or `ENV=https://git.example.com/it/scoop-env`. A pinned bucket is only used when its local clone has that origin, and `scoop bucket add` refuses any other repository for that name. If the SQLite cache is enabled, it is reconciled with the allowlist whenever the policy or the setting changes and on every `scoop update`.

Scoop runs in user space, so these settings are a policy against untrusted sources, not a security boundary against the user. They do not stop a user who edits the configuration file or their local bucket clone, points the `SCOOP` environment variable at another root, or replaces Scoop Core. Deployments that need a hard boundary get it from a global install with file permissions and application control. The design notes at the top of the managed catalog section in `lib/buckets.ps1` record the decisions and their reasons.

## Other application buckets

Many other application buckets hosted on GitHub can be found on [ScoopSearch](https://scoop.sh/) or via [other search engines](https://rasa.github.io/scoop-directory/#other-search-engines).
