# infra/Makefile
#
# terraform init に -backend-config を付け忘れると、黙ってローカル state へ
# 再初期化される。それを防ぐための薄いラッパ。直接 terraform を叩かないこと。
#
# 使い方:
#   make init ENV=playground
#   make validate ENV=playground
#   make plan ENV=playground
#
# ENV は environments/ 配下のディレクトリ名 (playground / primenumber / quick)。

ENV ?=
ENVDIR := environments/$(ENV)

.PHONY: check-env init validate plan fmt fmt-check moved graph help

help:
	@echo "使い方: make <target> ENV=<playground|primenumber|quick>"
	@echo ""
	@echo "  init        -backend-config 付きで初期化する"
	@echo "  validate    backend 無しで構文と型を検証する (AWS 接続不要)"
	@echo "  plan        plan を取る。受け入れ基準は docs/23 §4 を参照"
	@echo "  fmt         infra/ 全体を整形する"
	@echo "  fmt-check   整形済みかを確認する (CI 用)"
	@echo "  moved       moved.tf を再生成する (playground 専用)"
	@echo "  graph       依存グラフを出力する"

check-env:
ifndef ENV
	$(error ENV が未指定。例: make plan ENV=playground)
endif
	@test -d "$(ENVDIR)" || { echo "環境が存在しない: $(ENVDIR)"; exit 1; }

init: check-env
	@test -f "$(ENVDIR)/backend.hcl" || { \
	  echo "backend.hcl が無い: $(ENVDIR)/backend.hcl"; \
	  echo "ローカル state で初期化されるのを防ぐため中断する。"; exit 1; }
	cd $(ENVDIR) && terraform init -backend-config=backend.hcl

# backend を無効化して初期化するため、AWS 認証も S3 バケットも不要。
# モジュール構成そのものの検証に使う。
validate: check-env
	cd $(ENVDIR) && terraform init -backend=false -input=false && terraform validate

plan: check-env
	@echo "受け入れ基準: 0 to add, 0 to change, 0 to destroy"
	@echo "例外は aws_api_gateway_deployment.metadata の 1 件のみ。"
	@echo "aws_cloudfront_distribution.edge に -/+ が出たら即中断すること。"
	@echo ""
	cd $(ENVDIR) && terraform plan

fmt:
	terraform fmt -recursive .

fmt-check:
	terraform fmt -recursive -check .

# state を直接読んで割り当て表と突き合わせる。漏れがあればエラーで止まる。
moved:
	cd .. && python3 infra/scripts/generate-moved.py > infra/environments/playground/moved.tf

graph: check-env
	cd $(ENVDIR) && terraform graph
