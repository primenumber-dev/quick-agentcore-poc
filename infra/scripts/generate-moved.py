#!/usr/bin/env python3
"""terraform-playground-pattern4 のフラットな state を infra/environments/playground の
モジュール構成へ移すための moved ブロックを生成する。

使い方:
    python3 infra/scripts/generate-moved.py > infra/environments/playground/moved.tf

state を直接読んで全 managed リソースを列挙し、割り当て表と突き合わせる。
割り当て漏れがあればエラーで停止するので、モジュール構成を変えたら
ASSIGNMENT を更新すること。生成結果は必ず terraform plan で検証する
(受け入れ基準は docs/23-weekly-verification-plan-week6.md §4 を参照)。
"""

import json
import os
import sys

STATE = "terraform-playground-pattern4/terraform.tfstate"

# モジュール名 -> そのモジュールが持つ "<type>.<name>" のリスト。
# リソースラベルは移行元と同一に保っているため、移動先は
# "module.<module>.<type>.<name>" になる。
ASSIGNMENT = {
    "network": [
        "aws_vpc.main",
        "aws_subnet.public",
        "aws_subnet.private",
        "aws_internet_gateway.main",
        "aws_route_table.public",
        "aws_route_table.private",
        "aws_route_table_association.public",
        "aws_route_table_association.private",
        "aws_eip.nat",
        "aws_instance.nat",
        "aws_security_group.nat",
    ],
    "parameters": [
        "aws_kms_key.ssm",
        "aws_kms_alias.ssm",
    ],
    "mcp_server_ecs": [
        "aws_ecs_cluster.main",
        "aws_cloudwatch_log_group.ecs",
        "aws_iam_role.ecs_app_task",
        "aws_iam_role.ecs_task_execution",
        "aws_iam_role_policy.ecs_app_task_dynamodb",
        "aws_iam_role_policy.ecs_app_task_ssm",
        "aws_iam_role_policy.ecs_task_execution_ssm",
        "aws_iam_role_policy_attachment.ecs_task_execution",
        "aws_lb.main",
        "aws_lb_listener.http",
        "aws_lb_target_group.app",
        "aws_security_group.alb",
        "aws_security_group.ecs",
        "aws_ecr_repository.app",
        "aws_ecr_lifecycle_policy.app",
    ],
    "auth": [
        "aws_cognito_user_pool.main",
        "aws_cognito_user_pool_client.mcp",
        "aws_cognito_user_pool_domain.main",
        "aws_cognito_resource_server.mcp",
        "aws_cognito_managed_login_branding.main",
    ],
    "dcr": [
        "aws_lambda_function.dcr_authorizer",
        "aws_lambda_function.dcr_register",
        "aws_iam_role.dcr_authorizer",
        "aws_iam_role.dcr_register",
        "aws_iam_role_policy.dcr_authorizer_dynamodb",
        "aws_iam_role_policy.dcr_register_cognito",
        "aws_iam_role_policy.dcr_register_dynamodb",
        "aws_iam_role_policy_attachment.dcr_authorizer_basic",
        "aws_iam_role_policy_attachment.dcr_register_basic",
        "aws_cloudwatch_log_group.dcr_authorizer",
        "aws_cloudwatch_log_group.dcr_register",
    ],
    "api_gateway": [
        "aws_apigatewayv2_api.main",
        "aws_apigatewayv2_authorizer.lambda",
        "aws_apigatewayv2_integration.alb",
        "aws_apigatewayv2_integration.cognito_authorize",
        "aws_apigatewayv2_integration.cognito_revoke",
        "aws_apigatewayv2_integration.cognito_token",
        "aws_apigatewayv2_integration.dcr_register",
        "aws_apigatewayv2_integration.metadata",
        "aws_apigatewayv2_route.authorize",
        "aws_apigatewayv2_route.mcp",
        "aws_apigatewayv2_route.register",
        "aws_apigatewayv2_route.revoke",
        "aws_apigatewayv2_route.token",
        "aws_apigatewayv2_route.well_known",
        "aws_apigatewayv2_stage.main",
        "aws_apigatewayv2_vpc_link.main",
        "aws_api_gateway_rest_api.metadata",
        "aws_api_gateway_deployment.metadata",
        "aws_api_gateway_stage.metadata",
        "aws_cloudwatch_log_group.apigw_access",
        # lambda.tf から移設。API が「与える」権限なので api-gateway が持つ
        # (docs/23 §1.3)
        "aws_lambda_permission.dcr_authorizer_invoke",
        "aws_lambda_permission.dcr_register_invoke",
    ],
    "edge_waf": [
        "aws_cloudfront_distribution.edge",
        "aws_wafv2_web_acl.edge",
        "aws_wafv2_web_acl_logging_configuration.edge",
        "aws_cloudwatch_log_group.waf_edge",
    ],
}

