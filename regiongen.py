#!/usr/bin/env python3
"""
regiongen.py

Library-first procedural region generator.

Design goals:
- Deterministic output via --seed.
- Boring, human-editable JSON.
- Simple shapes that play nice with:
    - settlement_namegen.py
    - npcgen.py
    - towngen.py
    - dungeongen.py
- Color-based tile map in JSON for real rendering.
- Optional ASCII / ANSI views for quick debugging.
- Supports:
    - 'continent' mode: one main landmass with rivers (default).
    - 'archipelago' mode: multiple islands.

Usage (CLI):
    python regiongen.py --width 60 --height 40 --years 400 --seed 123 --output region.json
    python regiongen.py --mode continent --ansi
    python regiongen.py --mode archipelago --ascii

Usage (library):
    from regiongen import RegionGenerator
    gen = RegionGenerator(width=60, height=40, years=400, seed=123, mode="continent")
    data = gen.generate_region()
"""

import argparse
import json
import math
import random
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from settlement_namegen import SettlementNameGenerator


class RegionGenerator:
    def __init__(
        self,
        width: int = 60,
        height: int = 40,
        years: int = 400,
        seed: Optional[int] = None,
        sea_level: float = 0.35,
        mode: str = "continent",  # 'continent' or 'archipelago'
        settlement_namer: Optional[SettlementNameGenerator] = None,
    ):
        self.width = width
        self.height = height
        self.years = years
        self.base_sea_level = sea_level
        self.mode = mode if mode in ("continent", "archipelago") else "continent"

        if seed is None:
            seed = random.randint(0, 999999)
        self.seed = seed
        self.rng = random.Random(seed)

        if settlement_namer is None:
            data_path = Path(__file__).parent / "settlement_name_data.json"
            self.settlement_namer = SettlementNameGenerator(data_file=str(data_path))
        else:
            self.settlement_namer = settlement_namer

        self.tiles: List[Dict] = []
        self.realms: Dict[str, Dict] = {}
        self.settlements: Dict[str, Dict] = {}
        self.events: List[Dict] = []
        self.roads: List[Dict] = []
        self.ruins: List[Dict] = []

    # ================= PUBLIC API =================

    def generate_region(self) -> Dict:
        self._generate_base_tiles()
        self._spawn_initial_realms()
        self._simulate_history()
        self._derive_settlements()
        self._derive_roads()
        self._derive_ruins()

        color_rows, color_legend = self._build_color_map()

        return {
            "schema": "region.v1",
            "seed": self.seed,
            "width": self.width,
            "height": self.height,
            "years": self.years,
            "mode": self.mode,
            "tiles": self.tiles,
            "realms": list(self.realms.values()),
            "settlements": list(self.settlements.values()),
            "roads": self.roads,
            "ruins": self.ruins,
            "events": self.events,
            "color_map": {
                "rows": color_rows,
                "legend": color_legend,
            },
        }

    # ================= TILES & BIOMES =================

    def _generate_base_tiles(self) -> None:
        """
        Generate elevation, moisture, biome, and water.

        continent:
            - One dominant landmass.
            - Enforce that only the largest landmass survives.
        archipelago:
            - Multiple blobs (previous behavior).
        """

        if self.mode == "continent":
            # Single big continent-ish shape centered in the map.
            cx = (self.width - 1) / 2.0
            cy = (self.height - 1) / 2.0
            max_r = max(self.width, self.height) / 2.2  # radius-ish

            for y in range(self.height):
                for x in range(self.width):
                    dx = x - cx
                    dy = y - cy
                    dist = math.sqrt(dx * dx + dy * dy)

                    # Core: closer to center => higher base elevation
                    base = 1.0 - (dist / max_r)

                    # Gentle edge falloff and clamp
                    base = max(0.0, min(1.0, base))

                    # Add some noisy bumps so coastlines wiggle
                    bump1 = (self.rng.random() - 0.5) * 0.25
                    bump2 = (self.rng.random() - 0.5) * 0.15 * (base + 0.3)
                    e = base + bump1 + bump2

                    e = max(0.0, min(1.0, e))

                    # Moisture: loose north/south band + noise
                    lat_factor = 1.0 - abs((y / (self.height - 1)) - 0.5) * 1.6
                    m = lat_factor + (self.rng.random() - 0.5) * 0.4
                    m = max(0.0, min(1.0, m))

                    # Initial water guess using base_sea_level
                    water = e < self.base_sea_level
                    biome = self._choose_biome(e, m, water)

                    self.tiles.append(
                        {
                            "x": x,
                            "y": y,
                            "elevation": round(e, 3),
                            "moisture": round(m, 3),
                            "biome": biome,
                            "water": water,
                            "river": False,
                            "realm_id": None,
                            "settlement_id": None,
                        }
                    )

            # Important: enforce ONE main landmass; kill stray islands.
            self._enforce_continent_connectivity()

        else:
            # ARCHIPELAGO: multi-blob version (similar to earlier behavior).
            num_masses = max(2, (self.width * self.height) // 800)
            centers = [
                (
                    self.rng.randint(0, self.width - 1),
                    self.rng.randint(0, self.height - 1),
                    self.rng.uniform(8, 16),
                )
                for _ in range(num_masses)
            ]

            for y in range(self.height):
                for x in range(self.width):
                    e = 0.0
                    for cx, cy, rad in centers:
                        dx = x - cx
                        dy = y - cy
                        d = math.sqrt(dx * dx + dy * dy)
                        contrib = max(0.0, 1.0 - (d / rad))
                        if contrib > e:
                            e = contrib

                    e += (self.rng.random() - 0.5) * 0.15
                    e = max(0.0, min(1.0, e))

                    lat_factor = 1.0 - abs((y / (self.height - 1)) - 0.5) * 1.6
                    m = lat_factor + (self.rng.random() - 0.5) * 0.4
                    m = max(0.0, min(1.0, m))

                    water = e < self.base_sea_level
                    biome = self._choose_biome(e, m, water)

                    self.tiles.append(
                        {
                            "x": x,
                            "y": y,
                            "elevation": round(e, 3),
                            "moisture": round(m, 3),
                            "biome": biome,
                            "water": water,
                            "river": False,
                            "realm_id": None,
                            "settlement_id": None,
                        }
                    )

        # Now carve rivers on the final land/water layout.
        self._carve_rivers(count=max(4, (self.width * self.height) // 700))

    def _enforce_continent_connectivity(self) -> None:
        """
        Ensure there's a single dominant landmass.

        - Find all connected components of non-water tiles.
        - Keep the largest as land.
        - Convert all smaller components to ocean.

        This directly kills stray islands so you get a true "region" to play in.
        """
        # Build adjacency on current land tiles
        land_indices = [i for i, t in enumerate(self.tiles) if not t["water"]]
        if not land_indices:
            return

        visited = set()
        components: List[List[int]] = []

        for start in land_indices:
            if start in visited:
                continue
            stack = [start]
            comp = []
            visited.add(start)
            while stack:
                idx = stack.pop()
                comp.append(idx)
                x = self.tiles[idx]["x"]
                y = self.tiles[idx]["y"]
                for n in self._neighbors(x, y):
                    n_idx = self._idx(n["x"], n["y"])
                    if n_idx not in visited and not self.tiles[n_idx]["water"]:
                        visited.add(n_idx)
                        stack.append(n_idx)
            components.append(comp)

        if len(components) <= 1:
            return

        # Keep largest as continent; other land -> water
        components.sort(key=len, reverse=True)
        main = set(components[0])

        for comp in components[1:]:
            for idx in comp:
                t = self.tiles[idx]
                t["water"] = True
                t["biome"] = "ocean"
                t["river"] = False
                t["realm_id"] = None
                t["settlement_id"] = None

    def _choose_biome(self, e: float, m: float, water: bool) -> str:
        if water:
            return "ocean"
        if e > 0.85:
            return "mountain"
        if e > 0.7:
            return "highland"
        if m < 0.2:
            return "desert"
        if m < 0.45:
            return "grassland"
        if m < 0.75:
            return "temperate_forest"
        return "wetlands"

    def _carve_rivers(self, count: int) -> None:
        """Pick some high tiles and run downhill-ish paths to water."""
        land_tiles = [t for t in self.tiles if not t["water"] and t["elevation"] > 0.6]
        if not land_tiles:
            return

        self.rng.shuffle(land_tiles)
        starts = land_tiles[:count]

        for start in starts:
            x, y = start["x"], start["y"]
            for _ in range(80):  # max length
                idx = self._idx(x, y)
                tile = self.tiles[idx]
                tile["river"] = True

                neighbors = self._neighbors(x, y)
                if not neighbors:
                    break

                next_tile = min(
                    neighbors,
                    key=lambda t: t["elevation"]
                    + (0 if t["water"] else 0.05 * self.rng.random()),
                )

                if next_tile["water"]:
                    break
                if next_tile["elevation"] > tile["elevation"] and not tile["water"]:
                    break

                x, y = next_tile["x"], next_tile["y"]

    # ================= REALMS & HISTORY =================

    def _spawn_initial_realms(self) -> None:
        fertile = [
            t
            for t in self.tiles
            if not t["water"]
            and t["biome"] in ("grassland", "temperate_forest", "wetlands")
        ]
        self.rng.shuffle(fertile)

        target_realms = max(2, min(6, (self.width * self.height) // 1200))
        used: List[Tuple[int, int]] = []

        for i in range(target_realms * 2):
            if len(self.realms) >= target_realms:
                break
            if i >= len(fertile):
                break

            tile = fertile[i]
            x, y = tile["x"], tile["y"]

            if any(abs(x - ux) + abs(y - uy) < 6 for (ux, uy) in used):
                continue

            rid = f"realm_{len(self.realms) + 1}"
            realm = {
                "id": rid,
                "name": self._make_realm_name(len(self.realms)),
                "color": self._random_color(),
                "capital_settlement_id": None,
                "founded_year": 0,
                "dissolved_year": None,
                "culture": "lowland",
                "notes": [],
            }
            self.realms[rid] = realm
            used.append((x, y))
            tile["realm_id"] = rid

        if not self.realms and fertile:
            tile = fertile[0]
            rid = "realm_1"
            self.realms[rid] = {
                "id": rid,
                "name": self._make_realm_name(0),
                "color": self._random_color(),
                "capital_settlement_id": None,
                "founded_year": 0,
                "dissolved_year": None,
                "culture": "lowland",
                "notes": [],
            }
            tile["realm_id"] = rid

    def _simulate_history(self) -> None:
        if not self.realms:
            return

        step = max(10, self.years // 30)
        current_year = 0

        for rid in self.realms:
            self.realms[rid]["strength"] = 1.0

        while current_year < self.years:
            current_year += step
            self._realm_expansion_tick(current_year)
            if self.rng.random() < 0.35:
                self._random_crisis(current_year)

        for r in self.realms.values():
            r.pop("strength", None)

    def _realm_expansion_tick(self, year: int) -> None:
        tiles_by_realm: Dict[str, List[Dict]] = {}
        for t in self.tiles:
            rid = t["realm_id"]
            if rid:
                tiles_by_realm.setdefault(rid, []).append(t)

        for rid, realm_tiles in tiles_by_realm.items():
            size = len(realm_tiles)
            realm = self.realms.get(rid)
            if not realm:
                continue

            desired_growth = max(1, size // 12)
            attempts = 0
            grown = 0

            self.rng.shuffle(realm_tiles)
            for t in realm_tiles:
                if grown >= desired_growth:
                    break
                for n in self._neighbors(t["x"], t["y"]):
                    if n["water"] or n["biome"] == "mountain":
                        continue
                    if n["realm_id"] is None:
                        n["realm_id"] = rid
                        grown += 1
                    elif n["realm_id"] != rid:
                        other_id = n["realm_id"]
                        other_size = len(tiles_by_realm.get(other_id, [])) or 1
                        chance = 0.4 * (size / (size + other_size))
                        if self.rng.random() < chance:
                            n["realm_id"] = rid
                            grown += 1
                attempts += 1
                if attempts > desired_growth * 6:
                    break

            if size > (self.width * self.height) * 0.18 and all(
                not (
                    e["type"] == "EMPIRE_PEAK" and rid in e.get("realm_ids", [])
                )
                for e in self.events
            ):
                realm["notes"].append(
                    f"Once ruled as a dominant realm around year {year}."
                )
                self.events.append(
                    {
                        "id": f"event_empire_{rid}_{year}",
                        "year": year,
                        "type": "EMPIRE_PEAK",
                        "realm_ids": [rid],
                        "settlement_id": None,
                        "summary": f"{realm['name']} reached its greatest extent.",
                    }
                )

    def _random_crisis(self, year: int) -> None:
        realm_ids = [rid for rid in self.realms if self._realm_tile_count(rid) > 0]
        if not realm_ids:
            return

        rid = self.rng.choice(realm_ids)
        realm = self.realms[rid]
        tiles = [t for t in self.tiles if t["realm_id"] == rid]
        if not tiles:
            return

        crisis_type = self.rng.choice(["PLAGUE", "CIVIL_WAR", "SUCCESSION"])

        if crisis_type in ("PLAGUE", "SUCCESSION"):
            border_tiles = [t for t in tiles if self._is_border_tile(t)]
            if not border_tiles:
                return
            self.rng.shuffle(border_tiles)
            cut = max(1, len(tiles) // self.rng.randint(6, 10))
            for t in border_tiles[:cut]:
                t["realm_id"] = None
            summary = f"{realm['name']} lost territory to internal crisis."
        else:
            if len(self.realms) > 8 or len(tiles) < 12:
                return
            new_id = f"realm_{len(self.realms) + 1}"
            name = self._make_realm_name(len(self.realms))
            color = self._random_color()
            self.realms[new_id] = {
                "id": new_id,
                "name": name,
                "color": color,
                "capital_settlement_id": None,
                "founded_year": year,
                "dissolved_year": None,
                "culture": realm.get("culture", "lowland"),
                "notes": [f"Splintered from {realm['name']} in civil war."],
            }
            self.rng.shuffle(tiles)
            for t in tiles[: len(tiles) // 2]:
                t["realm_id"] = new_id
            summary = f"Civil war split {realm['name']}, creating {name}."

        self.events.append(
            {
                "id": f"event_{crisis_type}_{rid}_{year}",
                "year": year,
                "type": crisis_type,
                "realm_ids": [rid],
                "settlement_id": None,
                "summary": summary,
            }
        )

    # ================= SETTLEMENTS, ROADS, RUINS =================

    def _derive_settlements(self) -> None:
        tiles_by_realm: Dict[str, List[Dict]] = {}
        for t in self.tiles:
            rid = t["realm_id"]
            if rid:
                tiles_by_realm.setdefault(rid, []).append(t)

        sid_counter = 1

        for rid, realm_tiles in tiles_by_realm.items():
            if not realm_tiles:
                continue

            fertile = [
                t
                for t in realm_tiles
                if not t["water"]
                and t["biome"] in ("grassland", "temperate_forest", "wetlands")
            ]
            candidates = fertile or realm_tiles
            cap_tile = self._most_central_tile(candidates)

            cap_id = f"settlement_{sid_counter}"
            sid_counter += 1

            cap_name = self._make_settlement_name(kind="capital")
            capital = {
                "id": cap_id,
                "name": cap_name,
                "type": "city",
                "tile": [cap_tile["x"], cap_tile["y"]],
                "realm_id": rid,
                "founded_year": 0,
                "population": self._pop_estimate("city"),
                "tags": ["capital"],
                "history": [f"Founded as the seat of {self.realms[rid]['name']}."],
            }

            self.settlements[cap_id] = capital
            self.realms[rid]["capital_settlement_id"] = cap_id
            cap_tile["settlement_id"] = cap_id

            size = len(realm_tiles)
            extra = min(3, max(1, size // 80))
            placed = 0

            self.rng.shuffle(realm_tiles)
            for t in realm_tiles:
                if placed >= extra:
                    break
                if t["settlement_id"] or t["water"]:
                    continue

                score = 0
                if t["river"]:
                    score += 2
                if t["biome"] in ("grassland", "temperate_forest", "wetlands"):
                    score += 1
                if score == 0:
                    continue

                stype = "town" if self.rng.random() < 0.7 else "fort"
                sid = f"settlement_{sid_counter}"
                sid_counter += 1
                name = self._make_settlement_name(kind=stype)

                tags: List[str] = []
                if stype == "fort":
                    tags.append("fortress")
                if t["river"]:
                    tags.append("river_trade")
                if t["biome"] == "wetlands":
                    tags.append("marsh_edge")

                self.settlements[sid] = {
                    "id": sid,
                    "name": name,
                    "type": stype,
                    "tile": [t["x"], t["y"]],
                    "realm_id": rid,
                    "founded_year": self.rng.randint(
                        10, max(20, self.years // 2)
                    ),
                    "population": self._pop_estimate(stype),
                    "tags": tags,
                    "history": [],
                }

                t["settlement_id"] = sid
                placed += 1

    def _derive_roads(self) -> None:
        for realm in self.realms.values():
            cap_id = realm.get("capital_settlement_id")
            if not cap_id or cap_id not in self.settlements:
                continue
            cap = self.settlements[cap_id]
            cx, cy = cap["tile"]

            for s in self.settlements.values():
                if s["realm_id"] != realm["id"] or s["id"] == cap_id:
                    continue
                sx, sy = s["tile"]
                path = self._line_between(cx, cy, sx, sy)
                self.roads.append(
                    {
                        "from": cap_id,
                        "to": s["id"],
                        "tiles": path,
                        "type": "road",
                    }
                )

    def _derive_ruins(self) -> None:
        border_tiles = [
            t
            for t in self.tiles
            if not t["water"]
            and self._is_border_tile(t)
            and not t["settlement_id"]
        ]
        self.rng.shuffle(border_tiles)
        target = min(5, len(border_tiles) // 30)

        for i in range(target):
            t = border_tiles[i]
            ruin_id = f"ruin_{i + 1}"
            name = self._make_settlement_name(kind="ruin")
            self.ruins.append(
                {
                    "id": ruin_id,
                    "name": name,
                    "tile": [t["x"], t["y"]],
                    "origin_settlement_id": None,
                    "destroyed_year": self.rng.randint(
                        max(5, self.years // 4), self.years
                    ),
                    "cause": self.rng.choice(
                        ["CIVIL_WAR", "RAID", "PLAGUE", "ARCANE_DISASTER"]
                    ),
                    "tags": ["haunted", "contested_border"],
                    "notes": ["Legends speak of lost crowns and unquiet dead."],
                }
            )

    # ================= COLOR MAP (JSON) =================

    def _build_color_map(self):
        biome_colors = {
            "mountain": "#888888",
            "highland": "#aa8c5f",
            "grassland": "#7fbf3f",
            "temperate_forest": "#2e8b57",
            "wetlands": "#3b6b6b",
            "desert": "#d9c27f",
        }

        deep_ocean = "#1b3b6f"
        shallow_ocean = "#3465a4"
        river_color = "#3f8dd9"
        city_color = "#ffcc00"
        town_color = "#ffd966"
        fort_color = "#ff9900"
        ruin_color = "#cc6666"

        ruin_positions = {tuple(r["tile"]) for r in self.ruins}
        settlements_by_pos = {tuple(s["tile"]): s for s in self.settlements.values()}

        rows: List[List[str]] = []

        for y in range(self.height):
            row: List[str] = []
            for x in range(self.width):
                t = self.tiles[self._idx(x, y)]
                pos = (x, y)

                if pos in ruin_positions:
                    color = ruin_color
                elif pos in settlements_by_pos:
                    st = settlements_by_pos[pos]
                    if st["type"] == "city":
                        color = city_color
                    elif st["type"] == "town":
                        color = town_color
                    elif st["type"] == "fort":
                        color = fort_color
                    else:
                        color = town_color
                else:
                    if t["water"]:
                        if t["elevation"] < self.base_sea_level * 0.6:
                            color = deep_ocean
                        else:
                            color = shallow_ocean
                    elif t["river"]:
                        color = river_color
                    else:
                        color = biome_colors.get(t["biome"], "#000000")

                row.append(color)
            rows.append(row)

        legend = {
            deep_ocean: "deep_ocean",
            shallow_ocean: "shallow_ocean",
            river_color: "river",
            biome_colors["grassland"]: "grassland",
            biome_colors["temperate_forest"]: "temperate_forest",
            biome_colors["highland"]: "highland",
            biome_colors["mountain"]: "mountain",
            biome_colors["desert"]: "desert",
            biome_colors["wetlands"]: "wetlands",
            city_color: "city",
            town_color: "town",
            fort_color: "fort",
            ruin_color: "ruin",
        }

        return rows, legend

    # ================= HELPERS =================

    def _make_settlement_name(self, kind: str) -> str:
        return self.settlement_namer.generate_name(kind=kind, rng=self.rng)

    def _idx(self, x: int, y: int) -> int:
        return y * self.width + x

    def _neighbors(self, x: int, y: int) -> List[Dict]:
        out: List[Dict] = []
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < self.width and 0 <= ny < self.height:
                out.append(self.tiles[self._idx(nx, ny)])
        return out

    def _realm_tile_count(self, rid: str) -> int:
        return sum(1 for t in self.tiles if t["realm_id"] == rid)

    def _is_border_tile(self, t: Dict) -> bool:
        rid = t["realm_id"]
        if not rid:
            return False
        for n in self._neighbors(t["x"], t["y"]):
            if n["realm_id"] != rid:
                return True
        return False

    def _most_central_tile(self, tiles: List[Dict]) -> Dict:
        if not tiles:
            return self.tiles[0]
        avg_x = sum(t["x"] for t in tiles) / len(tiles)
        avg_y = sum(t["y"] for t in tiles) / len(tiles)
        return min(
            tiles,
            key=lambda t: (t["x"] - avg_x) ** 2 + (t["y"] - avg_y) ** 2,
        )

    def _line_between(self, x0: int, y0: int, x1: int, y1: int) -> List[List[int]]:
        points: List[List[int]] = []
        dx = abs(x1 - x0)
        dy = -abs(y1 - y0)
        sx = 1 if x0 < x1 else -1
        sy = 1 if y0 < y1 else -1
        err = dx + dy
        x, y = x0, y0
        while True:
            points.append([x, y])
            if x == x1 and y == y1:
                break
            e2 = 2 * err
            if e2 >= dy:
                err += dy
                x += sx
            if e2 <= dx:
                err += dx
                y += sy
        return points

    def _random_color(self) -> str:
        r = self.rng.randint(80, 220)
        g = self.rng.randint(80, 220)
        b = self.rng.randint(80, 220)
        return f"#{r:02x}{g:02x}{b:02x}"

    def _pop_estimate(self, stype: str) -> int:
        if stype == "city":
            return self.rng.randint(8000, 25000)
        if stype == "town":
            return self.rng.randint(1500, 6000)
        if stype == "fort":
            return self.rng.randint(400, 1800)
        return self.rng.randint(200, 800)

    def _make_realm_name(self, index: int) -> str:
        prefixes = ["Ashen", "Grey", "Varn", "Eld", "Kor", "Thorn", "Mar", "Sel", "Drak"]
        suffixes = ["hold", "reach", "marches", "realm", "clan", "throne", "dominion"]
        return f"{self.rng.choice(prefixes)}{self.rng.choice(suffixes)}"


# ================= ANSI MAP (TERMINAL COLOR) =================

def print_ansi_map(data: Dict) -> None:
    RESET = "\033[0m"
    COLORS = {
        "deep_ocean": "\033[48;5;17m",
        "shallow_ocean": "\033[48;5;19m",
        "river": "\033[48;5;25m",
        "mountain": "\033[48;5;244m",
        "highland": "\033[48;5;137m",
        "grassland": "\033[48;5;70m",
        "temperate_forest": "\033[48;5;28m",
        "wetlands": "\033[48;5;23m",
        "desert": "\033[48;5;179m",
        "city": "\033[48;5;220m",
        "town": "\033[48;5;229m",
        "fort": "\033[48;5;208m",
        "ruin": "\033[48;5;52m",
        "unknown": "\033[48;5;196m",
    }

    w = data["width"]
    h = data["height"]
    tiles = data["tiles"]
    settlements = {tuple(s["tile"]): s for s in data["settlements"]}
    ruins = {tuple(r["tile"]) for r in data["ruins"]}

    for y in range(h):
        row = []
        for x in range(w):
            pos = (x, y)
            t = tiles[y * w + x]

            if pos in ruins:
                bg = COLORS["ruin"]
            elif pos in settlements:
                st = settlements[pos]
                if st["type"] == "city":
                    bg = COLORS["city"]
                elif st["type"] == "town":
                    bg = COLORS["town"]
                elif st["type"] == "fort":
                    bg = COLORS["fort"]
                else:
                    bg = COLORS["town"]
            else:
                if t["water"]:
                    if t["elevation"] < 0.15:
                        bg = COLORS["deep_ocean"]
                    else:
                        bg = COLORS["shallow_ocean"]
                elif t["river"]:
                    bg = COLORS["river"]
                else:
                    biome = t["biome"]
                    if biome == "mountain":
                        bg = COLORS["mountain"]
                    elif biome == "highland":
                        bg = COLORS["highland"]
                    elif biome == "grassland":
                        bg = COLORS["grassland"]
                    elif biome == "temperate_forest":
                        bg = COLORS["temperate_forest"]
                    elif biome == "wetlands":
                        bg = COLORS["wetlands"]
                    elif biome == "desert":
                        bg = COLORS["desert"]
                    else:
                        bg = COLORS["unknown"]

            row.append(f"{bg}  {RESET}")
        print("".join(row))


# ================= CLI =================

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Procedural region generator (library-first)."
    )
    parser.add_argument("--width", type=int, default=60, help="Map width in tiles.")
    parser.add_argument("--height", type=int, default=40, help="Map height in tiles.")
    parser.add_argument("--years", type=int, default=400, help="Length of simulated history.")
    parser.add_argument("--seed", type=int, default=None, help="Random seed.")
    parser.add_argument("--output", type=str, default="region.json", help="Output JSON file path.")
    parser.add_argument(
        "--mode",
        type=str,
        default="continent",
        choices=["continent", "archipelago"],
        help="Landmass style: 'continent' (one main landmass) or 'archipelago' (many islands).",
    )
    parser.add_argument(
        "--ascii",
        action="store_true",
        help="Print simple ASCII (~ water, . land, C/t/F/x for settlements/ruins).",
    )
    parser.add_argument(
        "--ansi",
        action="store_true",
        help="Print colorized map using ANSI background colors.",
    )

    args = parser.parse_args()

    gen = RegionGenerator(
        width=args.width,
        height=args.height,
        years=args.years,
        seed=args.seed,
        mode=args.mode,
    )
    data = gen.generate_region()

    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    if args.ascii:
        w = data["width"]
        h = data["height"]
        tiles = data["tiles"]
        settlements = {tuple(s["tile"]): s for s in data["settlements"]}
        ruins = {tuple(r["tile"]) for r in data["ruins"]}

        for y in range(h):
            row_chars = []
            for x in range(w):
                pos = (x, y)
                t = tiles[y * w + x]
                if pos in ruins:
                    ch = "x"
                elif pos in settlements:
                    st = settlements[pos]
                    if st["type"] == "city":
                        ch = "C"
                    elif st["type"] == "town":
                        ch = "t"
                    elif st["type"] == "fort":
                        ch = "F"
                    else:
                        ch = "t"
                elif t["water"]:
                    ch = "~"
                else:
                    ch = "."
                row_chars.append(ch)
            print("".join(row_chars))

    if args.ansi:
        print_ansi_map(data)

    print(f"Region generated with seed={data['seed']} in {args.mode} mode -> {args.output}")


if __name__ == "__main__":
    main()
