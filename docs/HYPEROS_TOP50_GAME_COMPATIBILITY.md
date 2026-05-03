# HyperOS Top 50 Game Compatibility (Targeted)

Method legend: **Native** (Linux build), **Proton** (Steam Play), **Wine/Lutris**.

| Game | Method | Proton/Wine target | Notes |
|---|---|---|---|
| Counter-Strike 2 | Native | native | Stable on Mesa/NVIDIA; disable overlays if stutter. |
| Dota 2 | Native | native | Vulkan native path preferred. |
| Apex Legends | Proton | Proton Hotfix | EAC-compatible; occasional shader stutter first runs. |
| PUBG: Battlegrounds | Proton | Proton Experimental | Anti-cheat updates may regress. |
| GTA V | Proton | Proton Experimental | Rockstar launcher reliability varies. |
| Rust | Native/Proton | native or Experimental | EAC compatibility can change per update. |
| War Thunder | Native | native | Generally stable. |
| Team Fortress 2 | Native | native | Mature OpenGL path. |
| Path of Exile | Proton | Proton Experimental | Use DX12 renderer + vkd3d for smoother frametimes. |
| Destiny 2 | Unsupported | N/A | Not playable on Linux due to anti-cheat policy. |
| Rainbow Six Siege | Unsupported | N/A | Anti-cheat blocks Linux/Proton. |
| Valorant | Unsupported | N/A | Vanguard kernel anti-cheat unsupported on Linux. |
| Fortnite | Unsupported | N/A | EAC configuration currently blocks Linux clients. |
| Overwatch 2 | Proton | Proton Experimental | Battle.net via Steam/Lutris wrapper. |
| Warframe | Native/Proton | native or Experimental | Native works; Proton may help launcher issues. |
| The Finals | Proton | Proton Hotfix | Easy Anti-Cheat support may vary by season patch. |
| Helldivers 2 | Proton | Proton Experimental | Good with recent Mesa/NVIDIA drivers. |
| Elden Ring | Proton | GE-Proton9 | Stable with fsync and shader pre-cache. |
| Cyberpunk 2077 | Proton | Proton Experimental | VKD3D tuning improves consistency. |
| Baldur's Gate 3 | Native/Proton | native | Vulkan native recommended first. |
| Hogwarts Legacy | Proton | GE-Proton9 | Shader compilation stutter expected initially. |
| Red Dead Redemption 2 | Proton | Proton Experimental | Rockstar launcher + Vulkan recommended. |
| The Witcher 3 | Proton | Proton 9 | DX12 path works via vkd3d-proton. |
| Monster Hunter: World | Proton | Proton 9 | Set launch options conservatively. |
| Monster Hunter Rise | Proton | Proton 9 | Generally stable. |
| Forza Horizon 5 | Proton | Proton Experimental | Works best with current kernel/Mesa. |
| EA Sports FC 25 | Unsupported | N/A | EA anti-cheat prevents Linux play. |
| Call of Duty: Warzone | Unsupported | N/A | Ricochet anti-cheat unsupported on Linux. |
| Call of Duty: MWIII | Unsupported | N/A | Ricochet anti-cheat unsupported on Linux. |
| ARK: Survival Ascended | Proton | Proton Experimental | Heavy GPU/VRAM usage; prefer MangoHud telemetry. |
| ARK: Survival Evolved | Native/Proton | native | Legacy title; CPU bottlenecks common. |
| DayZ | Proton | Proton Experimental | BattlEye support may shift. |
| Dead by Daylight | Proton | Proton Hotfix | Anti-cheat state can change on updates. |
| No Man's Sky | Proton | Proton 9 | Generally excellent compatibility. |
| Civilization VI | Native | native | Stable native path. |
| Stellaris | Native | native | CPU-bound late game; governor helps. |
| Crusader Kings III | Native | native | Stable native path. |
| Total War: Warhammer III | Proton | Proton 9 | Large VRAM footprint. |
| Euro Truck Simulator 2 | Native | native | Stable with OpenGL/Vulkan choices. |
| American Truck Simulator | Native | native | Similar to ETS2 behavior. |
| Rocket League | Proton | Proton 9 | Works via Steam; Epic path via Lutris/Wine. |
| Roblox | Wine/Lutris | Wine-Staging latest | Community-supported only; can break after updates. |
| World of Warcraft | Wine/Lutris | Wine-Staging latest | DX12 mode preferred. |
| Diablo IV | Wine/Lutris | Wine-Staging latest | Battle.net launcher reliability varies. |
| League of Legends | Unsupported | N/A | Vanguard rollout broke Linux support. |
| Genshin Impact | Wine/Lutris | Wine-Staging latest | Launcher anti-tamper updates may break compatibility. |
| Honkai: Star Rail | Wine/Lutris | Wine-Staging latest | Similar anti-tamper caveats. |
| Final Fantasy XIV | Native/Proton | Proton 9 | XIVLauncher or Steam route both viable. |
| Black Desert | Proton | Proton Experimental | EAC behavior can vary. |
| Palworld | Proton | Proton Experimental | Good results on current Proton. |
| Remnant II | Proton | Proton Experimental | GPU-heavy; FSR/upscaling advised. |

## Fallback policy

If a profile is missing or invalid, `hyperos-game-launch` executes the game command directly without profile injections and prints a warning.
