# 納品ブロッカー台帳

> この章で分かること
> QUICK様のAWS環境へTerraformを納品するにあたり、現状のコードでは達成できない事項を固定IDで管理する台帳。各ブロッカーの根拠(file:line)、影響、対処方針、現在の状態を記録し、解消するまで追跡する。[20-production-readiness-checklist.md](../20-production-readiness-checklist.md)が「本番運用として安全か」を問うのに対し、本台帳は「**別のAWSアカウントで動かせるか**」だけを問う。

作成日: 2026-09-15 | 対象: primenumber内部資料(FDE成果物) | 初出: [00-handoff.md §18.4](../00-handoff.md)

---

## 状態の凡例

| 状態 | 意味 |
|---|---|
| 未対応 | 着手していない |
| 対応中 | フェーズ2で作業中 |
| 設計済 | 設計文書はあるが実装していない |
| 解消 | コードに反映され、検証も済んだ |

---

## 一覧

| ID | 重要度 | 概要 | 状態 | 担当フェーズ |
|---|---|---|---|---|
| [DB-01](#db-01-本番相当のterraformが1世代以上古い) | 高 | `terraform/`(本番相当)が1世代以上古く、WAF・CloudFront・DCRが無い | 未対応 | フェーズ2(設計)/ 別途(適用) |
| [DB-02](#db-02-ecsサービスがterraform管理外) | 高 | ECSサービスとタスク定義がTerraform管理外(ecspresso所有) | 未対応 | フェーズ2(設計のみ) |
| [DB-03](#db-03-variableブロックが0個) | 高 | `variable`ブロックが0個、`.tfvars`が0個 | 対応中 | フェーズ2 |
| [DB-04](#db-04-kms暗号文が特定アカウントの鍵に紐づく) | 高 | `terraform/ssm.tf`のKMS暗号文がprimenumberの鍵に紐づく | 未対応 | フェーズ2(設計のみ) |
| [DB-05](#db-05-playgroundのstateがローカルファイルのみ) | 高 | playgroundのstateがローカルファイルのみ(**75リソース**) | 未対応 | フェーズ2 |
| [DB-06](#db-06-アプリコードのテーブル名直書き) | 低 | アプリコードのDynamoDBテーブル名直書き | **ほぼ解消** | フェーズ2(残作業2点) |
| [DB-07](#db-07-cognitoドメインプレフィックスのグローバル一意性) | 中 | Cognitoドメインプレフィックスがリージョン内でグローバル一意 | 対応中 | フェーズ2 |
| [DB-08](#db-08-本番相当環境へ一度もデプロイしていない) | 中 | 本番相当環境へ一度もデプロイしていない | 未対応 | フェーズ4以降 |
| [DB-09](#db-09-terraform管理外の手作業リソースが多数) | 中 | Terraform管理外の手作業リソースが多数 | 未対応 | フェーズ3 |

---

## DB-01 本番相当のterraformが1世代以上古い

**重要度**: 高 | **状態**: 未対応

`terraform/`(11ファイル、925行)にはWAF・CloudFront・DCR Lambda・Lambda Authorizerが**一切無い**。Week4〜5の成果([18](../18-weekly-verification-report-week4.md)・[22](../22-weekly-verification-report-week5.md))はすべて`terraform-playground-pattern4/`(13ファイル、1642行)にのみ存在する。

| 差分 | `terraform/` | `terraform-playground-pattern4/` |
|---|---|---|
| Authorizer | JWT型(`apigateway.tf:84-99`) | Lambda REQUEST型(`apigateway.tf:94-103`) |
| `/register`・`/revoke` | 無し | 有り(`apigateway.tf:193,208`) |
| WAF / CloudFront | 無し | `cloudfront_waf.tf`(512行) |
| DCR Lambda | 無し | `lambda.tf`(182行) |
| アクセスログ | 無し | 有り(`apigateway.tf:63,68`) |
| `openapi.yaml` | `RESOURCE_SERVER_IDENTIFIER`・`AS_METADATA_JSON`無し | 有り |

**統合方向は playground → terraform**。ただし1箇所だけ例外があり、`terraform/ssm.tf:20-72`の`for_each`マップ + `aws_kms_secrets`パターンはplayground側より汎用のため、`secrets`モジュールはこちらを正とする。

**対処**: `enable_dcr` / `edge-waf.enabled`フラグで`primenumber`環境を旧世代の挙動から開始させ(差分ゼロ)、世代マージを意図的な別変更として切り出す。

**引き継ぐべき知見**: `terraform/apigateway.tf:91-95`に、**resource server identifierを`audience`に設定して全トークンが壊れた記録**がコメントで残っている。これは本番401バグ([00-handoff.md §14.2](../00-handoff.md))そのもので、世代マージの際に失ってはならない。

---

## DB-02 ECSサービスがTerraform管理外

**重要度**: 高 | **状態**: 未対応(フェーズ2は設計のみ)

`aws_ecs_service`と`aws_ecs_task_definition`は**どちらの`.tf`にも存在しない**。ecspressoが所有している。

- `ecspresso/app/ecspresso.yml:7-10` が primenumberアカウントのtfstate S3 URL(`s3://terraform.tfstate.professional-services-quick-poc/terraform.tfstate`)を**ハードコードして直読み**している
- playgroundには**ecspresso設定が存在しない**。stateがローカルファイルでtfstateプラグインが読めないためで、[DB-05](#db-05-playgroundのstateがローカルファイルのみ)と連動している

**対処(設計のみ)**: 2案を併記して判断する。

| 案 | 内容 | 評価 |
|---|---|---|
| (a) Terraformへ取り込む | `aws_ecs_service`を`cluster/service`、`aws_ecs_task_definition`を`family:revision`でimport。CDがイメージを回すなら`lifecycle { ignore_changes = [task_definition, desired_count] }`が必須。`must_env "IMAGE_TAG"`(`ecs-task-def.json:10`)の代替が要る | 管理の一元化。ただしTerraformとCDの責務境界を設計し直す必要がある |
| (b) ecspressoを維持 | `ecspresso.yml`を環境別に分割し、`:10`のstate URLだけを環境ごとに変える | 低リスク。**PoCではおそらくこちらが正解** |

いずれの案でも、同時に`ecs-task-def.json:26-31`へ`TABLE_NAME`を追加する([DB-06](#db-06-アプリコードのテーブル名直書き)の残作業)。

---

## DB-03 variableブロックが0個

**重要度**: 高 | **状態**: 対応中(フェーズ2の主作業)

`terraform/`・`terraform-playground-pattern4/`とも`variable`ブロック**0個**、`.tfvars`**0個**。リポジトリ内で唯一`variable`を持つのは`docs/terraform-examples/agentcore-vpc-mode/main.tf`(6個)だが、これは参考実装である。

直書きされている主なもの:

| 種別 | 該当 |
|---|---|
| AWSプロファイル名 | `terraform-playground-pattern4/provider.tf:21`、`cloudfront_waf.tf:18`(`quick-agentcore-poc-playground`)。`terraform/scripts/*.sh`3本(`quick-poc-admin`) |
| アカウントID | `lambda.tf:9`、`ecs.tf:88`(`883660531246`をARN内に直書き) |
| リージョン | 約20箇所 |
| S3バケット名 | `terraform/provider.tf:5`(backendは部分設定になっていない) |
| AMI名フィルタ | `vpc.tf:77` |
| リソース名プレフィックス | 約40行の`quick-mcp-poc` |
| 外部ドメイン | `ssm.tf:26` / `terraform/ssm.tf:23`(`qr1.devmarket.myquick.net`) |

**対処**: `infra/modules/` + `infra/environments/{playground,primenumber,quick}`へ再構成し、環境差分を`terraform.tfvars`と`backend.hcl`に集約する。詳細は[23-weekly-verification-plan-week6.md §3](../23-weekly-verification-plan-week6.md)。

**注意**: ルート`outputs`の名称は`ecspresso`との互換契約であり、改名するとデプロイが壊れる(同 §3.3)。

---

## DB-04 KMS暗号文が特定アカウントの鍵に紐づく

**重要度**: 高 | **状態**: 未対応(フェーズ2は設計のみ)

`terraform/ssm.tf:35,39` にKMS暗号文(CiphertextBlob)がコミットされており、primenumberアカウントのKMSキーに紐づいている。別アカウントでは復号できず、**`apply`が必ず失敗する**。

**鶏卵問題がある**: 復号に使う鍵は同じ`apply`で作られるため、納品先では二段階適用になる。

1. `encrypted_parameters = {}` で`apply`し、KMSキーを作る
2. `terraform/scripts/encrypt-secret.sh`で新しい鍵に対して暗号化し、tfvarsへ投入して再`apply`

`terraform/ssm.tf:57,65`の`payload != ""`ガードがこの流れに既に対応している。

**推奨は代案**: 暗号文をコミットする方式そのものをやめ、`aws ssm put-parameter`で帯域外に投入し`data.aws_ssm_parameter`で読む。クロスアカウント問題が恒久的に消え、二段階適用も不要になる。`quick`環境はこちらを採用する。

---

## DB-05 playgroundのstateがローカルファイルのみ

**重要度**: 高 | **状態**: 未対応

`terraform-playground-pattern4/provider.tf:1-18`には**backendブロックが無い**。stateは`terraform-playground-pattern4/terraform.tfstate`としてディスク上にのみ存在する。

**リソース数は75**(managed 75 / instances 82、ほかdata source 12)。[00-handoff.md §18.4-5](../00-handoff.md)の「59リソース」は誤りで、本台帳作成時にstateを直接パースして訂正した。差は`for_each`で2インスタンスを持つ7リソース(`aws_eip.nat`、`aws_instance.nat`、`aws_route_table.private`、`aws_route_table_association.private`/`.public`、`aws_subnet.private`/`.public`)によるもの。

このファイルにはSSMのプレースホルダ値と`random_password.origin_verify`の生成結果が含まれる。`.gitignore:3`(`*.tfstate`)で追跡対象外であることは確認済み。

**対処**: バージョニング + SSE + パブリックアクセスブロックのS3バケットをplaygroundアカウントに作り、`terraform init -migrate-state`。ロックはDynamoDBテーブルではなくS3ネイティブ(`use_lockfile = true`、`terraform/provider.tf:9`と揃える)。

**連動**: これが解消すると、playgroundでもecspressoのtfstateプラグインが使えるようになり[DB-02](#db-02-ecsサービスがterraform管理外)の選択肢(b)が現実的になる。

---

## DB-06 アプリコードのテーブル名直書き

**重要度**: 低 | **状態**: **ほぼ解消**(残作業2点)

[00-handoff.md §18.4-6](../00-handoff.md)は「アプリコードがDynamoDBテーブル名とリージョンを直書き(`server/src/db.ts:20`、`cli/src/db.ts:4`)」としているが、**すでに環境変数化されている**。

```typescript
// server/src/db.ts:21 / cli/src/db.ts:5
const TABLE_NAME = process.env.TABLE_NAME ?? "quick-mcp-poc-users";
```

Week5の[19-weekly-verification-plan-week5.md §2.1 F12](../19-weekly-verification-plan-week5.md)の対応が入っている。残るリージョン直書き(`server/src/db.ts:10`、`cli/src/db.ts:13`)は`DYNAMODB_ENDPOINT_URL`分岐内のLocalStack専用箇所で無害。

**残作業**:

1. `??`フォールバックの除去(既定値に依存した事故を防ぐ)
2. `ecspresso/app/ecs-task-def.json:26-31`の`environment`へ`TABLE_NAME`を追加

**なお残っている回避策**: `ecs.tf:84` と `ecs.tf:88` でIAMが2つのテーブルを許可している。Terraformが作るテーブルと、実際に読まれるAgentCore Runtime検証時のテーブルの両方である(`ecs.tf:86`のコメント参照)。`dynamodb_table_arns`変数としてリスト化し、環境ごとに正しい1つだけを渡せるようにする。

---

## DB-07 Cognitoドメインプレフィックスのグローバル一意性

**重要度**: 中 | **状態**: 対応中

Cognitoのドメインプレフィックスは**リージョン内でグローバル一意**。同一リージョンに複数環境を立てるには変数化が必須である。

| 環境 | 該当 | 値 |
|---|---|---|
| primenumber | `terraform/cognito.tf:48` | `quick-mcp-poc-auth` |
| primenumber(local pool) | `terraform/cognito.tf:107` | `local-quick-mcp-poc-auth` |
| playground | `cognito.tf:62` | `quick-mcp-poc-pattern4-verify` |

playgroundが`-pattern4-verify`を名乗っているのは、**`quick-mcp-poc-auth`が既に取られていたため**である(ファイル冒頭コメント)。つまりこの制約は既に一度実害を出している。

**対処**: `domain_prefix`を`auth`モジュールの入力とし、環境ごとに指定する。`quick`環境には新規かつ未使用の値を割り当てる。

**関連**: カスタムドメイン(ACM)を導入すればこの制約から外れ、同時に`ENFORCE_ORIGIN_VERIFY`(`lambda.tf:79`)を`true`にできる([19-weekly-verification-plan-week5.md §1.1 D5](../19-weekly-verification-plan-week5.md))。

---

## DB-08 本番相当環境へ一度もデプロイしていない

**重要度**: 中 | **状態**: 未対応

`terraform/`は一度も`apply`されていない。プロファイルが`AWSPowerUserAccess`でIAM作成権限が無く、かつ実クライアントデータ(41ユーザー)があるため書き込み禁止で運用しているため。**CI/CDの本番パスは未検証の白地**である。

`terraform/`のコードが実際に通るかどうかの確証が無いまま、納品先環境という3つ目の未検証環境を増やすことになる。

**対処**: フェーズ4のCI/CD設計([00-handoff.md §18.5](../00-handoff.md))で、本番パスの検証方法(`plan`のみのdry-run、権限の棚卸し、GitHub OIDC → AssumeRoleへの置換)を決める。

---

## DB-09 Terraform管理外の手作業リソースが多数

**重要度**: 中 | **状態**: 未対応

| リソース | 備考 |
|---|---|
| AgentCore Runtime(3つ) | AWS CLIで作成。**`.tf`に定義が1件も無い**(コメント言及3件のみ)。[ARCHITECTURE-VERSIONS.md](./ARCHITECTURE-VERSIONS.md)の「タグ付けできるコード状態が存在しない」に対応 |
| VPCエンドポイント | AgentCore VPCモード検証時。参考実装は`docs/terraform-examples/agentcore-vpc-mode/main.tf` |
| Webデモ用Lambda | `web-demo`関連 |
| テストユーザー | Cognito |
| DynamoDBテーブル本体 | `quick-mcp-poc-users`。`lambda.tf:5-6`が「意図的にTerraform管理外」と明記。本番は41ユーザーの実データがあり作り直せない |

棚卸しは[17-environment-resource-map.md](../17-environment-resource-map.md)を参照。

**対処**: フェーズ3(AWS環境の整理とバージョニング)で扱う。playgroundはtrocco・PetStore等と**共用**のため、対象を`quick-mcp-poc*`に限定する。**削除は必ず事前確認を取る**。

---

## 更新ルール

1. 状態が変わったら本台帳を更新し、根拠(コミット・検証結果)を書く。
2. 新たなブロッカーを見つけたらIDを追番で発行する。既存IDの意味は変えない。
3. 「本番運用として安全か」に属する事項は本台帳ではなく[20-production-readiness-checklist.md](../20-production-readiness-checklist.md)へ登録する。
4. 納品時は、QUICK様環境で解消済みのIDを記録する。
