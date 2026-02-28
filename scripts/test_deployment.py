import asyncio, json, time, sys
import boto3
import httpx

# Usage:
# python scripts/test_deployment.py \
#   --email you@example.com \
#   --temp-password 'TEMP...' \
#   --new-password 'YourNewPass123' \
#   --pool-id us-east-1_xxx \
#   --client-id xxxxx \
#   --api1 https://xxxx.execute-api.us-east-1.amazonaws.com \
#   --api2 https://yyyy.execute-api.eu-west-1.amazonaws.com

def arg(name):
    if name in sys.argv:
        return sys.argv[sys.argv.index(name)+1]
    return None

EMAIL = arg("--email")
TEMP_PASSWORD = arg("--temp-password")
NEW_PASSWORD = arg("--new-password")
POOL_ID = arg("--pool-id")
CLIENT_ID = arg("--client-id")
API1 = arg("--api1")
API2 = arg("--api2")

if not all([EMAIL, TEMP_PASSWORD, NEW_PASSWORD, POOL_ID, CLIENT_ID, API1, API2]):
    raise SystemExit("Missing args. See header comments in script.")

cognito = boto3.client("cognito-idp", region_name="us-east-1")

def get_jwt():
    # Attempt auth; handle NEW_PASSWORD_REQUIRED
    resp = cognito.initiate_auth(
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": EMAIL, "PASSWORD": TEMP_PASSWORD},
        ClientId=CLIENT_ID,
    )
    if resp.get("ChallengeName") == "NEW_PASSWORD_REQUIRED":
        resp2 = cognito.respond_to_auth_challenge(
            ClientId=CLIENT_ID,
            ChallengeName="NEW_PASSWORD_REQUIRED",
            Session=resp["Session"],
            ChallengeResponses={
                "USERNAME": EMAIL,
                "NEW_PASSWORD": NEW_PASSWORD
            }
        )
        return resp2["AuthenticationResult"]["IdToken"]
    return resp["AuthenticationResult"]["IdToken"]

async def call_endpoint(client, url, token, method="GET"):
    headers = {"Authorization": f"Bearer {token}"}
    start = time.perf_counter()
    r = await client.request(method, url, headers=headers, timeout=30)
    latency_ms = (time.perf_counter() - start) * 1000
    data = r.json()
    return r.status_code, data, latency_ms

async def main():
    token = get_jwt()

    async with httpx.AsyncClient() as client:
        greet1 = call_endpoint(client, f"{API1}/greet", token, "GET")
        greet2 = call_endpoint(client, f"{API2}/greet", token, "GET")
        (s1, d1, l1), (s2, d2, l2) = await asyncio.gather(greet1, greet2)

        print("\n=== /greet results ===")
        print("Region1:", s1, d1, f"{l1:.1f} ms")
        print("Region2:", s2, d2, f"{l2:.1f} ms")

        assert d1.get("region") in API1, "Region1 response doesn't match endpoint region"
        assert d2.get("region") in API2, "Region2 response doesn't match endpoint region"

        disp1 = call_endpoint(client, f"{API1}/dispatch", token, "POST")
        disp2 = call_endpoint(client, f"{API2}/dispatch", token, "POST")
        (s3, d3, l3), (s4, d4, l4) = await asyncio.gather(disp1, disp2)

        print("\n=== /dispatch results ===")
        print("Region1:", s3, d3, f"{l3:.1f} ms")
        print("Region2:", s4, d4, f"{l4:.1f} ms")

        assert d3.get("region") in API1
        assert d4.get("region") in API2

    print("\nAll assertions passed. (SNS publishes happen inside Lambda + ECS task.)")

if __name__ == "__main__":
    asyncio.run(main())
