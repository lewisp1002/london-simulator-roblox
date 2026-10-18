"""Builds INSTALL.luau: one block of code that puts every script from src/ into Roblox Studio.

Paste INSTALL.luau into Studio's Command Bar and press Enter. Run this again after changing anything in src/:

    python3 tools/build_installer.py
"""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Same naming rules Rojo uses, so the installer and Rojo always agree
SUFFIXES = [
    (".server.luau", "Script"),
    (".client.luau", "LocalScript"),
    (".luau", "ModuleScript"),
]

HEADER = """\
-- London Simulator installer
-- Paste ALL of this into Roblox Studio's Command Bar and press Enter.
-- It creates every folder and script in the right place, replacing old copies.
-- Made by tools/build_installer.py from the files in src/, so don't edit this file by hand.

local function folder(parent: Instance, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		return existing
	end
	local newFolder = Instance.new("Folder")
	newFolder.Name = name
	newFolder.Parent = parent
	return newFolder
end

-- Names of the scripts this installer puts in each folder, so old ones that were removed or renamed can go
local installed: { [Instance]: { [string]: boolean } } = {}

local function put(parent: Instance, className: string, name: string, source: string)
	local old = parent:FindFirstChild(name)
	if old then
		old:Destroy()
	end
	local newScript: any = Instance.new(className)
	newScript.Name = name
	newScript.Source = source
	newScript.Parent = parent
	installed[parent] = installed[parent] or {}
	installed[parent][name] = true
end

-- Deletes scripts in our folders that aren't in the repo any more (e.g. a script that was renamed)
local function removeOldScripts(parent: Instance)
	local keep = installed[parent] or {}
	for _, child in parent:GetChildren() do
		if child:IsA("LuaSourceContainer") and not keep[child.Name] then
			print("Removed old script " .. child:GetFullName())
			child:Destroy()
		end
	end
end
"""


# Streaming settings live on Workspace in the place file, so the installer sets them. Opportunistic means
# players' devices drop the streets they've left behind (by default they keep everything they've ever seen,
# so the game got slower the longer you drove).
STREAMING = """
workspace.StreamingEnabled = true
pcall(function()
	workspace.StreamingTargetRadius = 900
end)
pcall(function()
	(workspace :: any).StreamOutBehavior = (Enum :: any).StreamOutBehavior.Opportunistic
end)
"""


# An earlier try put photo textures from the UK Map PBR pack on every road, pavement and wall through
# MaterialService. Those images don't load as material textures (roads went almost black), so this removes
# them. Roblox's own 2022 materials (grainy asphalt, herringbone pavement) look right with the colours in TownKit.
MATERIALS = """
do
	local MaterialService = game:GetService("MaterialService")
	for _, info in { { "LdnTarmac", Enum.Material.Asphalt }, { "LdnSlabs", Enum.Material.Pavement }, { "LdnConcrete", Enum.Material.Concrete }, { "LdnSlate", Enum.Material.Slate }, { "LdnRender", Enum.Material.Plaster } } do
		local variant = MaterialService:FindFirstChild(info[1])
		if variant then
			variant:Destroy()
		end
		if MaterialService:GetBaseMaterialOverride(info[2]) == info[1] then
			MaterialService:SetBaseMaterialOverride(info[2], "")
		end
	end
end
"""


def long_string(text: str) -> str:
    level = 0
    while f"]{'=' * level}]" in text:
        level += 1
    eq = "=" * level
    # Luau drops a newline straight after the opening bracket, so the source comes out unchanged
    return f"[{eq}[\n{text}]{eq}]"


def script_class(file: Path) -> tuple[str, str]:
    for suffix, class_name in SUFFIXES:
        if file.name.endswith(suffix):
            if file.name.startswith("init."):
                raise SystemExit(f"{file}: init scripts aren't supported by the installer yet")
            return class_name, file.name[: -len(suffix)]
    raise SystemExit(f"{file}: not a .luau file")


def emit_dir(lines: list[str], directory: Path, var: str, counter: list[int]) -> int:
    count = 0
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            counter[0] += 1
            child_var = f"folder{counter[0]}"
            lines.append(f'local {child_var} = folder({var}, "{entry.name}")')
            count += emit_dir(lines, entry, child_var, counter)
        elif entry.suffix == ".luau":
            class_name, name = script_class(entry)
            source = entry.read_text(encoding="utf-8")
            lines.append(f'put({var}, "{class_name}", "{name}", {long_string(source)})')
            count += 1
    lines.append(f"removeOldScripts({var})")
    return count


def emit_node(lines: list[str], name: str, node: dict, parent_var: str | None, counter: list[int]) -> int:
    counter[0] += 1
    var = f"folder{counter[0]}"
    if parent_var is None:
        lines.append(f'local {var} = game:GetService("{name}")')
    elif "$path" in node:
        lines.append(f'local {var} = folder({parent_var}, "{name}")')
    else:
        lines.append(f'local {var} = {parent_var}:WaitForChild("{name}")')

    count = 0
    if "$path" in node:
        count += emit_dir(lines, ROOT / node["$path"], var, counter)
    for child_name, child in node.items():
        if not child_name.startswith("$"):
            count += emit_node(lines, child_name, child, var, counter)
    return count


def main() -> None:
    project = json.loads((ROOT / "default.project.json").read_text(encoding="utf-8"))
    lines = [HEADER]
    counter = [0]
    count = 0
    for service_name, node in project["tree"].items():
        if not service_name.startswith("$"):
            count += emit_node(lines, service_name, node, None, counter)
    lines.append(STREAMING)
    lines.append(MATERIALS)
    lines.append(f'\nprint("London Simulator installed {count} scripts. Press Play to test!")\n')
    (ROOT / "INSTALL.luau").write_text("\n".join(lines), encoding="utf-8")
    print(f"Wrote INSTALL.luau with {count} scripts")


if __name__ == "__main__":
    main()
