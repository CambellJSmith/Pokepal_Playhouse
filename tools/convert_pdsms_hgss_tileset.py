#!/usr/bin/env python3
"""Convert a Pokemon DS Map Studio .pdsts tileset into Godot-importable OBJ meshes.

This parser mirrors the tagged binary format implemented by PDSMS TilesetIO.java.
It does not require Java or Pokemon DS Map Studio itself.
"""

from __future__ import annotations

import argparse
import json
import shutil
import struct
from dataclasses import dataclass, field
from pathlib import Path
from typing import BinaryIO

TAG_TILE = 0
TAG_IMG_NAME = 1
TAG_PNAME_IMD = 2
TAG_TNAME_IMD = 3
TAG_MAT_NAME = 4
TAG_MATERIAL_START = 9
TAG_MATERIAL_END = 10
TAG_WIDTH = 11
TAG_HEIGHT = 12
TAG_XTILEABLE = 13
TAG_YTILEABLE = 14
TAG_VCOORDS = 15
TAG_TCOORDS = 16
TAG_FINDSQUADS = 17
TAG_FINDSTRIS = 18
TAG_TIDS = 19
TAG_OBJNAME = 21
TAG_NCOORDS = 22
TAG_TOFFSETSQUAD = 24
TAG_TOFFSETSTRI = 25
TAG_SMARTGRID = 26
TAG_GLOBALMAPPING = 27
TAG_GLOBALTEXSCALE = 28
TAG_FOG = 30
TAG_BOTHFACE = 31
TAG_NORMALORIENT = 32
TAG_ALPHA = 33
TAG_TEXGENMODE = 34
TAG_INCLUDE_IN_IMD = 35
TAG_UTILEABLE = 36
TAG_VTILEABLE = 37
TAG_XOFFSET = 38
TAG_YOFFSET = 39
TAG_TEX_TILING_U = 40
TAG_TEX_TILING_V = 41
TAG_COLOR_FORMAT = 42
TAG_LIGHT0 = 43
TAG_LIGHT1 = 44
TAG_LIGHT2 = 45
TAG_LIGHT3 = 46
TAG_RENDER_BORDER = 47
TAG_VERTEX_COLORS = 48
TAG_COLORS = 49
TAG_FINDSQUADS_EXTENDED = 50
TAG_FINDSTRIS_EXTENDED = 51


@dataclass
class Material:
    index: int = -1
    image_name: str = ""
    material_name: str = ""
    palette_name_imd: str = ""
    texture_name_imd: str = ""
    fog: bool = False
    both_faces: bool = False
    uniform_normal_orientation: bool = False
    always_include_in_imd: bool = False
    alpha: int = 31
    texgen_mode: int = 0
    tex_tiling_u: int = 0
    tex_tiling_v: int = 0
    color_format: int = 0
    lights: list[bool] = field(default_factory=lambda: [True, True, True, True])
    render_border: bool = False
    vertex_colors: bool = False


@dataclass
class Face:
    vertex_indices: list[int]
    texture_indices: list[int]
    normal_indices: list[int]
    color_indices: list[int]


@dataclass
class Tile:
    index: int = -1
    width: int = 1
    height: int = 1
    x_tileable: bool = False
    y_tileable: bool = False
    u_tileable: bool = False
    v_tileable: bool = False
    global_mapping: bool = False
    global_tex_scale: float = 1.0
    x_offset: float = 0.0
    y_offset: float = 0.0
    vertices: list[float] = field(default_factory=list)
    texcoords: list[float] = field(default_factory=list)
    normals: list[float] = field(default_factory=list)
    colors: list[float] = field(default_factory=list)
    quad_faces: list[Face] = field(default_factory=list)
    tri_faces: list[Face] = field(default_factory=list)
    texture_ids: list[int] = field(default_factory=list)
    quad_material_offsets: list[int] = field(default_factory=list)
    tri_material_offsets: list[int] = field(default_factory=list)
    obj_name: str = ""


