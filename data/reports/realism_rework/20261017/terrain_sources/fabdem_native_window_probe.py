import json,math,hashlib,traceback
from pathlib import Path
from datetime import datetime,timezone
import requests,rasterio,numpy as np
from rasterio.windows import from_bounds,Window
from pyproj import Geod
base='https://huggingface.co/buckets/links-ads/fabdem/resolve/'
url=base+'tiles/N30E120-N40E130_FABDEM_V1-2/N37E126_FABDEM_V1-2.tif'
bbox=[126.971,37.5608,126.9815,37.5694];origin=[126.97625,37.5651]
audit={'time_utc':datetime.now(timezone.utc).isoformat(),'status':'NOT_ACQUIRED','source_url':url,'upstream_dataset':'https://research-information.bris.ac.uk/en/datasets/fabdem-v1-2/','source_role':'LINKS converter-publisher mirror; upstream pixel identity not independently proven','requested_bbox_wsen':bbox,'local_origin_lon_lat':origin,'large_archive_downloaded':False,'runtime_modified':False,'metadata_reads':[]}
for name in ['README.md','readme.txt','license.txt','stac_catalog/N37E126_FABDEM_V1-2/N37E126_FABDEM_V1-2.json']:
 try:
  r=requests.get(base+name,timeout=(8,18));entry={'url':base+name,'status':r.status_code,'bytes':len(r.content)}
  if r.status_code==200 and len(r.content)<100000:
   path=Path('/private/tmp/fabdem-links-'+name.rsplit('/',1)[-1]);path.write_bytes(r.content);entry.update(path=str(path),sha256=hashlib.sha256(r.content).hexdigest())
  audit['metadata_reads'].append(entry)
 except Exception as e:audit['metadata_reads'].append({'url':base+name,'error':str(e)})
try:
 with rasterio.Env(GDAL_DISABLE_READDIR_ON_OPEN='EMPTY_DIR',CPL_VSIL_CURL_ALLOWED_EXTENSIONS='.tif',GDAL_HTTP_TIMEOUT='20',GDAL_HTTP_CONNECTTIMEOUT='8',GDAL_HTTP_MAX_RETRY='0',VSI_CACHE=False,GDAL_CACHEMAX=8*1024*1024,CPL_VSIL_CURL_CHUNK_SIZE=16384):
  with rasterio.open('/vsicurl/'+url) as src:
   source={'driver':src.driver,'width':src.width,'height':src.height,'count':src.count,'dtype':src.dtypes,'crs':str(src.crs),'crs_wkt':src.crs.to_wkt(),'bounds':list(src.bounds),'transform':list(src.transform),'nodata':src.nodata,'block_shapes':src.block_shapes,'overviews':src.overviews(1),'tags':src.tags(),'image_structure_tags':src.tags(ns='IMAGE_STRUCTURE')}
   fractional=from_bounds(*bbox,transform=src.transform);col=math.floor(fractional.col_off);row=math.floor(fractional.row_off);right=math.ceil(fractional.col_off+fractional.width);bottom=math.ceil(fractional.row_off+fractional.height);window=Window(col,row,right-col,bottom-row)
   data=src.read(1,window=window,masked=True);valid=data.compressed();output=Path('/private/tmp/fabdem-deoksugung-v1-2-crop.tif');profile=src.profile.copy();profile.update(width=int(window.width),height=int(window.height),transform=src.window_transform(window),tiled=False,compress='deflate');profile.pop('blockxsize',None);profile.pop('blockysize',None)
   with rasterio.open(output,'w',**profile) as dst:dst.write(data.filled(src.nodata),1);dst.update_tags(**src.tags())
   samples=[]
   for label,lon,lat in [('technical_origin',*origin),('bbox_sw',bbox[0],bbox[1]),('bbox_ne',bbox[2],bbox[3])]:
    r,c=src.index(lon,lat);x,y=src.xy(r,c);v=float(next(src.sample([(lon,lat)]))[0]);samples.append({'label':label,'requested_lon_lat':[lon,lat],'nearest_pixel_row_col':[r,c],'actual_pixel_centre_lon_lat':[x,y],'raw_elevation_m':v,'is_exact_ground_anchor':False})
   geod=Geod(ellps='WGS84');_,_,east=geod.inv(origin[0],origin[1],origin[0]+abs(src.res[0]),origin[1]);_,_,north=geod.inv(origin[0],origin[1],origin[0],origin[1]+abs(src.res[1]));audit.update(status='ACQUIRED_MIRROR_NATIVE_WINDOW',source_metadata=source,window={'col_off':col,'row_off':row,'width':int(window.width),'height':int(window.height)},crop_path=str(output),crop_bytes=output.stat().st_size,crop_sha256=hashlib.sha256(output.read_bytes()).hexdigest(),pixel_values_sha256=hashlib.sha256(data.filled(src.nodata).tobytes()).hexdigest(),statistics={'valid_count':int(valid.size),'masked_count':int(np.ma.count_masked(data)),'finite':bool(np.isfinite(valid).all()),'minimum_m':float(valid.min()),'maximum_m':float(valid.max()),'mean_m':float(valid.mean()),'median_m':float(np.median(valid)),'standard_deviation_m':float(valid.std())},native_grid_spacing_at_origin_m={'east_west':east,'north_south':north},nearest_native_samples=samples,vertical_datum_status='Copernicus parent product uses EGM2008 orthometric metres per official handbook. Require FABDEM-specific raw tag/readme confirmation; do not equate EPSG:4326 horizontal CRS with ellipsoidal height.',interpretation='A model-derived coarse bare-earth estimate with buildings/forest biases removed, not local survey or measured street/curb elevation. No resampling or fabricated height values in this crop.')
except Exception as e:audit.update(error_type=type(e).__name__,error=str(e))
Path('/private/tmp/fabdem-window-audit.json').write_text(json.dumps(audit,ensure_ascii=False,indent=2)+'\n');print(json.dumps(audit,ensure_ascii=False,indent=2))
