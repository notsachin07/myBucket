import json
import os
import boto3
import pytds
import certifi
import traceback

s3_client = boto3.client('s3', region_name=os.environ.get('AWS_REGION_VAL'))

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
                'Access-Control-Allow-Headers': 'Content-Type,Authorization',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST,PUT,DELETE'
            },
            'body': ''
        }
    elif http_method == 'GET':
        return handle_get()
    elif http_method == 'DELETE':
        return handle_delete(event)
    else:
        # Default to POST (upload generation)
        return handle_post(event)

def handle_get():
    try:
        db_server = os.environ.get('DB_SERVER')
        db_user = os.environ.get('DB_USER')
        db_password = os.environ.get('DB_PASSWORD')
        db_name = os.environ.get('DB_NAME')
        bucket_name = os.environ.get('S3_BUCKET_NAME')
        
        conn = pytds.connect(
            server=db_server,
            user=db_user,
            password=db_password,
            database=db_name,
            cafile=certifi.where()
        )
        cursor = conn.cursor()
        
        # Fetch the most recently uploaded files
        cursor.execute("SELECT FileName, FolderPath, S3Url, ContentType, UploadedAt FROM Files ORDER BY UploadedAt DESC")
        rows = cursor.fetchall()
        
        results = []
        for row in rows:
            file_name = row[0]
            folder_path_val = row[1]
            s3_url = row[2]
            content_type = row[3]
            uploaded_at = row[4].isoformat() if row[4] else None
            
            # Construct the S3 key
            folder_path = folder_path_val.rstrip('/')
            s3_key = f"{folder_path}/{file_name}"
            
            # Generate a presigned GET URL for securely viewing the image
            presigned_url = s3_client.generate_presigned_url(
                'get_object',
                Params={
                    'Bucket': bucket_name,
                    'Key': s3_key,
                },
                ExpiresIn=900 # 15 minutes
            )
            
            results.append({
                'fileName': file_name,
                'folderPath': folder_path_val,
                'contentType': content_type,
                's3Url': s3_url,
                'previewUrl': presigned_url,
                'uploadedAt': uploaded_at
            })
            
        cursor.close()
        conn.close()
        
        return {
            'statusCode': 200,
            'headers': {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Headers': 'Content-Type',
                'Access-Control-Allow-Methods': 'OPTIONS,GET,POST'
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
        
        # 2. Insert record into Azure SQL Database
        db_server = os.environ.get('DB_SERVER')
        db_user = os.environ.get('DB_USER')
        db_password = os.environ.get('DB_PASSWORD')
        db_name = os.environ.get('DB_NAME')
        
        conn = pytds.connect(
            server=db_server,
            user=db_user,
            password=db_password,
            database=db_name,
            cafile=certifi.where()
        )
        cursor = conn.cursor()
        
        insert_query = """
            INSERT INTO Files (FileName, FolderPath, S3Url, ContentType)
            VALUES (%s, %s, %s, %s)
        """
        cursor.execute(insert_query, (file_name, folder_path, s3_url, content_type))
        conn.commit()
        
        cursor.close()
        conn.close()
        
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
        
        # 2. Delete from Azure SQL Database
        db_server = os.environ.get('DB_SERVER')
        db_user = os.environ.get('DB_USER')
        db_password = os.environ.get('DB_PASSWORD')
        db_name = os.environ.get('DB_NAME')
        
        conn = pytds.connect(
            server=db_server,
            user=db_user,
            password=db_password,
            database=db_name,
            cafile=certifi.where()
        )
        cursor = conn.cursor()
        
        delete_query = "DELETE FROM Files WHERE FileName = %s AND FolderPath = %s"
        cursor.execute(delete_query, (file_name, folder_path))
        conn.commit()
        
        cursor.close()
        conn.close()
        
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