class Reader:
    def __init__(self, stream: BinaryIO) -> None:
        self.stream = stream

    def read_exact(self, size: int) -> bytes:
        data = self.stream.read(size)
        if len(data) != size:
            raise EOFError(f"Expected {size} bytes, got {len(data)}.")
        return data

    def read_i32(self) -> int:
        return struct.unpack(">i", self.read_exact(4))[0]

    def read_f32(self) -> float:
        return struct.unpack(">f", self.read_exact(4))[0]

    def read_scalar_i32(self) -> int:
        size = self.read_i32()
        if size != 1:
            raise ValueError(f"Expected scalar integer element size 1, got {size}.")
        return self.read_i32()

    def read_scalar_f32(self) -> float:
        size = self.read_i32()
        if size != 1:
            raise ValueError(f"Expected scalar float element size 1, got {size}.")
        return self.read_f32()

    def read_bool(self) -> bool:
        return self.read_scalar_i32() == 1

    def read_string(self) -> str:
        size = self.read_i32()
        return self.read_exact(size).decode("utf-8", errors="replace")

    def read_i32_array(self) -> list[int]:
        size = self.read_i32()
        return [self.read_i32() for _ in range(size)]

    def read_f32_array(self) -> list[float]:
        size = self.read_i32()
        return [self.read_f32() for _ in range(size)]

    def read_i32_matrix(self) -> list[list[int]]:
        rows = self.read_i32()
        matrix: list[list[int]] = []
        for _ in range(rows):
            cols = self.read_i32()
            matrix.append([self.read_i32() for _ in range(cols)])
        return matrix

    def read_faces(self, vertex_count: int, extended: bool) -> list[Face]:
        count = self.read_i32()
        faces: list[Face] = []
        for _ in range(count):
            vertex_indices = [self.read_i32() for _ in range(vertex_count)]
            texture_indices = [self.read_i32() for _ in range(vertex_count)]
            normal_indices = [self.read_i32() for _ in range(vertex_count)]
            if extended:
                color_indices = [self.read_i32() for _ in range(vertex_count)]
            else:
                color_indices = [1] * vertex_count
            faces.append(Face(vertex_indices, texture_indices, normal_indices, color_indices))
        return faces


