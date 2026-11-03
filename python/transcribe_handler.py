import uuid

import boto3
import urllib.parse
transcribe = boto3.client('transcribe')

def lambda_handler(event, context):
    print("Yay we made it here!!")
    bucket = event['Records'][0]['s3']['bucket']['name']
    key = urllib.parse.unquote_plus(event['Records'][0]['s3']['object']['key'], encoding='utf-8')

    filename = key.split('/')[-1]

    fileURI = f"s3://{bucket}/{key}"

    job_name = f"transcribe-{filename.replace('.', '-')}-{uuid.uuid4().hex[:8]}"

    # get file extension
    file_ext = filename.split('.')[-1].lower()
    if file_ext not in ['mp3', 'mp4', 'm4a', 'wav', 'flac', 'ogg', 'amr', 'webm']:
        print(f"Unsupported file format: {file_ext}")
        return

    job_args = {
        "TranscriptionJobName": job_name,
        "Media": {"MediaFileUri": fileURI},
        "MediaFormat": file_ext,
        "LanguageCode": "en-US",
        "OutputBucketName": bucket,
        "OutputKey": f"transcripts/{job_name}.json"
    }

    # start transcribe job
    response = transcribe.start_transcription_job(**job_args)
    
    job_status = response['TranscriptionJob']['TranscriptionJobStatus']
    print(f"Transcription job initiated successfully: {job_status}")

    return {
        'statusCode': 200,
        'body': f"Started transcription job {job_name}",
        'jobStatus': job_status
    }
