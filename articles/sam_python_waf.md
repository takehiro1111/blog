---
title: "[Python]SAMでLambdaをデプロイしてみた"
emoji: "🐙"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS","Lambda","Python","SAM","Terraform"]
published: true
---

![](/images/py_logo/python-logo-master-v3-TM.png)

&nbsp;

## 記事を書く経緯
- 業務で特定のWAFルールの削除、再作成を自動化するというタスクがあり自身のメモとしての記事です。
GithubActionsでの対応も検討していますが、一旦以下のようにSAMを用いたAWS Lambdaで対応しようと考えています。

## 前提
1. SAM CLIをインストール済みであること。
2. Pythonの基本的な文法を押さえていること。
3. IAMロールの作成を行うので、AWS CLI or Terraformを扱える状態にあること。
(本記事ではTerraformで作成しています。)
&nbsp;

## 1. SAMプロジェクトを作成する
- プロジェクトに必要なファイル群を作成したいディレクトリへ移動し以下コマンドを実行。
```zsh
sam init
```

- インタラクティブな設定の説明
```zsh
You can preselect a particular runtime or package type when using the `sam init` experience.
Call `sam init --help` to learn more.

Which template source would you like to use?
        1 - AWS Quick Start Templates
        2 - Custom Template Location
Choice: 1 # 特別な要件が無ければマネージドのテンプレートを選択。

Choose an AWS Quick Start application template
        1 - Hello World Example
        2 - Data processing
        3 - Hello World Example with Powertools for AWS Lambda
        4 - Multi-step workflow
        5 - Scheduled task
        6 - Standalone function
        7 - Serverless API
        8 - Infrastructure event management
        9 - Lambda Response Streaming
        10 - Serverless Connector Hello World Example
        11 - Multi-step workflow with Connectors
        12 - GraphQLApi Hello World Example
        13 - Full Stack
        14 - Lambda EFS example
        15 - DynamoDB Example
        16 - Machine Learning
Template: 1 # 作りたいものに近いテンプレートを選択。

Use the most popular runtime and package type? (Python and zip) [y/N]: y # 最も一般的なランタイム（Python）とパッケージタイプ（zip）を使用するかどうか。

Would you like to enable X-Ray tracing on the function(s) in your application?  [y/N]: N # Lambda関数でAWS X-Rayトレースを有効にするかどうか。
X-Ray will incur an additional cost. View https://aws.amazon.com/xray/pricing/ for more details

Would you like to enable monitoring using CloudWatch Application Insights?
For more info, please view https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/cloudwatch-application-insights.html [y/N]: y # CloudWatch Application Insightsを有効にするかどうか。
AppInsights monitoring may incur additional cost. View https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/appinsights-what-is.html#appinsights-pricing for more details

Would you like to set Structured Logging in JSON format on your Lambda functions?  [y/N]: y # Lambda関数でJSON形式の構造化ログを有効にするかどうか。
Structured Logging in JSON format might incur an additional cost. View https://docs.aws.amazon.com/lambda/latest/dg/monitoring-cloudwatchlogs.html#monitoring-cloudwatchlogs-pricing for more details

Project name [sam-app]: {your_project_name} # プロジェクトの名前を指定する。

    -----------------------
    Generating application:
    -----------------------
    Name: waf-delete-create
    Runtime: python3.9
    Architectures: x86_64
    Dependency Manager: pip
    Application Template: hello-world
    Output Directory: .
    Configuration file: waf-delete-create/samconfig.toml
    
    Next steps can be found in the README file at waf-delete-create/README.md
        

Commands you can use next
=========================
[*] Create pipeline: cd waf-delete-create && sam pipeline init --bootstrap
[*] Validate SAM template: cd waf-delete-create && sam validate
[*] Test Function in the Cloud: cd waf-delete-create && sam sync --stack-name {stack-name} --watch
```
&nbsp;
## 2.Lambdaの実行権限を作成する。
- Lambgda関数を実行するためのIAMロールの作成
```hcl
data "aws_caller_identity" "current" {}

data "aws_region" "default" {
  name = "ap-northeast-1"
}

resource "aws_iam_role" "lambda_execute_waf" {
  name = "lambda-execute-waf"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Action = "sts:AssumeRole"
      }
    ]
  })
}

data "aws_iam_policy_document" "lambda_execute_waf" {
  statement {
    effect = "Allow"
    actions = [
      "wafv2:CreateRule",
      "wafv2:DeleteRule",
      "wafv2:UpdateWebACL",
      "wafv2:GetWebACL",
      "wafv2:ListWebACLs"
    ]
    resources = ["arn:aws:wafv2:us-east-1:${data.aws_caller_identity.current.account_id}:global/webacl/*/*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["arn:aws:logs:${data.aws_region.default.name}:${data.aws_caller_identity.current.account_id}:log-group:*:*"]
  }
}

resource "aws_iam_role_policy" "lambda_execute_waf" {
  name   = aws_iam_role.lambda_execute_waf.name
  role   = aws_iam_role.lambda_execute_waf.name
  policy = data.aws_iam_policy_document.lambda_execute_waf.json
}
```
&nbsp;

