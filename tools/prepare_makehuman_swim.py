#!/usr/bin/env python3
"""Convert verified MakeHuman CC0 data into weighted, UV-textured swim GLBs.

This is an original format converter. It does not import or copy MakeHuman's
AGPL application code. Run after the source files in provenance.json are cached.
The original body, targets, rig, weights, eyes and fitting surface are CC0 data.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
from pathlib import Path
import shutil
import struct
import urllib.request
import zipfile

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
CORE_COMMIT = "a8bc2d54ff0ac92e78ff71431b1023eda42bf482"
CORE = ROOT / "data/cache/human_assets/makehuman" / CORE_COMMIT
SYSTEM = ROOT / "data/cache/human_assets/makehuman/system_assets_cc0_20240414"
OUT = ROOT / "game/assets/vendor/makehuman_swim"


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def fetch_originals():
    """Restore ignored original-data cache from checked-in, SHA-pinned provenance."""
    manifest = json.loads((OUT / "provenance.json").read_text())
    records = manifest["source_files"]
    archives = {}

    class HTTPRangeFile(io.RawIOBase):
        def __init__(self, record):
            self.url = record["archive_url"]
            headers = urllib.request.urlopen(urllib.request.Request(self.url, method="HEAD"), timeout=40).headers
            self.size, self.etag = int(headers["Content-Length"]), headers.get("ETag")
            if self.size != record["archive_bytes"] or self.etag != record["archive_etag"]:
                raise ValueError("Official system archive changed; do not silently replace pinned original data")
            self.pos = 0

        def seekable(self):
            return True

        def seek(self, amount, mode=0):
            self.pos = amount if mode == 0 else (self.pos + amount if mode == 1 else self.size + amount)
            return self.pos

        def tell(self):
            return self.pos

        def read(self, amount=-1):
            amount = self.size - self.pos if amount < 0 else min(amount, self.size - self.pos)
            if amount == 0:
                return b""
            req = urllib.request.Request(self.url, headers={"Range": f"bytes={self.pos}-{self.pos + amount - 1}", "If-Range": self.etag})
            with urllib.request.urlopen(req, timeout=60) as response:
                content = response.read()
                if response.status != 206 or len(content) != amount:
                    raise ValueError("Official asset server did not honour selected-member range read")
            self.pos += amount
            return content

    for record in records:
        path = ROOT / record["file"]
        if path.exists() and digest(path) == record["sha256"]:
            continue
        if "url" in record:
            content = urllib.request.urlopen(record["url"], timeout=60).read()
        else:
            url = record["archive_url"]
            if url not in archives:
                archives[url] = zipfile.ZipFile(HTTPRangeFile(record))
            content = archives[url].read(record["archive_member"])
        if len(content) != record["bytes"] or hashlib.sha256(content).hexdigest() != record["sha256"]:
            raise ValueError("Source size or SHA does not match pinned original: " + record["file"])
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    for directory in (CORE, SYSTEM):
        prefix = str(directory.relative_to(ROOT)) + "/"
        (directory / "DOWNLOADS.json").write_text(json.dumps([r for r in records if r["file"].startswith(prefix)], indent=2) + "\n")


def obj(path):
    verts, uv, groups = [], [], {}
    group = "default"
    for line in Path(path).read_text().splitlines():
        row = line.split()
        if not row:
            continue
        if row[0] == "v":
            verts.append([float(x) for x in row[1:4]])
        elif row[0] == "vt":
            uv.append([float(row[1]), 1.0 - float(row[2])])
        elif row[0] == "g":
            group = row[1]
        elif row[0] == "f":
            face = []
            for token in row[1:]:
                p = token.split("/")
                face.append((int(p[0]) - 1, int(p[1]) - 1 if len(p) > 1 and p[1] else 0))
            groups.setdefault(group, []).append(face)
    return np.asarray(verts, dtype=float), np.asarray(uv, dtype=float), groups


def unit(v, fallback=(1, 0, 0)):
    length = np.linalg.norm(v)
    return v / length if length > 1e-10 else np.array(fallback, dtype=float)


def alias(name):
    central = {"root": "Pelvis", "spine05": "Spine", "spine04": "Spine1", "spine03": "Spine2", "spine02": "Spine3", "spine01": "Spine4", "head": "Head"}
    if name in central:
        return "Bip01 " + central[name]
    if name.endswith((".L", ".R")):
        part, side = name[:-2], name[-1]
        main = {"upperleg01": "Thigh", "lowerleg01": "Calf", "foot": "Foot", "upperarm01": "UpperArm", "lowerarm01": "Forearm", "wrist": "Hand"}
        if part in main:
            return f"Bip01 {side} {main[part]}"
        if part.startswith("finger"):
            return f"Bip01 {side} Finger{part[6:]}"
    return name


def quaternion(matrix):
    # Numerically stable rotation matrix -> glTF quaternion [x,y,z,w].
    m = matrix
    if np.trace(m) > 0:
        s = math.sqrt(float(np.trace(m) + 1.0)) * 2
        q = [(m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s, (m[1, 0] - m[0, 1]) / s, s / 4]
    else:
        i = int(np.argmax(np.diag(m)))
        if i == 0:
            s = math.sqrt(float(1 + m[0, 0] - m[1, 1] - m[2, 2])) * 2
            q = [s / 4, (m[0, 1] + m[1, 0]) / s, (m[0, 2] + m[2, 0]) / s, (m[2, 1] - m[1, 2]) / s]
        elif i == 1:
            s = math.sqrt(float(1 + m[1, 1] - m[0, 0] - m[2, 2])) * 2
            q = [(m[0, 1] + m[1, 0]) / s, s / 4, (m[1, 2] + m[2, 1]) / s, (m[0, 2] - m[2, 0]) / s]
        else:
            s = math.sqrt(float(1 + m[2, 2] - m[0, 0] - m[1, 1])) * 2
            q = [(m[0, 2] + m[2, 0]) / s, (m[1, 2] + m[2, 1]) / s, s / 4, (m[1, 0] - m[0, 1]) / s]
    return unit(np.asarray(q), (0, 0, 0, 1)).tolist()


def smooth_normals(verts, faces):
    normals = np.zeros_like(verts)
    for face in faces:
        for i in range(1, len(face) - 1):
            a, b, c = [face[k][0] for k in (0, i, i + 1)]
            normal = np.cross(verts[b] - verts[a], verts[c] - verts[a])
            for index in (a, b, c):
                normals[index] += normal
    lengths = np.linalg.norm(normals, axis=1)
    normals /= np.maximum(lengths[:, None], 1e-12)
    return normals


def clip(poly, height, keep_above):
    """Interpolate position/UV/full source bone weights at a garment hem."""
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a_in = a[0][1] >= height - 1e-9 if keep_above else a[0][1] <= height + 1e-9
        b_in = b[0][1] >= height - 1e-9 if keep_above else b[0][1] <= height + 1e-9
        if a_in:
            result.append(a)
        if a_in != b_in:
            t = (height - a[0][1]) / (b[0][1] - a[0][1])
            result.append(tuple(x + (y - x) * t for x, y in zip(a, b)))
    return result


def clip_armhole(poly, arm_ids, threshold=.30):
    """Cut the arm-weight contour, retaining interpolated boundary vertices.

    Whole-face rejection makes saw teeth on the shoulder. Each shared source
    edge now intersects the same scalar contour at the same point; position,
    UV, normal and the full163 influence vector are interpolated together.
    """
    result = []
    for a, b in zip(poly, poly[1:] + poly[:1]):
        a_value, b_value = a[3][arm_ids].sum(), b[3][arm_ids].sum()
        a_in, b_in = a_value <= threshold, b_value <= threshold
        if a_in:
            result.append(a)
        if a_in != b_in:
            t = (threshold - a_value) / (b_value - a_value)
            result.append(tuple(x + (y - x) * t for x, y in zip(a, b)))
    return result


class GLB:
    def __init__(self, names, parents, rests, label):
        self.binary = bytearray()
        self.doc = {"asset": {"version": "2.0", "generator": "Sim2Seoul original MakeHuman CC0 data converter", "copyright": "MakeHuman CC0 data; modifications Sim2Seoul"}, "scene": 0, "scenes": [{"nodes": [0]}], "nodes": [{"name": label, "children": []}], "meshes": [], "skins": [], "bufferViews": [], "accessors": [], "buffers": [{"byteLength": 0}], "materials": [], "images": [], "textures": [], "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}]}
        self.names, self.parents, self.rests = names, parents, rests
        for i, name in enumerate(names):
            local = rests[i] if parents[i] < 0 else np.linalg.inv(rests[parents[i]]) @ rests[i]
            self.doc["nodes"].append({"name": alias(name), "translation": local[:3, 3].tolist(), "rotation": quaternion(local[:3, :3]), "children": [], "extras": {"makehuman_source_bone": name}})
            self.doc["nodes"][0 if parents[i] < 0 else parents[i] + 1]["children"].append(i + 1)
        inverse = np.asarray([np.linalg.inv(m).T.reshape(16) for m in rests], dtype="<f4")
        ibm = self.accessor(inverse, "MAT4", 5126)
        self.doc["skins"].append({"name": "MakeHumanOriginal163BoneSkin", "joints": list(range(1, len(names) + 1)), "skeleton": 1, "inverseBindMatrices": ibm})

    def accessor(self, array, kind, component, target=None, bounds=False):
        array = np.ascontiguousarray(array)
        while len(self.binary) % 4:
            self.binary.append(0)
        view = {"buffer": 0, "byteOffset": len(self.binary), "byteLength": array.nbytes}
        if target:
            view["target"] = target
        self.doc["bufferViews"].append(view)
        self.binary.extend(array.tobytes())
        access = {"bufferView": len(self.doc["bufferViews"]) - 1, "componentType": component, "count": len(array), "type": kind}
        if bounds:
            access.update(min=array.min(axis=0).tolist(), max=array.max(axis=0).tolist())
        self.doc["accessors"].append(access)
        return len(self.doc["accessors"]) - 1

    def material(self, name, texture=None, colour=(1, 1, 1, 1), roughness=.68, double=False):
        pbr = {"baseColorFactor": list(colour), "metallicFactor": 0, "roughnessFactor": roughness}
        if texture:
            self.doc["images"].append({"uri": texture})
            self.doc["textures"].append({"source": len(self.doc["images"]) - 1, "sampler": 0})
            pbr["baseColorTexture"] = {"index": len(self.doc["textures"]) - 1}
        self.doc["materials"].append({"name": name, "pbrMetallicRoughness": pbr, "doubleSided": double, "alphaMode": "OPAQUE"})
        return len(self.doc["materials"]) - 1

    def mesh(self, name, polygons, material):
        # A polygon point carries xyz, uv, normal, all163 source weights.
        values, indices, lookup = [], [], {}
        for poly in polygons:
            local = []
            for p in poly:
                key = tuple(np.round(np.concatenate(p), 9))
                if key not in lookup:
                    lookup[key] = len(values)
                    values.append(p)
                local.append(lookup[key])
            for i in range(1, len(poly) - 1):
                tri = [local[0], local[i], local[i + 1]]
                if np.linalg.norm(np.cross(values[tri[1]][0] - values[tri[0]][0], values[tri[2]][0] - values[tri[0]][0])) > 1e-11:
                    indices.extend(tri)
        pos = np.asarray([x[0] for x in values], dtype="<f4")
        uv = np.asarray([x[1] for x in values], dtype="<f4")
        normal = np.asarray([unit(x[2]) for x in values], dtype="<f4")
        full_weights = np.asarray([x[3] for x in values])
        joint = np.argsort(-full_weights, axis=1)[:, :4].astype("<u2")
        weight = np.take_along_axis(full_weights, joint, axis=1)
        discarded = 1 - weight.sum(1)
        weight /= weight.sum(1)[:, None]
        weight = weight.astype("<f4")
        attributes = {"POSITION": self.accessor(pos, "VEC3", 5126, 34962, True), "NORMAL": self.accessor(normal, "VEC3", 5126, 34962), "TEXCOORD_0": self.accessor(uv, "VEC2", 5126, 34962), "JOINTS_0": self.accessor(joint, "VEC4", 5123, 34962), "WEIGHTS_0": self.accessor(weight, "VEC4", 5126, 34962)}
        idx = self.accessor(np.asarray(indices, dtype="<u4"), "SCALAR", 5125, 34963)
        self.doc["meshes"].append({"name": name, "primitives": [{"attributes": attributes, "indices": idx, "material": material}]})
        self.doc["nodes"][0]["children"].append(len(self.doc["nodes"]))
        self.doc["nodes"].append({"name": name, "mesh": len(self.doc["meshes"]) - 1, "skin": 0})
        return {"name": name, "vertices": len(values), "triangles": len(indices) // 3, "bounds_min": pos.min(0).tolist(), "bounds_max": pos.max(0).tolist(), "maximum_discarded_weight_before_top4_renormalization": float(max(discarded)), "mean_discarded_weight_before_top4_renormalization": float(np.mean(discarded)), "maximum_weight_sum_error": float(np.max(abs(weight.sum(1) - 1))), "unweighted_vertices": int(np.sum(full_weights.sum(1) < .9999))}

    def save(self, path):
        while len(self.binary) % 4:
            self.binary.append(0)
        self.doc["buffers"][0]["byteLength"] = len(self.binary)
        header = json.dumps(self.doc, separators=(",", ":")).encode()
        header += b" " * (-len(header) % 4)
        content = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(header) + 8 + len(self.binary)) + struct.pack("<II", len(header), 0x4E4F534A) + header + struct.pack("<II", len(self.binary), 0x004E4942) + self.binary
        path.write_bytes(content)


def convert(sex):
    raw, uv, groups = obj(CORE / "makehuman/data/3dobjs/base.obj")
    applied = []
    for title in (f"asian-{sex}-young.target", f"universal-{sex}-young-averagemuscle-averageweight.target"):
        path = CORE / "makehuman/data/targets/macrodetails" / title
        for line in path.read_text().splitlines():
            row = line.split()
            if row and not row[0].startswith("#"):
                raw[int(row[0])] += np.asarray(row[1:4], dtype=float)
        applied.append(title)
    body_indices = sorted({i for f in groups["body"] for i, _ in f})
    body = raw[body_indices]
    scale = 1.70 / (body[:, 1].max() - body[:, 1].min())
    raw[:, 1] -= body[:, 1].min()
    raw *= scale
    data = json.loads((CORE / "makehuman/data/rigs/default.mhskel").read_text())
    names = []
    def visit(name):
        parent = data["bones"][name]["parent"]
        if parent and parent not in names:
            visit(parent)
        if name not in names:
            names.append(name)
    for name in data["bones"]:
        visit(name)
    ids = {name: i for i, name in enumerate(names)}
    parents = [ids[data["bones"][n]["parent"]] if data["bones"][n]["parent"] else -1 for n in names]
    weights = np.zeros((len(raw), len(names)))
    original_weights = json.loads((CORE / "makehuman/data/rigs/default_weights.mhw").read_text())["weights"]
    for name, rows in original_weights.items():
        for vertex, amount in rows:
            weights[int(vertex), ids[name]] += amount
    assert np.all(weights.sum(1) > 0), "Every source body/helper vertex needs actual source weights"
    weights /= weights.sum(1)[:, None]
    rests, bone_meta = [], []
    for i, name in enumerate(names):
        bone = data["bones"][name]
        head = raw[data["joints"][bone["head"]]].mean(0)
        tail = raw[data["joints"][bone["tail"]]].mean(0)
        y = unit(tail - head, (0, 1, 0))
        x = unit(np.cross(y, [0, 0, 1]), (1, 0, 0))
        z = unit(np.cross(x, y), (0, 0, 1))
        m = np.eye(4)
        m[:3, :3] = np.stack([x, y, z], axis=1)
        m[:3, 3] = head
        rests.append(m)
        bone_meta.append({"source": name, "exported": alias(name), "parent_index": parents[i], "head_m": head.tolist(), "tail_m": tail.tolist(), "global_rest_column_major": m.T.reshape(16).tolist()})
    assert len(set(map(alias, names))) == len(names)
    glb = GLB(names, parents, rests, f"MakeHumanCC0Swim_{sex}")
    skin = glb.material("CC0OriginalSkinUV", f"textures/{sex}_skin.png", roughness=.70)
    swim = glb.material("AlwaysOpaqueSwimwear", colour=(.025, .14, .19, 1) if sex == "male" else (.055, .09, .22, 1), roughness=.82, double=True)
    eye_mat = glb.material("CC0OriginalBrownEyes", "textures/brown_eye.png", roughness=.32)
    body_normals = smooth_normals(raw, groups["body"])
    def poly(face, positions, tex, normals, source_weights):
        return [(positions[v].copy(), tex[t].copy(), normals[v].copy(), source_weights[v].copy()) for v, t in face]
    arm_ids = [i for i, n in enumerate(names) if n.startswith(("upperarm", "lowerarm", "wrist", "finger"))]
    visible_body = []
    covered_faces = 0
    hidden_lower, hidden_upper = (.70, 1.00) if sex == "male" else (.70, 1.42)
    for face in groups["body"]:
        vi = [v for v, _ in face]
        centre_y = float(raw[vi, 1].mean())
        is_arm = float(weights[vi][:, arm_ids].sum(1).mean()) > .30
        if hidden_lower < centre_y < hidden_upper and not is_arm:
            # Remove anatomy inside fixed opaque swimwear, with overlap at
            # collar/hem. This also prevents skin poking through during flexion.
            covered_faces += 1
            continue
        visible_body.append(face)
    reports = [glb.mesh("TexturedBody", [poly(f, raw, uv, body_normals, weights) for f in visible_body], skin)]
    # Derive actual garment geometry from the source fitting mesh; no capsules.
    # Shorty one-piece for female covers the chest as well as pelvis/thighs.
    helper = groups["helper-tights"]
    hn = smooth_normals(raw, helper)
    fitted = raw + hn * .009
    lower, upper = (.67, 1.035) if sex == "male" else (.67, 1.455)
    garments = []
    for face in helper:
        p = clip(clip(poly(face, fitted, uv, hn, weights), lower, True), upper, False)
        p = clip_armhole(p, arm_ids)
        if len(p) >= 3:
            garments.append(p)
    reports.append(glb.mesh("OpaqueSwimShorts" if sex == "male" else "OpaqueShortySwimsuit", garments, swim))
    ev, euv, eg = obj(SYSTEM / "eyes/low-poly/low-poly.obj")
    proxy = (SYSTEM / "eyes/low-poly/low-poly.mhclo").read_text().split("verts 0\n", 1)[1]
    mapping = [int(l.strip()) for l in proxy.splitlines() if l.strip() and not l.startswith("#")]
    assert len(mapping) == len(ev)
    ev = raw[mapping]
    ef = [f for faces in eg.values() for f in faces]
    en = smooth_normals(ev, ef)
    reports.append(glb.mesh("CC0LowPolyEyes", [poly(f, ev, euv, en, weights[mapping]) for f in ef], eye_mat))
    file = OUT / f"swim_{sex}.glb"
    glb.save(file)
    meta = {"sex_variant": sex, "units": "metres", "up": "+Y", "forward": "+Z", "raw_source_vertices": len(raw), "body_source_faces": len(groups["body"]), "body_source_unique_vertices": len(body_indices), "excluded_source_groups": sorted(g for g in groups if g != "body"), "allowed_derived_helper_group": "helper-tights only, cropped opaque garment; never a skin surface", "genital_helpers_rendered": False, "height_normalization_m": 1.70, "target_names": applied, "target_weights": [1, 1], "source_unit_scale_after_targets": float(scale), "bone_count": len(names), "bone_export_policy": "163 original bones, topological order; only names aliased to game semantic Bip01 labels", "garment_height_clip_m": [lower, upper], "garment_fit_outward_m": .009, "garment_always_opaque": True, "uv_policy": "Original OBJ UV, V flipped for glTF convention", "normal_policy": "Area-weighted smooth original polygon normals; no software code reused", "influence_policy": "Original weights, select top four per exported vertex, renormalize; interpolated source weights on new hem vertices", "eyes_policy": "Original CC0 low-poly proxy mapped directly to its 100 core helper-eye source vertices, source UV and original source weights", "surfaces": reports, "bones": bone_meta, "file": str(file.relative_to(ROOT)), "bytes": file.stat().st_size, "sha256": digest(file)}
    meta["body_faces_removed_inside_opaque_swimwear"] = covered_faces
    meta["covered_anatomy_removal_interval_m"] = [hidden_lower, hidden_upper]
    meta["skin_garment_overlap_at_hem_and_collar_m"] = .03
    meta["garment_armhole_clip_policy"] = {"method": "per_vertex_source_arm_weight_isocontour_with_shared_edge_interpolation", "maximum_arm_weight": .30, "interpolated_fields": ["position", "original_uv", "normal", "all163_source_weights"], "whole_face_mean_weight_rejection": False, "opaque_coverage_and_body_exclusion_intervals_unchanged": True}
    (OUT / f"swim_{sex}.metadata.json").write_text(json.dumps(meta, indent=2) + "\n")
    return {k: v for k, v in meta.items() if k != "bones"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fetch", action="store_true", help="Restore SHA-pinned original data from official URLs before converting")
    args = parser.parse_args()
    if args.fetch:
        fetch_originals()
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    for directory in (CORE, SYSTEM):
        rows = json.loads((directory / "DOWNLOADS.json").read_text())
        for row in rows:
            assert digest(ROOT / row["file"]) == row["sha256"], "Original data changed: " + row["file"]
        records.extend(rows)
    (OUT / "textures").mkdir(exist_ok=True)
    for sex in ("male", "female"):
        shutil.copyfile(SYSTEM / f"skins/young_asian_{sex}/young_lightskinned_{sex}_diffuse3.png", OUT / f"textures/{sex}_skin.png")
    shutil.copyfile(SYSTEM / "eyes/materials/brown_eye.png", OUT / "textures/brown_eye.png")
    shutil.copyfile(CORE / "LICENSE.ASSETS.md", OUT / "LICENSE.CC0.md")
    shutil.copyfile(CORE / "LICENSE.md", OUT / "UPSTREAM_LICENSE_SCOPE.md")
    variants = [convert(sex) for sex in ("male", "female")]
    manifest = {"supplier": "MakeHuman community", "license": "CC0-1.0 data assets only", "license_scope_source": f"https://github.com/makehumancommunity/makehuman/blob/{CORE_COMMIT}/LICENSE.md", "system_asset_pack_license_page": "https://static.makehumancommunity.org/assets/assetpacks/makehuman_system_assets.html", "upstream_core_commit": CORE_COMMIT, "source_files": records, "software_code_copied": False, "original_data_cache_is_not_runtime_required": True, "converter": "tools/prepare_makehuman_swim.py", "converter_sha256": digest(__file__), "rights_note": "CC0 data only. MakeHuman software AGPL code is not incorporated. Asset labels are original supplier filenames, not a claim about any real person's identity. No Rockstar/Take-Two/GTA assets.", "variants": variants, "runtime_files": [{"file": str(p.relative_to(ROOT)), "bytes": p.stat().st_size, "sha256": digest(p)} for p in sorted(OUT.rglob("*")) if p.is_file() and p.name != "provenance.json" and not p.name.endswith(".import")]}
    (OUT / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"output": str(OUT), "variants": [{"sex": v["sex_variant"], "bytes": v["bytes"], "sha256": v["sha256"], "surfaces": v["surfaces"]} for v in variants]}, indent=2))


if __name__ == "__main__":
    main()