def parse_tileset(path: Path) -> tuple[list[Material], list[Tile], list[list[list[int]]]]:
    materials: list[Material] = []
    tiles: list[Tile] = []
    smart_grids: list[list[list[int]]] = []
    current_material: Material | None = None
    current_tile: Tile | None = None

    with path.open("rb") as stream:
        reader = Reader(stream)
        while True:
            raw_tag = stream.read(1)
            if not raw_tag:
                break
            tag = raw_tag[0]

            if tag == TAG_MATERIAL_START:
                current_material = Material(index=reader.read_scalar_i32())
            elif tag == TAG_MATERIAL_END:
                reader.read_scalar_i32()
                if current_material is None:
                    raise ValueError("Material end encountered before material start.")
                materials.append(current_material)
                current_material = None
            elif tag == TAG_IMG_NAME:
                _require_material(current_material, tag).image_name = reader.read_string()
            elif tag == TAG_MAT_NAME:
                _require_material(current_material, tag).material_name = reader.read_string()
            elif tag == TAG_PNAME_IMD:
                _require_material(current_material, tag).palette_name_imd = reader.read_string()
            elif tag == TAG_TNAME_IMD:
                _require_material(current_material, tag).texture_name_imd = reader.read_string()
            elif tag == TAG_FOG:
                _require_material(current_material, tag).fog = reader.read_bool()
            elif tag == TAG_BOTHFACE:
                _require_material(current_material, tag).both_faces = reader.read_bool()
            elif tag == TAG_NORMALORIENT:
                _require_material(current_material, tag).uniform_normal_orientation = reader.read_bool()
            elif tag == TAG_INCLUDE_IN_IMD:
                _require_material(current_material, tag).always_include_in_imd = reader.read_bool()
            elif tag == TAG_ALPHA:
                _require_material(current_material, tag).alpha = reader.read_scalar_i32()
            elif tag == TAG_TEXGENMODE:
                _require_material(current_material, tag).texgen_mode = reader.read_scalar_i32()
            elif tag == TAG_TEX_TILING_U:
                _require_material(current_material, tag).tex_tiling_u = reader.read_scalar_i32()
            elif tag == TAG_TEX_TILING_V:
                _require_material(current_material, tag).tex_tiling_v = reader.read_scalar_i32()
            elif tag == TAG_COLOR_FORMAT:
                _require_material(current_material, tag).color_format = reader.read_scalar_i32()
            elif tag in (TAG_LIGHT0, TAG_LIGHT1, TAG_LIGHT2, TAG_LIGHT3):
                _require_material(current_material, tag).lights[tag - TAG_LIGHT0] = reader.read_bool()
            elif tag == TAG_RENDER_BORDER:
                _require_material(current_material, tag).render_border = reader.read_bool()
            elif tag == TAG_VERTEX_COLORS:
                _require_material(current_material, tag).vertex_colors = reader.read_bool()
            elif tag == TAG_SMARTGRID:
                smart_grids.append(reader.read_i32_matrix())
            elif tag == TAG_TILE:
                if current_tile is not None:
                    tiles.append(current_tile)
                current_tile = Tile(index=reader.read_scalar_i32())
            elif tag == TAG_WIDTH:
                _require_tile(current_tile, tag).width = reader.read_scalar_i32()
            elif tag == TAG_HEIGHT:
                _require_tile(current_tile, tag).height = reader.read_scalar_i32()
            elif tag == TAG_XTILEABLE:
                _require_tile(current_tile, tag).x_tileable = reader.read_bool()
            elif tag == TAG_YTILEABLE:
                _require_tile(current_tile, tag).y_tileable = reader.read_bool()
            elif tag == TAG_UTILEABLE:
                _require_tile(current_tile, tag).u_tileable = reader.read_bool()
            elif tag == TAG_VTILEABLE:
                _require_tile(current_tile, tag).v_tileable = reader.read_bool()
            elif tag == TAG_GLOBALMAPPING:
                _require_tile(current_tile, tag).global_mapping = reader.read_bool()
            elif tag == TAG_GLOBALTEXSCALE:
                _require_tile(current_tile, tag).global_tex_scale = reader.read_scalar_f32()
            elif tag == TAG_XOFFSET:
                _require_tile(current_tile, tag).x_offset = reader.read_scalar_f32()
            elif tag == TAG_YOFFSET:
                _require_tile(current_tile, tag).y_offset = reader.read_scalar_f32()
            elif tag == TAG_VCOORDS:
                _require_tile(current_tile, tag).vertices = reader.read_f32_array()
            elif tag == TAG_TCOORDS:
                _require_tile(current_tile, tag).texcoords = reader.read_f32_array()
            elif tag == TAG_NCOORDS:
                _require_tile(current_tile, tag).normals = reader.read_f32_array()
            elif tag == TAG_COLORS:
                _require_tile(current_tile, tag).colors = reader.read_f32_array()
            elif tag == TAG_FINDSQUADS:
                _require_tile(current_tile, tag).quad_faces = reader.read_faces(4, False)
            elif tag == TAG_FINDSTRIS:
                _require_tile(current_tile, tag).tri_faces = reader.read_faces(3, False)
            elif tag == TAG_FINDSQUADS_EXTENDED:
                _require_tile(current_tile, tag).quad_faces = reader.read_faces(4, True)
            elif tag == TAG_FINDSTRIS_EXTENDED:
                _require_tile(current_tile, tag).tri_faces = reader.read_faces(3, True)
            elif tag == TAG_TIDS:
                _require_tile(current_tile, tag).texture_ids = reader.read_i32_array()
            elif tag == TAG_TOFFSETSQUAD:
                _require_tile(current_tile, tag).quad_material_offsets = reader.read_i32_array()
            elif tag == TAG_TOFFSETSTRI:
                _require_tile(current_tile, tag).tri_material_offsets = reader.read_i32_array()
            elif tag == TAG_OBJNAME:
                _require_tile(current_tile, tag).obj_name = reader.read_string()
            else:
                raise ValueError(f"Unknown PDSMS tileset tag {tag} at byte offset {stream.tell() - 1}.")

    if current_tile is not None:
        tiles.append(current_tile)
    return materials, tiles, smart_grids


def _require_material(material: Material | None, tag: int) -> Material:
    if material is None:
        raise ValueError(f"Material tag {tag} encountered outside a material block.")
    return material


def _require_tile(tile: Tile | None, tag: int) -> Tile:
    if tile is None:
        raise ValueError(f"Tile tag {tag} encountered before the first tile block.")
    return tile


