import json
import os
import boto3
import traceback
from supabase import create_client, Client

# S3 client
s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION_VAL'))

_supabase_client = None

def get_supabase_client() -> Client:
    global _supabase_client
    if _supabase_client is None:
        supabase_url = os.environ.get('SUPABASE_URL')
        supabase_key = os.environ.get('SUPABASE_KEY')
        if not supabase_url or not supabase_key:
            raise ValueError("SUPABASE_URL and SUPABASE_KEY must be set in environment variables.")
        _supabase_client = create_client(supabase_url, supabase_key)
    return _supabase_client

def lambda_handler(event, context):
    # API Gateway REST API uses 'httpMethod'
    # HTTP API or Lambda Function URLs use 'requestContext' -> 'http' -> 'method'
    http_method = event.get('httpMethod')
    if not http_method:
        http_method = event.get('requestContext', {}).get('http', {}).get('method')
        
    if http_method == 'OPTIONS':
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,Authorization,last-sync',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,PUT,DELETE'
            },
            'body': ''
        }
    elif http_method == 'GET':
        return handle_get(event)
    elif http_method == 'DELETE':
        return handle_delete(event)
    elif http_method == 'POST':
        query_params = event.get('queryStringParameters') or {}
        if query_params.get('action') == 'presign':
            return handle_presign(event)
        return handle_post(event)
    else:
        return {'statusCode': 405, 'body': 'Method Not Allowed'}

def handle_get(event):
    try:
        supabase = get_supabase_client()
        headers = event.get('headers') or {}
        last_sync = headers.get('last-sync') or headers.get('Last-Sync')
        
        query = supabase.table('files').select('file_name, folder_path, s3_url, content_type, uploaded_at, is_deleted')
        
        if last_sync:
            query = query.gt('uploaded_at', last_sync)
            
        # Fetch the delta (limit to 1000 since it's just metadata)
        response = query.order('uploaded_at', desc=True).limit(1000).execute()
        
        rows = response.data
        
        results = []
        for row in rows:
            file_name = row.get('file_name')
            folder_path_val = row.get('folder_path')
            s3_url = row.get('s3_url')
            content_type = row.get('content_type')
            is_deleted = row.get('is_deleted', False)
            
            uploaded_at = row.get('uploaded_at')
            if hasattr(uploaded_at, 'isoformat'):
                uploaded_at = uploaded_at.isoformat()
            
            results.append({
                'fileName': file_name,
                'folderPath': folder_path_val,
                'contentType': content_type,
                's3Url': s3_url,
                'uploadedAt': uploaded_at,
                'isDeleted': is_deleted
            })
            
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type,last-sync',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE'
            },
            'body': json.dumps(results)
        }
    except Exception as e:
        print("Error fetching files:", str(e))
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': 'Internal Server Error in GET',
                'error': str(e),
                'trace': traceback.format_exc()
            })
        }

def handle_presign(event):
    try:
        body = json.loads(event.get('body', '{}'))
        files_to_presign = body.get('files', [])
        
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        
        presigned_urls = {}
        for f in files_to_presign:
            file_name = f.get('fileName')
            folder_path = f.get('folderPath')
            if not file_name or not folder_path:
                continue
                
            folder_path = folder_path.rstrip('/')
            s3_key = f"{folder_path}/{file_name}"
            
            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={'Bucket': bucket_name, 'Key': s3_key},
                ExpiresIn=900 # 15 minutes
            )
            
            dict_key = f"{folder_path}/{file_name}"
            presigned_urls[dict_key] = presigned_url
            
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE'
            },
            'body': json.dumps({'presignedUrls': presigned_urls})
        }
    except Exception as e:
        print("Error in presign:", str(e))
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({'message': 'Internal Server Error in PRESIGN'})
        }

def handle_post(event):
    try:
        body = json.loads(event.get('body', '{}'))
        file_name = body.get('fileName')
        folder_path = body.get('folderPath')
        content_type = body.get('contentType', 'application/octet-stream')
        
        if not file_name or not folder_path:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': 'Missing fileName or folderPath in request body'})
            }
            
        # Clean up folder path and construct S3 Key
        folder_path = folder_path.rstrip('/')
        s3_key = f"{folder_path}/{file_name}"
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        aws_region = os.environ.get('AWS_REGION')
        s3_url = f"https://{bucket_name}.s3.{aws_region}.amazonaws.com/{s3_key}"
        
        # 1. Generate Presigned URL
        presigned_url = s3_client.generate_presigned_url(
            'put_object',
            Params={
                'Bucket': bucket_name,
                'Key': s3_key,
                'ContentType': content_type
            },
            ExpiresIn=900 # 15 minutes
        )
        
        # 2. Insert record into Supabase Database
        supabase = get_supabase_client()
        supabase.table('files').insert({
            'file_name': file_name,
            'folder_path': folder_path,
            's3_url': s3_url,
            'content_type': content_type
        }).execute()
        
        # 3. Return the presigned URL
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST'
            },
            'body': json.dumps({
                'presignedUrl': presigned_url,
                's3Url': s3_url,
                's3Key': s3_key
            })
        }
        
    except Exception as e:
        print("Error processing request:", str(e))
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': 'Internal Server Error in POST', 
                'error': str(e),
                'trace': traceback.format_exc()
            })
        }

def handle_delete(event):
    try:
        body = json.loads(event.get('body', '{}'))
        file_name = body.get('fileName')
        folder_path = body.get('folderPath')
        
        if not file_name or not folder_path:
            return {
                'statusCode': 400,
                'headers': {'Access-Control-Allow-Origin': '*'},
                'body': json.dumps({'message': 'Missing fileName or folderPath in request body'})
            }
            
        folder_path = folder_path.rstrip('/')
        s3_key = f"{folder_path}/{file_name}"
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        
        # 1. Delete from S3
        s3_client.delete_object(Bucket=bucket_name, Key=s3_key)
        
        # 2. Soft-Delete from Supabase Database
        supabase = get_supabase_client()
        from datetime import datetime, timezone
        now_iso = datetime.now(timezone.utc).isoformat()
        
        supabase.table('files').update({
            'is_deleted': True,
            'uploaded_at': now_iso
        }).eq('file_name', file_name).eq('folder_path', folder_path).execute()
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,DELETE'
            },
            'body': json.dumps({'message': 'File deleted successfully'})
        }
        
    except Exception as e:
        print("Error deleting file:", str(e))
        traceback.print_exc()
        return {
            'statusCode': 500,
            'headers': {'Access-Control-Allow-Origin': '*'},
            'body': json.dumps({
                'message': 'Internal Server Error in DELETE', 
                'error': str(e),
                'trace': traceback.format_exc()
            })
        }
