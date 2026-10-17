#!/usr/bin/env python3
"""Extract licensed Seoul contour/spot-height sources; do not interpolate terrain.

Use .venv-data/bin/python. The city ZIP stays in /private/tmp. Only the exact
region plus a <=200m metric halo is written to the repository. All original
height attributes are retained separately from game coordinates; no runtime Y
or vertical-datum conversion is assigned.
"""
import argparse
import hashlib
import json
import math
import struct
import urllib.parse
import urllib.request
import zipfile
from collections import Counter
from pathlib import Path

import pyproj
import shapely
from pyproj import CRS, Transformer
from pyproj.transformer import TransformerGroup
from shapely import transform as transform_geometry
from shapely.geometry import LineString, Point, Polygon, box, mapping
from shapely.ops import unary_union

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ARCHIVE = Path('/private/tmp/sim2seoul-terrain-alternatives/seoul-contours-20250320.zip')
DEFAULT_OUTPUT = ROOT / 'data/raw/supplemental/seoul_terrain/20261018'
ZIP_SHA256 = '4fbe3c7e061b5974e7403ec116855304ed8ae321eebcc0d12c31ca8fb7be30bf'
ZIP_BYTES = 45852601
CATALOGUE_URL = 'https://data.seoul.go.kr/dataList/OA-22241/F/1/datasetView.do'
DOWNLOAD_URL = 'https://datafile.seoul.go.kr/bigfile/iot/inf/nio_download.do?&useCache=false'
DOWNLOAD_FORM = {'infId': 'OA-22241', 'seqNo': '', 'seq': '2', 'infSeq': '1'}
KOGL_URL = 'https://www.kogl.or.kr/info/licenseType1.do'
LAYERS = [('contours', '등고선 5000/N3L_F001', 'CONT'),
          ('spot_heights', '표고 5000/N3P_F002', 'NUME')]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def encode(value):
    return (json.dumps(value, ensure_ascii=False, indent=2, allow_nan=False) + '\n').encode()


def transformed(geometry, transformer):
    return transform_geometry(geometry, transformer.transform, interleaved=False)


def download(archive):
    if archive.exists():
        return
    assert not archive.resolve().is_relative_to(ROOT), 'Do not store the city ZIP in the repository'
    archive.parent.mkdir(parents=True, exist_ok=True)
    request = urllib.request.Request(DOWNLOAD_URL,
        data=urllib.parse.urlencode(DOWNLOAD_FORM).encode(),
        headers={'Referer': CATALOGUE_URL, 'User-Agent': 'Sim2Seoul-public-terrain-research/1.0'})
    with urllib.request.urlopen(request, timeout=45) as response, archive.open('wb') as target:
        assert response.status == 200
        total = 0
        while chunk := response.read(1024 * 1024):
            total += len(chunk)
            assert total <= 60_000_000, 'Unexpected archive size; preserve failure and inspect source'
            target.write(chunk)


def attributes(data):
    count = struct.unpack_from('<I', data, 4)[0]
    header_size, record_size = struct.unpack_from('<HH', data, 8)
    fields, position = [], 1
    for offset in range(32, header_size - 1, 32):
        field = data[offset:offset + 32]
        fields.append((field[:11].split(b'\0')[0].decode('cp949'), chr(field[11]), position, field[16]))
        position += field[16]
    rows = []
    for index in range(count):
        record = data[header_size + index * record_size:header_size + (index + 1) * record_size]
        assert len(record) == record_size and record[:1] == b' ', 'Deleted/truncated DBF record'
        row = {}
        for name, kind, start, size in fields:
            text = record[start:start + size].decode('cp949').strip()
            row[name] = float(text) if text and kind in ('N', 'F') else (text or None)
        rows.append(row)
    return rows


