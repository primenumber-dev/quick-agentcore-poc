import json
import boto3

AGENT_RUNTIME_ARN = "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj"

session = boto3.Session(profile_name="quick-agentcore-poc-playground", region_name="ap-northeast-1")
client = session.client("bedrock-agentcore")

payload = json.dumps(
    {"jsonrpc": "2.0", "id": 1, "method": "tools/list", "params": {}}
).encode()

try:
    response = client.invoke_agent_runtime(
        agentRuntimeArn=AGENT_RUNTIME_ARN,
        payload=payload,
        contentType="application/json",
        accept="application/json, text/event-stream",
    )
    print(response["response"].read())
except Exception as e:
    print(f"Error (expected): {e}")
