import os, json
import boto3

ecs = boto3.client("ecs")

CLUSTER_ARN = os.environ["CLUSTER_ARN"]
TASKDEF_ARN = os.environ["TASKDEF_ARN"]
SUBNETS = os.environ["SUBNETS"].split(",")
SG = os.environ["SECURITY_GRP"]
REGION = os.environ["REGION_NAME"]

def handler(event, context):
    ecs.run_task(
        cluster=CLUSTER_ARN,
        taskDefinition=TASKDEF_ARN,
        launchType="FARGATE",
        networkConfiguration={
            "awsvpcConfiguration": {
                "subnets": SUBNETS,
                "securityGroups": [SG],
                "assignPublicIp": "ENABLED"
            }
        }
    )

    return {
        "statusCode": 200,
        "headers": {"content-type": "application/json"},
        "body": json.dumps({"region": REGION, "dispatched": True})
    }