def shapes(shp, shx):
    """Read the two advertised shape types and validate every SHX record offset."""
    assert struct.unpack_from('>I', shp, 0)[0] == 9994
    assert struct.unpack_from('>I', shp, 24)[0] * 2 == len(shp)
    assert (len(shx) - 100) % 8 == 0
    for index, offset in enumerate(range(100, len(shx), 8)):
        start_words, size_words = struct.unpack_from('>II', shx, offset)
        number, actual_words = struct.unpack_from('>II', shp, start_words * 2)
        assert number == index + 1 and actual_words == size_words
        data = memoryview(shp)[start_words * 2 + 8:(start_words + 4 + size_words) * 2]
        assert len(data) == size_words * 2
        kind = struct.unpack_from('<I', data, 0)[0]
        if kind == 1:
            yield number, digest(data), [Point(*struct.unpack_from('<2d', data, 4))]
        elif kind == 3:
            count, vertices = struct.unpack_from('<II', data, 36)
            starts = list(struct.unpack_from(f'<{count}I', data, 44)) + [vertices]
            assert starts[0] == 0 and starts == sorted(starts)
            points = [struct.unpack_from('<2d', data, 44 + 4 * count + 16 * i) for i in range(vertices)]
            yield number, digest(data), [LineString(points[a:b]) for a, b in zip(starts, starts[1:])]
        elif kind == 0:
            yield number, digest(data), []
        else:
            raise ValueError(f'Unsupported source shape type: {kind}')


def line_parts(geometry):
    if geometry.geom_type == 'LineString':
        return [geometry] if geometry.length > .000001 else []
    if hasattr(geometry, 'geoms'):
        return [part for item in geometry.geoms for part in line_parts(item)]
    return []