# アドレスの形が変わる移動。
#
# playground は 3 つの SSM パラメータを個別リソースとして持っていたが、
# parameters モジュールは terraform/ssm.tf:45-72 の for_each マップ方式を採用した
# (2 世代のうち汎用な方。payload != "" ガードが納品先の二段階適用を支える)。
# そのため移動先はマップキー付きのアドレスになる。
#
# SSM パラメータの同一性は name 属性で決まる。moved で state を移せば
# name は変わらないので差分は出ない。逆に、ここを書き漏らすと
# 3 つのパラメータが destroy されて作り直される。
REKEYED = {
    "aws_ssm_parameter.quick_api_base":
        'module.parameters.aws_ssm_parameter.ssm_plain_parameters["/quick-api/base"]',
    "aws_ssm_parameter.quick_api_user":
        'module.parameters.aws_ssm_parameter.ssm_plaintext_parameters["/quick-api/user"]',
    "aws_ssm_parameter.quick_api_pass":
        'module.parameters.aws_ssm_parameter.ssm_plaintext_parameters["/quick-api/pass"]',
}

# 環境ルートに据え置くもの。moved ブロックを書いてはいけない。
#   random_password.origin_verify: dcr と edge-waf の両方が参照するためルートへ
#     引き上げた。アドレスが変わらないので移動不要。誤って消すと再生成で
#     X-Origin-Verify がローテートし、稼働中の CloudFront と Lambda Authorizer の
#     間に不一致窓が開く(docs/23 §1.3)。
#   aws_dynamodb_table.mcp_users: 環境ごとに存在有無が異なる。本番は 41 ユーザーの
#     実データがあり Terraform 管理外(DELIVERY-BLOCKERS DB-09)。
ROOT_RESOURCES = [
    "random_password.origin_verify",
    "aws_dynamodb_table.mcp_users",
]


def main():
    if not os.path.exists(STATE):
        sys.exit("state が見つからない: %s (リポジトリルートで実行すること)" % STATE)

    with open(STATE, encoding="utf-8") as fh:
        state = json.load(fh)

    actual = sorted(
        "%s.%s" % (r["type"], r["name"])
        for r in state["resources"]
        if r.get("mode") == "managed"
    )

    assigned = {}
    for module, addresses in ASSIGNMENT.items():
        for address in addresses:
            if address in assigned:
                sys.exit("割り当てが重複している: %s" % address)
            assigned[address] = module

    known = set(assigned) | set(ROOT_RESOURCES) | set(REKEYED)
    missing = [a for a in actual if a not in known]
    extra = sorted(known - set(actual))

    if missing:
        sys.exit("割り当てが無いリソース(ASSIGNMENT を更新すること):\n  " + "\n  ".join(missing))
    if extra:
        sys.exit("state に存在しないリソースを割り当てている:\n  " + "\n  ".join(extra))

    print("# 自動生成: python3 infra/scripts/generate-moved.py")
    print("#")
    print("# terraform-playground-pattern4/ のフラットな state を、モジュール構成の")
    print("# アドレスへ移す。terraform state mv ではなく moved ブロックを使う理由は、")
    print("# diff でレビューでき、冪等で、apply 前に plan が検証してくれるため。")
    print("#")
    print("# 受け入れ基準: plan が 0 to add, 0 to change, 0 to destroy になること。")
    print("# 例外は aws_api_gateway_deployment.metadata の 1 件のみ(openapi.yaml が")
    print("# モジュール配下へ移り path.module が変わるため sha1 トリガが動く)。")
    print("# aws_cloudfront_distribution.edge に -/+ が出たら即中断すること。")
    print("#")
    print("# 詳細: docs/23-weekly-verification-plan-week6.md §4")
    print("#")
    print("# 据え置き(moved ブロックを書かない): %s" % ", ".join(ROOT_RESOURCES))

    count = 0
    for module in ASSIGNMENT:
        print("\n# --- %s ---" % module)
        for address in ASSIGNMENT[module]:
            print("moved {")
            print("  from = %s" % address)
            print("  to   = module.%s.%s" % (module, address))
            print("}")
            count += 1

    print("\n# --- アドレスの形が変わるもの (for_each 化) ---")
    for src, dst in REKEYED.items():
        print("moved {")
        print("  from = %s" % src)
        print("  to   = %s" % dst)
        print("}")
        count += 1

    print("\n# moved ブロック数: %d / state の managed リソース: %d / 据え置き: %d"
          % (count, len(actual), len(ROOT_RESOURCES)), file=sys.stderr)
    print("生成完了", file=sys.stderr)


if __name__ == "__main__":
    main()