def face_groups(faces: list[Face], offsets: list[int], group_count: int) -> list[list[Face]]:
    if group_count <= 0:
        return []
    normalized_offsets = list(offsets)
    while len(normalized_offsets) < group_count:
        normalized_offsets.append(len(faces))
    result: list[list[Face]] = []
    for index in range(group_count):
        start = normalized_offsets[index] if index < len(normalized_offsets) else len(faces)
        end = normalized_offsets[index + 1] if index + 1 < len(normalized_offsets) else len(faces)
        start = max(0, min(start, len(faces)))
        end = max(start, min(end, len(faces)))
        result.append(faces[start:end])
    return result


def write_tile_obj(tile: Tile, materials: list[Material], output_dir: Path, texture_dir_name: str) -> str:
    tile_name = f"tile_{tile.index:03d}"
    obj_path = output_dir / f"{tile_name}.obj"
    mtl_path = output_dir / f"{tile_name}.mtl"

    with obj_path.open("w", encoding="utf-8", newline="\n") as obj:
        obj.write(f"# Generated from PDSMS tile {tile.index}: {tile.obj_name}\n")
        obj.write(f"mtllib {mtl_path.name}\n")
        obj.write(f"o {tile_name}\n")

        for offset in range(0, len(tile.vertices), 3):
            values = tile.vertices[offset:offset + 3]
            if len(values) == 3:
                obj.write(f"v {values[0]:.9g} {values[1]:.9g} {values[2]:.9g}\n")
        for offset in range(0, len(tile.texcoords), 2):
            values = tile.texcoords[offset:offset + 2]
            if len(values) == 2:
                obj.write(f"vt {values[0]:.9g} {values[1]:.9g}\n")
        for offset in range(0, len(tile.normals), 3):
            values = tile.normals[offset:offset + 3]
            if len(values) == 3:
                obj.write(f"vn {values[0]:.9g} {values[1]:.9g} {values[2]:.9g}\n")

        quad_groups = face_groups(tile.quad_faces, tile.quad_material_offsets, len(tile.texture_ids))
        tri_groups = face_groups(tile.tri_faces, tile.tri_material_offsets, len(tile.texture_ids))
        for group_index, material_id in enumerate(tile.texture_ids):
            obj.write(f"usemtl material_{material_id:03d}\n")
            if group_index < len(quad_groups):
                for face in quad_groups[group_index]:
                    obj.write(_obj_face_line(face))
            if group_index < len(tri_groups):
                for face in tri_groups[group_index]:
                    obj.write(_obj_face_line(face))

    with mtl_path.open("w", encoding="utf-8", newline="\n") as mtl:
        for material_id in tile.texture_ids:
            if material_id < 0 or material_id >= len(materials):
                continue
            material = materials[material_id]
            alpha = max(0.0, min(float(material.alpha) / 31.0, 1.0))
            image_name = Path(material.image_name.replace("\\", "/")).name
            mtl.write(f"newmtl material_{material_id:03d}\n")
            mtl.write("Ka 1.0 1.0 1.0\n")
            mtl.write("Kd 1.0 1.0 1.0\n")
            mtl.write("Ks 0.0 0.0 0.0\n")
            mtl.write(f"d {alpha:.6f}\n")
            mtl.write(f"map_Kd ../{texture_dir_name}/{image_name}\n\n")
    return obj_path.name


def _obj_face_line(face: Face) -> str:
    tokens: list[str] = []
    for index in range(len(face.vertex_indices)):
        vertex_index = face.vertex_indices[index]
        texture_index = face.texture_indices[index] if index < len(face.texture_indices) else 0
        normal_index = face.normal_indices[index] if index < len(face.normal_indices) else 0
        if texture_index > 0 and normal_index > 0:
            tokens.append(f"{vertex_index}/{texture_index}/{normal_index}")
        elif texture_index > 0:
            tokens.append(f"{vertex_index}/{texture_index}")
        elif normal_index > 0:
            tokens.append(f"{vertex_index}//{normal_index}")
        else:
            tokens.append(str(vertex_index))
    return "f " + " ".join(tokens) + "\n"