def generate(archive, halo):
    raw = archive.read_bytes()
    assert len(raw) == ZIP_BYTES and digest(raw) == ZIP_SHA256, 'Official source ZIP changed; inspect before replacing pinned source'
    source = zipfile.ZipFile(archive)
    config_bytes = (ROOT / 'config/region.json').read_bytes()
    region = json.loads(config_bytes)
    prj = source.read('등고선 5000/N3L_F001.prj')
    assert prj == source.read('표고 5000/N3P_F002.prj')
    source_crs = CRS.from_wkt(prj.decode())
    assert source_crs.to_epsg() == 5174
    metric_crs = CRS.from_user_input(region['metric_crs'])
    operation = TransformerGroup(source_crs, metric_crs, always_xy=True)
    assert operation.best_available and operation.transformers and operation.transformers[0].accuracy >= 0
    to_metric = operation.transformers[0]
    to_ll = Transformer.from_crs(metric_crs, 4326, always_xy=True)
    from_ll = Transformer.from_crs(4326, metric_crs, always_xy=True)
    origin = from_ll.transform(*region['origin_lon_lat'])
    west, south, east, north = region['bbox_west_south_east_north']
    region_metric = Polygon([from_ll.transform(*point) for point in
                            [(west, south), (east, south), (east, north), (west, north)]])
    clip_metric = region_metric.buffer(halo, quad_segs=16)
    assert region_metric.is_valid and clip_metric.is_valid
    source_clip = transformed(clip_metric, Transformer.from_crs(metric_crs, source_crs, always_xy=True)).envelope.buffer(2.)
    outputs = {'source_original.prj': prj,
               'source_original_field_notes.txt': source.read('등고선,표고.txt')}
    layers, statistics, source_files, all_controls = {}, {}, {}, []
    for layer, stem, height_field in LAYERS:
        dbf = attributes(source.read(stem + '.dbf'))
        shp, shx = source.read(stem + '.shp'), source.read(stem + '.shx')
        for extension in ('.dbf', '.shp', '.shx', '.prj', '.shp.xml'):
            data = source.read(stem + extension)
            source_files[stem + extension] = {'bytes': len(data), 'sha256': digest(data)}
        features, local_records, scanned = [], [], 0
        for number, geometry_hash, parts in shapes(shp, shx):
            scanned += 1
            props = dbf[number - 1]
            height = props['HEIGHT']
            assert height is not None and math.isfinite(height) and abs(height - props[height_field]) < .00000001
            for part_index, part in enumerate(parts):
                if not source_clip.intersects(part.envelope):
                    continue
                clipped = transformed(part, to_metric).intersection(clip_metric)
                pieces = ([clipped] if clipped.geom_type == 'Point' and not clipped.is_empty else []) if layer == 'spot_heights' else line_parts(clipped)
                for clip_index, piece in enumerate(pieces):
                    assert clip_metric.buffer(.00001).covers(piece)
                    identifier = f'{layer}:{number}:{part_index}:{clip_index}'
                    inside = region_metric.intersects(piece)
                    provenance = {'source_record': number, 'source_part': part_index,
                        'clip_part': clip_index, 'source_geometry_sha256': geometry_hash,
                        'source_properties': props, 'height_m': height,
                        'height_source_field': height_field, 'height_confirmed_by_field': 'HEIGHT',
                        'height_kind': 'source_contour_constant_elevation' if layer == 'contours' else 'source_map_spot_elevation',
                        'vertical_datum': None, 'vertical_datum_status': 'not_explicitly_documented_in_download',
                        'touches_exact_region': inside, 'halo_only': not inside}
                    if layer == 'spot_heights':
                        provenance['original_source_xy_m'] = list(part.coords[0])
                        local_geometry = [piece.x - origin[0], -(piece.y - origin[1])]
                    else:
                        local_geometry = [[x - origin[0], -(y - origin[1])] for x, y in piece.coords]
                    local_records.append({'id': identifier, **provenance,
                                          'point_xz_m' if layer == 'spot_heights' else 'line_xz_m': local_geometry})
                    features.append({'type': 'Feature', 'id': identifier, 'properties': provenance,
                                     'geometry': mapping(transformed(piece, to_ll))})
                    all_controls.append(piece)
        assert scanned == len(dbf)
        assert features and all(item['height_m'] > 0 for item in local_records)
        heights = [item['height_m'] for item in local_records]
        statistics[layer] = {'source_records_scanned_and_shx_validated': scanned,
            'local_parts_including_halo': len(local_records),
            'parts_touching_exact_region': sum(item['touches_exact_region'] for item in local_records),
            'height_min_m': min(heights), 'height_max_m': max(heights),
            'distinct_heights': sorted(set(heights)),
            'source_SCLS_counts': dict(Counter(item['source_properties']['SCLS'] for item in local_records))}
        collection = {'type': 'FeatureCollection', 'name': 'seoul_2023_' + layer + '_region_and_halo',
            'source_catalogue': CATALOGUE_URL, 'source_archive_sha256': ZIP_SHA256,
            'license': 'KOGL Type1: attribution; commercial use and modification permitted',
            'coordinate_reference': 'RFC7946 WGS84 longitude, latitude; heights remain explicit properties, not geometry Z',
            'features': features}
        outputs[layer + '_wgs84.geojson'] = encode(collection)
        layers[layer] = local_records
    local = {'schema_version': 1, 'task': 'SEOUL_OFFICIAL_LOCAL_TERRAIN_SOURCE_CONTROLS',
        'coordinate_system': {'metric_crs': metric_crs.to_string(), 'origin_lon_lat': region['origin_lon_lat'],
            'origin_east_north_m': list(origin), 'axes': {'x': 'east delta metres', 'z': 'negative north delta metres'},
            'heights': 'Original source height_m attributes; NOT assigned runtime Y',
            'vertical_datum': None, 'vertical_datum_status': 'unknown; no geoid or local-Y conversion applied'},
        'source_bbox_west_south_east_north': region['bbox_west_south_east_north'],
        'region_polygon_xz_m': [[x - origin[0], -(y - origin[1])] for x, y in region_metric.exterior.coords],
        'halo_m': halo,
        'clip_polygon_xz_m': [[x - origin[0], -(y - origin[1])] for x, y in clip_metric.exterior.coords],
        'layers': layers, 'interpolation': None, 'runtime_terrain_changed': False}
    outputs['terrain_source_controls_local.json'] = encode(local)
    controls_hull = unary_union(all_controls).convex_hull
    license_record = {'catalogue_url': CATALOGUE_URL, 'catalogue_title': '서울시 경사도',
        'provider': '서울특별시 도시공간본부 도시계획상임기획과',
        'catalogue_description_original': '요청한 경사도 shp은 없고, 경사도를 추출할 수 있는 표고점, 등고선 shp파일 제공입니다. (국토지리정보원에서 고시하는 2023년기준 수치 지형도 입니다.)',
        'catalogue_file': '서울시 등고선.zip', 'catalogue_file_modified': '2025-03-20',
        'catalogue_original_license': '공공누리 1유형 : 출처표시 (상업적 이용 및 변경 가능)',
        'catalogue_third_party_copyright': '없음', 'verified_date': '2026-10-18',
        'license_url': KOGL_URL, 'license_type': 'KOGL Type1',
        'rights': ['Online/offline sharing and use', 'Modification and derivative works', 'Commercial use'],
        'conditions': ['Credit the provider and work, and link to source when possible.',
            'Do not imply government endorsement or special relationship.',
            'Describe clipping, coordinate conversion and later interpolation as modifications; do not present them as measured new source data.'],
        'suggested_credit': '서울특별시 「서울시 경사도」의 표고점·등고선(국토지리정보원 2023년 기준 수치지형도, 파일 갱신 2025-03-20), 공공누리 제1유형. Sim2Seoul이 현재 권역 및 주변 200m를 추출하고 좌표를 변환함. 원자료: ' + CATALOGUE_URL,
        'archive_retention': 'Full Seoul ZIP is temporary local evidence only and must not be committed. Local clips, original field notes/PRJ, source hashes and provenance are retained.',
        'scope': 'The data source licence permits reuse; factual ground quality, vertical reference and real-world pedestrian access remain separate questions.'}
    outputs['source_license.json'] = encode(license_record)
    manifest = {'schema_version': 1, 'task': local['task'], 'result': 'SOURCE_INPUTS_READY_NO_DEM_INTERPOLATION',
        'generator': {'path': 'tools/prepare_seoul_terrain_sources.py', 'sha256': digest(Path(__file__).read_bytes()),
            'dependencies': {'pyproj': pyproj.__version__, 'shapely': shapely.__version__}},
        'region_config_sha256': digest(config_bytes),
        'archive': {'filename': '서울시 등고선.zip', 'bytes': ZIP_BYTES, 'sha256': ZIP_SHA256,
            'download_url': DOWNLOAD_URL, 'method': 'POST', 'form': DOWNLOAD_FORM,
            'anonymous_access_observed': True, 'not_a_repository_asset': True},
        'source_files': source_files, 'source_crs_epsg': 5174, 'source_prj_sha256': digest(prj),
        'horizontal_transform': {'description': to_metric.description, 'stated_operation_accuracy_m': to_metric.accuracy,
            'best_available': operation.best_available, 'unavailable_operations': [item.name for item in operation.unavailable_operations],
            'scope': 'Coordinate-operation metadata, not an independent survey accuracy claim.'},
        'vertical_datum': None, 'halo_m': halo, 'statistics': statistics,
        'validation': {'all_source_shx_offsets_and_dbf_counts_match': True,
            'HEIGHT_matches_CONT_or_NUME': True, 'all_clipped_geometry_inside_metric_region_plus_halo': True,
            'exact_region_area_m2': region_metric.area, 'clip_area_m2': clip_metric.area,
            'region_outside_controls_convex_hull_m2': region_metric.difference(controls_hull).area},
        'limitations': ['A 5m contour interval is not a measured 5m DEM grid.',
            'No interpolation has been applied; spaces between controls are unsampled.',
            'Spot-height semantic code F0027217 is retained; no additional classification or accuracy is invented.',
            'Vertical datum and source survey accuracy are not explicitly documented in the downloaded PRJ/field notes.',
            'Do not recover curbs, stairs, roof heights or tunnel/bridge levels from these sparse controls alone.',
            'Original source heights, generated terrain and authored corrections must remain distinguishable.'],
        'outputs': {name: {'bytes': len(data), 'sha256': digest(data)} for name, data in outputs.items()}}
    outputs['manifest.json'] = encode(manifest)
    return outputs, manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, default=DEFAULT_ARCHIVE)
    parser.add_argument('--output', type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument('--halo-m', type=float, default=200.)
    parser.add_argument('--download', action='store_true', help='Download the official city ZIP to temporary archive path if absent')
    parser.add_argument('--check', action='store_true', help='Regenerate in memory and verify saved byte-identical outputs')
    args = parser.parse_args()
    assert 0 <= args.halo_m <= 200
    if args.download:
        download(args.archive)
    assert args.archive.is_file(), 'Supply the official pinned ZIP with --archive, or use --download'
    outputs, manifest = generate(args.archive, args.halo_m)
    for name, data in outputs.items():
        path = args.output / name
        if args.check:
            assert path.read_bytes() == data, f'Generated source differs: {name}'
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    print(json.dumps({'result': 'PASS', 'mode': 'check' if args.check else 'write',
        'output': str(args.output), 'statistics': manifest['statistics'],
        'validation': manifest['validation']}, ensure_ascii=False))


if __name__ == '__main__':
    main()
