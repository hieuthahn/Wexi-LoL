# Wexi LoL fork: multi-source augment stats

This fork adds remote ARAM Mayhem augment statistics from several providers to [Wexi LoL](https://github.com/Loeraw/Wexi-LoL). Upstream features stay unchanged. Read the compliance section before you install or share a build.

## What the fork adds

- Champion-specific augment win rate, pick rate and sample size from up to five providers, plus HexMayhem's global numbers.
- Settings → Augment data sources → Primary source picks which provider leads the badge (default playaram.gg). When that provider lacks the augment, or you choose "Pool all sources", the badge shows the pooled estimate below.
- The pooled estimate pools every champion-specific provider on the guide's patch, for example `T1 · 胜率 57.1% · +2.3 · 选用率 8.0% · gộp 2 nguồn`. `+2.3` is the gap in percentage points from the champion's average.
- Pooling compares each source's win rate with that source's own champion average, because sources differ by region and rank (Mayhem:Meta runs about 3 points above AramHex for Jax). It combines those gaps with DerSimonian-Laird random effects, so when sources disagree, AramHex's very large CN sample cannot outvote the others.
- Pooling skips playaram.gg (no sample size), arammeta (top 3 only), HexMayhem (global), rows under 100 games, and providers on another patch. When nothing qualifies, the badge falls back to the first provider with data and labels its patch.
- The guide list shows the leading line in bold, then the pooled line, then one line per provider.
- playaram.gg also feeds three guidance pieces. Editorial combos appear as a second badge under each card (`⚡S Trái Tim Sắt Đá + Thức Tỉnh Tối Thượng`) and as a collapsible "Playstyles & augment combos" section with items and tips. Augments missing from the champion page fall back to playaram's global S+ to D tier. A `▲3.5` or `▼2.1` marks the biggest win-rate moves since the last patch, champion-specific first. Combo tiers are editor ratings, not win rates. The champion page, `/loi-aram-hon-loan` and `/thay-doi-phien-ban` download together and stay cached for 6 hours. Tiers and moves from another patch stay hidden.
- Picks from aram.caoviethoang.me appear as `★ caoviethoang`, separate from statistics.
- Settings → Augment data sources toggles each provider and stores the aramgg API key in macOS Keychain.

## Pick and build help

- The app infers which augment you took from the pointer position when the card triple closes, and lets you fix it: right-click an augment in the guide to mark it, or remove it from the "Taken" strip.
- Each offered card gets `✅ Pick` when it clearly leads (combo with a taken augment first, then at least 1.5 points of win rate) or `⚠` when it trails the best card by 3 points. Close calls get no mark. The app never clicks for you.
- The item build overlay suggests at most two counter-item swaps from the enemy team's damage split and healing, using Data Dragon item data.
- Settings → AI game plan runs your local `claude` (Haiku, low effort) or `codex` (`codex/gpt-6-luna`, low reasoning) once per matchup and again after each taken augment. It never runs while cards are on screen. A plan nudges card verdicts (`AI+2`), adds notes and may replace the item swaps. The app keeps only augment and item IDs it offered, so invented IDs never reach the UI. Prompts carry champion, augment and item names, never player names. The Claude call skips user hooks and plugins but copies the `env` block of `~/.claude/settings.json`, so a configured gateway still applies. In one Jax test, Haiku answered in about 13 s for about $0.004, and Luna answered in about 8 s but mistook an ally for an enemy.

## Providers

Priority runs top to bottom. Without a pooled estimate, the badge uses the first champion-specific provider with data, then falls back to HexMayhem.

| Provider | Access | Per champion | Win rate | Sample size | Region | Terms | Default |
| --- | --- | --- | --- | --- | --- | --- | --- |
| [aramgg](https://aramgg.com) | [Data API](https://data.dtodo.cn/api/v1/en/docs/cf-data-api.md), free key, 200 credits a day | Yes | Yes | Yes | Per record | Documented API | Off until a key is saved |
| [AramHex](https://github.com/czgreat/aramhex-data) | GitHub dataset, `latest.json` then `data-v<seq>` tag | Yes | Yes | Yes | CN | CC BY-NC 4.0 | On |
| [Mayhem:Meta](https://mayhemmeta.com) | Champion page HTML | Yes | Yes | Yes | Not stated | robots.txt allows | On |
| [playaram.gg](https://playaram.gg) | Champion page HTML (`/tuong/`) | Yes | Yes | No | Not stated | robots.txt allows `/tuong/`, blocks `/api/` | On |
| [arammeta](https://arammeta.com) | Public `api/tier-list.json` | Top 3 per rarity | Yes | Yes | TW | No license | Off |
| [HexMayhem](https://hexmayhem.com) | Augment page HTML | No, global | Yes | Yes | Not stated | robots.txt allows | On |
| [aram.caoviethoang.me](https://aram.caoviethoang.me) | Champion page HTML | Editorial picks | No | No | Not applicable | robots.txt allows | On |

Rejected sources:

- MayhemStats: about 14 games per champion each patch, too few to show.
- arammayhem.com: pick rates only, no per-champion data, slug IDs.
- aramkit.com: undocumented `api.aramkit.com`.
- hexgate.app: 3,330 games per patch.
- Hexdata: HTML only, and AramHex already covers the CN server.
- lolhaidou: WeChat mini program.
- cchappy: no reachable domain.
- aramlol.vercel.app: re-publishes the sources above.

No provider verifies Vietnam-server data. playaram.gg and aram.caoviethoang.me appear here because Vietnamese players use them, not because of their match region.

## Network and cache

- Requests start only when the guide loads a Mayhem champion, never while augment cards are on screen.
- Each provider has a freshness window: aramgg 1 hour, HexMayhem 30 minutes, editorial picks 12 hours, the rest 6 hours. The app re-checks freshness at most every five minutes.
- Responses live in `~/Library/Caches/WexiLoL/AugmentStats`. When a request fails, the app reads the last cached copy that still parses.
- aramgg spends 1 credit per uncached champion. After an HTTP 429 the app stops calling aramgg until 00:00 UTC.
- A three-augment lookup takes about 0.006 ms in a debug build (`AugmentStatsSourcesTests`).

## Set up aramgg

1. Sign in at the [developer portal](https://data.dtodo.cn/developer.html) with GitHub and create a key.
2. Open Settings → Augment data sources, enable aramgg, paste the key and press Save API Key.

## Build a fork release

```bash
script/package_fork_dmg.sh 1   # creates dist/Wexi.LoL-<upstream>-vn.1.dmg
```

The script builds the upstream bundle, stamps the version as `<upstream>-vn.<n>`, re-signs it ad hoc and packages a DMG. The update checker reads this fork's GitHub releases, so tag releases `v<upstream>-vn.<n>`.

## Stay in sync with upstream

```bash
git fetch upstream
git merge upstream/main
swift test
```

Fork code lives in new files (`App/RiftCore/AugmentStats*.swift`, `App/RiftOverlay/Augment*.swift`, `script/package_fork_dmg.sh`). Upstream files carry only these edits:

- `GuideViews.swift`: one line adds the settings section, and one view replaces the augment row's stats text.
- `HintOverlay.swift`: three lines attach the store and use its badge text.
- `UpdateChecker.swift`: one line points update checks at this fork.

Expect conflicts only when upstream rewrites those lines.

## Compliance and unresolved risks

- **Riot policy forbids augment win rates.** The League policy at [developer.riotgames.com/docs/lol](https://developer.riotgames.com/docs/lol) lists as unapproved: "Products cannot display win rates for Augments or Arena Mode items. This applies to all websites, applications and overlays." Upstream Wexi LoL already shows augment win rates, and this fork shows more of them. Riot has not approved this app.
- **Real-time overlays.** The same policy rejects apps that "dictate player decisions" and approves overlays with "static data that is available prior to the game". The badge shows pre-game aggregate data but appears during augment selection.
- **Source provenance.** AramHex's author describes collecting CN matches through logged-in accounts on the CN match-history gateway, and arammeta crawls via the League Client API. The fork only downloads their published aggregates.
- **Licenses.** AramHex is CC BY-NC 4.0, so a paid or ad-supported build must drop it. arammeta publishes no license.
- **No account data leaves the machine.** The fork sends only champion IDs and slugs to providers. The aramgg key goes only to `data.dtodo.cn`.
