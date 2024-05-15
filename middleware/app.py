from fastapi import FastAPI, HTTPException, Request
import traceback
import requests
import base64
import os
import random
import time
import uvicorn
from validator import validate
from upload import upload_in_memory_object
from requests.adapters import HTTPAdapter, Retry
from typing import Dict, Any
from schemas.api import API_SCHEMA
from schemas.img2img import IMG2IMG_SCHEMA
from schemas.txt2img import TXT2IMG_SCHEMA
from schemas.options import OPTIONS_SCHEMA

app = FastAPI()

BASE_URL = 'http://127.0.0.1:3000'
TIMEOUT = 60
POST_RETRIES = 3

session = requests.Session()
retries = Retry(total=10, backoff_factor=0.1, status_forcelist=[502, 503, 504])
session.mount('http://', HTTPAdapter(max_retries=retries))
machine_id = os.environ.get('SALAD_MACHINE_ID', 'Unknown')

# ---------------------------------------------------------------------------- #
#                              Automatic Functions                             #
# ---------------------------------------------------------------------------- #

def wait_for_service():
    retries = 0

    while True:
        try:
            payload = {
                "prompt": "a cat",
                "negative_prompt": "",
                "seed": -1,
                "batch_size": 1,
                "steps": 22,
                "cfg_scale": 7,
                "width": 512,
                "height": 768,
                "sampler_name": "DPM++ 2M Karras",
                "sampler_index": "DPM++ 2M Karras",
                "restore_faces": False,
                "enable_hr": False,
                "override_settings": {
                    "sd_model_checkpoint": "epicphotogasm_y",
                    "enable_pnginfo": False
                }
            }
            requests.post(
                url=f'{BASE_URL}/sdapi/v1/txt2img',
                json=payload,
                timeout=20
            )
            return
        except requests.exceptions.RequestException:
            retries += 1

            print('LOG: Service not ready yet. Retrying...')
        except Exception as err:
            print(f'ERROR: {err}')

        time.sleep(10)


def send_get_request(endpoint):
    return session.get(
        url=f'{BASE_URL}/{endpoint}',
        timeout=TIMEOUT
    )


def send_post_request(endpoint, payload, retry=0):
    response = session.post(
        url=f'{BASE_URL}/{endpoint}',
        json=payload,
        timeout=TIMEOUT
    )

    # Retry the post request in case the model has not completed loading yet
    if response.status_code == 404:
        if retry < POST_RETRIES:
            retry += 1
            print(f'WARNING: Received HTTP 404 from endpoint: {endpoint}. Retrying: {retry}')
            time.sleep(0.2)
            return send_post_request(endpoint, payload, retry)

    return response


def validate_api(event):
    if 'api' not in event['input']:
        return {
            'errors': '"api" is a required field in the "input" payload'
        }

    api = event['input']['api']

    if type(api) is not dict:
        return {
            'errors': '"api" must be a dictionary containing "method" and "endpoint"'
        }

    api['endpoint'] = api['endpoint'].lstrip('/')

    return validate(api, API_SCHEMA)


def validate_payload(event):
    method = event['input']['api']['method']
    endpoint = event['input']['api']['endpoint']
    payload = event['input']['payload']
    validated_input = payload

    if endpoint == 'txt2img':
        validated_input = validate(payload, TXT2IMG_SCHEMA)
    elif endpoint == 'img2img':
        validated_input = validate(payload, IMG2IMG_SCHEMA)
    elif endpoint == 'options' and method == 'POST':
        validated_input = validate(payload, OPTIONS_SCHEMA)

    return endpoint, event['input']['api']['method'], validated_input

def is_url(s):
    return s.startswith('http://') or s.startswith('https://')

def convert_image_to_base64(url):
    response = requests.get(url)
    response.raise_for_status()  # Ensure that the request was successful
    return base64.b64encode(response.content).decode('utf-8')

def process_image_fields(payload):
    if 'init_images' in payload:
        payload['init_images'] = [
            convert_image_to_base64(image) if is_url(image) else image
            for image in payload['init_images']
        ]
    
    if 'mask' in payload and is_url(payload['mask']):
        payload['mask'] = convert_image_to_base64(payload['mask'])

    if 'alwayson_scripts' in payload:
        # reactor is not included, so can be removed
        if 'reactor' in payload['alwayson_scripts']:
            first_arg = payload['alwayson_scripts']['reactor']['args'][0]
            if is_url(first_arg):
                payload['alwayson_scripts']['reactor']['args'][0] = convert_image_to_base64(first_arg)

        if 'controlnet' in payload['alwayson_scripts']:
            input_image = payload['alwayson_scripts']['controlnet']['args'][0]['input_image']
            if is_url(input_image):
                payload['alwayson_scripts']['controlnet']['args'][0]['input_image'] = convert_image_to_base64(input_image)

async def upload_and_return(response, endpoint_url):
    image_data = base64.b64decode(response.json()['images'][0])
    file_name = f"{int(time.time())}_{random.randint(1000, 9999)}.png"
    bucket_name = "output_images"
    bucket_creds = {
        "endpointUrl": endpoint_url,
        "accessId": os.environ.get('BUCKET_ACCESS_KEY_ID'),
        "accessSecret": os.environ.get('BUCKET_SECRET_ACCESS_KEY')
    }
    upload_url = await upload_in_memory_object(file_name, image_data, bucket_name=bucket_name, bucket_creds=bucket_creds)
    return {'image_url': upload_url}

# ---------------------------------------------------------------------------- #
#                                The Handler                                   #
# ---------------------------------------------------------------------------- #

@app.post("/api")
async def process_request(request: Request):
    event = await request.json()
    validated_api = validate_api(event)

    if 'errors' in validated_api:
        raise HTTPException(status_code=400, detail=validated_api['errors'])

    endpoint, method, validated_payload = validate_payload(event)

    if 'errors' in validated_payload:
        raise HTTPException(status_code=400, detail=validated_payload['errors'])

    if 'validated_input' in validated_payload:
        payload = validated_payload['validated_input']
    else:
        payload = validated_payload

    process_image_fields(payload)

    try:
        print(f'LOG: Sending {method} request to: /{endpoint}')

        if method == 'GET':
            response = send_get_request(endpoint)
        elif method == 'POST':
            response = send_post_request(endpoint, payload)
        
        if response.status_code == 200:
            return response.json()
        else:
            print(f'ERROR: HTTP Status code: {response.status_code}. Machine ID: {machine_id}')
            print(f'ERROR: Response: {response.json()}')

            return {
                'error': f'A1111 status code: {response.status_code}',
                'output': response.json()
            }
    except Exception as e:
        error_trace = traceback.format_exc()
        print(f'ERROR: An exception was raised on machine {machine_id}: {e}\n{error_trace}')
        raise HTTPException(status_code=500, detail=f"An internal server error occurred on machine on machine {machine_id}:\n{error_trace}")

if __name__ == "__main__":
    wait_for_service()
    print('LOG: Automatic1111 API is ready')
    uvicorn.run("app:app", host="::", port=80, log_level="error")
