''' PodWorker | modules | upload.py '''
import os
import io
import time
import logging
from urllib.parse import urlparse
from typing import Optional, Tuple

import aioboto3
from botocore.config import Config
from boto3.s3.transfer import TransferConfig
from tqdm_loggable.auto import tqdm

logger = logging.getLogger("upload utility")
FMT = "%(filename)-20s:%(lineno)-4d %(asctime)s %(message)s"
logging.basicConfig(level=logging.INFO, format=FMT, handlers=[logging.StreamHandler()])

def extract_region_from_url(endpoint_url):
    parsed_url = urlparse(endpoint_url)
    if '.s3.' in endpoint_url:
        return endpoint_url.split('.s3.')[1].split('.')[0]
    if parsed_url.netloc.endswith('.digitaloceanspaces.com'):
        return endpoint_url.split('.')[1].split('.digitaloceanspaces.com')[0]
    return None

def get_transfer_config(file_size: int) -> TransferConfig:
    # If the file is smaller than 5 MB, disable multipart uploads
    if file_size < 5 * 1024 * 1024:  # less than 5 MB
        return TransferConfig(
            multipart_threshold=file_size + 1,  # Set threshold above the file size to avoid multipart upload
        )
    # Otherwise, use your existing configuration
    return TransferConfig(
        multipart_threshold=1024 * 25,
        max_concurrency=10,  # or os.cpu_count()
        multipart_chunksize=1024 * 25,
        use_threads=False
    )

async def upload_in_memory_object(
        file_name: str, file_data: bytes,
        bucket_creds: Optional[dict] = None,
        bucket_name: Optional[str] = None,
        prefix: Optional[str] = None) -> str:
    file_size = len(file_data)
    transfer_config = get_transfer_config(file_size)

    if not bucket_name:
        bucket_name = time.strftime('%m-%y')

    key = f"{prefix}/{file_name}" if prefix else file_name

    endpoint_url = bucket_creds.get('endpointUrl') if bucket_creds else os.environ.get('BUCKET_ENDPOINT_URL')
    access_key_id = bucket_creds.get('accessId') if bucket_creds else os.environ.get('BUCKET_ACCESS_KEY_ID')
    secret_access_key = bucket_creds.get('accessSecret') if bucket_creds else os.environ.get('BUCKET_SECRET_ACCESS_KEY')
    region = extract_region_from_url(endpoint_url) if endpoint_url else None

    session = aioboto3.Session(aws_access_key_id=access_key_id, aws_secret_access_key=secret_access_key, region_name=region)
    async with session.client('s3', endpoint_url=endpoint_url, config=Config(signature_version='s3v4')) as s3:
        with tqdm(total=file_size, unit='B', unit_scale=True, desc=file_name) as progress_bar:
            await s3.upload_fileobj(
                io.BytesIO(file_data), bucket_name, key,
                Config=transfer_config,
                Callback=progress_bar.update
            )

        presigned_url = await s3.generate_presigned_url(
            'get_object',
            Params={'Bucket': bucket_name, 'Key': key},
            ExpiresIn=604800
        )

    return presigned_url
