import json
import sys
import boto3

AGENT_RUNTIME_ARN = "arn:aws:bedrock-agentcore:ap-northeast-1:883660531246:runtime/quickMcpPocVerification-Aoo0d23yyj"
TEST_SUB = "agentcore-verification-user"

mcp_method = sys.argv[1] if len(sys.argv) > 1 else "tools/list"
mcp_params = json.loads(sys.argv[2]) if len(sys.argv) > 2 else {}

session = boto3.Session(profile_name="quick-agentcore-poc-playground", region_name="ap-northeast-1")
client = session.client("bedrock-agentcore")


def add_custom_header(request, **kwargs):
    request.headers.add_header("x-cognito-sub", TEST_SUB)


client.meta.events.register_first(
    "before-sign.bedrock-agentcore.InvokeAgentRuntime", add_custom_header
)

payload = json.dumps(
    {"jsonrpc": "2.0", "id": 1, "method": mcp_method, "params": mcp_params}
).encode()

response = client.invoke_agent_runtime(
    agentRuntimeArn=AGENT_RUNTIME_ARN,
    payload=payload,
    contentType="application/json",
    accept="application/json, text/event-stream",
)

body = response["response"].read()
print(json.dumps(json.loads(body), ensure_ascii=False, indent=2))