def copy_textures(materials: list[Material], source_dir: Path, texture_dir: Path) -> list[str]:
    texture_dir.mkdir(parents=True, exist_ok=True)
    copied: list[str] = []
    seen: set[str] = set()
    for material in materials:
        raw_name = material.image_name.replace("\\", "/")
        source_path = source_dir / raw_name
        if not source_path.exists():
            source_path = source_dir / Path(raw_name).name
        if not source_path.exists():
            continue
        destination = texture_dir / source_path.name
        if destination.name in seen:
            continue
        shutil.copy2(source_path, destination)
        seen.add(destination.name)
        copied.append(destination.name)
    return sorted(copied)


def tile_bounds(tile: Tile) -> dict[str, list[float]]:
    if len(tile.vertices) < 3:
        return {"min": [0.0, 0.0, 0.0], "max": [0.0, 0.0, 0.0]}
    xs = tile.vertices[0::3]
    ys = tile.vertices[1::3]
    zs = tile.vertices[2::3]
    return {
        "min": [min(xs), min(ys), min(zs)],
        "max": [max(xs), max(ys), max(zs)],
    }


def write_catalog(
    source_tileset: Path,
    materials: list[Material],
    tiles: list[Tile],
    smart_grids: list[list[list[int]]],
    output_dir: Path,
    obj_names: dict[int, str],
    copied_textures: list[str],
) -> None:
    catalog = {
        "format": "pokepal-hgss-pdsms-catalog-v1",
        "source_tileset": source_tileset.name,
        "tile_count": len(tiles),
        "material_count": len(materials),
        "smart_grid_count": len(smart_grids),
        "textures": copied_textures,
        "materials": [
            {
                "id": index,
                "image": material.image_name,
                "name": material.material_name,
                "alpha": material.alpha,
                "both_faces": material.both_faces,
            }
            for index, material in enumerate(materials)
        ],
        "tiles": [
            {
                "id": tile.index,
                "source_name": tile.obj_name,
                "mesh": f"tiles/{obj_names[tile.index]}",
                "width": tile.width,
                "height": tile.height,
                "x_tileable": tile.x_tileable,
                "y_tileable": tile.y_tileable,
                "u_tileable": tile.u_tileable,
                "v_tileable": tile.v_tileable,
                "global_mapping": tile.global_mapping,
                "global_texture_scale": tile.global_tex_scale,
                "offset": [tile.x_offset, tile.y_offset],
                "material_ids": tile.texture_ids,
                "bounds": tile_bounds(tile),
                "quad_count": len(tile.quad_faces),
                "triangle_count": len(tile.tri_faces),
            }
            for tile in tiles
        ],
        "smart_grids": smart_grids,
    }
    with (output_dir / "catalog.json").open("w", encoding="utf-8") as handle:
        json.dump(catalog, handle, indent=2)
        handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("tileset", type=Path, help="Path to Tileset_2_HGSS_Overworld.pdsts")
    parser.add_argument("source_dir", type=Path, help="Directory containing the PDSMS textures")
    parser.add_argument("output_dir", type=Path, help="Destination for generated Godot assets")
    args = parser.parse_args()

    tileset_path = args.tileset.resolve()
    source_dir = args.source_dir.resolve()
    output_dir = args.output_dir.resolve()
    tile_output_dir = output_dir / "tiles"
    texture_output_dir = output_dir / "textures"

    if not tileset_path.is_file():
        raise SystemExit(f"Tileset file not found: {tileset_path}")
    if not source_dir.is_dir():
        raise SystemExit(f"Tileset source directory not found: {source_dir}")

    if output_dir.exists():
        shutil.rmtree(output_dir)
    tile_output_dir.mkdir(parents=True, exist_ok=True)

    materials, tiles, smart_grids = parse_tileset(tileset_path)
    if not tiles:
        raise SystemExit("No tiles were parsed from the PDSMS tileset.")

    copied_textures = copy_textures(materials, source_dir, texture_output_dir)
    obj_names: dict[int, str] = {}
    for tile in tiles:
        obj_names[tile.index] = write_tile_obj(tile, materials, tile_output_dir, "textures")

    write_catalog(
        tileset_path,
        materials,
        tiles,
        smart_grids,
        output_dir,
        obj_names,
        copied_textures,
    )

    print(f"Converted {len(tiles)} HGSS tiles.")
    print(f"Copied {len(copied_textures)} texture files.")
    print(f"Extracted {len(smart_grids)} PDSMS smart-drawing grids.")
    print(f"Output: {output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