## 3.SAMテンプレートの作成
- ディレクトリ構造
```zsh
tree
.
├── README.md
├── __init__.py
├── events
│   ├── event.json
│   └── get_web_acl.json
├── lambda_function
│   ├── waf_delete.py
│   └── waf_recreate.py
├── samconfig.toml
├── template.yaml
└── tests
    ├── __init__.py
    ├── integration
    │   ├── __init__.py
    │   └── test_api_gateway.py
    ├── requirements.txt
    └── unit
        ├── __init__.py
        └── test_handler.py
```

- IAMロールも含め、`template.yml`を編集する。
```yml:template.yml
AWSTemplateFormatVersion: '2010-09-09'
Transform: AWS::Serverless-2016-10-31
Description: >
  Sample SAM Template for waf rule create and delete

# More info about Globals: https://github.com/awslabs/serverless-application-model/blob/master/docs/globals.rst
Globals:
  Function:
    Timeout: 3
    MemorySize: 128

    # You can add LoggingConfig parameters such as the Logformat, Log Group, and SystemLogLevel or ApplicationLogLevel. Learn more here https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/sam-resource-function.html#sam-function-loggingconfig.
    LoggingConfig:
      LogFormat: JSON

Resources:
  DeleteWAFRuleFunction:
    Type: AWS::Serverless::Function # More info about Function Resource: https://github.com/awslabs/serverless-application-model/blob/master/versions/2016-10-31.md#awsserverlessfunction
    Properties:
      Handler: delete_waf_rule.lambda_handler
      Runtime: python3.12
      CodeUri: lambda_function/
      Role: 'arn:aws:iam::{アカウントID}:role/lambda-execute-waf'
      Architectures:
      - x86_64

  CreateWAFRuleFunction:
    Type: AWS::Serverless::Function
    Properties:
      Handler: create_waf_rule.lambda_handler
      Runtime: python3.12
      CodeUri: lambda_function/
      Role: 'arn:aws:iam::{アカウントID}:role/lambda-execute-waf'
      Architectures:
      - x86_64
```

- この時点でビルドが可能か確認しておく。(後でエラーが発生した際に切り分けやすくするため。)
```zsh
sam build --use-container
# 中略

Commands you can use next
=========================
[*] Validate SAM template: sam validate
[*] Invoke Function: sam local invoke
[*] Test Function in the Cloud: sam sync --stack-name {{stack-name}} --watch
[*] Deploy: sam deploy --guided
```

## 3.Lambda関数の作成
- 実務の環境に調整する必要はあるが、特定のWAFルールを削除、作成する関数を適用。

### WAFルールの削除
```py
import boto3

waf = boto3.client('wafv2','us-east-1')

def lambda_handler(event, context):
    web_acl_name = event['WebACL']['Name']
    rule_name_to_delete = event['WebACL']['Rules'][0]['Name']
    web_acl_id = event['WebACL']['Id']
    scope = event['WebACL']['Scope']
    
    # Get the Web ACL
    web_acl = waf.get_web_acl(
        Name = web_acl_name,
        Scope = scope,
        Id = web_acl_id,
    )
    
    # Filter out the rule to delete
    updated_rules = [rule for rule in web_acl['WebACL']['Rules'] if rule['Name'] != rule_name_to_delete]
    
    try:
    # Update the Web ACL without the deleted rule
        response = waf.update_web_acl(
            Name= web_acl_name,
            Scope= scope,
            Id= web_acl_id,
            DefaultAction= web_acl['WebACL']['DefaultAction'],
            Rules= updated_rules,
            VisibilityConfig= web_acl['WebACL']['VisibilityConfig'],
            LockToken= web_acl['LockToken']
        )
    except Exception as e:
        print(f"Error Delete Web ACL Rule: {e}")
        raise e

    return response

```

