import json, os, time
import boto3
from datetime import datetime, timezone

ddb = boto3.client("dynamodb")
sns = boto3.client("sns", region_name="us-east-1")  # topic is in us-east-1

TABLE = os.environ["TABLE_NAME"]
SNS_ARN = os.environ["SNS_ARN"]
EMAIL = os.environ["EMAIL"]
REPO_URL = os.environ["REPO_URL"]
REGION = os.environ["REGION_NAME"]

def handler(event, context):
    now = datetime.now(timezone.utc).isoformat()
    pk = f"user#{EMAIL}"
    sk = f"ts#{int(time.time())}"

    ddb.put_item(
        TableName=TABLE,
        Item={
            "pk": {"S": pk},
            "sk": {"S": sk},
            "created_at": {"S": now},
            "region": {"S": REGION},
            "request_id": {"S": context.aws_request_id},
        }
    )

    payload = {
        "email": EMAIL,
        "source": "Lambda",
        "region": REGION,
        "repo": REPO_URL
    }

    sns.publish(
        TopicArn=SNS_ARN,
        Message=json.dumps(payload),
    )

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"region": REGION})
    }