### ルールの再作成
```py
import boto3

waf = boto3.client('wafv2','us-east-1')

def lambda_handler(event, context):
    web_acl_name = event['WebACL']['Name']
    web_acl_id = event['WebACL']['Id']
    scope = event['WebACL']['Scope']
    recreate_rule_name = event['WebACL']['Rules'][0]['Name']
    statement = event['WebACL']['Rules'][0]['Statement']
    priority = event['WebACL']['Rules'][0]['Priority']
    
    # Get the Web ACL
    web_acl = waf.get_web_acl(
        Name = web_acl_name,
        Scope = scope,
        Id = web_acl_id
    )
    
    # Add the new rule
    new_rule = {
        'Name': recreate_rule_name,
        'Priority': priority,
        'Action': {'Block': {}},
        'Statement': statement,
        'VisibilityConfig': {
            'SampledRequestsEnabled': True,
            'CloudWatchMetricsEnabled': True,
            'MetricName': web_acl_name
        }
    }
    
    updated_rules = web_acl['WebACL']['Rules'] + [new_rule]
    
    try:
    # Update the Web ACL with the new rule
        response = waf.update_web_acl(
            Name = web_acl_name,
            Scope = scope,
            Id = web_acl_id,
            DefaultAction = web_acl['WebACL']['DefaultAction'],
            Rules = updated_rules,
            VisibilityConfig = web_acl['WebACL']['VisibilityConfig'],
            LockToken = web_acl['LockToken']
        )
    except Exception as e:
        print(f"Error Recreate Web ACL Rule: {e}")
        raise e
    
    return response

```

### eventで渡すデータ

```json
{
  "WebACL": {
      "Name": "example-web-acl",
      "Id": "{string}",
      "Scope": "CLOUDFRONT",
      "ARN": "arn:aws:wafv2:us-east-1:{アカウントID}:global/webacl/example-web-acl/{WAFのID}",
      "DefaultAction": {
          "Allow": {}
      },
      "Description": "ACL for allowing specific regions",
      "Rules": [
          {
              "Name": "CountOtherRegions",
              "Priority": 1,
              "Statement": {
                  "NotStatement": {
                      "Statement": {
                          "GeoMatchStatement": {
                              "CountryCodes": [
                                  "JP",
                                  "US"
                              ]
                          }
                      }
                  }
              },
              "Action": {
                  "Block": {}
              },
              "VisibilityConfig": {
                  "SampledRequestsEnabled": true,
                  "CloudWatchMetricsEnabled": true,
                  "MetricName": "countOtherRegions"
              }
          }
      ],
      "VisibilityConfig": {
          "SampledRequestsEnabled": true,
          "CloudWatchMetricsEnabled": true,
          "MetricName": "exampleWebACL"
      },
      "Capacity": 1,
      "ManagedByFirewallManager": false,
      "LabelNamespace": "awswaf:{アカウントID}:webacl:example-web-acl:"
  },
  "LockToken": "{string}"
}

```

- ローカルでのテスト実施
```zsh
sam local invoke DeleteWAFRuleFunction --event get_web_acl.json
```

```zsh
sam local invoke CreateWAFRuleFunction --event get_web_acl.json
```

## 4.AWSへデプロイの実施

- デプロイする際に対話的に設定する。
```zsh
sam deploy --guided
```
```zsh
Setting default arguments for 'sam deploy'
        =========================================
        Stack Name [waf-rule]: 
        AWS Region [ap-northeast-1]: 
        #Shows you resources changes to be deployed and require a 'Y' to initiate deploy
        Confirm changes before deploy [Y/n]: Y
        #SAM needs permission to be able to create roles to connect to the resources in your template
        Allow SAM CLI IAM role creation [Y/n]: Y
        #Preserves the state of previously provisioned resources when an operation fails
        Disable rollback [y/N]: y
        Save arguments to configuration file [Y/n]: Y
        SAM configuration file [samconfig.toml]: 
        SAM configuration environment [default]: 

```
- デプロイ後に手動で呼び出す際のコマンド
```zsh
sam remote invoke DeleteWAFRuleFunction --event get_web_acl.json --stack-name waf-rule --region ap-northeast-1
```

```zsh
sam remote invoke CreateWAFRuleFunction --event get_web_acl.json --stack-name waf-rule --region ap-northeast-1
```

## 参考
https://docs.aws.amazon.com/ja_jp/serverless-application-model/latest/developerguide/what-is-sam.html
https://docs.aws.amazon.com/ja_jp/serverless-application-model/latest/developerguide/install-sam-cli.html
https://docs.aws.amazon.com/ja_jp/serverless-application-model/latest/developerguide/serverless-sam-cli-command-reference.html
https://docs.aws.amazon.com/ja_jp/serverless-application-model/latest/developerguide/using-sam-cli-deploy.html
https://zenn.dev/fusic/articles/3eaf7d66d513fd
https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/wafv2.html
https://dev.classmethod.jp/articles/lambda-my-first-step/
